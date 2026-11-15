"""Tests for the `/v3` app endpoints with a stub classifier (no weights needed)."""

import io
from pathlib import Path

import pytest

fastapi = pytest.importorskip("fastapi")
pytest.importorskip("PIL")
pytest.importorskip("httpx")

from fastapi import FastAPI
from fastapi.testclient import TestClient
from PIL import Image

from api.v3 import V3State, build_router

CLASSES = [
    {"class_id": "M02", "index": 0, "common_name": "Coyote", "scientific_name": "Canis latrans", "group": "large_mammal"},
    {"class_id": "I01", "index": 1, "common_name": "Banana slug (genus)", "scientific_name": "Ariolimax", "group": "gastropod"},
]


class StubClassifier:
    def __init__(self):
        self.calls = 0

    def predict_image(self, image, top_k=3):
        self.calls += 1
        preds = [
            {**{k: CLASSES[1][k] for k in ("class_id", "common_name", "scientific_name", "group")}, "probability": 0.93},
            {**{k: CLASSES[0][k] for k in ("class_id", "common_name", "scientific_name", "group")}, "probability": 0.07},
        ][:top_k]
        return {"model_version": "stub", "top": preds[0], "predictions": preds, "low_confidence": False}


def jpeg(size=(64, 48)) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", size, (200, 180, 40)).save(buf, format="JPEG")
    return buf.getvalue()


@pytest.fixture()
def client(tmp_path: Path):
    stub = StubClassifier()
    ref = tmp_path / "ref"
    ref.mkdir()
    (ref / "I01.jpg").write_bytes(jpeg())
    (ref / "credits.json").write_text('{"I01": {"photographer": "Pat", "license": "CC BY"}, "M02": {"photographer": "X", "license": "CC0"}}')
    state = V3State(store_root=tmp_path / "app", classifier_factory=lambda: stub, classes=CLASSES, reference_dir=ref)
    app = FastAPI()
    app.include_router(build_router(state))
    return TestClient(app), stub


def test_health_species_and_lazy_model(client):
    c, stub = client
    h = c.get("/v3/health").json()
    assert h["num_classes"] == 2 and h["model_loaded"] is False
    species = c.get("/v3/species").json()["species"]
    assert [s["class_id"] for s in species] == ["M02", "I01"]
    assert all(s["sighting_count"] == 0 and s["cover_image_url"] is None for s in species)
    assert stub.calls == 0
    # Only species whose reference file exists advertise one.
    assert species[0]["reference_image_url"] is None and species[0]["reference_credit"] is None
    assert species[1]["reference_credit"] == "Photo by Pat (CC BY) via iNaturalist"
    assert c.get(species[1]["reference_image_url"]).headers["content-type"] == "image/jpeg"
    assert c.get("/v3/species/M02/image").status_code == 404
    assert c.get("/v3/species/ZZZ/image").status_code == 404


def test_demo_rows_can_be_cleared(tmp_path):
    from api.store import SightingStore

    store = SightingStore(tmp_path / "s")
    pred = StubClassifier().predict_image(None)
    kwargs = dict(description="", prediction=pred, jpeg_bytes=jpeg(), latitude=None, longitude=None)
    real = store.create(name="Real", **kwargs)
    demo = store.create(name="Demo", is_demo=True, created_at="2026-01-01T00:00:00+00:00", **kwargs)
    store.rate(demo["id"], "d", 5)
    store.add_comment(demo["id"], "Demo user", "hi")
    assert (real["is_demo"], demo["is_demo"], store.demo_count()) == (False, True, 1)
    assert store.delete_demo() == 1
    assert [s["name"] for s in store.list()] == ["Real"]
    assert not store.image_path(demo["id"]).exists() and store.comments(demo["id"]) == []


