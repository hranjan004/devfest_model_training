"""Native coy response adapter backed only by the real 34-class BioCLIP API.

This service does not detect animals or synthesize predictions. Full-image boxes
preserve the native response schema; photo-quality values are image heuristics.
Run from the repository with ``scripts/run_coy.sh``.
"""
from __future__ import annotations

import io
import json
import math
import os
from functools import lru_cache
from pathlib import Path

import numpy as np
import requests
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from PIL import Image, ImageOps, UnidentifiedImageError

from wildlife.models.ucsc34 import MODEL_VERSION
from wildlife.quality.scoring import compute_identification_ready_rating, score_photograph

MAX_UPLOAD_BYTES = 10 * 1024 * 1024
MAX_IMAGE_PIXELS = 25_000_000
DETECTOR_VERSION = "none-whole-image"


def create_app(*, classes=None, model_root=None, upstream_url=None):
    """Allow test catalogs without loading trained weights or replacing inference."""
    root = Path(model_root or os.environ.get("DEVFEST_MODEL_ROOT") or Path(__file__).resolve().parents[1])
    run_dir = Path(os.environ.get("WILDLIFE_UCSC34_RUN_DIR", str(root / "runs/ucsc34_bioclip_v4")))
    upstream_url = (upstream_url or os.environ.get("WILDLIFE_V4_URL", "http://127.0.0.1:8080")).rstrip("/")
    app = FastAPI(title="coy BioCLIP compatibility service", version="1.0")

    @lru_cache(maxsize=1)
    def catalog():
        try:
            rows = classes if classes is not None else json.loads((run_dir / "classes.json").read_text())
            required = ("class_id", "common_name", "scientific_name", "group")
            if len(rows) != 34 or any(not all(isinstance(row.get(k), str) and row[k] for k in required) for row in rows):
                raise ValueError("Expected the trained 34-class catalog")
            by_id = {row["class_id"]: row for row in rows}
            if len(by_id) != 34:
                raise ValueError("Duplicate class IDs")
            return rows, by_id
        except (OSError, ValueError, TypeError, AttributeError) as exc:
            raise HTTPException(503, "Trained 34-class catalog is missing or invalid. Restore classes.json in WILDLIFE_UCSC34_RUN_DIR.") from exc

    def upstream(method, path, **kwargs):
        try:
            response = requests.request(method, upstream_url + path, timeout=(4, 90), **kwargs)
            response.raise_for_status()
            result = response.json()
            if not isinstance(result, dict):
                raise ValueError("Expected an object")
            return result
        except (requests.RequestException, ValueError) as exc:
            raise HTTPException(502, "The real BioCLIP-v4 service is unavailable or returned an invalid response.") from exc

    @app.get("/healthz")
    def health():
        rows, _ = catalog()
        status = upstream("GET", "/v3/health")
        if (status.get("status") != "ok" or not status.get("weights_present")
                or status.get("num_classes") != len(rows) or status.get("model_version") != MODEL_VERSION):
            raise HTTPException(503, "The upstream classifier does not match the trained 34-class BioCLIP-v4 model.")
        return {"ready": True, "model_version": status["model_version"],
                "detector_version": DETECTOR_VERSION, "num_classes": len(rows),
                "inference_mode": "whole_photo", "quality_method": "image_heuristics",
                "model_loaded": status.get("model_loaded", False)}

    @app.get("/v1/classes")
    def list_classes():
        rows, _ = catalog()
        return {"num_classes": len(rows), "classes": rows}

    @app.get("/reference/{class_id}")
    def reference(class_id: str):
        _, by_id = catalog()
        if class_id not in by_id:
            raise HTTPException(404, "Unknown class")
        path = root / "data/app_reference" / f"{class_id}.jpg"
        if not path.is_file():
            raise HTTPException(404, "No reference photo for this class")
        return FileResponse(path, media_type="image/jpeg")

    @app.post("/v2/predict")
    def predict(file: UploadFile = File(...)):
        # A sync endpoint runs its blocking image work and requests in a worker.
        raw = file.file.read(MAX_UPLOAD_BYTES + 1)
        if not raw or len(raw) > MAX_UPLOAD_BYTES:
            raise HTTPException(413, "Upload must contain an image no larger than 10 MB.")
        try:
            with Image.open(io.BytesIO(raw)) as source:
                if source.format not in {"JPEG", "PNG"}:
                    raise HTTPException(415, "Use JPEG or PNG.")
                if source.width * source.height > MAX_IMAGE_PIXELS:
                    raise HTTPException(413, "Image exceeds 25 megapixels.")
                rgb = ImageOps.exif_transpose(source).convert("RGB")
        except (UnidentifiedImageError, OSError, Image.DecompressionBombError) as exc:
            raise HTTPException(422, "Invalid image.") from exc
        _, by_id = catalog()
        # Send original image bytes; neither the demo nor unknown images bypass inference.
        result = upstream("POST", "/v3/identify", files={"file": ("image", raw, file.content_type or "application/octet-stream")})
        try:
            if result["model_version"] != MODEL_VERSION or type(result["low_confidence"]) is not bool:
                raise ValueError("Incompatible model response")
            top = result["top"]
            class_id, probability = top["class_id"], float(top["probability"])
            candidates = [{"class_id": p["class_id"], "probability": float(p["probability"])} for p in result["predictions"]]
            if not candidates or len(candidates) > 34 or candidates[0] != {"class_id": class_id, "probability": probability}:
                raise ValueError("Inconsistent top prediction")
            if len({p["class_id"] for p in candidates}) != len(candidates):
                raise ValueError("Duplicate candidates")
            for p in candidates:
                if p["class_id"] not in by_id or not math.isfinite(p["probability"]) or not 0 <= p["probability"] <= 1:
                    raise ValueError("Invalid class or probability")
        except (KeyError, TypeError, ValueError, OverflowError) as exc:
            raise HTTPException(502, "The trained classifier returned an incompatible prediction.") from exc
        record = by_id[class_id]
        quality = score_photograph(np.asarray(rgb)).to_dict()
        status = "uncertain" if result["low_confidence"] else "identified"
        species = {k: record[k] for k in ("class_id", "common_name", "scientific_name", "group")} if status == "identified" else None
        detection = {"box": [0, 0, rgb.width, rgb.height], "box_source": "full_image",
                     "detector_confidence": 0, "status": status, "species": species,
                     "confidence_calibrated": probability if status == "identified" else None,
                     "top_3": candidates, "quality": quality,
                     "rating": compute_identification_ready_rating(quality["overall"], probability, status)}
        return {"status": status, "detections": [detection], "primary_index": 0,
                "model_version": result["model_version"], "detector_version": DETECTOR_VERSION,
                "explanation": "Whole-photo classification across 34 trained classes. No animal detection was run. Photo-quality scores are image heuristics.",
                "recorded_on": None}

    @app.post("/v1/feedback")
    def feedback():
        raise HTTPException(503, "Correction review is not connected in this local service.")

    return app


app = create_app()
