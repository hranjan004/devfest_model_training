"""Contract tests: stubs exist only here; production forwards every valid photo."""
import copy
import io
import json
from pathlib import Path

import pytest

pytest.importorskip("fastapi")
pytest.importorskip("httpx")
pytest.importorskip("PIL")
pytest.importorskip("requests")
from fastapi.testclient import TestClient
from PIL import Image
import requests

from api import coy_bridge

CLASSES = json.loads((Path(__file__).parent / "fixtures/coy_classes.json").read_text())


def jpeg(size=(64, 48), format="JPEG"):
    stream = io.BytesIO()
    Image.new("RGB", size, (180, 150, 70)).save(stream, format=format)
    return stream.getvalue()


class Upstream:
    def __init__(self):
        self.calls = []
        self.health = {"status": "ok", "weights_present": True, "num_classes": 34,
                       "model_version": coy_bridge.MODEL_VERSION, "model_loaded": True}
        self.prediction = self.for_class(CLASSES[0])

    @staticmethod
    def for_class(row, probability=0.923456789):
        top = {"class_id": row["class_id"], "probability": probability}
        return {"model_version": coy_bridge.MODEL_VERSION, "top": top,
                "predictions": [top], "low_confidence": False}

    def request(self, method, url, **kwargs):
        self.calls.append((method, url, kwargs))
        payload = self.health if url.endswith("/v3/health") else self.prediction
        response = requests.Response()
        response.status_code = 200
        response._content = json.dumps(payload).encode()
        return response


@pytest.fixture
def service(monkeypatch, tmp_path):
    upstream = Upstream()
    monkeypatch.setattr(coy_bridge.requests, "request", upstream.request)
    app = coy_bridge.create_app(classes=CLASSES, model_root=tmp_path, upstream_url="http://real-model.test")
    return TestClient(app), upstream, tmp_path


@pytest.mark.parametrize("row", CLASSES, ids=lambda row: row["class_id"])
def test_all_trained_classes_preserve_identity_probability_and_image(service, row):
    client, upstream, _ = service
    upstream.prediction = upstream.for_class(row)
    raw = jpeg()
    response = client.post("/v2/predict", files={"file": ("wildlife.jpg", raw, "image/jpeg")})
    assert response.status_code == 200
    result = response.json()
    detection = result["detections"][0]
    assert detection["species"] == {k: row[k] for k in ("class_id", "common_name", "scientific_name", "group")}
    assert detection["confidence_calibrated"] == upstream.prediction["top"]["probability"]
    assert detection["top_3"] == upstream.prediction["predictions"]
    assert detection["box_source"] == "full_image" and detection["detector_confidence"] == 0
    assert detection["box"] == [0, 0, 64, 48]
    assert result["model_version"] == coy_bridge.MODEL_VERSION
    assert upstream.calls[-1][0:2] == ("POST", "http://real-model.test/v3/identify")
    assert upstream.calls[-1][2]["files"]["file"][1] == raw


def test_uncertain_result_keeps_candidates_without_claiming_identification(service):
    client, upstream, _ = service
    upstream.prediction = upstream.for_class(CLASSES[0], 0.31)
    upstream.prediction["low_confidence"] = True
    response = client.post("/v2/predict", files={"file": ("wildlife.jpg", jpeg(), "image/jpeg")})
    detection = response.json()["detections"][0]
    assert detection["status"] == "uncertain"
    assert detection["species"] is None and detection["confidence_calibrated"] is None and detection["rating"] is None
    assert detection["top_3"][0]["probability"] == 0.31


@pytest.mark.parametrize("damage", ["unknown_class", "nan", "out_of_range", "no_candidates", "top_mismatch", "missing_flag", "wrong_model"])
def test_incompatible_inference_never_becomes_a_result(service, damage):
    client, upstream, _ = service
    result = copy.deepcopy(upstream.prediction)
    if damage == "unknown_class": result["top"]["class_id"] = result["predictions"][0]["class_id"] = "unknown"
    if damage == "nan": result["top"]["probability"] = result["predictions"][0]["probability"] = float("nan")
    if damage == "out_of_range": result["top"]["probability"] = result["predictions"][0]["probability"] = 1.1
    if damage == "no_candidates": result["predictions"] = []
    if damage == "top_mismatch": result["top"] = {"class_id": CLASSES[1]["class_id"], "probability": 0.5}
    if damage == "missing_flag": del result["low_confidence"]
    if damage == "wrong_model": result["model_version"] = "other-model"
    upstream.prediction = result
    assert client.post("/v2/predict", files={"file": ("image.jpg", jpeg(), "image/jpeg")}).status_code == 502


def test_upstream_failure_is_reported_without_fallback(service, monkeypatch):
    client, _, _ = service
    def unavailable(*args, **kwargs):
        raise requests.ConnectionError("offline")
    monkeypatch.setattr(coy_bridge.requests, "request", unavailable)
    assert client.post("/v2/predict", files={"file": ("image.jpg", jpeg(), "image/jpeg")}).status_code == 502
    assert client.get("/healthz").status_code == 502


def test_health_requires_exact_trained_model_and_exposes_all_classes(service):
    client, upstream, _ = service
    assert client.get("/v1/classes").json() == {"num_classes": 34, "classes": CLASSES}
    assert client.get("/healthz").json()["inference_mode"] == "whole_photo"
    upstream.health["weights_present"] = False
    assert client.get("/healthz").status_code == 503
    upstream.health["weights_present"] = True
    upstream.health["num_classes"] = 20
    assert client.get("/healthz").status_code == 503


def test_invalid_and_oversized_uploads_do_not_call_inference(service, monkeypatch):
    client, upstream, _ = service
    def send(raw, kind="image/jpeg"):
        return client.post("/v2/predict", files={"file": ("image", raw, kind)})
    assert send(b"").status_code == 413
    assert send(b"not an image").status_code == 422
    assert send(jpeg(format="GIF"), "image/gif").status_code == 415
    monkeypatch.setattr(coy_bridge, "MAX_IMAGE_PIXELS", 100)
    assert send(jpeg()).status_code == 413
    monkeypatch.setattr(coy_bridge, "MAX_UPLOAD_BYTES", 10)
    assert send(b"x" * 11).status_code == 413
    assert upstream.calls == []


def test_references_are_allowlisted_and_feedback_is_honest(service):
    client, _, root = service
    refs = root / "data/app_reference"
    refs.mkdir(parents=True)
    class_id = CLASSES[0]["class_id"]
    (refs / f"{class_id}.jpg").write_bytes(jpeg())
    (refs / "unknown.jpg").write_bytes(jpeg())
    assert client.get(f"/reference/{class_id}").headers["content-type"] == "image/jpeg"
    assert client.get("/reference/unknown").status_code == 404
    assert client.get(f"/reference/{CLASSES[1]['class_id']}").status_code == 404
    assert client.post("/v1/feedback").status_code == 503


def test_missing_model_catalog_does_not_prevent_service_from_explaining_error(tmp_path, monkeypatch):
    monkeypatch.delenv("WILDLIFE_UCSC34_RUN_DIR", raising=False)
    client = TestClient(coy_bridge.create_app(model_root=tmp_path))
    response = client.get("/v1/classes")
    assert response.status_code == 503 and "classes.json" in response.json()["detail"]
