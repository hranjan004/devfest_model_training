#!/usr/bin/env python3
"""Download one clear CC0 / CC-BY reference photo per class for the app's Species tab.

Writes data/app_reference/<class_id>.jpg and data/app_reference/credits.json.
The folder is gitignored (dataset images are never committed). Re-run to refresh.
"""

from __future__ import annotations

import io
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
sys.path.insert(0, str(ROOT / "scripts"))

from PIL import Image, ImageOps

import inat_photos
from wildlife.models.ucsc34 import Ucsc34Classifier, load_classes

OUT = ROOT / "data" / "app_reference"


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    credits_path = OUT / "credits.json"
    credits = json.loads(credits_path.read_text()) if credits_path.exists() else {}
    force = "--force" in sys.argv
    classifier = Ucsc34Classifier()
    for record in load_classes():
        class_id = record["class_id"]
        target = OUT / f"{class_id}.jpg"
        if target.exists() and class_id in credits and not force:
            continue
        # Recent research-grade photos, keeping the one the 34-class model is most sure
        # shows this species. That filters out distant, cluttered, or novelty shots.
        chosen, image, best = None, None, 0.0
        tried = 0
        for observation in inat_photos.observations(record["resolved_taxon_id"]):
            photo = inat_photos.first_photo(observation, "medium")
            if not photo:
                continue
            candidate = ImageOps.exif_transpose(
                Image.open(io.BytesIO(inat_photos.download(photo["url"])))
            ).convert("RGB")
            top = classifier.predict_image(candidate, top_k=1)["top"]
            tried += 1
            landscape = candidate.width >= candidate.height
            score = top["probability"] + (0.002 if landscape else 0.0)
            if top["class_id"] == class_id and score > best:
                chosen, image, best = photo, candidate, score
            if tried >= 8 or (best >= 0.992 and tried >= 3):
                break
        if not chosen:
            print(f"{class_id} {record['common_name']}: no CC0/CC-BY photo found", flush=True)
            continue
        image.save(target, format="JPEG", quality=88)
        credits[class_id] = {k: chosen[k] for k in ("photographer", "license", "observation_url", "photo_id")}
        credits_path.write_text(json.dumps(credits, indent=2))
        print(f"{class_id} {record['common_name']}: {best:.3f} {chosen['photographer']} ({chosen['license']})", flush=True)
    print(f"{len(list(OUT.glob('*.jpg')))} reference photos in {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
