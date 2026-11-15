#!/usr/bin/env python3
"""Verify every taxon_id in configs/species.yaml against the iNaturalist v1 API.

For each class, checks that the configured taxon_id resolves to an active taxon
whose scientific name matches `scientific_name` and whose rank is `species`.
Exits non-zero on any mismatch so it can gate a data pull (Milestone 6).

Uses one batched API call (well under the 1 req/s limit in data_sources.yaml).

Usage:
    python3 scripts/verify_taxon_ids.py
"""

from __future__ import annotations

import json
from pathlib import Path
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT / "src") not in sys.path:
    sys.path.insert(0, str(ROOT / "src"))

from wildlife.schemas import load_species_taxonomy

API = "https://api.inaturalist.org/v1/taxa/{ids}"
USER_AGENT = "UCSC-Wildlife-Vision/1.0 (academic project)"


def fetch_taxa(taxon_ids: list[int]) -> dict[int, dict]:
    url = API.format(ids=",".join(str(t) for t in taxon_ids))
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.load(resp)
    return {int(r["id"]): r for r in payload.get("results", [])}


def main() -> int:
    records = load_species_taxonomy()
    found = fetch_taxa([r.taxon_id for r in records])
    failures = 0
    for rec in records:
        taxon = found.get(rec.taxon_id)
        if taxon is None:
            status = "FAIL  taxon_id does not exist"
        elif taxon.get("name") != rec.scientific_name:
            status = f"FAIL  resolves to {taxon.get('name')!r} ({taxon.get('preferred_common_name')})"
        elif taxon.get("rank") != "species":
            status = f"FAIL  rank is {taxon.get('rank')!r}, expected 'species'"
        elif not taxon.get("is_active", True):
            status = "FAIL  taxon is inactive"
        else:
            status = "ok"
        if status != "ok":
            failures += 1
        print(f"{rec.class_id}  {rec.taxon_id:>7}  {rec.scientific_name:<28} {status}")
    print(f"\n{len(records) - failures}/{len(records)} taxon IDs verified")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
