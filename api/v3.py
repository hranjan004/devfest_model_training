"""`/v3` app endpoints: 34-class BioCLIP inference plus the sightings feed the iOS app uses.

    GET  /v3/health
    GET  /v3/species
    GET  /v3/species/{class_id}/image     reference photo (scripts/fetch_reference_photos.py)
    POST /v3/identify                     multipart: file
    GET  /v3/sightings                    ?sort=newest|top_rated|most_comments|alphabetical&class_id=
    POST /v3/sightings                    multipart: file, name, description, latitude, longitude
    GET  /v3/sightings/{id}
    GET  /v3/sightings/{id}/image
    POST /v3/sightings/{id}/ratings       json: {stars}
    GET  /v3/sightings/{id}/comments
    POST /v3/sightings/{id}/comments      json: {author, text}

The caller identifies itself for "my rating" with an `X-Device-Id` header.
"""

from __future__ import annotations

import io
import os
from pathlib import Path
import threading
import json
from typing import Any, Callable, Dict, List, Optional

from fastapi import APIRouter, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from api.store import SORTS, SightingStore
from wildlife.models.ucsc34 import MODEL_VERSION, default_run_dir, load_classes

ROOT = Path(__file__).resolve().parents[1]
MAX_UPLOAD_BYTES = int(os.environ.get("WILDLIFE_MAX_UPLOAD_BYTES", 10 * 1024 * 1024))
MAX_IMAGE_PIXELS = int(os.environ.get("WILDLIFE_MAX_IMAGE_PIXELS", 25_000_000))
STORED_MAX_SIDE = 1600


class RatingBody(BaseModel):
    stars: int = Field(ge=1, le=5)


class CommentBody(BaseModel):
    author: str = Field(default="Anonymous", max_length=40)
    text: str = Field(min_length=1, max_length=500)


class V3State:
    """Holds the lazily loaded classifier and the sighting store."""

    def __init__(
        self,
        store_root: Optional[Path] = None,
        classifier_factory: Optional[Callable[[], Any]] = None,
        classes: Optional[List[Dict[str, Any]]] = None,
        reference_dir: Optional[Path] = None,
    ) -> None:
        self.reference_dir = reference_dir or Path(
            os.environ.get("WILDLIFE_REFERENCE_DIR", str(ROOT / "data" / "app_reference"))
        )
        self.store = SightingStore(
            store_root or Path(os.environ.get("WILDLIFE_APP_DATA_DIR", str(ROOT / "data" / "app")))
        )
        self._factory = classifier_factory or self._default_factory
        self._classifier: Optional[Any] = None
        self._load_lock = threading.Lock()
        self._classes = classes

    @staticmethod
    def _default_factory() -> Any:
        from wildlife.models.ucsc34 import Ucsc34Classifier

        return Ucsc34Classifier()

    def reference_credits(self) -> Dict[str, Dict[str, Any]]:
        """Credits for the reference photos that are actually on disk."""
        path = self.reference_dir / "credits.json"
        if not path.exists():
            return {}
        credits = json.loads(path.read_text())
        return {k: v for k, v in credits.items() if (self.reference_dir / f"{k}.jpg").exists()}

    @property
    def loaded(self) -> bool:
        return self._classifier is not None

    @property
    def classifier(self) -> Any:
        if self._classifier is None:
            with self._load_lock:
                if self._classifier is None:
                    self._classifier = self._factory()
        return self._classifier

    @property
    def classes(self) -> List[Dict[str, Any]]:
        if self._classes is None:
            self._classes = load_classes()
        return self._classes


