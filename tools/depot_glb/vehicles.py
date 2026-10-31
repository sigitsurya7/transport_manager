"""Kendaraan modular: sasis/kabin + bodi muatan (atau tractor head + semitrailer).

Data (id sasis, bodi, warna livery, panjang bodi) dibaca dari
content/vehicle_models.json — sumber yang sama dengan simulasi — sehingga
model 3D dan katalog tidak bisa menyimpang. Geometri dibangun di koordinat
lokal (x = 0 di ujung belakang, menghadap +x), lalu digeser sehingga ujung
belakang berada di x = -REAR: semua kendaraan berhenti dengan bak tepat di
depan platform dock.

Tiap kendaraan berpintu belakang juga punya varian "_open" (pintu terbuka,
interior terlihat) dan daftar titik palet muatan di lantai bak.
"""
from __future__ import annotations

import json
import math
import os

from geom import MeshBuilder

REAR = 2.7            # jarak ujung belakang ke origin kendaraan
CRATE = 0.74          # sisi palet muatan (sama dengan cargo_crate)
CONTENT = os.path.join(os.path.dirname(__file__), "..", "..", "content", "vehicle_models.json")


def load_catalog(path: str = CONTENT) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


# ---------------------------------------------------------------- detail umum


def wheels(m: MeshBuilder, xs, half_track, r=0.36, dual=False, w=0.26):
    for x in xs:
        for z in (-half_track, half_track):
            zs = [z, z - 0.27 if z > 0 else z + 0.27] if dual else [z]
            for zz in zs:
                m.cylinder("tire", (x, r, zz), r, w, axis="z", sides=10)
            outer = z + (w / 2 + 0.005 if z > 0 else -w / 2 - 0.005)
            m.cylinder("hub", (x, r, outer), r * 0.47, 0.02, axis="z", sides=8)


def fenders(m: MeshBuilder, xs, half, r, mat="chassis"):
    """Spakbor tipis di atas roda belakang + mudflap."""
    for x in xs:
        for s in (-1, 1):
            m.box(mat, (x, 2 * r + 0.06, s * half), (2 * r + 0.3, 0.05, 0.34))
            m.box("rubber", (x - r - 0.12, r + 0.1, s * half), (0.03, 0.5, 0.32))


def shadow(m: MeshBuilder, x0, x1, width):
    m.box("shadow", ((x0 + x1) / 2, 0.012, 0), (x1 - x0, 0.004, width + 0.06))


def plate(m: MeshBuilder, x, y, front: bool):
    m.box("plate", (x + (0.012 if front else -0.012), y, 0), (0.02, 0.15, 0.48))


def taillights(m: MeshBuilder, x, half, y=0.85):
    for s in (-1, 1):
        m.box("taillight", (x - 0.02, y, s * half), (0.04, 0.2, 0.18))
    plate(m, x, y - 0.12, front=False)


def headlights(m: MeshBuilder, x, y, half, w=0.3):
    for s in (-1, 1):
        m.box("headlight", (x, y, s * half), (0.05, 0.17, w))


def windshield(m: MeshBuilder, x_bottom, x_top, y0, y1, hw):
    """Kaca miring tipis (dua muka, tidak ter-cull)."""
    m.solid("window", [
        [(x_bottom + 0.012, y0, -hw), (x_top + 0.012, y1, -hw), (x_top + 0.012, y1, hw), (x_bottom + 0.012, y0, hw)],
        [(x_bottom - 0.02, y0, -hw), (x_top - 0.02, y1, -hw), (x_top - 0.02, y1, hw), (x_bottom - 0.02, y0, hw)],
        [(x_bottom - 0.02, y0, -hw), (x_bottom + 0.012, y0, -hw), (x_top + 0.012, y1, -hw), (x_top - 0.02, y1, -hw)],
        [(x_bottom - 0.02, y0, hw), (x_bottom + 0.012, y0, hw), (x_top + 0.012, y1, hw), (x_top - 0.02, y1, hw)],
    ])


def slanted_block(m: MeshBuilder, mat, x0, x1, y0, y1, hw, slope, inset=0.0):
    """Blok dengan muka depan (+x) miring ke belakang sebesar [slope] di atas."""
    a = hw - inset
    m.solid(mat, [
        [(x0, y0, -hw), (x1, y0, -hw), (x1 - slope, y1, -a), (x0, y1, -a)],
        [(x0, y0, hw), (x1, y0, hw), (x1 - slope, y1, a), (x0, y1, a)],
        [(x0, y0, -hw), (x0, y0, hw), (x0, y1, a), (x0, y1, -a)],
        [(x1, y0, -hw), (x1, y0, hw), (x1 - slope, y1, a), (x1 - slope, y1, -a)],
        [(x0, y1, -a), (x1 - slope, y1, -a), (x1 - slope, y1, a), (x0, y1, a)],
        [(x0, y0, -hw), (x1, y0, -hw), (x1, y0, hw), (x0, y0, hw)],
    ])


def mirrors(m: MeshBuilder, x, y, hw, big=False):
    for s in (-1, 1):
        m.box("frame", (x, y, s * (hw + 0.14)), (0.05, 0.05, 0.28))
        m.box("frame", (x, y + (0.0 if not big else 0.05), s * (hw + 0.3)), (0.08, 0.42 if big else 0.2, 0.08))


# ---------------------------------------------------------------- kabin


