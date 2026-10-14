#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = ["ocrmac"]
# ///
"""zocr_fallback <image-path> — same output contract as tools/zocr.swift (Apple Vision OCR
via ocrmac/pyobjc), used when swiftc can't build (a real, hit-during-implementation issue:
this machine's Command Line Tools SDK fails to build the Foundation module for Vision.swift
with "could not build module 'Foundation'" — a known CLT-only quirk, not a code bug). Run
through `uvx --from ocrmac`, which caches its own venv, so only the first call per machine
pays the pyobjc install cost (~1-2s after cache; a few seconds cold)."""
import json
import sys


def main():
    if len(sys.argv) < 2:
        print("usage: zocr_fallback.py <image>", file=sys.stderr)
        return 2
    try:
        from ocrmac import ocrmac
    except ImportError:
        print("zocr_fallback: ocrmac not available", file=sys.stderr)
        return 2
    try:
        results = ocrmac.OCR(sys.argv[1], framework="vision").recognize()
    except Exception as e:
        print(f"zocr_fallback: recognition failed: {e}", file=sys.stderr)
        return 2

    # sort top-to-bottom (high y = high on screen, matching Vision's bottom-left origin),
    # then left-to-right — same ordering rule as zocr.swift
    rows = sorted(results, key=lambda r: (-round(r[2][1] + r[2][3], 2), r[2][0]))
    total_area = 0.0
    total_chars = 0
    conf_sum = 0.0
    for text, conf, box in rows:
        x, y, w, h = box
        total_area += w * h
        total_chars += len(text)
        conf_sum += conf
        print(json.dumps({"t": text, "c": conf, "x": x, "y": 1 - y - h, "w": w, "h": h}))

    n = len(rows)
    print(json.dumps({"lines": n, "chars": total_chars, "coverage": total_area,
                      "mean_conf": (conf_sum / n) if n else 0.0}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
