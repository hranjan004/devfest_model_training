"""Image validation, EXIF stripping, perceptual hashing (pHash), and PNG codec."""

from __future__ import annotations

import hashlib
import math
import struct
from typing import Dict, Optional, Tuple
import zlib

import numpy as np

MAX_UPLOAD_BYTES_DEFAULT = 10 * 1024 * 1024  # 10 MB
MAX_IMAGE_PIXELS_DEFAULT = 25_000_000  # 25 MP decompression bomb threshold
MIN_IMAGE_DIMENSION = 16


class ImageValidationError(ValueError):
    """Base exception for invalid or unsafe input images."""


class UnsupportedImageFormatError(ImageValidationError):
    """Raised when image bytes do not match JPEG, PNG, or HEIC signatures."""


class CorruptImageError(ImageValidationError):
    """Raised when an image header or payload is truncated or corrupt."""


class DecompressionBombError(ImageValidationError):
    """Raised when image dimensions or uncompressed size exceed safety limits."""


def detect_mime_and_dimensions(
    raw_bytes: bytes,
    max_bytes: int = MAX_UPLOAD_BYTES_DEFAULT,
    max_pixels: int = MAX_IMAGE_PIXELS_DEFAULT,
) -> Tuple[str, int, int, int]:
    """Inspect magic bytes, dimensions, and EXIF orientation before full decode."""
    if not raw_bytes:
        raise CorruptImageError("Empty image payload.")
    if len(raw_bytes) > max_bytes:
        raise DecompressionBombError(
            f"Image byte length {len(raw_bytes)} exceeds limit {max_bytes}."
        )

    if raw_bytes.startswith(b"\x89PNG\r\n\x1a\n"):
        if len(raw_bytes) < 24 or raw_bytes[12:16] != b"IHDR":
            raise CorruptImageError("Malformed PNG IHDR header.")
        width, height = struct.unpack(">II", raw_bytes[16:24])
        if width <= 0 or height <= 0:
            raise CorruptImageError("Invalid zero dimensions in PNG header.")
        if width * height > max_pixels:
            raise DecompressionBombError(
                f"PNG dimensions {width}x{height} ({width * height} px) exceed max_pixels={max_pixels}."
            )
        return "image/png", int(width), int(height), 1

    if raw_bytes.startswith(b"\xff\xd8\xff"):
        width, height, orientation = _parse_jpeg_header(raw_bytes)
        if width * height > max_pixels:
            raise DecompressionBombError(
                f"JPEG dimensions {width}x{height} ({width * height} px) exceed max_pixels={max_pixels}."
            )
        return "image/jpeg", width, height, orientation

    if len(raw_bytes) >= 12 and raw_bytes[4:8] == b"ftyp":
        brand = raw_bytes[8:12]
        if brand in {b"heic", b"heix", b"hevc", b"mif1", b"msf1"}:
            width, height = _parse_isobmff_ispe(raw_bytes)
            if width * height > max_pixels:
                raise DecompressionBombError(
                    f"HEIC dimensions {width}x{height} exceed max_pixels={max_pixels}."
                )
            return "image/heic", width, height, 1

    raise UnsupportedImageFormatError(
        "Unsupported image format. Only JPEG, PNG, and HEIC are accepted."
    )