def cab_nosed(m: MeshBuilder, livery, x_back, cab_len, hood, width, *, doors=1, hd=False, compact=False):
    """Kabin bermoncong (pikap): kap mesin pendek, kaca miring."""
    hw = width / 2
    base_y = 1.15 if not hd else 1.3
    top = base_y + (0.78 if not compact else 0.72)
    x1 = x_back + cab_len
    m.box_on_ground(livery, (x_back + x1) / 2, 0, (cab_len, base_y - 0.48, width), y0=0.48)
    m.box_on_ground(livery, x1 + hood / 2, 0, (hood, 0.62 if not hd else 0.72, width - 0.04), y0=0.48)
    slanted_block(m, livery, x_back, x1, base_y, top, hw, 0.42, inset=0.05)
    windshield(m, x1 + 0.005, x1 - 0.42 + 0.005, base_y + 0.05, top - 0.05, hw - 0.15)
    m.box("window", (x_back - 0.005, base_y + 0.4, 0), (0.02, 0.38, width - 0.5))           # kaca belakang
    win_len = (cab_len - 0.6) / doors
    for s in (-1, 1):
        for d in range(doors):
            wx = x1 - 0.55 - win_len * (d + 0.5)
            m.box("window", (wx, base_y + 0.38, s * (hw - 0.02)), (win_len - 0.1, 0.4, 0.03))
            m.box("door_line", (wx - win_len / 2 + 0.02, base_y - 0.1, s * hw), (0.02, 0.7, 0.012))
        m.box("frame", (x1 - 0.12, base_y + 0.12, s * (hw + 0.09)), (0.1, 0.13, 0.18))         # spion
    front = x1 + hood
    m.box("frame", (front + 0.02, 0.85 if not hd else 0.95, 0), (0.05, 0.24, width * 0.62))  # gril
    m.box("chassis", (front + 0.07, 0.58, 0), (0.14, 0.26, width + 0.02))                       # bumper
    headlights(m, front + 0.03, 0.9 if not hd else 1.0, hw - 0.22)
    plate(m, front + 0.14, 0.58, front=True)
    if hd:                                                                                       # bullbar + snorkel + rak atap
        for s in (-1, 1):
            m.box("exhaust", (front + 0.22, 0.85, s * 0.45), (0.06, 0.65, 0.06))
        m.box("exhaust", (front + 0.22, 1.15, 0), (0.06, 0.06, 1.0))
        m.box("chassis", (x1 - 0.6, (base_y + top) / 2 + 0.1, hw + 0.06), (0.1, 0.9, 0.1))
        for x in (x_back + 0.15, x1 - 0.55):
            m.box("frame", (x, top + 0.1, 0), (0.06, 0.06, width - 0.2))
        for s in (-1, 1):
            m.box("frame", ((x_back + x1 - 0.4) / 2, top + 0.14, s * (hw - 0.12)), (cab_len - 0.5, 0.05, 0.05))
    return front + 0.14


def cab_over(m: MeshBuilder, livery, x_back, cab_len, width, base_y, height, *, slope=0.12,
             sleeper=False, fairing=False, stripe=None, visor=False, big_mirrors=False):
    """Kabin datar (cab-over) khas truk Indonesia."""
    hw = width / 2
    x1 = x_back + cab_len
    top = base_y + height
    m.box_on_ground(livery, (x_back + x1) / 2, 0, (cab_len, base_y - 0.45, width), y0=0.45)
    slanted_block(m, livery, x_back, x1, base_y, top, hw, slope)
    windshield(m, x1 + 0.005, x1 - slope + 0.005, base_y + 0.12, top - 0.14, hw - 0.12)
    for s in (-1, 1):
        m.box("window", (x1 - 0.45, base_y + height * 0.55, s * hw), (0.55, height * 0.42, 0.03))
        m.box("door_line", (x1 - 0.8, base_y - 0.05, s * hw), (0.02, height * 0.9, 0.012))
        m.box("frame", (x1 - 0.55, 0.62, s * (hw + 0.04)), (0.4, 0.06, 0.12))                    # tangga
    mirrors(m, x1 - 0.1, base_y + 0.25, hw, big=big_mirrors)
    m.box("frame", (x1 + 0.03, base_y - 0.32, 0), (0.06, 0.34, width * 0.72))                   # gril
    for i in range(3):
        m.box("chassis", (x1 + 0.065, base_y - 0.22 - i * 0.1, 0), (0.01, 0.03, width * 0.68))
    m.box("chassis", (x1 + 0.07, 0.62, 0), (0.14, 0.32, width + 0.02))                          # bumper
    headlights(m, x1 + 0.04, 0.85 if base_y < 1.4 else base_y - 0.62, hw - 0.28)
    plate(m, x1 + 0.14, 0.6, front=True)
    if stripe:
        m.box(stripe, ((x_back + x1) / 2, base_y + 0.05, 0), (cab_len + 0.01, 0.12, width + 0.012))
    if visor:
        m.box("frame", (x1 - slope - 0.02, top - 0.02, 0), (0.25, 0.06, width - 0.1))
    for dz in (-hw + 0.25, -0.15, 0.15, hw - 0.25):                                               # lampu marker
        m.box("amber", (x1 - slope - 0.05, top + 0.03, dz), (0.08, 0.05, 0.1))
    if sleeper:
        m.box_on_ground(livery, x_back - 0.35, 0, (0.7, height + base_y - 0.45, width - 0.02), y0=0.45)
        m.box("window", (x_back - 0.4, top - 0.45, hw - 0.005), (0.3, 0.22, 0.02))
    if fairing:
        fx0 = x_back - (0.7 if sleeper else 0.0)
        m.solid("fairing", [
            [(fx0, top, -hw + 0.1), (x1 - slope - 0.2, top, -hw + 0.1), (x1 - slope - 0.6, top + 0.55, -hw + 0.18),
             (fx0, top + 0.6, -hw + 0.18)],
            [(fx0, top, hw - 0.1), (x1 - slope - 0.2, top, hw - 0.1), (x1 - slope - 0.6, top + 0.55, hw - 0.18),
             (fx0, top + 0.6, hw - 0.18)],
        ])
    return x1 + 0.14


def cab_longnose(m: MeshBuilder, livery, x_back, cab_len, hood, width, height, *, sleeper=False, heavy=False):
    """Tractor konvensional: moncong panjang, cerobong ganda, filter udara."""
    hw = width / 2
    base_y = 1.45
    top = base_y + height
    x1 = x_back + cab_len
    m.box_on_ground(livery, (x_back + x1) / 2, 0, (cab_len, base_y - 0.5, width), y0=0.5)
    slanted_block(m, livery, x_back, x1, base_y, top, hw, 0.18, inset=0.04)
    windshield(m, x1 + 0.005, x1 - 0.18 + 0.005, base_y + 0.1, top - 0.12, hw - 0.12)
    hood_w = width * 0.62
    slanted_block(m, livery, x1, x1 + hood, 0.85, base_y + 0.15, hood_w / 2, 0.35, inset=0.06)
    m.box_on_ground("chassis", x1 + hood / 2, 0, (hood, 0.4, hood_w - 0.04), y0=0.5)
    for s in (-1, 1):                                                                            # spakbor depan
        m.box(livery, (x1 + hood - 0.55, 1.0, s * (hw - 0.15)), (1.1, 0.06, 0.45))
        m.box("window", (x1 - 0.45, base_y + height * 0.55, s * hw), (0.6, height * 0.4, 0.03))
        m.box("exhaust", (x_back - 0.12, top / 2 + 0.4, s * (hw - 0.12)), (0.12, top + 0.6, 0.12))  # cerobong
        m.cylinder("exhaust", (x1 + 0.2, base_y + 0.4, s * (hw + 0.05)), 0.16, 0.9, sides=8)     # filter udara
        m.box("frame", (x1 - 0.2, 0.75, s * (hw + 0.02)), (0.4, 0.06, 0.12))
    mirrors(m, x1 - 0.05, base_y + 0.35, hw, big=True)
    front = x1 + hood
    m.box("exhaust", (front + 0.03, 1.2, 0), (0.06, 0.75, hood_w * 0.9))                        # gril krom
    m.box("chassis" if not heavy else "exhaust", (front + 0.12, 0.62, 0), (0.22, 0.34, width))
    headlights(m, front - 0.35, 1.05, hw - 0.12, w=0.25)
    plate(m, front + 0.24, 0.62, front=True)
    if sleeper:
        m.box_on_ground(livery, x_back - 0.55, 0, (1.1, top - 0.5, width - 0.02), y0=0.5)
    if heavy:
        for s in (-1, 1):
            m.box("chassis", (front + 0.3, 0.9, s * 0.5), (0.1, 0.8, 0.1))
        m.box("chassis", (front + 0.3, 1.25, 0), (0.1, 0.08, 1.1))
    return front + 0.24


