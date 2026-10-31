"""Thumbnail PNG kendaraan dari mesh yang sama dengan GLB (tanpa dependensi).

Rasterizer z-buffer ortografis, pandangan 3/4 depan-kiri dari atas, flat
shading dengan cahaya searah + ambient, 2× supersampling, latar transparan.
"""
from __future__ import annotations

import math
import struct
import zlib

from geom import MATERIALS, MeshBuilder

LIGHT = (0.35, 0.85, 0.4)


def _norm(v):
    n = math.sqrt(sum(c * c for c in v)) or 1.0
    return tuple(c / n for c in v)


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def render(m: MeshBuilder, width=320, height=160, ss=2, eye=(1.0, 0.62, 1.25), skip=("shadow",)):
    W, H = width * ss, height * ss
    f = _norm(tuple(-c for c in eye))
    r = _norm(_cross(f, (0, 1, 0)))
    u = _cross(r, f)
    light = _norm(LIGHT)
    tris = []
    for mat, part in m.parts.items():
        if mat in skip:
            continue
        color = MATERIALS[mat][0][:3]
        pos, nrm, idx = part["pos"], part["nrm"], part["idx"]
        for i in range(0, len(idx), 3):
            a, b, c = idx[i], idx[i + 1], idx[i + 2]
            n = nrm[a]
            if _dot(n, f) > 0.02:                       # menghadap menjauh
                continue
            shade = 0.5 + 0.5 * max(0.0, _dot(n, light))
            col = tuple(min(1.0, ch * shade) ** (1 / 2.2) for ch in color)
            pts = [(_dot(pos[k], r), _dot(pos[k], u), _dot(pos[k], f)) for k in (a, b, c)]
            tris.append((pts, col))
    if not tris:
        raise ValueError("mesh kosong")
    xs = [p[0] for t, _ in tris for p in t]
    ys = [p[1] for t, _ in tris for p in t]
    span = max((max(xs) - min(xs)) / (W * 0.92), (max(ys) - min(ys)) / (H * 0.88))
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    zbuf = [math.inf] * (W * H)
    rgb = [None] * (W * H)
    for pts, col in tris:
        sp = [((p[0] - cx) / span + W / 2, H / 2 - (p[1] - cy) / span, p[2]) for p in pts]
        (x0, y0, z0), (x1, y1, z1), (x2, y2, z2) = sp
        area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if abs(area) < 1e-9:
            continue
        minx, maxx = max(0, int(min(x0, x1, x2))), min(W - 1, int(max(x0, x1, x2)) + 1)
        miny, maxy = max(0, int(min(y0, y1, y2))), min(H - 1, int(max(y0, y1, y2)) + 1)
        for py in range(miny, maxy + 1):
            fy = py + 0.5
            row = py * W
            for px in range(minx, maxx + 1):
                fx = px + 0.5
                w0 = ((x1 - fx) * (y2 - fy) - (x2 - fx) * (y1 - fy)) / area
                w1 = ((x2 - fx) * (y0 - fy) - (x0 - fx) * (y2 - fy)) / area
                w2 = 1 - w0 - w1
                if w0 < -1e-6 or w1 < -1e-6 or w2 < -1e-6:
                    continue
                z = w0 * z0 + w1 * z1 + w2 * z2
                k = row + px
                if z < zbuf[k]:
                    zbuf[k] = z
                    rgb[k] = col
    out = bytearray()
    for y in range(height):
        out.append(0)
        for x in range(width):
            acc = [0.0, 0.0, 0.0]
            cover = 0
            for dy in range(ss):
                for dx in range(ss):
                    c = rgb[(y * ss + dy) * W + x * ss + dx]
                    if c is not None:
                        cover += 1
                        for i in range(3):
                            acc[i] += c[i]
            if cover:
                out += bytes(int(acc[i] / cover * 255 + 0.5) for i in range(3))
                out.append(int(cover / (ss * ss) * 255 + 0.5))
            else:
                out += b"\0\0\0\0"
    return _png(width, height, bytes(out))


def _png(w, h, raw):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