def _parse_jpeg_header(data: bytes) -> Tuple[int, int, int]:
    idx = 2
    n = len(data)
    width = 0
    height = 0
    orientation = 1
    sof_markers = {
        0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
        0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF,
    }
    while idx < n:
        if data[idx] != 0xFF:
            idx += 1
            continue
        while idx < n and data[idx] == 0xFF:
            idx += 1
        if idx >= n:
            break
        marker = data[idx]
        idx += 1
        if marker in {0xD8, 0xD9} or (0xD0 <= marker <= 0xD7):
            continue
        if idx + 2 > n:
            raise CorruptImageError("Truncated JPEG marker length.")
        seg_len = struct.unpack(">H", data[idx : idx + 2])[0]
        if seg_len < 2 or idx + seg_len > n:
            raise CorruptImageError("Corrupt JPEG segment length.")
        seg_payload = data[idx + 2 : idx + seg_len]
        if marker == 0xE1 and seg_payload.startswith(b"Exif\x00\x00"):
            orientation = _parse_exif_orientation(seg_payload[6:])
        elif marker in sof_markers:
            if len(seg_payload) < 5:
                raise CorruptImageError("Truncated JPEG SOF segment.")
            height, width = struct.unpack(">HH", seg_payload[1:5])
            break
        idx += seg_len

    if width <= 0 or height <= 0:
        raise CorruptImageError("JPEG missing valid SOF width/height.")
    return int(width), int(height), int(orientation)


def _parse_exif_orientation(tiff: bytes) -> int:
    if len(tiff) < 8:
        return 1
    endian = tiff[:2]
    if endian == b"II":
        order = "<"
    elif endian == b"MM":
        order = ">"
    else:
        return 1
    # The byte-order character may only lead a struct format ("<HHI", never "<H<H<I").
    fmt_h, fmt_i, fmt_entry = order + "H", order + "I", order + "HHI"
    ifd_offset = struct.unpack(fmt_i, tiff[4:8])[0]
    if ifd_offset + 2 > len(tiff):
        return 1
    num_entries = struct.unpack(fmt_h, tiff[ifd_offset : ifd_offset + 2])[0]
    pos = ifd_offset + 2
    for _ in range(num_entries):
        if pos + 12 > len(tiff):
            break
        tag, field_type, count = struct.unpack(fmt_entry, tiff[pos : pos + 8])
        if tag == 0x0112 and field_type == 3 and count >= 1:
            val = struct.unpack(fmt_h, tiff[pos + 8 : pos + 10])[0]
            if 1 <= val <= 8:
                return int(val)
        pos += 12
    return 1


def _parse_isobmff_ispe(data: bytes) -> Tuple[int, int]:
    idx = data.find(b"ispe")
    if idx != -1 and idx + 16 <= len(data):
        width, height = struct.unpack(">II", data[idx + 8 : idx + 16])
        if width > 0 and height > 0:
            return int(width), int(height)
    return 64, 64


def strip_exif_bytes(raw_bytes: bytes) -> bytes:
    """Strip EXIF/GPS metadata segments from PNG or JPEG bytes."""
    if raw_bytes.startswith(b"\x89PNG\r\n\x1a\n"):
        out = bytearray(b"\x89PNG\r\n\x1a\n")
        pos = 8
        n = len(raw_bytes)
        keep_chunks = {b"IHDR", b"PLTE", b"tRNS", b"IDAT", b"IEND"}
        while pos + 8 <= n:
            length = struct.unpack(">I", raw_bytes[pos : pos + 4])[0]
            ctype = raw_bytes[pos + 4 : pos + 8]
            chunk_end = pos + 8 + length + 4
            if chunk_end > n:
                raise CorruptImageError("Truncated PNG chunk.")
            if ctype in keep_chunks:
                out.extend(raw_bytes[pos:chunk_end])
            pos = chunk_end
            if ctype == b"IEND":
                break
        return bytes(out)

    if raw_bytes.startswith(b"\xff\xd8\xff"):
        out = bytearray(b"\xff\xd8")
        idx = 2
        n = len(raw_bytes)
        while idx < n:
            if raw_bytes[idx] != 0xFF:
                out.extend(raw_bytes[idx:])
                break
            while idx < n and raw_bytes[idx] == 0xFF:
                idx += 1
            if idx >= n:
                break
            marker = raw_bytes[idx]
            idx += 1
            if marker == 0xDA:
                if idx + 2 > n:
                    raise CorruptImageError("Truncated JPEG SOS.")
                out.extend(b"\xff" + bytes([marker]) + raw_bytes[idx:])
                break
            if marker in {0xD8, 0xD9} or (0xD0 <= marker <= 0xD7):
                out.extend(b"\xff" + bytes([marker]))
                continue
            if idx + 2 > n:
                raise CorruptImageError("Truncated JPEG segment.")
            seg_len = struct.unpack(">H", raw_bytes[idx : idx + 2])[0]
            if seg_len < 2 or idx + seg_len > n:
                raise CorruptImageError("Invalid JPEG segment length.")
            if not (0xE1 <= marker <= 0xEF or marker == 0xFE):
                out.extend(b"\xff" + bytes([marker]) + raw_bytes[idx : idx + seg_len])
            idx += seg_len
        return bytes(out)

    return raw_bytes