def test_identify_and_upload_validation(client):
    c, _ = client
    r = c.post("/v3/identify", files={"file": ("a.jpg", jpeg(), "image/jpeg")})
    assert r.status_code == 200 and r.json()["top"]["class_id"] == "I01"
    assert c.post("/v3/identify", files={"file": ("a.jpg", b"not an image", "image/jpeg")}).status_code == 422
    gif = io.BytesIO()
    Image.new("RGB", (8, 8)).save(gif, format="GIF")
    assert c.post("/v3/identify", files={"file": ("a.gif", gif.getvalue(), "image/gif")}).status_code == 415


def test_sighting_lifecycle(client):
    c, _ = client
    r = c.post(
        "/v3/sightings",
        files={"file": ("slug.jpg", jpeg(), "image/jpeg")},
        data={"name": "Sammy", "description": "By the redwoods", "latitude": "36.9916", "longitude": "-122.0583"},
    )
    assert r.status_code == 201
    s = r.json()
    assert s["common_name"] == "Banana slug (genus)" and s["confidence"] == 0.93
    assert s["rating_count"] == 0 and s["comment_count"] == 0 and s["my_rating"] is None
    sid = s["id"]

    img = c.get(s["image_url"])
    assert img.status_code == 200 and img.headers["content-type"] == "image/jpeg"

    assert c.post(f"/v3/sightings/{sid}/ratings", json={"stars": 5}).status_code == 400
    assert c.post(f"/v3/sightings/{sid}/ratings", json={"stars": 9}, headers={"X-Device-Id": "a"}).status_code == 422
    c.post(f"/v3/sightings/{sid}/ratings", json={"stars": 5}, headers={"X-Device-Id": "a"})
    c.post(f"/v3/sightings/{sid}/ratings", json={"stars": 2}, headers={"X-Device-Id": "a"})  # replaces
    rated = c.post(f"/v3/sightings/{sid}/ratings", json={"stars": 4}, headers={"X-Device-Id": "b"}).json()
    assert rated["rating_count"] == 2 and rated["rating_average"] == 3.0 and rated["my_rating"] == 4

    assert c.post(f"/v3/sightings/{sid}/comments", json={"text": "  "}).status_code == 422
    made = c.post(f"/v3/sightings/{sid}/comments", json={"author": "Dean", "text": "Great find"})
    assert made.status_code == 201
    assert [m["text"] for m in c.get(f"/v3/sightings/{sid}/comments").json()["comments"]] == ["Great find"]

    c.post("/v3/sightings", files={"file": ("b.jpg", jpeg(), "image/jpeg")}, data={"name": "Alfie"})
    by_name = c.get("/v3/sightings", params={"sort": "alphabetical"}).json()["sightings"]
    assert [x["name"] for x in by_name] == ["Alfie", "Sammy"]
    top = c.get("/v3/sightings", params={"sort": "top_rated"}, headers={"X-Device-Id": "a"}).json()["sightings"]
    assert top[0]["name"] == "Sammy" and top[0]["my_rating"] == 2 and top[0]["comment_count"] == 1
    assert top[1]["latitude"] is None

    slug = [x for x in c.get("/v3/species").json()["species"] if x["class_id"] == "I01"][0]
    assert slug["sighting_count"] == 2 and slug["cover_image_url"].endswith("/image")
    assert c.get("/v3/sightings", params={"class_id": "M02"}).json()["sightings"] == []


def test_sighting_rejects_bad_input(client):
    c, _ = client
    f = {"file": ("a.jpg", jpeg(), "image/jpeg")}
    assert c.post("/v3/sightings", files=f, data={"name": "  "}).status_code == 422
    assert c.post("/v3/sightings", files=f, data={"name": "A", "latitude": "36.9"}).status_code == 422
    assert c.post("/v3/sightings", files=f, data={"name": "A", "latitude": "99", "longitude": "0"}).status_code == 422
    assert c.get("/v3/sightings", params={"sort": "bogus"}).status_code == 422
    assert c.get("/v3/sightings/nope").status_code == 404
