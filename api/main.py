"""FastAPI service for UCSC Wildlife Vision (`POST /v2/predict`, `POST /v1/predict`, `GET /healthz`, `POST /v1/feedback`, `GET /v1/classes`)."""

from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sys
import time
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT / "src") not in sys.path:
    sys.path.insert(0, str(ROOT / "src"))

from wildlife.data.clean import (
    CorruptImageError,
    DecompressionBombError,
    ImageValidationError,
    UnsupportedImageFormatError,
)
from wildlife.infer import WildlifePredictor
from wildlife.schemas import VALID_GROUPS, load_species_taxonomy


class WildlifeAPIService:
    """Core request handler implementing `/v2/predict`, `/v1/predict`, `/healthz`, `/v1/feedback`, and `/v1/classes`."""

    def __init__(
        self,
        checkpoint_path: Optional[Path] = None,
        detector: Optional[Any] = None,
        feedback_queue_path: Optional[Path] = None,
        max_upload_bytes: int = 10 * 1024 * 1024,
        rate_limit_per_minute: int = 30,
    ) -> None:
        default_ckpt = ROOT / "runs" / "efficientnet_b0_v1" / "best.ckpt"
        ckpt = checkpoint_path if checkpoint_path is not None else (
            Path(os.environ["WILDLIFE_CHECKPOINT_PATH"])
            if os.environ.get("WILDLIFE_CHECKPOINT_PATH")
            else (default_ckpt if default_ckpt.exists() else None)
        )
        self.predictor = WildlifePredictor(checkpoint_path=ckpt, detector=detector)
        self.feedback_queue_path = feedback_queue_path or Path(
            os.environ.get(
                "WILDLIFE_FEEDBACK_QUEUE_PATH",
                str(ROOT / "data" / "manifests" / "feedback_queue.jsonl"),
            )
        )
        self.max_upload_bytes = int(max_upload_bytes)
        self.rate_limit_per_minute = int(rate_limit_per_minute)
        self._feedback_timestamps: List[float] = []
        self.species_records = load_species_taxonomy()
        self.valid_class_ids = {r.class_id for r in self.species_records} | {"unknown"}

    def handle_healthz(self) -> Tuple[int, Dict[str, Any]]:
        return 200, {
            "status": "ok",
            "ready": True,
            "model_version": self.predictor.model_version,
            "detector_version": self.predictor.detector.version,
            "crop_version": self.predictor.crop_version,
            "calibration_version": self.predictor.calibration_version,
            "rating_version": self.predictor.rating_version,
            "argon_model_version": self.predictor.argon_model_version,
            "num_classes": 20,
        }

    def handle_classes(self) -> Tuple[int, Dict[str, Any]]:
        return 200, {
            "version": "2.0.0",
            "title": "UCSC Wildlife 20 Starter Species",
            "supported_groups": sorted(VALID_GROUPS),
            "classes": [r.to_public_dict() for r in self.species_records],
        }

    def handle_predict(
        self,
        image_bytes: Optional[bytes],
        crop_box: Optional[Any] = None,
        multiple_animals: bool = False,
        scene_hint: Optional[str] = None,
        image_url: Optional[str] = None,
        logits_override: Optional[Any] = None,
        api_version: str = "v1",
        explain: bool = False,
    ) -> Tuple[int, Dict[str, Any]]:
        if image_url is not None and str(image_url).strip() != "":
            return 400, {
                "error": "ssrf_prohibited",
                "detail": "Remote URL fetching is prohibited for security (SSRF protection). Upload image bytes directly.",
            }

        if not image_bytes:
            return 400, {
                "error": "empty_upload",
                "detail": "No image bytes provided.",
            }

        if len(image_bytes) > self.max_upload_bytes:
            return 413, {
                "error": "payload_too_large",
                "detail": f"Upload exceeds maximum size of {self.max_upload_bytes} bytes.",
            }

        try:
            res = self.predictor.predict_bytes(
                raw_bytes=image_bytes,
                crop_box=crop_box,
                multiple_animals_reported=multiple_animals,
                scene_hint=scene_hint,
                logits_override=logits_override,
                explain=explain,
            )
            if api_version == "v2":
                return 200, res.to_v2_dict()
            return 200, res.to_dict()
        except UnsupportedImageFormatError as exc:
            return 415, {"error": "unsupported_media_type", "detail": str(exc)}
        except DecompressionBombError as exc:
            return 413, {"error": "decompression_bomb_rejected", "detail": str(exc)}
        except (CorruptImageError, ImageValidationError, ValueError) as exc:
            return 422, {"error": "invalid_image", "detail": str(exc)}

    def handle_feedback(self, payload: Dict[str, Any]) -> Tuple[int, Dict[str, Any]]:
        """Store user corrections in review queue only (never automatic retraining, §1.7 & §12)."""
        now = time.time()
        self._feedback_timestamps = [
            t for t in self._feedback_timestamps if (now - t) < 60.0
        ]
        if len(self._feedback_timestamps) >= self.rate_limit_per_minute:
            return 429, {
                "error": "rate_limit_exceeded",
                "detail": "Too many feedback submissions; please wait before submitting again.",
            }

        consent = bool(payload.get("consent", False))
        if not consent:
            return 400, {
                "error": "consent_required",
                "detail": "Explicit user consent is required to store prediction corrections for review.",
            }

        corrected_class_id = str(payload.get("corrected_class_id", "")).strip()
        if corrected_class_id not in self.valid_class_ids:
            return 422, {
                "error": "invalid_class_id",
                "detail": f"corrected_class_id must be one of the 20 canonical IDs or 'unknown', got '{corrected_class_id}'.",
            }

        self._feedback_timestamps.append(now)
        record = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "predicted_class_id": payload.get("predicted_class_id"),
            "corrected_class_id": corrected_class_id,
            "model_version": self.predictor.model_version,
            "detector_version": self.predictor.detector.version,
            "crop_version": self.predictor.crop_version,
            "notes": str(payload.get("notes", ""))[:500],
            "consent": True,
            "action": "queued_for_human_review_only",
            "auto_retrain": False,
        }
        self.feedback_queue_path.parent.mkdir(parents=True, exist_ok=True)
        with self.feedback_queue_path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(record) + "\n")

        return 202, {
            "status": "queued_for_review",
            "auto_retrain": False,
            "corrected_class_id": corrected_class_id,
            "model_version": self.predictor.model_version,
        }