def fuel_tank(m: MeshBuilder, x, half, r=0.28, length=1.0):
    m.cylinder("tank_steel", (x, 0.75, half - 0.05), r, length, axis="x", sides=10)


def side_guard(m: MeshBuilder, x0, x1, half):
    for s in (-1, 1):
        for y in (0.55, 0.8):
            m.box("frame", ((x0 + x1) / 2, y, s * (half - 0.02)), (x1 - x0, 0.06, 0.03))


# ---------------------------------------------------------------- bodi muatan


def hollow_box(m: MeshBuilder, mat, x0, x1, y0, h, w, door_mat=None):
    """Bodi tertutup dengan pintu belakang terbuka (terlipat ke samping)."""
    t, hw = 0.05, w / 2
    m.box_on_ground(mat, (x0 + x1) / 2, 0, (x1 - x0, t, w), y0=y0)
    m.box_on_ground(mat, (x0 + x1) / 2, 0, (x1 - x0, t, w), y0=y0 + h - t)
    for s in (-1, 1):
        m.box_on_ground(mat, (x0 + x1) / 2, s * (hw - t / 2), (x1 - x0, h, t), y0=y0)
        m.box_on_ground(door_mat or mat, x0 + hw / 2 + 0.02, s * (hw + 0.04), (hw - 0.02, h - 0.08, 0.04), y0=y0 + 0.04)
    m.box_on_ground(mat, x1 - t / 2, 0, (t, h, w), y0=y0)
    m.box_on_ground("cargo_floor", (x0 + x1) / 2, 0, (x1 - x0 - 0.12, 0.02, w - 0.12), y0=y0 + t)


def closed_box(m: MeshBuilder, mat, x0, x1, y0, h, w, opened, *, stripe=None, rib=None, ribs=0):
    if opened:
        hollow_box(m, mat, x0, x1, y0, h, w)
    else:
        m.box_on_ground(mat, (x0 + x1) / 2, 0, (x1 - x0, h, w), y0=y0)
        m.box("frame", (x0 - 0.01, y0 + h / 2, 0), (0.02, h - 0.1, 0.03))
        for dz in (-0.25, 0.25):
            m.box("lock", (x0 - 0.025, y0 + h / 2, dz), (0.03, h * 0.7, 0.04))
    hw = w / 2
    if stripe:
        for s in (-1, 1):
            m.box(stripe, ((x0 + x1) / 2, y0 + h * 0.4, s * (hw + 0.012)), (x1 - x0, 0.24, 0.02))
    if rib and ribs:
        for i in range(ribs):
            x = x0 + 0.15 + i * (x1 - x0 - 0.3) / max(1, ribs - 1)
            for s in (-1, 1):
                m.box(rib, (x, y0 + h / 2, s * (hw + 0.015)), (0.1, h - 0.15, 0.03))
    for s in (-1, 1):                                                                            # list atap
        m.box("frame", ((x0 + x1) / 2, y0 + h - 0.02, s * (hw - 0.01)), (x1 - x0 + 0.02, 0.06, 0.06))
    m.box("frame", (x0 + 0.01, y0 + h - 0.02, 0), (0.06, 0.06, w + 0.02))
    m.box("frame", ((x0 + x1) / 2, y0 + 0.03, 0), (x1 - x0 + 0.02, 0.08, w + 0.02))               # list bawah
    for dz in (-hw + 0.1, hw - 0.1):
        m.box("amber", (x0 + 0.04, y0 + h - 0.1, dz), (0.03, 0.06, 0.06))


def open_bed(m: MeshBuilder, x0, x1, y0, w, side_h=0.42, mat="bed", posts=False, head_h=None):
    hw = w / 2
    m.box_on_ground(mat, (x0 + x1) / 2, 0, (x1 - x0, 0.1, w), y0=y0)
    for s in (-1, 1):
        m.box_on_ground(mat, (x0 + x1) / 2, s * (hw - 0.03), (x1 - x0, side_h, 0.06), y0=y0 + 0.1)
        m.box("frame", ((x0 + x1) / 2, y0 + 0.1 + side_h, s * (hw - 0.03)), (x1 - x0, 0.04, 0.08))
    m.box_on_ground(mat, x0 + 0.03, 0, (0.06, side_h, w), y0=y0 + 0.1)
    m.box_on_ground(mat, x1 - 0.03, 0, (0.06, head_h or side_h + 0.12, w), y0=y0 + 0.1)
    if posts:
        n = max(2, int((x1 - x0) / 0.9))
        for i in range(n + 1):
            x = x0 + 0.04 + i * (x1 - x0 - 0.08) / n
            for s in (-1, 1):
                m.box("frame", (x, y0 + 0.1 + side_h / 2, s * (hw + 0.005)), (0.06, side_h, 0.03))
    return y0 + 0.1


def flatbed(m: MeshBuilder, x0, x1, y0, w, head_h=1.0, stakes=True):
    hw = w / 2
    m.box_on_ground("wood_dark", (x0 + x1) / 2, 0, (x1 - x0, 0.12, w), y0=y0)
    m.box("frame", ((x0 + x1) / 2, y0 + 0.02, 0), (x1 - x0 + 0.02, 0.16, w + 0.03))
    m.box_on_ground("frame", x1 - 0.05, 0, (0.08, head_h, w), y0=y0 + 0.12)                       # headboard
    for i in range(4):
        m.box("pole", (x1 - 0.1, y0 + 0.3 + i * head_h / 4, 0), (0.02, 0.05, w - 0.1))
    if stakes:
        n = max(3, int((x1 - x0) / 1.1))
        for i in range(n):
            x = x0 + 0.2 + i * (x1 - x0 - 0.5) / (n - 1)
            for s in (-1, 1):
                m.box_on_ground("frame", x, s * (hw - 0.04), (0.06, 0.45, 0.06), y0=y0 + 0.12)
    return y0 + 0.12


