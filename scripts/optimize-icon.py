#!/usr/bin/env python3
"""Reduce ICNS PNG color entropy while retaining every resolution and alpha.

Requires Pillow only when rebuilding the icon. Small representations keep their pixels;
larger ones reserve separate palette entries for the opaque tile and soft edges.
"""
import io
from pathlib import Path
import struct
import sys

from PIL import Image


def without_metadata(payload: bytes) -> bytes:
    """Keep PNG image data and transparency, excluding EXIF/text/provenance."""
    output = bytearray(payload[:8])
    offset = 8
    while offset < len(payload):
        size = struct.unpack(">I", payload[offset:offset + 4])[0]
        kind = payload[offset + 4:offset + 8]
        assert offset + size + 12 <= len(payload)
        if kind in (b"IHDR", b"PLTE", b"tRNS", b"IDAT", b"IEND"):
            output.extend(payload[offset:offset + size + 12])
        offset += size + 12
    assert offset == len(payload)
    return bytes(output)


def optimize_png(payload: bytes) -> bytes:
    payload = without_metadata(payload)
    image = Image.open(io.BytesIO(payload)).convert("RGBA")
    if image.width < 128:
        return payload
    opaque = image.convert("RGB").quantize(colors=224, method=Image.Quantize.MEDIANCUT)
    edge = image.quantize(colors=31, method=Image.Quantize.FASTOCTREE)
    edge_palette = edge.getpalette("RGBA")
    palette = opaque.getpalette("RGB")[:224 * 3]
    alpha = [253] * 224
    for index in range(31):
        palette.extend(edge_palette[index * 4:index * 4 + 3])
        alpha.append(edge_palette[index * 4 + 3])
    palette.extend([0, 0, 0])
    alpha.append(0)
    indices = bytes(o if a >= 250 else 255 if a <= 5 else e + 224
                    for o, e, a in zip(opaque.tobytes(), edge.tobytes(), image.getchannel("A").tobytes()))
    result = Image.frombytes("P", image.size, indices)
    result.putpalette(palette)
    result.info["transparency"] = bytes(alpha)
    output = io.BytesIO()
    result.save(output, format="PNG", optimize=True)
    compressed = output.getvalue()
    return compressed if len(compressed) < len(payload) else payload


def main() -> None:
    source, target = map(Path, sys.argv[1:])
    raw = source.read_bytes()
    assert raw[:4] == b"icns" and struct.unpack(">I", raw[4:8])[0] == len(raw)
    offset, chunks = 8, bytearray()
    while offset < len(raw):
        kind, size = struct.unpack(">4sI", raw[offset:offset + 8])
        assert size >= 8 and offset + size <= len(raw)
        payload = raw[offset + 8:offset + size]
        if payload.startswith(b"\x89PNG"):
            payload = optimize_png(payload)
        chunks.extend(struct.pack(">4sI", kind, len(payload) + 8))
        chunks.extend(payload)
        offset += size
    target.write_bytes(struct.pack(">4sI", b"icns", len(chunks) + 8) + chunks)
    print(f"ICNS: {len(raw):,} → {target.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
