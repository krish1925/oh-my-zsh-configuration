#!/usr/bin/env python3
"""usage: icon.py out.png — 1024px app icon (dark rounded square, green ">_"), standard library only."""
import struct
import sys
import zlib

N = 1024


def sd_round_box(x, y, cx, cy, hx, hy, r):
    qx, qy = abs(x - cx) - (hx - r), abs(y - cy) - (hy - r)
    return (max(qx, 0) ** 2 + max(qy, 0) ** 2) ** 0.5 + min(max(qx, qy), 0) - r


def sd_segment(x, y, ax, ay, bx, by):
    px, py, dx, dy = x - ax, y - ay, bx - ax, by - ay
    t = max(0.0, min(1.0, (px * dx + py * dy) / (dx * dx + dy * dy)))
    return ((px - t * dx) ** 2 + (py - t * dy) ** 2) ** 0.5


def cover(d):  # signed distance (px) -> anti-aliased coverage 0..1
    return max(0.0, min(1.0, 0.5 - d))


rows = []
for j in range(N):
    y = j + 0.5
    g = j / N
    bg = (int(34 - 26 * g), int(36 - 27 * g), int(46 - 34 * g))  # top #22242e -> bottom #080911
    row = bytearray([0])
    for i in range(N):
        x = i + 0.5
        a = cover(sd_round_box(x, y, 512, 512, 412, 412, 185))
        if a == 0.0:
            row += b"\x00\x00\x00\x00"
            continue
        # the ">" chevron and the "_" cursor, stroke half-width 36
        d = min(sd_segment(x, y, 330, 350, 520, 512), sd_segment(x, y, 520, 512, 330, 674)) - 36
        d = min(d, sd_round_box(x, y, 645, 690, 85, 34, 20))
        c = cover(d)
        r = int(bg[0] * (1 - c) + 92 * c)
        gr = int(bg[1] * (1 - c) + 242 * c)
        b = int(bg[2] * (1 - c) + 158 * c)
        row += bytes((r, gr, b, int(255 * a)))
    rows.append(bytes(row))


def chunk(tag, data):
    body = tag + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


png = (
    b"\x89PNG\r\n\x1a\n"
    + chunk(b"IHDR", struct.pack(">IIBBBBB", N, N, 8, 6, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
    + chunk(b"IEND", b"")
)
open(sys.argv[1], "wb").write(png)