def apply_exif_orientation(rgb: np.ndarray, orientation: int) -> np.ndarray:
    """Rotate/flip an HxWx3 RGB array according to EXIF Orientation tag (1..8)."""
    if orientation == 1:
        return rgb
    if orientation == 2:
        return np.fliplr(rgb).copy()
    if orientation == 3:
        return np.rot90(rgb, 2).copy()
    if orientation == 4:
        return np.flipud(rgb).copy()
    if orientation == 5:
        return np.rot90(np.fliplr(rgb), 1).copy()
    if orientation == 6:
        return np.rot90(rgb, -1).copy()
    if orientation == 7:
        return np.rot90(np.fliplr(rgb), -1).copy()
    if orientation == 8:
        return np.rot90(rgb, 1).copy()
    return rgb


def encode_rgb_to_png_bytes(rgb: np.ndarray) -> bytes:
    """Encode an HxWx3 uint8 RGB numpy array into standard PNG bytes using stdlib zlib."""
    if rgb.ndim == 2:
        rgb = np.stack([rgb, rgb, rgb], axis=-1)
    if rgb.ndim != 3 or rgb.shape[2] != 3:
        raise ValueError(f"Expected HxWx3 RGB array, got shape {rgb.shape}")
    arr = np.ascontiguousarray(rgb.astype(np.uint8))
    height, width, _ = arr.shape

    filter_col = np.zeros((height, 1), dtype=np.uint8)
    scanlines = np.hstack([filter_col, arr.reshape(height, width * 3)])
    compressed = zlib.compress(scanlines.tobytes(), level=6)

    def _chunk(chunk_type: bytes, payload: bytes) -> bytes:
        crc = zlib.crc32(chunk_type + payload) & 0xFFFFFFFF
        return struct.pack(">I", len(payload)) + chunk_type + payload + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", ihdr)
        + _chunk(b"IDAT", compressed)
        + _chunk(b"IEND", b"")
    )


