"""SQLite store for app sightings, star ratings, and comments (`/v3` endpoints)."""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
import json
import sqlite3
import threading
from typing import Any, Dict, List, Optional
import uuid

SCHEMA = """
CREATE TABLE IF NOT EXISTS sightings (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    class_id TEXT NOT NULL,
    confidence REAL NOT NULL,
    low_confidence INTEGER NOT NULL DEFAULT 0,
    predictions TEXT NOT NULL,
    model_version TEXT NOT NULL,
    latitude REAL,
    longitude REAL,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS ratings (
    sighting_id TEXT NOT NULL REFERENCES sightings(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,
    stars INTEGER NOT NULL CHECK (stars BETWEEN 1 AND 5),
    created_at TEXT NOT NULL,
    PRIMARY KEY (sighting_id, device_id)
);
CREATE TABLE IF NOT EXISTS comments (
    id TEXT PRIMARY KEY,
    sighting_id TEXT NOT NULL REFERENCES sightings(id) ON DELETE CASCADE,
    author TEXT NOT NULL,
    text TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_comments_sighting ON comments(sighting_id, created_at);
CREATE INDEX IF NOT EXISTS idx_sightings_class ON sightings(class_id);
"""

SORTS = {
    "newest": "s.created_at DESC",
    "top_rated": "rating_average DESC, rating_count DESC, s.created_at DESC",
    "most_comments": "comment_count DESC, s.created_at DESC",
    "alphabetical": "s.name COLLATE NOCASE ASC",
}

