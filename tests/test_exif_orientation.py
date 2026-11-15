"""Regression: JPEGs carrying an EXIF IFD (every iPhone photo) must decode, not 500."""

import io

from PIL import Image

from wildlife.data.clean import _parse_exif_orientation, decode_image_bytes, detect_mime_and_dimensions


def _jpeg_with_orientation(orientation: int) -> bytes:
    exif = Image.Exif()
    exif[0x0112] = orientation
    buf = io.BytesIO()
    Image.new("RGB", (64, 48), (90, 120, 80)).save(buf, "JPEG", exif=exif.tobytes())
    return buf.getvalue()


def test_jpeg_with_exif_orientation_decodes():
    raw = _jpeg_with_orientation(6)
    mime, width, height, orientation = detect_mime_and_dimensions(raw)[:4]
    assert (mime, width, height, orientation) == ("image/jpeg", 64, 48, 6)
    decoded, _meta = decode_image_bytes(raw)
    assert decoded.ndim == 3


def test_big_endian_tiff_orientation():
    # "MM" header, IFD at offset 8, one entry: tag 0x0112, type SHORT, count 1, value 3
    tiff = b"MM\x00\x2a\x00\x00\x00\x08" + b"\x00\x01" + b"\x01\x12\x00\x03\x00\x00\x00\x01\x00\x03\x00\x00"
    assert _parse_exif_orientation(tiff) == 3