def _decode_png_pure_python(raw_bytes: bytes, max_pixels: int) -> np.ndarray:
    pos = 8
    n = len(raw_bytes)
    width = height = bit_depth = color_type = 0
    idat_parts = []
    seen_iend = False

    while pos + 8 <= n:
        length = struct.unpack(">I", raw_bytes[pos : pos + 4])[0]
        ctype = raw_bytes[pos + 4 : pos + 8]
        data_start = pos + 8
        data_end = data_start + length
        crc_end = data_end + 4
        if crc_end > n:
            raise CorruptImageError("Truncated PNG chunk payload.")
        chunk_data = raw_bytes[data_start:data_end]
        expected_crc = struct.unpack(">I", raw_bytes[data_end:crc_end])[0]
        actual_crc = zlib.crc32(ctype + chunk_data) & 0xFFFFFFFF
        if expected_crc != actual_crc:
            raise CorruptImageError("PNG chunk CRC mismatch.")

        if ctype == b"IHDR":
            width, height, bit_depth, color_type, comp, filt, interlace = struct.unpack(
                ">IIBBBBB", chunk_data[:13]
            )
            if width * height > max_pixels:
                raise DecompressionBombError(f"PNG exceeds max_pixels={max_pixels}")
            if bit_depth != 8 or interlace != 0:
                raise CorruptImageError("Unsupported PNG bit depth or interlace in pure decoder.")
        elif ctype == b"IDAT":
            idat_parts.append(chunk_data)
        elif ctype == b"IEND":
            seen_iend = True
            break
        pos = crc_end

    if not seen_iend or not idat_parts or width <= 0 or height <= 0:
        raise CorruptImageError("Incomplete PNG stream (missing IDAT or IEND).")

    channels = {0: 1, 2: 3, 4: 2, 6: 4}.get(color_type)
    if channels is None:
        raise CorruptImageError(f"Unsupported PNG color_type={color_type}")

    expected_len = height * (1 + width * channels)
    try:
        decomp = zlib.decompressobj()
        raw_scanlines = decomp.decompress(b"".join(idat_parts), expected_len + 1024)
    except zlib.error as exc:
        raise CorruptImageError(f"Corrupt PNG zlib stream: {exc}") from exc

    if len(raw_scanlines) < expected_len:
        raise CorruptImageError("Truncated uncompressed PNG scanlines.")

    stride = width * channels
    recon = np.zeros((height, stride), dtype=np.uint8)
    offset = 0
    for r in range(height):
        ftype = raw_scanlines[offset]
        row_bytes = np.frombuffer(
            raw_scanlines, dtype=np.uint8, count=stride, offset=offset + 1
        ).copy()
        offset += 1 + stride
        if ftype == 0:
            recon[r] = row_bytes
        elif ftype == 1:
            for i in range(channels, stride):
                row_bytes[i] = (int(row_bytes[i]) + int(row_bytes[i - channels])) & 0xFF
            recon[r] = row_bytes
        elif ftype == 2:
            if r > 0:
                row_bytes = (
                    (row_bytes.astype(np.int32) + recon[r - 1].astype(np.int32)) & 0xFF
                ).astype(np.uint8)
            recon[r] = row_bytes
        elif ftype == 3:
            prev_row = recon[r - 1] if r > 0 else np.zeros(stride, dtype=np.uint8)
            for i in range(stride):
                left = int(row_bytes[i - channels]) if i >= channels else 0
                up = int(prev_row[i])
                row_bytes[i] = (int(row_bytes[i]) + ((left + up) >> 1)) & 0xFF
            recon[r] = row_bytes
        elif ftype == 4:
            prev_row = recon[r - 1] if r > 0 else np.zeros(stride, dtype=np.uint8)
            for i in range(stride):
                a = int(row_bytes[i - channels]) if i >= channels else 0
                b = int(prev_row[i])
                c = int(prev_row[i - channels]) if (r > 0 and i >= channels) else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                row_bytes[i] = (int(row_bytes[i]) + pr) & 0xFF
            recon[r] = row_bytes
        else:
            raise CorruptImageError(f"Invalid PNG filter type {ftype}")

    img = recon.reshape((height, width, channels))
    if channels == 1:
        return np.repeat(img, 3, axis=2)
    if channels == 2:
        return np.repeat(img[:, :, :1], 3, axis=2)
    if channels == 4:
        return img[:, :, :3].copy()
    return img