def reefer_unit(m: MeshBuilder, x1, y_top, w):
    m.box("reefer_unit", (x1 + 0.2, y_top - 0.3, 0), (0.4, 0.52, w * 0.78))
    for i in range(3):
        m.box("reefer_grill", (x1 + 0.405, y_top - 0.45 + i * 0.14, 0), (0.01, 0.06, w * 0.62))


def curtain(m: MeshBuilder, x0, x1, y0, h, w, opened, color):
    hw = w / 2
    if opened:
        hollow_box(m, color, x0, x1, y0, h, w, door_mat="frame")
    else:
        m.box_on_ground(color, (x0 + x1) / 2, 0, (x1 - x0 - 0.1, h - 0.16, w), y0=y0 + 0.08)
        m.box_on_ground("frame", x0 + 0.02, 0, (0.06, h, w + 0.02), y0=y0)
        for dz in (-0.3, 0.3):
            m.box("lock", (x0 - 0.02, y0 + h / 2, dz), (0.03, h * 0.7, 0.04))
    m.box_on_ground("frame", x1 - 0.03, 0, (0.06, h, w + 0.02), y0=y0)
    m.box("strap", ((x0 + x1) / 2, y0 + h - 0.05, 0), (x1 - x0, 0.1, w + 0.03))                   # rel atas
    m.box("frame", ((x0 + x1) / 2, y0 + 0.04, 0), (x1 - x0, 0.08, w + 0.03))
    n = int((x1 - x0) / 0.6)
    for i in range(1, n):
        x = x0 + i * (x1 - x0) / n
        for s in (-1, 1):
            m.box("strap", (x, y0 + h / 2, s * (hw + 0.012)), (0.04, h - 0.2, 0.02))


def container(m: MeshBuilder, x0, x1, y0, h, w, opened, color="container", rib="container_rib"):
    hw = w / 2
    if opened:
        hollow_box(m, color, x0, x1, y0, h, w)
    else:
        m.box_on_ground(color, (x0 + x1) / 2, 0, (x1 - x0, h, w), y0=y0)
        for dz in (-0.55, -0.2, 0.2, 0.55):
            m.box("lock", (x0 - 0.03, y0 + h / 2, dz * w / 2.1), (0.04, h - 0.3, 0.05))
    n = int((x1 - x0) / 0.32)
    for i in range(n):
        x = x0 + 0.2 + i * (x1 - x0 - 0.4) / max(1, n - 1)
        for s in (-1, 1):
            m.box(rib, (x, y0 + h / 2, s * (hw + 0.015)), (0.1, h - 0.2, 0.03))
    m.box(rib, ((x0 + x1) / 2, y0 + h - 0.06, 0), (x1 - x0 + 0.02, 0.12, w + 0.02))
    for x in (x0 + 0.08, x1 - 0.08):                                                             # sudut kontainer
        for y in (y0 + 0.08, y0 + h - 0.08):
            for s in (-1, 1):
                m.box("lock", (x, y, s * (hw + 0.01)), (0.18, 0.16, 0.06))


def dump(m: MeshBuilder, x0, x1, y0, h, w, color, guard_len=0.9):
    hw = w / 2
    m.box_on_ground(color, (x0 + x1) / 2, 0, (x1 - x0, 0.14, w), y0=y0)
    for s in (-1, 1):
        m.box_on_ground(color, (x0 + x1) / 2, s * (hw - 0.04), (x1 - x0, h, 0.08), y0=y0 + 0.14)
        for i in range(4):
            x = x0 + 0.3 + i * (x1 - x0 - 0.6) / 3
            m.box("chassis", (x, y0 + 0.14 + h / 2, s * (hw + 0.02)), (0.1, h, 0.05))
        m.box("frame", ((x0 + x1) / 2, y0 + 0.14 + h, s * (hw - 0.04)), (x1 - x0, 0.06, 0.12))
    m.box_on_ground(color, x0 + 0.05, 0, (0.1, h, w), y0=y0 + 0.14)                              # pintu belakang
    m.box_on_ground(color, x1 - 0.05, 0, (0.1, h + 0.25, w), y0=y0 + 0.14)
    m.box(color, (x1 + guard_len / 2 - 0.05, y0 + h + 0.36, 0), (guard_len, 0.08, w - 0.1))     # pelindung kabin
    m.cylinder("hub", (x1 + 0.12, y0 - 0.15, 0), 0.12, 0.7, sides=8)                              # silinder hidrolik


def tanker(m: MeshBuilder, x0, x1, y0, r, color="tank_steel"):
    cy = y0 + r
    m.cylinder(color, ((x0 + x1) / 2, cy, 0), r, x1 - x0, axis="x", sides=14)
    for x in (x0 + 0.02, x1 - 0.02):
        m.cylinder("frame", (x, cy, 0), r * 0.98, 0.06, axis="x", sides=14)
    n = int((x1 - x0) / 1.4)
    for i in range(1, n):
        m.cylinder("frame", (x0 + i * (x1 - x0) / n, cy, 0), r + 0.015, 0.06, axis="x", sides=14)
    m.box("frame", ((x0 + x1) / 2, cy + r + 0.04, 0), (x1 - x0 - 0.4, 0.05, 0.5))                 # jalur atas
    for i in range(max(1, n)):
        m.cylinder("exhaust", (x0 + (i + 0.5) * (x1 - x0) / max(1, n), cy + r + 0.08, 0), 0.22, 0.1, sides=10)
    for s in (-1, 1):
        m.box("frame", ((x0 + x1) / 2, cy + r + 0.3, s * 0.27), (x1 - x0 - 0.4, 0.04, 0.04))      # pagar
        m.box("chassis", ((x0 + x1) / 2, y0 + 0.2, s * r * 0.8), (x1 - x0 - 0.3, 0.12, 0.25))
    m.box_on_ground("frame", x0 - 0.04, 0, (0.06, 2 * r, 0.4), y0=y0 + 0.1)                      # tangga
    m.box("reefer_grill", ((x0 + x1) / 2, y0 + 0.25, r * 0.85), (0.6, 0.35, 0.3))                 # kotak katup
    m.box("hazard", (x0 + 0.01, cy, 0), (0.02, 0.35, 0.45))
    m.box("cone", (x0 - 0.005, cy, 0), (0.01, 0.25, 0.35))                                        # panel bahaya