_SELECT = """
SELECT s.*,
       COALESCE((SELECT AVG(stars) FROM ratings r WHERE r.sighting_id = s.id), 0) AS rating_average,
       (SELECT COUNT(*) FROM ratings r WHERE r.sighting_id = s.id) AS rating_count,
       (SELECT COUNT(*) FROM comments c WHERE c.sighting_id = s.id) AS comment_count,
       (SELECT stars FROM ratings r WHERE r.sighting_id = s.id AND r.device_id = :device_id) AS my_rating
FROM sightings s
"""


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class SightingStore:
    def __init__(self, root: Path) -> None:
        self.root = Path(root)
        self.image_dir = self.root / "images"
        self.image_dir.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        self._db = sqlite3.connect(str(self.root / "sightings.sqlite3"), check_same_thread=False)
        self._db.row_factory = sqlite3.Row
        self._db.execute("PRAGMA foreign_keys = ON")
        self._db.executescript(SCHEMA)
        columns = {row["name"] for row in self._db.execute("PRAGMA table_info(sightings)")}
        if "is_demo" not in columns:
            self._db.execute("ALTER TABLE sightings ADD COLUMN is_demo INTEGER NOT NULL DEFAULT 0")
        self._db.commit()

    def image_path(self, sighting_id: str) -> Path:
        return self.image_dir / f"{sighting_id}.jpg"

    def _row(self, row: sqlite3.Row) -> Dict[str, Any]:
        data = dict(row)
        data["predictions"] = json.loads(data["predictions"])
        data["low_confidence"] = bool(data["low_confidence"])
        data["is_demo"] = bool(data.get("is_demo", 0))
        data["rating_average"] = round(float(data["rating_average"]), 2)
        data["image_url"] = f"/v3/sightings/{data['id']}/image"
        return data

    def create(
        self,
        *,
        name: str,
        description: str,
        prediction: Dict[str, Any],
        jpeg_bytes: bytes,
        latitude: Optional[float],
        longitude: Optional[float],
        is_demo: bool = False,
        created_at: Optional[str] = None,
    ) -> Dict[str, Any]:
        sighting_id = uuid.uuid4().hex
        self.image_path(sighting_id).write_bytes(jpeg_bytes)
        with self._lock:
            self._db.execute(
                "INSERT INTO sightings (id, name, description, class_id, confidence, low_confidence,"
                " predictions, model_version, latitude, longitude, created_at, is_demo)"
                " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    sighting_id,
                    name,
                    description,
                    prediction["top"]["class_id"],
                    prediction["top"]["probability"],
                    int(prediction["low_confidence"]),
                    json.dumps(prediction["predictions"]),
                    prediction["model_version"],
                    latitude,
                    longitude,
                    created_at or _now(),
                    int(is_demo),
                ),
            )
            self._db.commit()
        return self.get(sighting_id)  # type: ignore[return-value]

    def get(self, sighting_id: str, device_id: str = "") -> Optional[Dict[str, Any]]:
        with self._lock:
            row = self._db.execute(
                _SELECT + " WHERE s.id = :id", {"id": sighting_id, "device_id": device_id}
            ).fetchone()
        return self._row(row) if row else None

    def list(
        self, sort: str = "newest", class_id: Optional[str] = None, device_id: str = ""
    ) -> List[Dict[str, Any]]:
        query = _SELECT
        params: Dict[str, Any] = {"device_id": device_id}
        if class_id:
            query += " WHERE s.class_id = :class_id"
            params["class_id"] = class_id
        query += f" ORDER BY {SORTS.get(sort, SORTS['newest'])}"
        with self._lock:
            rows = self._db.execute(query, params).fetchall()
        return [self._row(r) for r in rows]

    def delete(self, sighting_id: str) -> None:
        """Remove one sighting with its ratings, comments, and image file."""
        with self._lock:
            self._db.execute("DELETE FROM sightings WHERE id = ?", (sighting_id,))
            self._db.commit()
        self.image_path(sighting_id).unlink(missing_ok=True)

    def demo_count(self) -> int:
        with self._lock:
            return int(self._db.execute("SELECT COUNT(*) FROM sightings WHERE is_demo = 1").fetchone()[0])

    def delete_demo(self) -> int:
        """Remove every demo sighting with its ratings, comments, and image file."""
        with self._lock:
            ids = [r["id"] for r in self._db.execute("SELECT id FROM sightings WHERE is_demo = 1")]
            self._db.execute("DELETE FROM sightings WHERE is_demo = 1")
            self._db.commit()
        for sighting_id in ids:
            self.image_path(sighting_id).unlink(missing_ok=True)
        return len(ids)

    def species_stats(self) -> Dict[str, Dict[str, Any]]:
        """Per class: sighting count and the newest sighting (for the species card photo)."""
        with self._lock:
            rows = self._db.execute(
                "SELECT class_id, COUNT(*) AS n, MAX(created_at) AS latest FROM sightings GROUP BY class_id"
            ).fetchall()
            stats: Dict[str, Dict[str, Any]] = {}
            for row in rows:
                newest = self._db.execute(
                    "SELECT id FROM sightings WHERE class_id = ? ORDER BY created_at DESC LIMIT 1",
                    (row["class_id"],),
                ).fetchone()
                stats[row["class_id"]] = {
                    "sighting_count": int(row["n"]),
                    "cover_image_url": f"/v3/sightings/{newest['id']}/image",
                }
        return stats

    def rate(self, sighting_id: str, device_id: str, stars: int) -> None:
        with self._lock:
            self._db.execute(
                "INSERT INTO ratings (sighting_id, device_id, stars, created_at) VALUES (?, ?, ?, ?)"
                " ON CONFLICT(sighting_id, device_id) DO UPDATE SET stars = excluded.stars,"
                " created_at = excluded.created_at",
                (sighting_id, device_id, int(stars), _now()),
            )
            self._db.commit()

    def comments(self, sighting_id: str) -> List[Dict[str, Any]]:
        with self._lock:
            rows = self._db.execute(
                "SELECT id, author, text, created_at FROM comments WHERE sighting_id = ?"
                " ORDER BY created_at ASC, rowid ASC",
                (sighting_id,),
            ).fetchall()
        return [dict(r) for r in rows]

    def add_comment(self, sighting_id: str, author: str, text: str) -> Dict[str, Any]:
        comment = {"id": uuid.uuid4().hex, "author": author, "text": text, "created_at": _now()}
        with self._lock:
            self._db.execute(
                "INSERT INTO comments (id, sighting_id, author, text, created_at) VALUES (?, ?, ?, ?, ?)",
                (comment["id"], sighting_id, author, text, comment["created_at"]),
            )
            self._db.commit()
        return comment
