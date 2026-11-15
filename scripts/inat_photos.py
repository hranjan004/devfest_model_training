"""Shared helper: find CC0 / CC-BY research-grade iNaturalist photos for a taxon."""

from __future__ import annotations

import json
import os
import time
from typing import Any, Dict, Iterator, Optional
import urllib.parse
import urllib.request

API = "https://api.inaturalist.org/v1/observations"
USER_AGENT = os.environ.get(
    "INAT_USER_AGENT", "UCSC-Wildlife-Vision/2.1 (academic-research; contact=hranjan@ucsc.edu)"
)
ALLOWED = {"cc0": "CC0", "cc-by": "CC BY"}
_last_call = 0.0


def _get(url: str) -> bytes:
    """GET with the project's 1 request/second iNaturalist rate limit."""
    global _last_call
    wait = 1.0 - (time.time() - _last_call)
    if wait > 0:
        time.sleep(wait)
    _last_call = time.time()
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def download(url: str) -> bytes:
    return _get(url)


def observations(taxon_id: int, **extra: Any) -> Iterator[Dict[str, Any]]:
    params = {
        "taxon_id": taxon_id,
        "photo_license": "cc0,cc-by",
        "quality_grade": "research",
        "photos": "true",
        "per_page": 30,
        **extra,
    }
    payload = json.loads(_get(API + "?" + urllib.parse.urlencode(params)))
    yield from payload.get("results", [])


def first_photo(observation: Dict[str, Any], size: str) -> Optional[Dict[str, Any]]:
    """First CC0 / CC-BY photo of an observation, with its credit line."""
    for photo in observation.get("photos", []):
        code = (photo.get("license_code") or "").lower()
        if code not in ALLOWED or not photo.get("url"):
            continue
        user = observation.get("user") or {}
        return {
            "photo_id": photo["id"],
            "url": photo["url"].replace("/square.", f"/{size}."),
            "license": ALLOWED[code],
            "photographer": user.get("name") or user.get("login") or "iNaturalist user",
            "observation_url": observation.get("uri") or f"https://www.inaturalist.org/observations/{observation['id']}",
        }
    return None
