"""Unit tests for manifest schema, license enforcement, and image cleaning (Milestone 1)."""

from pathlib import Path
import struct
import numpy as np
import pytest

from wildlife.data.clean import (
    CorruptImageError,
    DecompressionBombError,
    UnsupportedImageFormatError,
    apply_exif_orientation,
    compute_phash,
    decode_image_bytes,
    encode_rgb_to_png_bytes,
    phash_hamming_distance,
    strip_exif_bytes,
)
from wildlife.data.licenses import (
    LicenseViolationError,
    audit_manifest_licenses,
    validate_photo_license,
)
from wildlife.data.manifest import (
    ManifestSchemaError,
    read_manifest_parquet,
    validate_manifest_schema,
    write_manifest_parquet,
)
from wildlife.schemas import MANIFEST_COLUMNS


def _make_sample_row(image_id: str = "img_M01_001", license_code: str = "cc-by") -> dict:
    return {
        "image_id": image_id,
        "observation_id": "obs_100",
        "observer_id": "user_10",
        "photo_id": "photo_100",
        "source_dataset": "inaturalist_open_data",
        "source_url": "inaturalist://photos/100",
        "photo_license": license_code,
        "photographer_credit": "Jane Doe",
        "scientific_name": "Odocoileus hemionus",
        "class_id": "M01",
        "taxon_id": 42220,
        "date_observed": "2026-10-01",
        "coarse_habitat": "Meadows",
        "region_tag": "ucsc",
        "image_path": "data/raw/img_M01_001.png",
        "image_sha256": "a" * 64,
        "phash": "0123456789abcdef",
        "width": 224,
        "height": 224,
        "label_reviewed": True,
        "crop_box": "0,0,224,224",
        "split": "train",
    }


def test_license_validation_rejects_unapproved_and_missing():
    # Failure case #11: Source license missing/unapproved -> do not ingest
    assert validate_photo_license("CC0") == "cc0"
    assert validate_photo_license("cc-by-4.0") == "cc-by"

    for bad_lic in ["", None, "cc-by-nc", "cc-by-nd", "cc-by-sa", "all-rights-reserved"]:
        with pytest.raises(LicenseViolationError):
            validate_photo_license(bad_lic)

    # CUB-200-2011 research-only restriction
    with pytest.raises(LicenseViolationError):
        validate_photo_license("cc-by", source_dataset="cub_200_2011", allow_research_only=False)


def test_audit_manifest_licenses_filters_unlicensed():
    rows = [
        _make_sample_row("img_1", "cc0"),
        _make_sample_row("img_2", "cc-by-nc"),
        _make_sample_row("img_3", ""),
    ]
    approved, summary = audit_manifest_licenses(rows)
    assert len(approved) == 1
    assert approved[0]["image_id"] == "img_1"
    assert summary["approved_count"] == 1
    assert summary["rejected_count"] == 2


def test_manifest_parquet_roundtrip_and_schema(tmp_path: Path):
    assert len(MANIFEST_COLUMNS) == 22
    row = _make_sample_row()
    out_pq = tmp_path / "manifest.parquet"
    write_manifest_parquet([row], out_pq)
    loaded = read_manifest_parquet(out_pq)
    assert len(loaded) == 1
    assert loaded[0]["image_id"] == "img_M01_001"
    assert list(loaded[0].keys()) == MANIFEST_COLUMNS

    bad_row = dict(row)
    bad_row["scientific_name"] = "Wrong species"
    with pytest.raises(ManifestSchemaError):
        validate_manifest_schema([bad_row])


def test_image_codec_exif_and_decompression_bomb():
    # Failure case #9: Rotate EXIF image, malformed image, huge decompression bomb, unsupported file type
    rgb = np.zeros((32, 48, 3), dtype=np.uint8)
    rgb[:10, :20, 0] = 250
    png_bytes = encode_rgb_to_png_bytes(rgb)
    decoded, meta = decode_image_bytes(png_bytes)
    assert decoded.shape == (32, 48, 3)
    assert meta["exif_stripped"] is True

    # Orientation 6 rotates 90 deg clockwise -> shape becomes (48, 32, 3)
    rot = apply_exif_orientation(decoded, 6)
    assert rot.shape == (48, 32, 3)

    # Unsupported file type
    with pytest.raises(UnsupportedImageFormatError):
        decode_image_bytes(b"<!DOCTYPE html><html>not an image</html>")

    # Malformed / truncated PNG
    with pytest.raises(CorruptImageError):
        decode_image_bytes(b"\x89PNG\r\n\x1a\ntruncated")

    # Decompression bomb (fake 20000 x 20000 PNG IHDR = 400M pixels > 25M limit)
    ihdr = struct.pack(">IIBBBBB", 20000, 20000, 8, 2, 0, 0, 0)
    bomb_png = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + ihdr + b"\x00\x00\x00\x00"
    with pytest.raises(DecompressionBombError):
        decode_image_bytes(bomb_png)
