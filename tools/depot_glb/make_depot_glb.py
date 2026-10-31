#!/usr/bin/env python3
"""Generator aset GLB low-poly bergaya untuk depot Transport Manager.

Menghasilkan:
  base.glb + modul per level fasilitas (parking/gate/dock/warehouse/office_1..3),
  palang gerbang, penanda konstruksi; depot.glb = pratinjau depot awal (lahan 40×30 m, 3 slot parkir, gerbang + pos jaga,
                       loading area, gudang beratap pelana, kantor) beserta lingkungan:
                       jalan umum bermarka, trotoar, pohon, lampu, rumah tetangga
  kendaraan (+ varian _open), palet muatan, pekerja (+ memanggul kardus), props
  worker.glb         — pekerja berompi
  depot_layout.json  — titik penting depot untuk animasi kendaraan di app

Gaya: warna flat yang rapi + pencahayaan engine; tanpa tekstur. Semua bentuk
adalah solid cembung yang sisi-sisinya diorientasikan otomatis menghadap
keluar, sehingga tidak ada sisi yang tak sengaja ter-cull.

Koordinat: Y ke atas, satuan meter, origin di tengah lahan, gerbang di sisi +Z.
"""
from __future__ import annotations

import json
import math
import os
import struct
import sys

from geom import *  # noqa: F401,F403  (MATERIALS, FACES, MeshBuilder, write_glb, …)
from geom import MATERIALS, MeshBuilder, write_glb


# ---------------------------------------------------------------- tata letak

ROAD_Z = 24.0                 # sumbu jalan umum di depan gerbang
ROAD_LANE_Z = 22.25           # lajur kiri (lalu lintas Indonesia) arah timur, sisi depot
GATE_Z = 15.0
LANE_Z = 6.0                  # jalur utama di dalam depot (aspal z 3..9)
FACADE_Z = -5.5               # muka gudang (pintu dock)
PLATFORM_EDGE_Z = -2.95       # tepi platform dock
DOCK_Z = -0.25                # pusat kendaraan saat dimuat: bak tepat di depan platform
SLOT_W = 3.5
SLOT_Z = -4.0
SLOTS = [(round(-1.25 - i * SLOT_W, 2), SLOT_Z) for i in range(8)]
DOCKS = {1: [11.0], 2: [8.5, 13.5], 3: [6.0, 10.0, 14.0]}
GATE_LANES = {1: [0.0], 2: [0.0], 3: [-2.5, 2.5]}
GATE_GAP = 5.3               # celah pagar untuk gerbang (gerbang level 3 paling lebar)

# Titik penting depot untuk animasi kendaraan & penempatan modul di app.
LAYOUT = {
    "outside": (0.0, ROAD_Z),
    "road_lane_z": ROAD_LANE_Z,
    "gate": (0.0, GATE_Z),
    "lane_z": LANE_Z,
    "parking_slots": SLOTS,
    "loading_dock": (11.0, -6.0),
    "dock_stop": (11.0, DOCK_Z),
    "docks": {str(k): [(x, DOCK_Z) for x in v] for k, v in DOCKS.items()},
    "gate_lanes": {str(k): v for k, v in GATE_LANES.items()},
    "booms": {
        "1": [{"hinge": (-3.75, GATE_Z), "model": "boom_long", "side": 1}],
        "2": [{"hinge": (-3.75, GATE_Z), "model": "boom_long", "side": 1}],
        "3": [{"hinge": (-4.65, GATE_Z), "model": "boom_short", "side": 1},
              {"hinge": (4.65, GATE_Z), "model": "boom_short_r", "side": -1}],
    },
    # Titik penanda konstruksi per fasilitas (di luar jalur kendaraan).
    "anchors": {
        "parking": (-24.0, -12.0),
        "workshop": (-7.75, -12.5),
        "gate": (9.5, 17.3),
        "loading_dock": (17.0, 1.0),
        "warehouse": (1.5, -11.0),
        "office": (-14.0, 17.5),
    },
}


def tree(m: MeshBuilder, x, z, s=1.0, light=False):
    m.cylinder("trunk", (x, 0.9 * s, z), 0.18 * s, 1.8 * s, sides=6)
    leaf = "leaf_light" if light else "leaf"
    m.cone(leaf, x, z, 1.4 * s, 1.5 * s, 2.2 * s, sides=7)
    m.cone(leaf, x, z, 2.6 * s, 1.1 * s, 1.9 * s, sides=7)
    m.block_box(x, z, 0.5 * s, 0.5 * s)


def bush(m: MeshBuilder, x, z, s=1.0):
    m.cone("leaf_light", x, z, 0.0, 0.8 * s, 0.9 * s, sides=6, top_radius=0.35 * s)
    m.block_box(x, z, 1.6 * s, 1.6 * s)


def lamp(m: MeshBuilder, x, z, facing_x=1.0):
    m.cylinder("pole", (x, 3.0, z), 0.08, 6.0, sides=6)
    m.box("pole", (x + 0.5 * facing_x, 6.0, z), (1.1, 0.1, 0.12))
    m.box("lamp", (x + 0.95 * facing_x, 5.92, z), (0.45, 0.08, 0.3))
    m.block_box(x, z, 0.3, 0.3)