def small_car(m: MeshBuilder, x, y0, color, length=3.8, width=1.62, facing=1):
    """Mobil penumpang (muatan car carrier / pajangan)."""
    m.box_on_ground(color, x, 0, (length, 0.6, width), y0=y0 + 0.3)
    m.box_on_ground(color, x - facing * 0.25, 0, (length * 0.55, 0.5, width - 0.1), y0=y0 + 0.9)
    m.box_on_ground("window", x - facing * 0.25, 0, (length * 0.56, 0.32, width - 0.08), y0=y0 + 0.98)
    for wx in (x + length * 0.32, x - length * 0.32):
        for s in (-1, 1):
            m.cylinder("tire", (wx, y0 + 0.3, s * (width / 2 - 0.05)), 0.3, 0.18, axis="z", sides=8)


def car_deck(m: MeshBuilder, x0, x1, y0, w):
    m.solid("bed", [[(x0, y0, -w / 2), (x1, y0 + 0.18, -w / 2), (x1, y0 + 0.18, w / 2), (x0, y0, w / 2)],
                    [(x0, y0 + 0.1, -w / 2), (x1, y0 + 0.28, -w / 2), (x1, y0 + 0.28, w / 2), (x0, y0 + 0.1, w / 2)]])
    for s in (-1, 1):
        m.box("marking_y", ((x0 + x1) / 2, y0 + 0.2, s * (w / 2 - 0.02)), (x1 - x0, 0.06, 0.04))
        m.box("frame", (x0 + 0.25, y0 + 0.08, s * 0.55), (0.5, 0.05, 0.4))                         # landasan
    m.box_on_ground("frame", x1 - 0.2, 0, (0.4, 0.6, 0.8), y0=y0 + 0.28)                          # winch
    m.cylinder("hub", (x1 - 0.2, y0 + 0.75, 0), 0.15, 0.7, axis="z", sides=8)


def crane(m: MeshBuilder, x, y0, color):
    m.box_on_ground("chassis", x, 0, (0.7, 0.35, 2.2), y0=y0 - 0.1)
    m.cylinder(color, (x, y0 + 0.9, 0), 0.26, 1.6, sides=8)
    m.box(color, (x - 0.05, y0 + 1.8, 0), (0.5, 0.32, 0.4))
    m.solid(color, [[(x - 0.2, y0 + 1.7, -0.14), (x - 2.8, y0 + 1.95, -0.12), (x - 2.8, y0 + 2.2, -0.12),
                     (x - 0.2, y0 + 2.05, -0.14)],
                    [(x - 0.2, y0 + 1.7, 0.14), (x - 2.8, y0 + 1.95, 0.12), (x - 2.8, y0 + 2.2, 0.12),
                     (x - 0.2, y0 + 2.05, 0.14)]])
    m.box("hub", (x - 2.85, y0 + 1.7, 0), (0.08, 0.5, 0.08))
    for s in (-1, 1):                                                                            # kaki penopang
        m.box("cone", (x, y0 - 0.05, s * 1.12), (0.25, 0.16, 0.18))


def log_bunks(m: MeshBuilder, x0, x1, y0, w):
    m.box_on_ground("frame", (x0 + x1) / 2, 0, (x1 - x0, 0.12, w - 0.3), y0=y0)
    for x in (x0 + 0.5, (x0 + x1) / 2, x1 - 0.5):
        m.box_on_ground("chassis", x, 0, (0.18, 0.18, w), y0=y0 + 0.12)
        for s in (-1, 1):
            m.box_on_ground("frame", x, s * (w / 2 - 0.05), (0.12, 1.5, 0.12), y0=y0 + 0.3)
    m.box_on_ground("frame", x1 + 0.05, 0, (0.1, 1.6, w), y0=y0 + 0.12)


# ---------------------------------------------------------------- semitrailer


def trailer(m: MeshBuilder, kind, x0, length, livery, opened):
    """Semitrailer 12 m dengan kaki penopang & tiga gandar belakang."""
    x1 = x0 + length
    deck = 1.35
    m.box_on_ground("chassis", (x0 + x1) / 2, 0, (length, 0.3, 1.0), y0=deck - 0.35)
    for s in (-1, 1):
        m.box_on_ground("frame", x1 - 3.2, s * 0.85, (0.12, deck - 0.4, 0.12))                    # kaki penopang
    wheels(m, (x0 + 1.0, x0 + 2.3, x0 + 3.6), 1.0, 0.48, dual=True)
    fenders(m, (x0 + 2.3,), 1.0, 0.48)
    side_guard(m, x0 + 4.4, x1 - 3.6, 1.2)
    taillights(m, x0, 1.0, y=0.9)
    shadow(m, x0, x1, 2.5)
    w = 2.5
    if kind == "trailer_container":
        for s in (-1, 1):
            m.box_on_ground("frame", (x0 + x1) / 2, s * 0.9, (length, 0.12, 0.15), y0=deck - 0.1)
        container(m, x0 + 0.05, x1 - 0.05, deck, 2.6, 2.44, opened)
        return deck
    if kind == "trailer_box":
        closed_box(m, "box_body", x0 + 0.05, x1 - 0.05, deck, 2.8, w, opened, stripe=livery)
        return deck + 0.05
    if kind == "trailer_flatbed":
        return flatbed(m, x0 + 0.05, x1 - 0.05, deck - 0.1, w, head_h=1.2)
    if kind == "trailer_tank":
        tanker(m, x0 + 0.3, x1 - 0.3, deck - 0.1, 1.15)
        return None
    if kind == "trailer_car":
        for y in (deck, deck + 1.7):
            m.box_on_ground("bed", (x0 + x1) / 2, 0, (length, 0.08, w - 0.1), y0=y)
        for i in range(5):
            x = x0 + 0.3 + i * (length - 0.6) / 4
            for s in (-1, 1):
                m.box_on_ground("frame", x, s * (w / 2 - 0.05), (0.1, 3.4, 0.1), y0=deck)
        for i, color in enumerate(("car_red", "body_white", "car_teal")):
            small_car(m, x0 + 2.2 + i * 3.9, deck + 0.08, color)
        for i, color in enumerate(("silver", "car_grey")):
            small_car(m, x0 + 2.6 + i * 4.3, deck + 1.78, color)
        return None
    raise ValueError(kind)


# ---------------------------------------------------------------- perakitan