class LocalAPIClient:
    """Synchronous test client mirroring `fastapi.testclient.TestClient` semantics."""

    def __init__(self, service: Optional[WildlifeAPIService] = None) -> None:
        self.service = service or WildlifeAPIService()

    def get(self, path: str) -> "LocalAPIResponse":
        if path == "/healthz":
            code, data = self.service.handle_healthz()
            return LocalAPIResponse(code, data)
        if path == "/v1/classes":
            code, data = self.service.handle_classes()
            return LocalAPIResponse(code, data)
        return LocalAPIResponse(404, {"error": "not_found"})

    def post(
        self,
        path: str,
        files: Optional[Dict[str, Any]] = None,
        data: Optional[Dict[str, Any]] = None,
        json_body: Optional[Dict[str, Any]] = None,
    ) -> "LocalAPIResponse":
        if path in {"/v1/predict", "/v2/predict"}:
            form = data or {}
            img_bytes = None
            if files and "file" in files:
                f_entry = files["file"]
                if isinstance(f_entry, tuple):
                    img_bytes = f_entry[1]
                elif isinstance(f_entry, (bytes, bytearray)):
                    img_bytes = bytes(f_entry)
            elif json_body and "image_bytes" in json_body:
                img_bytes = json_body["image_bytes"]

            api_ver = "v2" if path == "/v2/predict" else "v1"
            code, resp = self.service.handle_predict(
                image_bytes=img_bytes,
                crop_box=form.get("crop_box"),
                multiple_animals=bool(form.get("multiple_animals", False)),
                scene_hint=form.get("scene_hint"),
                image_url=form.get("image_url"),
                logits_override=form.get("logits_override"),
                api_version=api_ver,
                explain=bool(form.get("explain", False)),
            )
            return LocalAPIResponse(code, resp)

        if path == "/v1/feedback":
            body = json_body or data or {}
            code, resp = self.service.handle_feedback(body)
            return LocalAPIResponse(code, resp)

        return LocalAPIResponse(404, {"error": "not_found"})