def decode_image_bytes(
    raw_bytes: bytes,
    max_bytes: int = MAX_UPLOAD_BYTES_DEFAULT,
    max_pixels: int = MAX_IMAGE_PIXELS_DEFAULT,
    min_dim: int = MIN_IMAGE_DIMENSION,
) -> Tuple[np.ndarray, Dict[str, object]]:
    """Validate, strip EXIF, apply orientation, and decode image bytes to HxWx3 uint8 RGB."""
    mime, hdr_w, hdr_h, orientation = detect_mime_and_dimensions(
        raw_bytes, max_bytes=max_bytes, max_pixels=max_pixels
    )
    cleaned_bytes = strip_exif_bytes(raw_bytes)
    rgb: Optional[np.ndarray] = None

    if mime == "image/png":
        rgb = _decode_png_pure_python(cleaned_bytes, max_pixels=max_pixels)
    else:
        try:
            import fitz  # type: ignore

            pix = fitz.Pixmap(raw_bytes)
            if pix.n >= 3:
                if pix.alpha:
                    pix = fitz.Pixmap(fitz.csRGB, pix)
                arr = np.frombuffer(pix.samples, dtype=np.uint8).reshape(
                    (pix.height, pix.width, pix.n)
                )
                rgb = arr[:, :, :3].copy()
            else:
                gray = np.frombuffer(pix.samples, dtype=np.uint8).reshape(
                    (pix.height, pix.width, 1)
                )
                rgb = np.repeat(gray, 3, axis=2)
        except Exception:
            try:
                from PIL import Image  # type: ignore
                import io

                with Image.open(io.BytesIO(raw_bytes)) as im:
                    rgb = np.asarray(im.convert("RGB"), dtype=np.uint8)
            except Exception as exc:
                raise CorruptImageError(f"Failed to decode {mime} payload: {exc}") from exc

    rgb = apply_exif_orientation(rgb, orientation)
    h, w, _ = rgb.shape
    if h < min_dim or w < min_dim:
        raise ImageValidationError(
            f"Image dimensions {w}x{h} are smaller than minimum {min_dim}x{min_dim} thumbnail limit."
        )
    if h * w > max_pixels:
        raise DecompressionBombError(f"Decoded image pixel count {h * w} exceeds {max_pixels}.")

    sha256_hex = hashlib.sha256(cleaned_bytes).hexdigest()
    phash_hex = compute_phash(rgb)
    meta = {
        "mime_type": mime,
        "width": int(w),
        "height": int(h),
        "exif_orientation_applied": int(orientation),
        "exif_stripped": True,
        "image_sha256": sha256_hex,
        "phash": phash_hex,
    }
    return rgb, meta


def strip_exif_and_validate(
    raw_bytes: bytes,
    max_bytes: int = MAX_UPLOAD_BYTES_DEFAULT,
    max_pixels: int = MAX_IMAGE_PIXELS_DEFAULT,
) -> Tuple[bytes, np.ndarray, Dict[str, object]]:
    rgb, meta = decode_image_bytes(raw_bytes, max_bytes=max_bytes, max_pixels=max_pixels)
    safe_png = encode_rgb_to_png_bytes(rgb)
    return safe_png, rgb, meta


def _resize_grayscale_nearest(gray: np.ndarray, out_h: int, out_w: int) -> np.ndarray:
    in_h, in_w = gray.shape
    row_idx = (np.arange(out_h) * in_h // out_h).clip(0, in_h - 1)
    col_idx = (np.arange(out_w) * in_w // out_w).clip(0, in_w - 1)
    return gray[row_idx[:, None], col_idx[None, :]].astype(np.float64)


def compute_phash(rgb: np.ndarray) -> str:
    """Compute a 64-bit 2D DCT perceptual hash (16-char hex string)."""
    if rgb.ndim == 3:
        gray = (
            0.299 * rgb[:, :, 0].astype(np.float64)
            + 0.587 * rgb[:, :, 1].astype(np.float64)
            + 0.114 * rgb[:, :, 2].astype(np.float64)
        )
    else:
        gray = rgb.astype(np.float64)

    small = _resize_grayscale_nearest(gray, 32, 32)
    n = 32
    k = np.arange(8)[:, None]
    x = np.arange(n)[None, :]
    basis = np.cos(math.pi * (2 * x + 1) * k / (2.0 * n))
    dct_low = basis @ small @ basis.T
    flat = dct_low.flatten()
    ac_coeffs = flat[1:]
    med = float(np.median(ac_coeffs))
    bits = (flat > med).astype(np.uint8)
    val = 0
    for b in bits:
        val = (val << 1) | int(b)
    return f"{val:016x}"


def phash_hamming_distance(phash_a: str, phash_b: str) -> int:
    int_a = int(phash_a.strip(), 16)
    int_b = int(phash_b.strip(), 16)
    return int(bin(int_a ^ int_b).count("1"))
