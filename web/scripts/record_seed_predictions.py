#!/usr/bin/env python3
"""Run every seed photo through a live `/v2/predict` and store the real model output in seed.json.

Also coarsens `place` so the demo never shows an observer's street address
("2130 El Rancho Dr, Santa Cruz, CA 95060, USA" -> "Santa Cruz, CA").

    WILDLIFE_TEST_MODE=0 WILDLIFE_BIOCLIP2_HEAD=runs/bioclip2_local_t1/bioclip2_linear_head.npz \
        uvicorn api.main:app --port 8000
    python web/scripts/record_seed_predictions.py [--api http://localhost:8000]
"""
import argparse, io, json, re, urllib.request, uuid
from datetime import date
from pathlib import Path

SEED = Path(__file__).resolve().parents[1] / "src" / "data" / "seed.json"
STREET = re.compile(r"\b(St|Dr|Rd|Way|Blvd|Ave|Ln|Ct|Pl)\.?$", re.I)
DROP = {"USA", "US", "United States"}
STATE = {"California": "CA", "US-CA": "CA"}


def coarse_place(place: str) -> str:
    parts = []
    for raw in (p.strip() for p in place.split(",")):
        raw = re.sub(r"\s+\d{5}$", "", raw)  # zip code
        raw = STATE.get(raw, raw)
        if not raw or raw in DROP or raw[0].isdigit() or STREET.search(raw):
            continue
        parts.append(raw)
    return ", ".join(parts[:2]) or "Santa Cruz area"


def post_image(api: str, data: bytes) -> dict:
    boundary = uuid.uuid4().hex
    body = (
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"p.jpg\"\r\n"
        f"Content-Type: image/jpeg\r\n\r\n"
    ).encode() + data + f"\r\n--{boundary}--\r\n".encode()
    req = urllib.request.Request(f"{api}/v2/predict", data=body, method="POST",
                                 headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    return json.load(urllib.request.urlopen(req, timeout=60))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--api", default="http://localhost:8000")
    args = ap.parse_args()
    from PIL import Image

    seed = json.loads(SEED.read_text())
    keep = ("status", "detections", "primary_index", "primary", "detector_version", "crop_version", "model_version", "explanation")
    for s in seed:
        data = urllib.request.urlopen(s["image"], timeout=30).read()
        s["width"], s["height"] = Image.open(io.BytesIO(data)).size
        res = post_image(args.api, data)
        s["prediction"] = {k: res.get(k) for k in keep}
        s["prediction"]["recorded_on"] = date.today().isoformat()
        s["place"] = coarse_place(s["place"])
        p = res.get("primary") or {}
        print(s["class_id"], res["status"], (p.get("species") or {}).get("class_id"), s["place"])
    SEED.write_text(json.dumps(seed, indent=1, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
