#!/usr/bin/env python3
"""Fill the app with demo sightings so the feed, rankings, and maps have content.

Each demo sighting is a real research-grade iNaturalist observation made near the
UCSC campus: its CC0 / CC-BY photo, its public coordinates, and a credit line. The
species label and confidence come from running the 34-class model on the photo, and
photos the model gets wrong or is unsure about are skipped. Star ratings, comments,
and names are invented placeholders. Rows are flagged is_demo.

    python scripts/seed_demo_sightings.py           # add demo sightings (once)
    python scripts/seed_demo_sightings.py --clear   # remove them again
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import io
import os
from pathlib import Path
import random
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "src"))
sys.path.insert(0, str(ROOT / "scripts"))

from api.store import SightingStore

CAMPUS = {"lat": 36.9916, "lng": -122.0583}
NAMES = {
    "M01": "Deerly", "M02": "Whiskers", "M03": "Bob", "M04": "Ember", "M05": "Rocky",
    "M06": "Stripe", "M07": "Digger", "M08": "Nutmeg", "M09": "Ash", "M10": "Clover",
    "B01": "Tom", "B02": "Plume", "B03": "Blue", "B04": "Scrubby", "B05": "Poe",
    "B06": "Acorn", "B07": "Zip", "B08": "Robin", "B09": "Juno", "B10": "Towhee",
    "I01": "Sammy", "T01": "Big Red", "T02": "Doug", "T03": "Madrone", "T04": "Old Oak",
    "T05": "Tan", "T06": "Bay", "T07": "Maple", "G01": "Monarch", "G02": "Tiger",
    "G03": "Bumble", "G04": "Millie", "G05": "Dot", "G06": "Jacket",
}
COMMENTS = ["Great find", "I saw one near here last week", "What a clear photo", "Love this one", "Nice spot"]


def data_root() -> Path:
    return Path(os.environ.get("WILDLIFE_APP_DATA_DIR", str(ROOT / "data" / "app")))


def main() -> int:
    store = SightingStore(data_root())
    if "--clear" in sys.argv:
        print(f"Removed {store.delete_demo()} demo sightings.")
        return 0
    if store.demo_count() > 0:
        print("Demo sightings already exist. Use --clear to remove them first.")
        return 0

    from PIL import Image, ImageOps

    import inat_photos
    from api.v3 import _to_stored_jpeg
    from wildlife.models.ucsc34 import Ucsc34Classifier

    classifier = Ucsc34Classifier()
    rng = random.Random(34)
    now = datetime.now(timezone.utc)
    made = 0
    for record in classifier.classes:
        class_id = record["class_id"]
        picked = None
        for radius_km in (3, 15):
            for observation in inat_photos.observations(
                record["resolved_taxon_id"], radius=radius_km, order_by="votes", **CAMPUS
            ):
                if observation.get("obscured") or observation.get("geoprivacy") or observation.get("taxon_geoprivacy"):
                    continue
                coordinates = (observation.get("geojson") or {}).get("coordinates")
                photo = inat_photos.first_photo(observation, "large")
                if not coordinates or not photo:
                    continue
                image = ImageOps.exif_transpose(
                    Image.open(io.BytesIO(inat_photos.download(photo["url"])))
                ).convert("RGB")
                prediction = classifier.predict_image(image)
                if prediction["top"]["class_id"] != class_id or prediction["low_confidence"]:
                    continue  # keep the demo to photos the model identifies confidently
                picked = (image, prediction, photo, float(coordinates[1]), float(coordinates[0]))
                break
            if picked:
                break
        if not picked:
            print(f"{class_id} {record['common_name']}: no suitable observation near campus", flush=True)
            continue
        image, prediction, photo, latitude, longitude = picked
        created = now - timedelta(hours=rng.randint(2, 24 * 20))
        row = store.create(
            name=NAMES.get(class_id, record["common_name"]),
            description=f"Demo sighting. Photo by {photo['photographer']} ({photo['license']}) via iNaturalist. {photo['observation_url']}",
            prediction=prediction,
            jpeg_bytes=_to_stored_jpeg(image),
            latitude=latitude,
            longitude=longitude,
            is_demo=True,
            created_at=created.isoformat(timespec="seconds"),
        )
        for voter in range(rng.randint(2, 7)):
            store.rate(row["id"], f"demo-device-{voter}", rng.choice([3, 4, 4, 5, 5, 5]))
        for text in rng.sample(COMMENTS, rng.randint(0, 3)):
            store.add_comment(row["id"], "Demo user", text)
        made += 1
        print(f"{class_id} {row['name']}: {record['common_name']} {prediction['top']['probability']:.3f} at {latitude:.4f},{longitude:.4f}", flush=True)
    print(f"Added {made} demo sightings.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