def house(m: MeshBuilder, x, z, w, d, wall):
    m.box_on_ground(wall, x, z, (w, 3.0, d))
    m.gable_roof("tile", x, z, w + 0.6, d + 0.6, 3.0, 1.6)
    m.box_on_ground("frame", x, z - d / 2 - 0.02, (1.0, 2.0, 0.06))
    for dx in (-w / 4 - 0.4, w / 4 + 0.4):
        m.box_on_ground("glass", x + dx, z - d / 2 - 0.02, (1.1, 0.9, 0.05), y0=1.2)
    m.block_box(x, z, w + 0.6, d + 0.6)


def fence_run(m: MeshBuilder, x0, z0, x1, z1):
    length = math.hypot(x1 - x0, z1 - z0)
    n = max(1, int(length // 3.5))
    for i in range(n + 1):
        t = i / n
        m.box_on_ground("fence", x0 + (x1 - x0) * t, z0 + (z1 - z0) * t, (0.12, 1.9, 0.12))
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    along_x = abs(x1 - x0) > abs(z1 - z0)
    for y in (0.7, 1.6):
        m.box("fence", (cx, y, cz), (length, 0.06, 0.06) if along_x else (0.06, 0.06, length))
    m.block(x0 - 0.08, z0 - 0.08, x1 + 0.08, z1 + 0.08)


# ---------------------------------------------------------------- base (tidak ikut upgrade)

def build_base() -> MeshBuilder:
    m = MeshBuilder()
    m.box("grass", (0, -0.1, 4), (140, 0.2, 110))
    m.box("yard", (0, 0.0, 0), (40, 0.04, 30))
    # jalan umum + trotoar + marka; akses gerbang
    m.box("asphalt", (0, 0.01, ROAD_Z), (140, 0.04, 7))
    for side in (-1, 1):
        m.box("curb", (0, 0.08, ROAD_Z + side * 4.25), (140, 0.16, 1.5))
    for i in range(-17, 18):
        m.box("marking", (i * 4.0, 0.035, ROAD_Z), (2.0, 0.01, 0.15))
    m.box("asphalt", (0, 0.02, 18.5), (2 * GATE_GAP, 0.04, 7))
    # jalur dalam depot
    m.box("asphalt", (0, 0.025, LANE_Z), (40, 0.03, 6))
    m.box("asphalt", (0, 0.025, 12.05), (2 * GATE_GAP, 0.03, 6.1))
    m.box("asphalt", (11, 0.025, -1.0), (14, 0.03, 8))
    m.box("marking_y", (0, 0.045, LANE_Z - 3.05), (40, 0.01, 0.15))
    # pagar: utara (celah gerbang), timur, selatan
    fence_run(m, -20, 15, -GATE_GAP, 15)
    fence_run(m, GATE_GAP, 15, 20, 15)
    fence_run(m, 20, -15, 20, 15)
    fence_run(m, -20, -15, 20, -15)
    lamp(m, 19.2, -9.0, -1.0)
    lamp(m, -7.5, 14.5, -1.0)
    # pohon & rumah tetangga (di luar pagar)
    for x, z, s, light in [
        (26, -12, 1.3, True), (27, -1, 1.0, False), (25, 10, 1.15, True), (2, -22, 1.25, False),
        (15, -21, 1.0, True), (-12, -22, 1.1, True), (35, 16, 1.2, False), (40, -10, 1.3, True),
        (-40, 12, 1.1, False), (-42, -6, 1.3, True), (-38, -20, 1.0, False),
    ]:
        tree(m, x, z, s, light)
    for x in (-30, -15, 15, 30):
        tree(m, x, ROAD_Z + 6.5, 0.9, light=x > 0)
    for x, w, d, wall in [(-36, 9, 7, "house_a"), (-22, 8, 7, "house_b"), (21, 9, 7, "house_c"), (35, 8, 7, "house_a")]:
        house(m, x, ROAD_Z + 11.5, w, d, wall)
    return m


# ---------------------------------------------------------------- modul fasilitas

def build_parking(level: int) -> MeshBuilder:
    m = MeshBuilder()
    count = {1: 3, 2: 5, 3: 8}[level]
    west = SLOTS[count - 1][0] - SLOT_W / 2
    east = SLOTS[0][0] + SLOT_W / 2
    m.box("concrete", ((west + east) / 2, 0.03, SLOT_Z), (east - west, 0.03, 7.5))
    for i in range(count + 1):
        m.box("marking", (east - i * SLOT_W, 0.05, SLOT_Z), (0.12, 0.01, 6.5))
    for i in range(count):                                   # stopper roda (di bawah bodi, bukan rintangan)
        m.box("wall_base", (SLOTS[i][0], 0.08, SLOT_Z - 3.3), (1.6, 0.12, 0.2))
    if level < 3:
        fence_run(m, -20, -15, -20, 15)
        lamp(m, -18.6, -9.5)
    else:
        # perluasan lahan ke barat
        m.box("yard", (-25, 0.0, 0), (10, 0.04, 30))
        m.box("asphalt", (-25, 0.025, LANE_Z), (10, 0.03, 6))
        m.box("marking_y", (-25, 0.045, LANE_Z - 3.05), (10, 0.01, 0.15))
        fence_run(m, -30, -15, -30, 15)
        fence_run(m, -30, 15, -20, 15)
        fence_run(m, -30, -15, -20, -15)
        lamp(m, -28.8, 12.0)
        lamp(m, -28.8, -9.5)
    return m


def build_gate(level: int) -> MeshBuilder:
    m = MeshBuilder()
    px = 5.0 if level == 3 else 4.1                         # pilar
    for x in (-px, px):
        m.box_on_ground("concrete", x, GATE_Z, (0.6, 2.6, 0.6))
        m.box_on_ground("gate_red" if level == 1 else "accent", x, GATE_Z, (0.64, 0.3, 0.64), y0=2.0)
        m.block_box(x, GATE_Z, 0.64, 0.64)
    if level < 3:                                           # pagar pengisi sampai celah gerbang
        for side in (-1, 1):
            m.box_on_ground("fence", side * (px + 0.55), GATE_Z, (0.8, 1.9, 0.12))
            m.block(side * (px + 0.3), GATE_Z - 0.08, side * GATE_GAP, GATE_Z + 0.08)
    if level == 1:
        m.box_on_ground("office", 6.4, 12.8, (2.0, 2.4, 2.0))
        m.box_on_ground("glass", 6.4, 13.82, (1.4, 0.8, 0.04), y0=1.1)
        m.box("roof_dark", (6.4, 2.5, 12.8), (2.5, 0.18, 2.5))
        m.block_box(6.4, 12.8, 2.5, 2.5)
    else:
        m.box_on_ground("office", 7.0, 12.4, (3.0, 2.8, 2.6))
        m.box_on_ground("glass", 7.0, 13.72, (2.4, 1.0, 0.04), y0=1.2)
        m.box("roof_dark", (7.0, 2.9, 12.4), (3.6, 0.2, 3.2))
        m.box("accent", (7.0, 2.62, 13.73), (3.0, 0.22, 0.04))
        m.block_box(7.0, 12.4, 3.6, 3.2)
        for x in (-px, px):                                 # lampu lalu lintas
            m.box("frame", (x, 2.95, GATE_Z), (0.3, 0.6, 0.3))
            m.box("light_green", (x, 3.1, GATE_Z + 0.16), (0.16, 0.14, 0.02))
            m.box("light_red", (x, 2.82, GATE_Z + 0.16), (0.16, 0.14, 0.02))
    if level == 3:
        m.box_on_ground("curb", 0, GATE_Z, (0.6, 0.25, 3.0))  # pulau pembatas 2 jalur
        m.box_on_ground("concrete", 0, GATE_Z, (0.5, 2.6, 0.5))
        m.block_box(0, GATE_Z, 0.6, 3.0)
        m.box("canopy", (0, 4.7, GATE_Z), (11.2, 0.25, 4.0))  # kanopi (di atas, bukan rintangan)
        m.box("accent", (0, 4.55, GATE_Z + 2.0), (11.2, 0.3, 0.06))
        for x in (-px, px):
            m.box_on_ground("pole", x, GATE_Z + 1.8, (0.18, 4.6, 0.18))
            m.block_box(x, GATE_Z + 1.8, 0.18, 0.18)
        m.box("marking", (0, 0.05, 12.0), (0.15, 0.01, 6.0))
    return m


def build_boom(length: float, direction: int) -> MeshBuilder:
    """Palang gerbang, engsel di origin, memanjang ke arah ±X; diangkat app."""
    m = MeshBuilder()
    m.box("frame", (0, 0.55, 0), (0.45, 1.1, 0.45))           # rumah motor
    seg = length / 8
    for i in range(8):
        mat = "gate_red" if i % 2 == 0 else "gate_white"
        m.box(mat, (direction * (0.2 + seg * (i + 0.5)), 1.0, 0), (seg, 0.13, 0.13))
    return m


def build_dock(level: int) -> MeshBuilder:
    m = MeshBuilder()
    xs = DOCKS[level]
    door_z = FACADE_Z + 0.04
    depth = FACADE_Z - PLATFORM_EDGE_Z
    for x in xs:
        m.box_on_ground("door", x, door_z, (3.4, 3.8, 0.06))
        for i in range(1, 8):
            m.box("door_line", (x, i * 0.48, door_z + 0.035), (3.4, 0.05, 0.02))
        m.box_on_ground("frame", x, door_z + 0.02, (3.8, 0.2, 0.1), y0=3.8)
        m.box_on_ground("concrete", x, (FACADE_Z + PLATFORM_EDGE_Z) / 2, (3.9, 1.1, -depth))
        m.box("marking_y", (x, 1.11, PLATFORM_EDGE_Z + 0.08), (3.9, 0.02, 0.15))
        for dx in (-1.2, 1.2):
            m.box_on_ground("rubber", x + dx, PLATFORM_EDGE_Z + 0.03, (0.35, 0.5, 0.12), y0=0.45)
        if level == 3:                                       # dock leveler + lampu
            m.box("pole", (x, 1.12, PLATFORM_EDGE_Z + 0.2), (2.2, 0.04, 0.4))
            m.box("lamp", (x + 1.75, 3.2, FACADE_Z + 0.25), (0.3, 0.2, 0.3))
        m.block(x - 1.95, FACADE_Z, x + 1.95, PLATFORM_EDGE_Z)
    if level == 3:
        m.box("canopy", (10.0, 4.6, FACADE_Z + 1.3), (13.0, 0.18, 2.8))
    # palet & karton di tanah, di samping gudang (luar jalur manuver)
    for i, pz in enumerate([-4.6, -3.45, -2.3][: 2 + (level > 1)]):
        m.box_on_ground("wood", 19.05, pz, (0.95, 0.14, 0.95))
        m.box_on_ground("carton", 19.05, pz, (0.85, 0.55 + 0.2 * (i % 2), 0.85), y0=0.14)
        m.block_box(19.05, pz, 0.95, 0.95)
    return m


def build_warehouse(level: int) -> MeshBuilder:
    m = MeshBuilder()
    ww, wd, wh = {1: (14.0, 9.0, 5.6), 2: (16.0, 9.0, 6.6), 3: (16.0, 9.0, 7.6)}[level]
    wx = 10.0 if level == 1 else 11.0
    wz = FACADE_Z - wd / 2
    m.box_on_ground("wall_base", wx, wz, (ww + 0.1, 0.6, wd + 0.1))
    m.box_on_ground("wall", wx, wz, (ww, wh, wd))
    m.box("accent", (wx, wh - 0.35, FACADE_Z + 0.03), (ww, 0.5, 0.06))
    m.gable_roof("roof", wx, wz, ww + 0.8, wd + 1.2, wh, 1.8)
    m.box("roof_dark", (wx, wh + 1.82, wz), (ww + 0.9, 0.12, 0.3))
    for dz in (-2.5, 0.0, 2.5):
        m.box_on_ground("glass", wx - ww / 2 - 0.03, wz + dz, (0.05, 0.7, 1.6), y0=wh - 1.8)
    m.block(wx - ww / 2 - 0.05, FACADE_Z - wd - 0.05, wx + ww / 2 + 0.05, FACADE_Z)
    if level >= 2:                                           # kolom fasad & jendela atas
        for dx in (-ww / 2 + 0.2, ww / 2 - 0.2):
            m.box_on_ground("wall_base", wx + dx, FACADE_Z + 0.06, (0.4, wh, 0.12))
        m.box_on_ground("glass", wx, FACADE_Z + 0.04, (ww - 2, 0.6, 0.05), y0=wh - 1.4)
    if level == 3:                                           # panel surya & rak tinggi di sisi barat
        for i in range(4):
            x0 = wx - ww / 2 + 1.2 + i * 3.6
            m.solid("solar", [
                [(x0, wh + 0.35, wz - 3.8), (x0 + 3.0, wh + 0.35, wz - 3.8),
                 (x0 + 3.0, wh + 1.25, wz - 1.2), (x0, wh + 1.25, wz - 1.2)],
                [(x0, wh + 0.45, wz - 3.8), (x0 + 3.0, wh + 0.45, wz - 3.8),
                 (x0 + 3.0, wh + 1.35, wz - 1.2), (x0, wh + 1.35, wz - 1.2)],
                [(x0, wh + 0.35, wz - 3.8), (x0, wh + 0.45, wz - 3.8), (x0, wh + 1.35, wz - 1.2), (x0, wh + 1.25, wz - 1.2)],
                [(x0 + 3.0, wh + 0.35, wz - 3.8), (x0 + 3.0, wh + 0.45, wz - 3.8),
                 (x0 + 3.0, wh + 1.35, wz - 1.2), (x0 + 3.0, wh + 1.25, wz - 1.2)],
            ])
        for i in range(3):
            x = wx - ww / 2 - 1.4
            m.box_on_ground("rack", x, wz - 2.7 + i * 2.7, (1.2, 3.2, 2.2))
            for y in (1.0, 2.1):
                m.box_on_ground("carton", x, wz - 2.7 + i * 2.7, (1.0, 0.7, 2.0), y0=y)
        m.block(wx - ww / 2 - 2.0, wz - 3.8, wx - ww / 2, wz + 3.8)
    return m


def build_office(level: int) -> MeshBuilder:
    """Kantor di utara jalur utama (z 9.7..14.7), tidak menutupi jalan."""
    m = MeshBuilder()
    ox, oz, ow, od = -14.0, 12.2, 8.0, 5.0
    floors = 1 if level == 1 else 2
    oh = 3.6 * floors
    front = oz - od / 2
    m.box_on_ground("wall_base", ox, oz, (ow + 0.1, 0.4, od + 0.1))
    m.box_on_ground("office", ox, oz, (ow, oh, od))
    m.box("roof_dark", (ox, oh + 0.12, oz), (ow + 0.5, 0.24, od + 0.5))
    m.box("accent", (ox, oh - 0.3, front - 0.03), (ow, 0.35, 0.06))
    for f in range(floors):
        y0 = 1.1 + f * 3.6
        m.box_on_ground("glass", ox - 1.0, front - 0.03, (4.6, 1.3, 0.05), y0=y0)
        for dx in (-3.3, -1.0, 1.3):
            m.box_on_ground("frame", ox + dx, front - 0.05, (0.08, 1.3, 0.06), y0=y0)
    m.box_on_ground("frame", ox + 2.6, front - 0.03, (1.0, 2.2, 0.06))
    m.box_on_ground("door", ox + 2.0, oz + 0.8, (1.2, 0.7, 0.9), y0=oh + 0.24)
    m.block(ox - ow / 2 - 0.25, oz - od / 2 - 0.25, ox + ow / 2 + 0.25, oz + od / 2 + 0.25)
    if level == 3:                                           # sayap ruang dispatcher + tiang bendera
        wx, wz = ox + 6.6, oz + 0.4
        m.box_on_ground("office", wx, wz, (4.6, 3.6, 4.0))
        m.box_on_ground("glass", wx, wz - 2.03, (3.4, 1.3, 0.05), y0=1.1)
        m.box("roof_dark", (wx, 3.72, wz), (5.1, 0.24, 4.5))
        m.block(wx - 2.55, wz - 2.25, wx + 2.55, wz + 2.25)
        m.cylinder("pole", (ox - 4.9, 3.5, 9.8), 0.06, 7.0, sides=6)
        m.box("gate_red", (ox - 4.3, 6.6, 9.8), (1.2, 0.4, 0.04))
        m.box("gate_white", (ox - 4.3, 6.2, 9.8), (1.2, 0.4, 0.04))
        m.block_box(ox - 4.9, 9.8, 0.2, 0.2)
    bush(m, ox - ow / 2 - 0.9, oz + 1.0, 0.8)
    return m


def build_workshop(level: int) -> MeshBuilder:
    """Bengkel di selatan area parkir. Level 1: gudang perkakas (servis di bengkel luar)."""
    m = MeshBuilder()
    if level == 1:
        m.box_on_ground("wall", -2.5, -13.6, (2.4, 2.2, 1.8))
        m.box("roof_dark", (-2.5, 2.3, -13.6), (2.7, 0.15, 2.1))
        m.box_on_ground("door", -2.5, -12.68, (1.0, 1.8, 0.05))
        for i in range(3):
            m.cylinder("tire", (-4.2, 0.15 + i * 0.3, -13.9), 0.42, 0.26, sides=10)
        m.block(-4.7, -14.55, -1.25, -12.6)
        return m
    x0, x1 = (-12.0, -3.5) if level == 2 else (-13.0, -1.0)
    z0, z1 = -14.6, -10.4
    h = 4.4 if level == 2 else 5.2
    cx = (x0 + x1) / 2
    m.box_on_ground("wall_base", cx, (z0 + z1) / 2, (x1 - x0 + 0.1, 0.5, z1 - z0 + 0.1))
    m.box_on_ground("wall", cx, (z0 + z1) / 2, (x1 - x0, h, z1 - z0))
    m.box("roof_dark", (cx, h + 0.12, (z0 + z1) / 2), (x1 - x0 + 0.5, 0.24, z1 - z0 + 0.5))
    m.box("accent", (cx, h - 0.35, z1 + 0.03), (x1 - x0, 0.45, 0.06))
    bays = 1 if level == 2 else 2
    width = (x1 - x0) / bays
    for b in range(bays):
        dx = x0 + width * (b + 0.5)
        m.box_on_ground("door", dx, z1 + 0.04, (3.4, 3.4, 0.06))
        for i in range(1, 7):
            m.box("door_line", (dx, i * 0.5, z1 + 0.075), (3.4, 0.05, 0.02))
        m.box_on_ground("frame", dx, z1 + 0.06, (3.8, 0.18, 0.1), y0=3.4)
    # rak ban & kotak perkakas di sisi
    for i in range(3):
        m.cylinder("tire", (x1 + 0.7, 0.15 + i * 0.3, -11.2), 0.42, 0.26, sides=10)
    m.box_on_ground("gate_red", x1 + 0.7, -12.4, (0.6, 0.9, 0.5))
    if level == 3:                                           # crane gantry di atap
        m.box("frame", (cx, h + 0.8, z1 - 0.6), (x1 - x0 - 1, 0.25, 0.25))
        for x in (x0 + 0.6, x1 - 0.6):
            m.box_on_ground("frame", x, z1 - 0.6, (0.25, 0.8, 0.25), y0=h + 0.24)
    m.block(x0 - 0.05, z0 - 0.05, x1 + 1.05, z1 + 0.1)
    return m


def build_construction() -> MeshBuilder:
    """Penanda area konstruksi: pagar pembatas + kerucut, diletakkan di anchor."""
    m = MeshBuilder()
    for x in (-2.0, 0.0, 2.0):
        m.box_on_ground("barrier", x, 0, (1.8, 0.25, 0.12), y0=0.75)
        m.box("cone", (x, 0.6, 0), (1.8, 0.12, 0.13))
        for dx in (-0.8, 0.8):
            m.box_on_ground("pole", x + dx, 0, (0.08, 0.9, 0.3))
    for x, z in ((-3.2, 1.2), (3.2, 1.2), (-3.2, -1.2), (3.2, -1.2)):
        m.cone("cone", x, z, 0.0, 0.28, 0.75, sides=8, top_radius=0.04)
        m.box_on_ground("cone", x, z, (0.55, 0.05, 0.55))
    m.block(-3.5, -1.5, 3.5, 1.5)
    return m


# ---------------------------------------------------------------- kendaraan & pekerja
# Kendaraan dirakit dari katalog (vehicles.py + content/vehicle_models.json).

import vehicles  # noqa: E402

CATALOG = vehicles.load_catalog()
CRATE = vehicles.CRATE
# Kendaraan yang bisa masuk depot kota (punya GLB); yang butuh terminal truk hanya thumbnail.
VEHICLES = tuple(m["id"] for m in CATALOG["models"] if vehicles.depot_capable(m))
BODY_DOORS = {b["id"]: b["doors"] for b in CATALOG["bodies"]}
VEHICLES_WITH_DOORS = tuple(m["id"] for m in CATALOG["models"] if vehicles.depot_capable(m) and BODY_DOORS[m["body"]])
_MODELS = {m["id"]: m for m in CATALOG["models"]}


def build_vehicle(model_id: str, opened: bool = False):
    return vehicles.build_vehicle(_MODELS[model_id], CATALOG, opened)


def build_cargo_crate() -> MeshBuilder:
    """Satu palet muatan: palet kayu + kardus bertumpuk (origin di lantai)."""
    m = MeshBuilder()
    m.box_on_ground("wood", 0, 0, (CRATE, 0.1, CRATE))
    s = CRATE / 2 - 0.02
    for dx in (-s / 2, s / 2):
        for dz in (-s / 2, s / 2):
            m.box_on_ground("carton", dx, dz, (s - 0.02, 0.26, s - 0.02), y0=0.1)
    for dz in (-s / 2, s / 2):
        m.box_on_ground("carton_light", -s / 2 + 0.05, dz, (s - 0.02, 0.24, s - 0.02), y0=0.36)
    m.box("tape", (0, 0.36, 0), (CRATE - 0.06, 0.005, 0.06))
    return m


def build_worker(carry: bool = False) -> MeshBuilder:
    """Pekerja berompi, menghadap +X. carry=True: memanggul kardus di depan dada."""
    m = MeshBuilder()
    for dz in (-0.1, 0.1):
        m.box_on_ground("boots", 0.03, dz, (0.26, 0.1, 0.14))
        m.box_on_ground("pants", 0, dz, (0.17, 0.78, 0.16), y0=0.1)
    m.box_on_ground("shirt", 0, 0, (0.26, 0.6, 0.44), y0=0.86)
    m.box_on_ground("vest", 0, 0, (0.28, 0.5, 0.46), y0=0.92)
    m.box("reflect", (0, 1.15, 0), (0.29, 0.06, 0.47))
    if carry:
        for dz in (-0.25, 0.25):
            m.box("shirt", (0.2, 1.25, dz), (0.36, 0.11, 0.11))        # lengan ke depan
            m.box("skin", (0.4, 1.25, dz * 0.9), (0.08, 0.11, 0.1))
        m.box_on_ground("carton", 0.38, 0, (0.36, 0.32, 0.42), y0=1.12)
        m.box("tape", (0.38, 1.441, 0), (0.37, 0.004, 0.06))
    else:
        for dz in (-0.29, 0.29):
            m.box_on_ground("shirt", 0, dz, (0.13, 0.55, 0.12), y0=0.9)
            m.box_on_ground("skin", 0, dz, (0.12, 0.12, 0.11), y0=0.8)
    m.box_on_ground("skin", 0, 0, (0.22, 0.24, 0.22), y0=1.48)
    m.cone("helmet", 0, 0, 1.68, 0.17, 0.14, sides=8, top_radius=0.11)
    m.box("helmet", (0.1, 1.69, 0), (0.12, 0.03, 0.3))
    return m


def build_forklift(m: MeshBuilder, x, z, facing: int = -1):
    """Forklift kuning (diletakkan langsung di modul props)."""
    f = facing
    m.box_on_ground("cab_yellow", x, z, (1.6, 0.9, 1.05), y0=0.25)
    m.box_on_ground("chassis", x - f * 0.55, z, (0.5, 0.75, 1.0), y0=0.3)                  # pemberat
    m.box_on_ground("rubber", x - f * 0.1, z, (0.45, 0.12, 0.5), y0=1.15)                   # kursi
    for dz in (-0.45, 0.45):
        m.box_on_ground("chassis", x - f * 0.35, z + dz, (0.06, 1.3, 0.06), y0=1.15)        # rangka atap
        m.box_on_ground("pole", x + f * 0.82, z + dz * 0.6, (0.08, 2.4, 0.08))              # tiang
    m.box("chassis", (x - f * 0.05, 2.47, z), (0.85, 0.06, 1.0))
    for dz in (-0.25, 0.25):
        m.box_on_ground("pole", x + f * 1.35, z + dz, (1.0, 0.05, 0.1), y0=0.08)             # garpu
    for wx in (x + f * 0.5, x - f * 0.5):
        for dz in (-0.48, 0.48):
            m.cylinder("tire", (wx, 0.25, z + dz), 0.25, 0.2, axis="z", sides=8)
    m.block(x - 1.9, z - 0.6, x + 1.9, z + 0.6)


def build_props() -> MeshBuilder:
    """Dekorasi & properti depot (tetap, tidak ikut upgrade), di luar jalur kendaraan."""
    m = MeshBuilder()
    # --- area istirahat (gazebo) di timur laut
    gx, gz = 12.0, 12.0
    for dx in (-1.8, 1.8):
        for dz in (-1.6, 1.6):
            m.box_on_ground("wood_dark", gx + dx, gz + dz, (0.14, 2.5, 0.14))
    m.gable_roof("tile", gx, gz, 4.6, 4.2, 2.5, 1.0)
    m.box_on_ground("wood", gx, gz, (1.8, 0.08, 0.9), y0=0.72)                                # meja
    m.box_on_ground("wood_dark", gx, gz, (0.12, 0.72, 0.12))
    for dz in (-0.85, 0.85):
        m.box_on_ground("wood", gx, gz + dz, (1.8, 0.07, 0.32), y0=0.42)                      # bangku
        m.box_on_ground("wood_dark", gx, gz + dz, (1.6, 0.42, 0.08))
    m.box_on_ground("galon", gx + 1.4, gz - 1.2, (0.3, 0.45, 0.3), y0=0.0)                   # galon minum
    m.block(gx - 2.3, gz - 2.1, gx + 2.3, gz + 2.1)
    # --- parkir motor karyawan
    for i, color in enumerate(("cab_red", "cab_blue", "chassis", "cab_red")):
        bx, bz = 15.6 + i * 1.0, 10.7
        m.box_on_ground(color, bx, bz, (0.32, 0.45, 1.3), y0=0.35)
        m.box_on_ground("rubber", bx, bz - 0.15, (0.28, 0.1, 0.6), y0=0.8)
        for dz in (-0.62, 0.62):
            m.cylinder("tire", (bx, 0.3, bz + dz), 0.3, 0.1, axis="x", sides=8)
        m.box("pole", (bx, 1.05, bz + 0.6), (0.6, 0.05, 0.05))
        m.block(bx - 0.35, bz - 0.95, bx + 0.35, bz + 0.95)
    m.box("marking", (17.1, 0.05, 10.7), (4.2, 0.01, 0.08))
    # --- mobil staf (hatchback)
    cx, cz = 17.0, 13.4
    m.box_on_ground("car_teal", cx, cz, (3.6, 0.65, 1.62), y0=0.3)
    m.box_on_ground("car_teal", cx - 0.25, cz, (2.1, 0.55, 1.5), y0=0.95)
    m.box_on_ground("window", cx - 0.25, cz, (2.12, 0.36, 1.52), y0=1.05)
    for wx in (cx + 1.15, cx - 1.15):
        for dz in (-0.78, 0.78):
            m.cylinder("tire", (wx, 0.3, cz + dz), 0.3, 0.18, axis="z", sides=8)
    m.block(cx - 1.85, cz - 0.9, cx + 1.85, cz + 0.9)
    # --- sisi barat daya: kontainer bekas, menara air, genset, tumpukan ban
    kx, kz = -16.5, -13.2
    m.box_on_ground("container_red", kx, kz, (6.0, 2.6, 2.4))
    for i in range(15):
        x = kx - 2.8 + i * 0.4
        for side in (-1, 1):
            m.box("container_red_rib", (x, 1.3, kz + side * 1.215), (0.1, 2.4, 0.03))
    m.block(kx - 3.05, kz - 1.25, kx + 3.05, kz + 1.25)
    tx, tz = -14.4, -10.3
    for dx in (-0.6, 0.6):
        for dz in (-0.6, 0.6):
            m.box_on_ground("pole", tx + dx, tz + dz, (0.1, 3.2, 0.1))
    m.cylinder("tank", (tx, 3.9, tz), 0.85, 1.4, sides=10)
    m.cone("roof_dark", tx, tz, 4.6, 0.9, 0.4, sides=10)
    m.block(tx - 0.9, tz - 0.9, tx + 0.9, tz + 0.9)
    m.box_on_ground("genset", -18.6, -10.3, (1.6, 1.2, 1.0))
    for i in range(4):
        m.box("pole", (-18.6 - 0.5 + i * 0.33, 0.8, -10.3 - 0.51), (0.18, 0.5, 0.02))
    m.block(-19.45, -10.85, -17.75, -9.75)
    for i in range(3):
        m.cylinder("tire", (-16.8, 0.15 + i * 0.3, -10.1), 0.45, 0.28, sides=10)
    m.block(-17.3, -10.6, -16.3, -9.6)
    # --- tong sampah di samping kantor
    for i, color in enumerate(("bin_green", "bin_orange")):
        m.cylinder(color, (-19.25, 0.45, 10.4 + i * 0.75), 0.3, 0.9, sides=8)
    m.block(-19.6, 10.05, -18.9, 11.5)
    # --- forklift parkir di sisi timur dock
    build_forklift(m, 18.55, 1.2, facing=-1)
    # --- papan nama perusahaan & pot bunga di luar pagar utara
    for x in (-8.9, -6.1):
        m.box_on_ground("pole", x, 17.4, (0.12, 2.2, 0.12))
    m.box_on_ground("frame", -7.5, 17.4, (3.4, 1.1, 0.12), y0=1.3)
    m.box_on_ground("accent", -7.5, 17.33, (3.2, 0.35, 0.02), y0=1.65)
    m.block(-9.0, 17.3, -6.0, 17.5)
    for x in (14.5, 16.5, 18.5):
        m.box_on_ground("concrete", x, 15.9, (1.2, 0.45, 0.6))
        m.cone("leaf_light", x, 15.9, 0.45, 0.5, 0.55, sides=6, top_radius=0.2)
        m.block(x - 0.6, 15.6, x + 0.6, 16.2)
    return m


def merge(*builders: MeshBuilder) -> MeshBuilder:
    out = MeshBuilder()
    for b in builders:
        for mat, data in b.parts.items():
            p = out.parts.setdefault(mat, {"pos": [], "nrm": [], "idx": []})
            base = len(p["pos"])
            p["pos"] += data["pos"]
            p["nrm"] += data["nrm"]
            p["idx"] += [i + base for i in data["idx"]]
        out.blocks += b.blocks
    return out


def build_depot() -> MeshBuilder:
    """Depot lengkap level 1 dalam satu file (spike & pratinjau); palang di posisi tutup."""
    boom = build_boom(7.0, 1)
    hx, hz = LAYOUT["booms"]["1"][0]["hinge"]
    for p in boom.parts.values():
        p["pos"] = [(x + hx, y, z + hz) for x, y, z in p["pos"]]
    return merge(build_base(), build_props(), build_parking(1), build_gate(1), boom, build_dock(1),
                 build_warehouse(1), build_office(1), build_workshop(1))


def models() -> dict:
    out = {"base": build_base(), "props": build_props(), "construction": build_construction()}
    for lvl in (1, 2, 3):
        out[f"parking_{lvl}"] = build_parking(lvl)
        out[f"gate_{lvl}"] = build_gate(lvl)
        out[f"dock_{lvl}"] = build_dock(lvl)
        out[f"warehouse_{lvl}"] = build_warehouse(lvl)
        out[f"office_{lvl}"] = build_office(lvl)
        out[f"workshop_{lvl}"] = build_workshop(lvl)
    out["boom_long"] = build_boom(7.0, 1)
    out["boom_short"] = build_boom(4.0, 1)
    out["boom_short_r"] = build_boom(4.0, -1)
    for name in VEHICLES:
        out[name] = build_vehicle(name)[0]
        if name in VEHICLES_WITH_DOORS:
            out[f"{name}_open"] = build_vehicle(name, True)[0]
    out["cargo_crate"] = build_cargo_crate()
    out["worker"] = build_worker()
    out["worker_carry"] = build_worker(carry=True)
    out["depot"] = build_depot()
    return out


def bounds_xz(builder: MeshBuilder):
    pts = [v for p in builder.parts.values() for v in p["pos"]]
    return [round(min(v[0] for v in pts), 3), round(max(v[0] for v in pts), 3),
            round(min(v[2] for v in pts), 3), round(max(v[2] for v in pts), 3)]


# Anggaran segitiga (diuji) agar aset tetap ringan di HP kelas menengah.
BUDGET = {"base": 6000, "props": 4000, "depot": 12000, "construction": 400, "worker": 300,
          "worker_carry": 400, "cargo_crate": 200}
VEHICLE_BUDGET = 1600
MODULE_BUDGET = 2500


def budget(name: str) -> int:
    if name in BUDGET:
        return BUDGET[name]
    if name.removesuffix("_open") in VEHICLES:
        return VEHICLE_BUDGET
    return MODULE_BUDGET


def main(out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    built = models()
    for name, builder in built.items():
        tris = write_glb(builder, os.path.join(out_dir, f"{name}.glb"), name)
        print(f"{name}.glb: {tris} segitiga, {len(builder.parts)} material")
    layout = dict(LAYOUT)
    # Rintangan per modul (untuk uji tabrakan) & ukuran tapak kendaraan.
    layout["obstacles"] = {name: b.blocks for name, b in built.items() if b.blocks and name != "depot"}
    layout["vehicle_bounds"] = {name: bounds_xz(built[name]) for name in VEHICLES}
    # Titik palet muatan per kendaraan (koordinat model), terurut depan → belakang.
    layout["vehicle_cargo"] = {name: build_vehicle(name)[1] for name in VEHICLES}
    layout["vehicles_with_doors"] = list(VEHICLES_WITH_DOORS)
    # Dimensi (panjang, lebar, tinggi) semua model katalog, diuji cocok dengan data katalog.
    layout["vehicle_dims"] = {m["id"]: vehicles.dimensions(vehicles.build_vehicle(m, CATALOG)[0])
                              for m in CATALOG["models"]}
    with open(os.path.join(out_dir, "depot_layout.json"), "w") as f:
        json.dump(layout, f, indent=1)
    write_thumbnails(os.path.join(out_dir, "thumbs"))


THUMB_CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".thumb_cache")


def write_thumbnails(out_dir: str) -> None:
    """Thumbnail PNG semua model katalog (dealer, armada). Dilewati bila mesh tidak berubah."""
    import hashlib
    import thumbs
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(THUMB_CACHE, exist_ok=True)
    for model in CATALOG["models"]:
        mesh = vehicles.build_vehicle(model, CATALOG)[0]
        digest = hashlib.sha1(json.dumps(mesh.parts, sort_keys=True).encode()).hexdigest()[:16]
        path = os.path.join(out_dir, f"{model['id']}.png")
        stamp = os.path.join(THUMB_CACHE, f"{model['id']}.sha")
        if os.path.exists(path) and os.path.exists(stamp) and open(stamp).read() == digest:
            continue
        with open(path, "wb") as f:
            f.write(thumbs.render(mesh))
        with open(stamp, "w") as f:
            f.write(digest)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "out")