class LocalAPIResponse:
    def __init__(self, status_code: int, payload: Dict[str, Any]) -> None:
        self.status_code = int(status_code)
        self._payload = payload

    def json(self) -> Dict[str, Any]:
        return self._payload


service = WildlifeAPIService()

try:
    from fastapi import FastAPI, File, Form, UploadFile  # type: ignore
    from fastapi.middleware.cors import CORSMiddleware  # type: ignore
    from fastapi.responses import JSONResponse  # type: ignore

    app = FastAPI(
        title="UCSC Wildlife Vision API",
        version="2.0.0",
        description="Two-Stage Animal Detection, 20-Species Classification, Calibrated Confidence, and Photo Rating",
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["GET", "POST"],
        allow_headers=["*"],
    )

    @app.get("/healthz")
    async def healthz() -> Any:
        code, payload = service.handle_healthz()
        return JSONResponse(status_code=code, content=payload)

    @app.get("/v1/classes")
    async def list_classes() -> Any:
        code, payload = service.handle_classes()
        return JSONResponse(status_code=code, content=payload)

    @app.post("/v1/predict")
    async def predict_v1(
        file: Optional[UploadFile] = File(default=None),
        crop_box: Optional[str] = Form(default=None),
        multiple_animals: bool = Form(default=False),
        scene_hint: Optional[str] = Form(default=None),
        image_url: Optional[str] = Form(default=None),
    ) -> Any:
        raw_bytes = await file.read() if file is not None else None
        code, payload = service.handle_predict(
            image_bytes=raw_bytes,
            crop_box=crop_box,
            multiple_animals=multiple_animals,
            scene_hint=scene_hint,
            image_url=image_url,
            api_version="v1",
        )
        return JSONResponse(status_code=code, content=payload)

    @app.post("/v2/predict")
    async def predict_v2(
        file: Optional[UploadFile] = File(default=None),
        crop_box: Optional[str] = Form(default=None),
        scene_hint: Optional[str] = Form(default=None),
        image_url: Optional[str] = Form(default=None),
        explain: bool = Form(default=False),
    ) -> Any:
        raw_bytes = await file.read() if file is not None else None
        code, payload = service.handle_predict(
            image_bytes=raw_bytes,
            crop_box=crop_box,
            scene_hint=scene_hint,
            image_url=image_url,
            api_version="v2",
            explain=explain,
        )
        return JSONResponse(status_code=code, content=payload)

    @app.post("/v1/feedback")
    async def submit_feedback(payload: Dict[str, Any]) -> Any:
        code, resp = service.handle_feedback(payload)
        return JSONResponse(status_code=code, content=resp)

    # /v3: fine-tuned 34-class BioCLIP 2 adapter + sightings feed used by the iOS app.
    # The model loads on the first identify request (or at startup with WILDLIFE_PRELOAD=1).
    from api.v3 import build_router  # type: ignore

    v3_router = build_router()
    app.include_router(v3_router)

    if os.environ.get("WILDLIFE_PRELOAD", "0") == "1":

        @app.on_event("startup")
        def _preload_ucsc34() -> None:
            v3_router.state.classifier  # type: ignore[attr-defined]

except Exception:
    app = None
