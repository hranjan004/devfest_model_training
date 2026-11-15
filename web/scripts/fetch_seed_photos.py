#!/usr/bin/env python3
"""Fetch demo feed photos: CC0/CC-BY research-grade iNaturalist observations near UCSC.

Writes web/src/data/seed.json. Locations are rounded to 2 decimals (~1 km) so the
demo never shows exact positions. One API call per species, 1.1 s apart.
"""
import json, sys, time, urllib.parse, urllib.request
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[2]
species = yaml.safe_load((ROOT / "configs/species.yaml").read_text())["species"]
out = []
for sp in species:
    q = urllib.parse.urlencode({
        "taxon_name": sp["scientific_name"], "quality_grade": "research", "photos": "true",
        "photo_license": "cc0,cc-by", "lat": 36.99, "lng": -122.06, "radius": 25,
        "per_page": 3, "order_by": "votes",
    })
    req = urllib.request.Request(f"https://api.inaturalist.org/v1/observations?{q}",
                                 headers={"User-Agent": "UCSC-Wildlife-Vision/2.1 (academic project)"})
    results = json.load(urllib.request.urlopen(req, timeout=30))["results"]
    for obs in results[:2]:
        if obs["taxon"]["name"].split(" ")[:2] != sp["scientific_name"].split(" ")[:2]:
            continue
        ph = next((p for p in obs["photos"] if p.get("license_code") in ("cc0", "cc-by")), None)
        if not ph or not obs.get("location"):
            continue
        lat, lng = (round(float(v), 2) for v in obs["location"].split(","))
        out.append({
            "id": f"inat-{obs['id']}", "class_id": sp["class_id"],
            "image": ph["url"].replace("square.", "medium."),
            "attribution": ph["attribution"], "license": ph["license_code"],
            "source": f"https://www.inaturalist.org/observations/{obs['id']}",
            "observed_on": obs.get("observed_on") or "", "lat": lat, "lng": lng,
            "place": obs.get("place_guess") or "Santa Cruz area",
            "observer": (obs.get("user") or {}).get("name") or (obs.get("user") or {}).get("login") or "iNaturalist observer",
        })
    print(sp["class_id"], len([o for o in out if o["class_id"] == sp["class_id"]]), file=sys.stderr)
    time.sleep(1.1)
(ROOT / "web/src/data/seed.json").write_text(json.dumps(out, indent=1))
print(len(out), "photos")