def _slots(x_back, x_front, floor_y, width, rows=2):
    """Titik palet di lantai bak, terurut dari depan (dekat kabin) ke belakang."""
    n = int((x_front - x_back) // (CRATE + 0.04))
    xs = [x_front - (CRATE / 2 + 0.03) - i * (CRATE + 0.04) for i in range(n)]
    if width < 2 * CRATE + 0.1:
        rows = 1
    zs = [(-1 + 2 * (j + 0.5) / rows) * (width / 2 - CRATE / 2 - 0.04) * (1 if rows > 1 else 0) for j in range(rows)]
    return [[x, floor_y, z] for x in xs for z in zs]


CARGO_BODIES = {"open", "canopy", "box", "van", "reefer", "curtain", "flatbed", "container", "crane"}

# Ukuran sasis: lebar, panjang kabin, tinggi lantai bak, roda, dsb.
TRUCKS = {
    "mini_cabover_k": dict(width=1.5, cab=1.15, floor=0.72, r=0.3, track=0.62, base=1.05, h=0.95, slope=0.1),
    "mini_cabover": dict(width=1.88, cab=1.08, floor=0.73, r=0.4, track=0.82, base=1.42, h=0.92, slope=0.12),
    "boxcar_semi": dict(width=1.72, cab=1.05, floor=0.67, r=0.36, track=0.78, base=1.3, h=0.72, slope=0.32),
    "light_cabover": dict(width=2.06, cab=1.24, floor=0.92, r=0.42, track=0.86, base=1.55, h=1.1, slope=0.12,
                          dual=True),
    "medium_cabover": dict(width=2.3, cab=1.5, floor=1.08, r=0.48, track=0.98, base=1.75, h=1.25, slope=0.14,
                           dual=True, visor=True),
    "heavy_cabover": dict(width=2.5, cab=1.7, floor=1.25, r=0.52, track=1.05, base=1.95, h=1.4, slope=0.14,
                          dual=True, visor=True, tandem=True, front2=True),
}


def build_vehicle(model: dict, cat: dict, opened: bool = False):
    """Rakit satu model katalog. Mengembalikan (MeshBuilder, titik palet)."""
    chassis = model["chassis"]
    body = next(b for b in cat["bodies"] if b["id"] == model["body"])
    livery = model.get("livery", "body_white")
    bl = body["length_m"]
    kind = body["kind"]
    m = MeshBuilder()
    slots = []
    gap = 0.12
    x0 = 0.05                                     # ujung belakang bodi

    if chassis.startswith("pickup"):
        spec = {"pickup_compact": (1.62, 1.05, 0.62, 0.32, 1, False, True),
                "pickup_single": (1.74, 1.05, 0.7, 0.35, 1, False, False),
                "pickup_double": (1.8, 1.9, 0.8, 0.36, 2, False, False),
                "pickup_hd": (1.86, 1.25, 0.85, 0.4, 1, True, False)}[chassis]
        width, cab_len, hood, r, doors, hd, compact = spec
        x1 = x0 + bl
        floor = 0.62 if not hd else 0.74
        m.box_on_ground("chassis", (x0 + x1 + cab_len + hood) / 2, 0, (x1 + cab_len + hood - x0, 0.28, width - 0.3),
                        y0=r - 0.05)
        front = cab_nosed(m, livery, x1 + gap, cab_len, hood, width, doors=doors, hd=hd, compact=compact)
        wheels(m, (x1 + gap + cab_len + hood * 0.35, x0 + bl * 0.42), width / 2 - 0.1, r)
        bw = width + 0.04
        if kind == "canopy":
            fl = open_bed(m, x0, x1, floor, bw, side_h=0.45, mat=livery)
            top = floor + 0.55 + 0.78
            if opened:
                m.box_on_ground("fairing", (x0 + x1) / 2, 0, (bl, 0.08, bw), y0=top - 0.08)
                for s in (-1, 1):
                    m.box_on_ground("fairing", (x0 + x1) / 2, s * (bw / 2 - 0.03), (bl, 0.78, 0.06), y0=floor + 0.55)
                m.solid("window", [[(x0, top, -bw / 2 + 0.1), (x0 - 0.5, top + 0.35, -bw / 2 + 0.1),
                                    (x0 - 0.5, top + 0.35, bw / 2 - 0.1), (x0, top, bw / 2 - 0.1)],
                                   [(x0 + 0.04, top + 0.02, -bw / 2 + 0.1), (x0 - 0.46, top + 0.37, -bw / 2 + 0.1),
                                    (x0 - 0.46, top + 0.37, bw / 2 - 0.1), (x0 + 0.04, top + 0.02, bw / 2 - 0.1)]])
            else:
                slanted_block(m, "fairing", x0, x1, floor + 0.55, top, bw / 2, -0.0, inset=0.04)
                m.box("window", (x0 - 0.01, floor + 0.95, 0), (0.02, 0.5, bw - 0.3))
            for s in (-1, 1):
                m.box("window", ((x0 + x1) / 2, floor + 0.95, s * (bw / 2 + 0.005)), (bl - 0.5, 0.4, 0.02))
            slots = _slots(x0 + 0.08, x1 - 0.08, fl, bw - 0.12)
        else:
            utility = body["id"] == "utility_bed"
            fl = open_bed(m, x0, x1, floor, bw, side_h=0.45, mat="bed" if not utility else livery,
                          head_h=0.9 if utility else None)
            if utility:                                                                          # rak + kotak perkakas
                m.box_on_ground("chassis", x1 - 0.25, 0, (0.4, 0.4, bw - 0.12), y0=fl + 0.45)
                for s in (-1, 1):
                    m.box_on_ground("frame", x0 + 0.1, s * (bw / 2 - 0.05), (0.06, 1.2, 0.06), y0=fl)
                    m.box("frame", ((x0 + x1 + cab_len) / 2 + 0.1, floor + 1.55, s * (bw / 2 - 0.05)),
                          (bl + cab_len - 0.2, 0.05, 0.05))
                m.box("frame", (x0 + 0.1, floor + 1.55, 0), (0.05, 0.05, bw))
            slots = _slots(x0 + 0.08, x1 - (0.5 if utility else 0.08), fl, bw - 0.12)
        taillights(m, x0, bw / 2 - 0.12, y=floor + 0.25)
        shadow(m, x0, front, width)
        return _finish(m, slots)

    if chassis.startswith("van"):
        spec = {"van_city": (1.66, 0.55, 1.95, 0.32, 0.12, False),
                "van_panel": (1.9, 0.95, 2.2, 0.36, 0.3, False),
                "van_highroof": (1.98, 0.95, 2.6, 0.38, 0.3, False),
                "van_large": (2.02, 1.0, 2.8, 0.4, 0.3, True)}[chassis]
        width, nose, height, r, slope_extra, dual = spec
        hw = width / 2
        cab = 1.1
        x1 = x0 + bl                                      # akhir ruang kargo, awal kabin
        front = x1 + cab + nose
        # kabin: badan bawah; ruang kargo: box tertutup atau berongga (pintu terbuka)
        m.box_on_ground(livery, (x1 + front) / 2, 0, (front - x1, 0.75, width), y0=0.4)
        if opened:
            hollow_box(m, livery, x0, x1, 0.4, height - 0.4, width)
        else:
            m.box_on_ground(livery, (x0 + x1) / 2, 0, (bl, height - 0.4, width), y0=0.4)
            m.box("frame", (x0 - 0.01, 0.4 + (height - 0.4) / 2, 0), (0.02, height - 0.5, 0.03))
            m.box("window", (x0 - 0.012, height - 0.55, 0), (0.02, 0.4, width - 0.5))
        slanted_block(m, livery, x1, x1 + cab, 1.15, height - (0.02 if chassis != "van_city" else 0.0), hw,
                      0.55 + slope_extra, inset=0.03)
        if nose > 0.6:                                    # kap miring ke depan
            m.solid(livery, [[(x1 + cab, 1.15, -hw), (front, 0.95, -hw + 0.05), (front, 0.95, hw - 0.05),
                              (x1 + cab, 1.15, hw)],
                             [(x1 + cab, 0.4, -hw), (front, 0.4, -hw + 0.05), (front, 0.4, hw - 0.05),
                              (x1 + cab, 0.4, hw)]])
        else:
            m.box_on_ground(livery, x1 + cab + nose / 2, 0, (nose, 0.75, width - 0.04), y0=0.4)
        windshield(m, x1 + cab + 0.005, x1 + cab - 0.55 - slope_extra + 0.005, 1.2, height - 0.12, hw - 0.12)
        for s in (-1, 1):
            m.box("window", (x1 + 0.45, 1.5, s * (hw + 0.005)), (0.6, 0.45, 0.02))
            m.box("door_line", (x1 + 0.05, 1.0, s * (hw + 0.005)), (0.02, 1.1, 0.012))
            m.box("door_line", (x1 - 0.85, 1.05, s * (hw + 0.005)), (0.02, height - 1.2, 0.012))       # pintu geser
            m.box("frame", (x1 - 1.45, height - 0.3, s * (hw + 0.005)), (1.2, 0.03, 0.02))           # rel pintu
            m.box("frame", (x1 + cab - 0.25, 1.35, s * (hw + 0.09)), (0.08, 0.14, 0.16))
        m.box("frame", (front + 0.02, 0.8, 0), (0.05, 0.22, width * 0.6))
        m.box("chassis", (front + 0.06, 0.48, 0), (0.12, 0.22, width + 0.02))
        m.box("chassis", (x0 - 0.04, 0.48, 0), (0.1, 0.22, width + 0.02))
        headlights(m, front + 0.03, 0.88, hw - 0.22)
        plate(m, front + 0.12, 0.48, front=True)
        taillights(m, x0, hw - 0.08, y=1.0)
        axle_r = x0 + bl * 0.28 if not dual else x0 + bl * 0.3
        wheels(m, (front - nose - 0.3 if nose > 0.6 else front - 0.65, axle_r), hw - 0.12, r, dual=dual)
        shadow(m, x0, front, width)
        slots = _slots(x0 + 0.06, x1 - 0.06, 0.45, width - 0.12)
        return _finish(m, slots)

    if chassis.startswith("tractor"):
        heavy_axle = chassis != "tractor_day"
        length = bl
        x1 = x0 + length
        fifth = x1 - 1.0                                   # kingpin di atas gandar belakang tractor
        floor = trailer(m, body["kind"], x0, length, "stripe" if livery != "stripe" else "cab_blue", opened)
        tx = fifth - (0.9 if heavy_axle else 0.3)          # gandar belakang tractor
        m.box_on_ground("chassis", fifth + 1.2, 0, (4.4, 0.32, 1.0), y0=0.72)
        m.box_on_ground("hazard", fifth, 0, (1.1, 0.12, 1.2), y0=1.05)                            # fifth wheel
        rear_axles = (tx, tx + 1.35) if heavy_axle else (tx,)
        wheels(m, rear_axles, 1.0, 0.52, dual=True)
        fenders(m, rear_axles, 1.0, 0.52)
        cab_x = fifth + 1.1
        if chassis in ("tractor_longnose", "tractor_hd"):
            front = cab_longnose(m, livery, cab_x + (1.1 if chassis == "tractor_hd" else 0.6), 1.6, 2.1, 2.45,
                                 1.55, sleeper=True, heavy=chassis == "tractor_hd")
            fx = front - 1.5
        else:
            sleeper = chassis != "tractor_day"
            front = cab_over(m, livery, cab_x + (0.7 if sleeper else 0.0), 1.9, 2.45, 1.95, 1.55, slope=0.14,
                             sleeper=sleeper, fairing=True, stripe="stripe" if livery == "body_white" else None,
                             visor=True, big_mirrors=True)
            fx = front - 1.0
        wheels(m, (fx,), 1.0, 0.52)
        for s in (-1, 1):
            fuel_tank(m, cab_x + 0.2, s * 1.05 if s > 0 else -1.0, r=0.3, length=1.2)
        shadow(m, x0, front, 2.5)
        if floor is not None and body["doors"]:
            slots = _slots(x0 + 0.15, x1 - 0.2, floor + 0.05, 2.3)
        return _finish(m, slots)

    # ---- truk cab-over (mini, engkel, sedang, tronton)
    t = TRUCKS[chassis]
    width, cab, floor, r = t["width"], t["cab"], t["floor"], t["r"]
    bw = width + (0.08 if kind not in ("open",) else 0.04)
    if kind in ("van",):
        raise ValueError("bodi van hanya untuk sasis van")
    x1 = x0 + bl
    cab_x = x1 + gap
    m.box_on_ground("chassis", (x0 + cab_x + cab) / 2 + 0.05, 0, (cab_x + cab - x0, 0.32, min(1.0, width - 0.6)),
                    y0=floor - 0.38)
    front = cab_over(m, livery, cab_x, cab, width, t["base"], t["h"], slope=t["slope"],
                     visor=t.get("visor", False), big_mirrors=width > 2.2,
                     stripe="stripe" if livery in ("body_white", "silver") and width > 1.8 else None)
    front_axle = cab_x + cab * 0.5
    rear = x0 + bl * (0.34 if chassis != "boxcar_semi" else 0.36)
    rear_axles = (rear - 0.7, rear + 0.65) if t.get("tandem") else (rear,)
    front_axles = (front_axle, front_axle - 1.3) if t.get("front2") else (front_axle,)
    wheels(m, front_axles, width / 2 - 0.16, r)
    wheels(m, rear_axles, width / 2 - 0.16, r, dual=t.get("dual", False))
    if width > 2.0:
        fenders(m, rear_axles, width / 2 - 0.16, r)
        fuel_tank(m, front_axle - cab * 0.5 - 0.65, width / 2 - 0.1, r=0.24, length=0.9)
        m.box("chassis", (front_axle - cab * 0.5 - 0.65, 0.75, -(width / 2 - 0.2)), (0.6, 0.4, 0.35))   # aki
    if width > 2.2:
        side_guard(m, max(rear_axles) + r + 0.15, front_axles[-1] - r - 0.15, width / 2)
    m.box("chassis", (x0 - 0.04, floor - 0.25, 0), (0.1, 0.24, width - 0.1))                     # bumper belakang
    taillights(m, x0 - 0.02, width / 2 - 0.15, y=floor - 0.1)
    shadow(m, x0, front, width)
    stripe = livery if livery not in ("body_white", "silver") else "stripe"
    h_box = {"mini_cabover": 2.1, "boxcar_semi": 1.9, "light_cabover": 2.3, "medium_cabover": 2.55,
             "heavy_cabover": 2.7, "mini_cabover_k": 1.5}[chassis]
    if kind in ("box", "reefer"):
        mat = "alu" if chassis == "boxcar_semi" else "box_body"
        closed_box(m, mat, x0, x1, floor, h_box, bw, opened, stripe=stripe if kind == "box" else "sign_blue",
                   rib="alu" if width > 2 else None, ribs=int(bl / 0.8) if width > 2 else 0)
        if kind == "reefer":
            reefer_unit(m, x1, floor + h_box, bw)
        slots = _slots(x0 + 0.1, x1 - 0.1, floor + 0.05, bw - 0.1)
    elif kind == "curtain":
        color = {"cab_green": "curtain_green", "cab_yellow": "curtain_yellow"}.get(livery, "curtain_blue")
        curtain(m, x0, x1, floor, h_box, bw, opened, color)
        slots = _slots(x0 + 0.1, x1 - 0.1, floor + 0.05, bw - 0.1)
    elif kind == "container":
        m.box_on_ground("bed", (x0 + x1) / 2 - 0.05, 0, (bl + 0.4, 0.14, bw), y0=floor - 0.12)
        container(m, x0 + 0.1, x1 - 0.1, floor + 0.02, h_box, bw, opened)
        slots = _slots(x0 + 0.2, x1 - 0.2, floor + 0.07, bw - 0.1)
    elif kind == "open":
        if body["id"] == "wood_bed_l":
            m.box_on_ground("wood_dark", (x0 + x1) / 2, 0, (bl, 0.12, bw + 0.04), y0=floor - 0.06)
            hw = (bw + 0.04) / 2
            for s in (-1, 1):
                m.box_on_ground("wood", (x0 + x1) / 2, s * (hw - 0.04), (bl, 0.95, 0.07), y0=floor + 0.06)
                for y in (floor + 0.38, floor + 0.7):
                    m.box("wood_dark", ((x0 + x1) / 2, y, s * hw), (bl, 0.05, 0.02))
            m.box_on_ground("wood", x0 + 0.03, 0, (0.07, 0.95, bw + 0.04), y0=floor + 0.06)
            m.box_on_ground("wood", x1 - 0.03, 0, (0.07, 1.3, bw + 0.04), y0=floor + 0.06)
            for x in (x0 + 0.03, x1 - 0.03):
                for s in (-1, 1):
                    m.box_on_ground("frame", x, s * (hw - 0.02), (0.1, 1.0, 0.1), y0=floor + 0.04)
            slots = _slots(x0 + 0.1, x1 - 0.1, floor + 0.06, bw - 0.08)
        else:
            dropside = body["id"] == "dropside_m"
            fl = open_bed(m, x0, x1, floor - 0.06, bw, side_h=0.5 if dropside else 0.38, mat="bed",
                          posts=dropside, head_h=1.1 if dropside else 0.6)
            slots = _slots(x0 + 0.08, x1 - 0.08, fl, bw - 0.12)
    elif kind == "flatbed":
        fl = flatbed(m, x0, x1, floor - 0.06, bw, head_h=1.1 if width < 2.2 else 1.3)
        slots = _slots(x0 + 0.1, x1 - 0.15, fl, bw - 0.1)
    elif kind == "dump":
        dump(m, x0, x1, floor, 0.75 if width < 2.4 else 1.0, bw, livery if livery != "body_white" else "bed",
             guard_len=gap + 0.1)
    elif kind == "tanker":
        rr = 0.88 if width < 2.2 else 1.1
        m.box_on_ground("chassis", (x0 + x1) / 2, 0, (bl, 0.12, 1.2), y0=floor - 0.1)
        tanker(m, x0 + 0.05, x1 - 0.05, floor - 0.02, rr)
    elif kind == "car_carrier":
        car_deck(m, x0, x1, floor, bw)
    elif kind == "crane":
        fl = flatbed(m, x0, x1 - 0.85, floor - 0.06, bw, head_h=0.6, stakes=False)
        m.box_on_ground("frame", x1 - 0.42, 0, (0.84, 0.12, bw), y0=floor - 0.06)
        crane(m, x1 - 0.42, floor + 0.06, "cab_yellow" if livery != "cab_yellow" else "cone")
        slots = _slots(x0 + 0.1, x1 - 0.95, fl, bw - 0.1)
    elif kind == "logs":
        log_bunks(m, x0, x1, floor - 0.06, bw)
    else:
        raise ValueError(f"bodi {kind} tidak didukung untuk {chassis}")
    if kind not in CARGO_BODIES:
        slots = []
    return _finish(m, slots)


def _finish(m: MeshBuilder, slots):
    """Geser ujung belakang ke x = -REAR (dihitung dari geometri)."""
    xmin = min(v[0] for p in m.parts.values() for v in p["pos"])
    dx = -REAR - xmin
    for p in m.parts.values():
        p["pos"] = [(x + dx, y, z) for x, y, z in p["pos"]]
    return m, [[round(x + dx, 3), round(y, 3), round(z, 3)] for x, y, z in slots]


def dimensions(m: MeshBuilder):
    pts = [v for p in m.parts.values() for v in p["pos"]]
    return (round(max(v[0] for v in pts) - min(v[0] for v in pts), 2),
            round(max(v[2] for v in pts) - min(v[2] for v in pts), 2),
            round(max(v[1] for v in pts), 2))


def depot_capable(model: dict) -> bool:
    """Kendaraan yang bisa masuk depot kota (bukan butuh terminal truk)."""
    return not (model.get("unlock") or {}).get("terminal", False)