def _decode_upload(raw: Optional[bytes]) -> Any:
    """Validate an upload and return an upright RGB PIL image."""
    from PIL import Image, ImageOps, UnidentifiedImageError

    if not raw:
        raise HTTPException(400, {"error": "empty_upload", "detail": "No image bytes provided."})
    if len(raw) > MAX_UPLOAD_BYTES:
        raise HTTPException(
            413, {"error": "payload_too_large", "detail": f"Upload exceeds {MAX_UPLOAD_BYTES} bytes."}
        )
    try:
        image = Image.open(io.BytesIO(raw))
        if image.format not in {"JPEG", "PNG"}:
            raise HTTPException(
                415, {"error": "unsupported_media_type", "detail": "Only JPEG and PNG are accepted."}
            )
        if image.width * image.height > MAX_IMAGE_PIXELS:
            raise HTTPException(
                413, {"error": "decompression_bomb_rejected", "detail": "Image has too many pixels."}
            )
        return ImageOps.exif_transpose(image).convert("RGB")
    except HTTPException:
        raise
    except (UnidentifiedImageError, OSError, ValueError) as exc:
        raise HTTPException(422, {"error": "invalid_image", "detail": "The file is not a readable image."}) from exc


def _to_stored_jpeg(image: Any) -> bytes:
    """Downscale and re-encode. Re-encoding drops EXIF, including any GPS tags."""
    copy = image.copy()
    copy.thumbnail((STORED_MAX_SIDE, STORED_MAX_SIDE))
    buffer = io.BytesIO()
    copy.save(buffer, format="JPEG", quality=88)
    return buffer.getvalue()


def _class_lookup(state: V3State) -> Dict[str, Dict[str, Any]]:
    return {c["class_id"]: c for c in state.classes}


def _public_sighting(state: V3State, row: Dict[str, Any]) -> Dict[str, Any]:
    record = _class_lookup(state).get(row["class_id"], {})
    row["common_name"] = record.get("common_name", row["class_id"])
    row["scientific_name"] = record.get("scientific_name", "")
    row["group"] = record.get("group", "")
    return row


