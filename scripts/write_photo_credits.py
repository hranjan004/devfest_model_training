#!/usr/bin/env python3
"""Write docs/demo/PHOTO_CREDITS.md for every iNaturalist photo that appears in the demo.

Sources: the sample input photo, the Species tab reference photos
(data/app_reference/credits.json), and the demo sightings (data/app).
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "src"))

from api.store import SightingStore
from wildlife.models.ucsc34 import load_classes

DEMO_CREDIT = re.compile(r"Photo by (?P<who>.+?) \((?P<lic>CC0|CC BY)\) via iNaturalist\. (?P<url>\S+)")
LICENSE_URL = {"CC0": "https://creativecommons.org/publicdomain/zero/1.0/",
               "CC BY": "https://creativecommons.org/licenses/by/4.0/"}


def cell(who: str, lic: str, url: str) -> str:
    return f"{who} | [{lic}]({LICENSE_URL[lic]}) | [observation]({url})"


def main() -> int:
    names = {c["class_id"]: c["common_name"] for c in load_classes()}
    out = ["# Photo credits", "",
           "Every photo shown in the demo screenshots and recording comes from iNaturalist and is",
           "licensed CC0 or CC BY by its photographer. Photos were resized and re-encoded for the app.", ""]

    sample = json.loads((ROOT / "docs/demo/sample_input.json").read_text())
    out += ["## Sample photo used for the identify step", "",
            "| File | Photographer | License | Source |", "|---|---|---|---|",
            f"| `docs/demo/sample_input.jpg` | {cell(sample['photographer'], sample['license'], sample['observation_url'])} |", ""]

    credits = json.loads((ROOT / "data/app_reference/credits.json").read_text())
    out += ["## Species tab reference photos", "",
            "| Class | Species | Photographer | License | Source |", "|---|---|---|---|---|"]
    for class_id in sorted(credits, key=lambda k: list(names).index(k)):
        c = credits[class_id]
        out.append(f"| `{class_id}` | {names[class_id]} | {cell(c['photographer'], c['license'], c['observation_url'])} |")
    out.append("")

    store = SightingStore(Path(os.environ.get("WILDLIFE_APP_DATA_DIR", str(ROOT / "data/app"))))
    demo = [s for s in store.list(sort="alphabetical") if s["is_demo"]]
    out += ["## Demo sightings", "",
            "Names, star ratings, and comments on these posts are placeholders. Locations are the",
            "public coordinates of each iNaturalist observation.", "",
            "| Post | Species | Photographer | License | Source |", "|---|---|---|---|---|"]
    for s in demo:
        m = DEMO_CREDIT.search(s["description"])
        if m:
            out.append(f"| {s['name']} | {names.get(s['class_id'], s['class_id'])} | {cell(m['who'], m['lic'], m['url'])} |")
    out.append("")
    (ROOT / "docs/demo/PHOTO_CREDITS.md").write_text("\n".join(out))
    print(f"Wrote credits for 1 sample, {len(credits)} reference, {len(demo)} demo photos")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