def build_router(state: Optional[V3State] = None) -> APIRouter:
    state = state or V3State()
    router = APIRouter(prefix="/v3", tags=["app"])
    router.state = state  # type: ignore[attr-defined]

    def require_sighting(sighting_id: str, device_id: str = "") -> Dict[str, Any]:
        row = state.store.get(sighting_id, device_id=device_id)
        if row is None:
            raise HTTPException(404, {"error": "not_found", "detail": "No such sighting."})
        return row

    @router.get("/health")
    def health() -> Dict[str, Any]:
        adapter = default_run_dir() / "model_adapter.pt"
        return {
            "status": "ok",
            "model_version": MODEL_VERSION,
            "num_classes": len(state.classes),
            "weights_present": adapter.exists() or state.loaded,
            "model_loaded": state.loaded,
        }

    @router.get("/species")
    def species() -> Dict[str, Any]:
        stats = state.store.species_stats()
        credits = state.reference_credits()

        def credit_line(class_id: str) -> Optional[str]:
            c = credits.get(class_id)
            return f"Photo by {c['photographer']} ({c['license']}) via iNaturalist" if c else None

        return {
            "model_version": MODEL_VERSION,
            "species": [
                {
                    "class_id": c["class_id"],
                    "common_name": c["common_name"],
                    "scientific_name": c["scientific_name"],
                    "group": c["group"],
                    "sighting_count": stats.get(c["class_id"], {}).get("sighting_count", 0),
                    "cover_image_url": stats.get(c["class_id"], {}).get("cover_image_url"),
                    "reference_image_url": f"/v3/species/{c['class_id']}/image" if c["class_id"] in credits else None,
                    "reference_credit": credit_line(c["class_id"]),
                }
                for c in state.classes
            ],
        }

    @router.get("/species/{class_id}/image")
    def species_image(class_id: str) -> FileResponse:
        if class_id not in _class_lookup(state):
            raise HTTPException(404, {"error": "not_found", "detail": "No such species."})
        path = state.reference_dir / f"{class_id}.jpg"
        if not path.exists():
            raise HTTPException(404, {"error": "not_found", "detail": "No reference photo for this species."})
        return FileResponse(path, media_type="image/jpeg", headers={"Cache-Control": "public, max-age=300"})

    @router.post("/identify")
    def identify(file: UploadFile = File(...), top_k: int = Form(default=3)) -> Dict[str, Any]:
        image = _decode_upload(file.file.read())
        return state.classifier.predict_image(image, top_k=top_k)

    @router.get("/sightings")
    def list_sightings(
        sort: str = "newest",
        class_id: Optional[str] = None,
        x_device_id: str = Header(default=""),
    ) -> Dict[str, Any]:
        if sort not in SORTS:
            raise HTTPException(422, {"error": "invalid_sort", "detail": f"sort must be one of {sorted(SORTS)}."})
        rows = state.store.list(sort=sort, class_id=class_id, device_id=x_device_id)
        return {"sightings": [_public_sighting(state, r) for r in rows]}

    @router.post("/sightings", status_code=201)
    def create_sighting(
        file: UploadFile = File(...),
        name: str = Form(...),
        description: str = Form(default=""),
        latitude: Optional[float] = Form(default=None),
        longitude: Optional[float] = Form(default=None),
    ) -> Dict[str, Any]:
        name = name.strip()
        if not name or len(name) > 60:
            raise HTTPException(422, {"error": "invalid_name", "detail": "name must be 1 to 60 characters."})
        if (latitude is None) != (longitude is None):
            raise HTTPException(422, {"error": "invalid_location", "detail": "Send both latitude and longitude, or neither."})
        if latitude is not None and not (-90 <= latitude <= 90 and -180 <= longitude <= 180):  # type: ignore[operator]
            raise HTTPException(422, {"error": "invalid_location", "detail": "Coordinates out of range."})
        image = _decode_upload(file.file.read())
        prediction = state.classifier.predict_image(image, top_k=3)
        row = state.store.create(
            name=name,
            description=description.strip()[:500],
            prediction=prediction,
            jpeg_bytes=_to_stored_jpeg(image),
            latitude=latitude,
            longitude=longitude,
        )
        return _public_sighting(state, row)

    @router.get("/sightings/{sighting_id}")
    def get_sighting(sighting_id: str, x_device_id: str = Header(default="")) -> Dict[str, Any]:
        return _public_sighting(state, require_sighting(sighting_id, x_device_id))

    @router.get("/sightings/{sighting_id}/image")
    def get_image(sighting_id: str) -> FileResponse:
        require_sighting(sighting_id)
        path = state.store.image_path(sighting_id)
        if not path.exists():
            raise HTTPException(404, {"error": "not_found", "detail": "Image file missing."})
        return FileResponse(path, media_type="image/jpeg", headers={"Cache-Control": "public, max-age=86400"})

    @router.post("/sightings/{sighting_id}/ratings")
    def rate(sighting_id: str, body: RatingBody, x_device_id: str = Header(default="")) -> Dict[str, Any]:
        if not x_device_id.strip():
            raise HTTPException(400, {"error": "device_id_required", "detail": "Send an X-Device-Id header."})
        require_sighting(sighting_id)
        state.store.rate(sighting_id, x_device_id.strip()[:64], body.stars)
        return _public_sighting(state, require_sighting(sighting_id, x_device_id))

    @router.get("/sightings/{sighting_id}/comments")
    def list_comments(sighting_id: str) -> Dict[str, Any]:
        require_sighting(sighting_id)
        return {"comments": state.store.comments(sighting_id)}

    @router.post("/sightings/{sighting_id}/comments", status_code=201)
    def add_comment(sighting_id: str, body: CommentBody) -> Dict[str, Any]:
        require_sighting(sighting_id)
        text = body.text.strip()
        if not text:
            raise HTTPException(422, {"error": "invalid_comment", "detail": "Comment text is empty."})
        return state.store.add_comment(sighting_id, body.author.strip() or "Anonymous", text)

    return router
