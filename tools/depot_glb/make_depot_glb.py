#!/usr/bin/env python3
"""Generator aset GLB low-poly bergaya untuk depot Transport Manager.

Menghasilkan:
  base.glb + modul per level fasilitas (parking/gate/dock/warehouse/office_1..3),
  palang gerbang, penanda konstruksi; depot.glb = pratinjau depot awal (lahan 40×30 m, 3 slot parkir, gerbang + pos jaga,
                       loading area, gudang beratap pelana, kantor) beserta lingkungan:
                       jalan umum bermarka, trotoar, pohon, lampu, rumah tetangga
  pickup.glb         — pikap box (menghadap +X)
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

# ---------------------------------------------------------------- palet (sRGB → linear)


def srgb(hex_color: str, alpha: float = 1.0) -> list[float]:
    h = hex_color.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [round(x ** 2.2, 4) for x in c] + [alpha]


MATERIALS = {
    # lingkungan
    "grass":      (srgb("#86b35a"), 0.0, 0.95),
    "grass_dark": (srgb("#6f9c48"), 0.0, 0.95),
    "yard":       (srgb("#b4b6b2"), 0.0, 0.9),
    "concrete":   (srgb("#c9c6bd"), 0.0, 0.85),
    "asphalt":    (srgb("#45494f"), 0.0, 0.92),
    "curb":       (srgb("#d8d4c9"), 0.0, 0.85),
    "marking":    (srgb("#f4f3ee"), 0.0, 0.6),
    "marking_y":  (srgb("#f2b630"), 0.0, 0.6),
    "trunk":      (srgb("#7a5a3c"), 0.0, 0.9),
    "leaf":       (srgb("#4f9a4a"), 0.0, 0.85),
    "leaf_light": (srgb("#6db455"), 0.0, 0.85),
    "pole":       (srgb("#5d666e"), 0.6, 0.45),
    "lamp":       (srgb("#fff3c4"), 0.0, 0.3),
    # bangunan
    "wall":       (srgb("#ece3cf"), 0.0, 0.85),
    "wall_base":  (srgb("#9c9a92"), 0.0, 0.9),
    "roof":       (srgb("#4e6d8c"), 0.3, 0.55),
    "roof_dark":  (srgb("#3d566f"), 0.3, 0.6),
    "door":       (srgb("#a3abb3"), 0.5, 0.45),
    "door_line":  (srgb("#7f8891"), 0.5, 0.5),
    "accent":     (srgb("#f2b630"), 0.1, 0.5),
    "office":     (srgb("#f6f3ec"), 0.0, 0.8),
    "glass":      (srgb("#7fb6d8"), 0.2, 0.08),
    "frame":      (srgb("#39434d"), 0.4, 0.5),
    "gate_red":   (srgb("#d23c30"), 0.2, 0.5),
    "gate_white": (srgb("#f6f6f2"), 0.1, 0.5),
    "fence":      (srgb("#6c7a76"), 0.6, 0.45),
    "rubber":     (srgb("#22252a"), 0.0, 0.9),
    "wood":       (srgb("#b8895a"), 0.0, 0.85),
    "carton":     (srgb("#c79b63"), 0.0, 0.9),
    "house_a":    (srgb("#e8d7b8"), 0.0, 0.85),
    "house_b":    (srgb("#cfe0e4"), 0.0, 0.85),
    "house_c":    (srgb("#f0c9a8"), 0.0, 0.85),
    "tile":       (srgb("#b5523b"), 0.0, 0.75),
    # kendaraan
    "body_white": (srgb("#f5f5f2"), 0.3, 0.35),
    "box_body":   (srgb("#f0f0ec"), 0.1, 0.45),
    "stripe":     (srgb("#f2b630"), 0.2, 0.4),
    "tire":       (srgb("#1d1f22"), 0.0, 0.88),
    "hub":        (srgb("#b9bec4"), 0.8, 0.3),
    "window":     (srgb("#1f2a33"), 0.3, 0.12),
    "chassis":    (srgb("#2c3036"), 0.4, 0.6),
    "headlight":  (srgb("#fff7d6"), 0.0, 0.2),
    "taillight":  (srgb("#d8342c"), 0.0, 0.3),
    # pekerja
    "skin":       (srgb("#c68b59"), 0.0, 0.7),
    "vest":       (srgb("#f28c28"), 0.0, 0.7),
    "reflect":    (srgb("#e8eef0"), 0.4, 0.3),
    "shirt":      (srgb("#3f5f86"), 0.0, 0.85),
    "pants":      (srgb("#2e3a4a"), 0.0, 0.9),
    "helmet":     (srgb("#f5d000"), 0.1, 0.4),
    "boots":      (srgb("#2a2420"), 0.0, 0.9),
    # konstruksi & detail upgrade
    "cone":       (srgb("#f2662a"), 0.0, 0.6),
    "barrier":    (srgb("#f4f1ea"), 0.0, 0.6),
    "light_green": (srgb("#3fd47a"), 0.0, 0.3),
    "light_red":  (srgb("#e8443a"), 0.0, 0.3),
    "canopy":     (srgb("#d9dde2"), 0.6, 0.35),
    "rack":       (srgb("#2f6db5"), 0.4, 0.5),
    "solar":      (srgb("#24364d"), 0.5, 0.2),
    "cab_blue":   (srgb("#2f6db5"), 0.3, 0.35),
    "bed":        (srgb("#8d939a"), 0.5, 0.5),
    "cab_red":    (srgb("#c8432f"), 0.3, 0.35),
    "cab_green":  (srgb("#3f8f5a"), 0.3, 0.35),
    "container":  (srgb("#2e7d7a"), 0.4, 0.5),
    "container_rib": (srgb("#256663"), 0.4, 0.55),
    "lock":       (srgb("#c9ced3"), 0.8, 0.3),
}

# Kubus satuan, dipakai juga oleh test winding.
FACES = [
    ((1, 0, 0), [(1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)]),
    ((-1, 0, 0), [(-1, -1, 1), (-1, 1, 1), (-1, 1, -1), (-1, -1, -1)]),
    ((0, 1, 0), [(-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1)]),
    ((0, -1, 0), [(-1, -1, 1), (-1, -1, -1), (1, -1, -1), (1, -1, 1)]),
    ((0, 0, 1), [(1, -1, 1), (1, 1, 1), (-1, 1, 1), (-1, -1, 1)]),
    ((0, 0, -1), [(-1, -1, -1), (-1, 1, -1), (1, 1, -1), (1, -1, -1)]),
]

# ---------------------------------------------------------------- vektor


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def norm(a):
    n = math.sqrt(dot(a, a)) or 1.0
    return (a[0] / n, a[1] / n, a[2] / n)


def centroid(points):
    k = len(points)
    return (sum(p[0] for p in points) / k, sum(p[1] for p in points) / k, sum(p[2] for p in points) / k)


# ---------------------------------------------------------------- geometri


class MeshBuilder:
    """Kumpulkan poligon per material → satu primitive per material."""

    def __init__(self):
        self.parts: dict[str, dict[str, list]] = {}
        # Jejak tabrakan di lantai (x0, z0, x1, z1): bangunan, pagar, lampu,
        # platform, palet. Kendaraan tidak boleh menyentuhnya (diuji di app).
        self.blocks: list[tuple[float, float, float, float]] = []

    def block(self, x0, z0, x1, z1):
        self.blocks.append((round(min(x0, x1), 3), round(min(z0, z1), 3), round(max(x0, x1), 3), round(max(z0, z1), 3)))

    def block_box(self, x, z, sx, sz):
        self.block(x - sx / 2, z - sz / 2, x + sx / 2, z + sz / 2)

    def solid(self, material: str, polygons: list[list[tuple]]):
        """Solid cembung: tiap poligon diorientasikan agar normalnya keluar."""
        center = centroid([v for poly in polygons for v in poly])
        p = self.parts.setdefault(material, {"pos": [], "nrm": [], "idx": []})
        for poly in polygons:
            n = norm(cross(sub(poly[1], poly[0]), sub(poly[2], poly[0])))
            if dot(n, sub(centroid(poly), center)) < 0:
                poly = list(reversed(poly))
                n = (-n[0], -n[1], -n[2])
            base = len(p["pos"])
            for v in poly:
                p["pos"].append(v)
                p["nrm"].append(n)
            for i in range(1, len(poly) - 1):
                p["idx"] += [base, base + i, base + i + 1]

    def box(self, material, center, size):
        cx, cy, cz = center
        hx, hy, hz = (s / 2 for s in size)
        self.solid(material, [[(cx + sx * hx, cy + sy * hy, cz + sz * hz) for sx, sy, sz in c] for _, c in FACES])

    def box_on_ground(self, material, x, z, size, y0=0.0):
        self.box(material, (x, y0 + size[1] / 2, z), size)

    def gable_roof(self, material, x, z, width_x, depth_z, y0, rise):
        """Atap pelana, bubungan sejajar sumbu X."""
        hx, hz = width_x / 2, depth_z / 2
        a, b = (x - hx, y0, z - hz), (x + hx, y0, z - hz)
        c, d = (x + hx, y0, z + hz), (x - hx, y0, z + hz)
        r1, r2 = (x - hx, y0 + rise, z), (x + hx, y0 + rise, z)
        self.solid(material, [[a, b, r2, r1], [d, r1, r2, c], [a, r1, d], [b, c, r2], [a, d, c, b]])

    def cylinder(self, material, center, radius, length, axis="y", sides=8):
        cx, cy, cz = center
        rings = []
        for s in (-0.5, 0.5):
            ring = []
            for i in range(sides):
                a = 2 * math.pi * (i + 0.5) / sides
                u, v = math.cos(a) * radius, math.sin(a) * radius
                if axis == "y":
                    ring.append((cx + u, cy + s * length, cz + v))
                elif axis == "z":
                    ring.append((cx + u, cy + v, cz + s * length))
                else:
                    ring.append((cx + s * length, cy + u, cz + v))
            rings.append(ring)
        lo, hi = rings
        polys = [lo, hi] + [[lo[i], lo[(i + 1) % sides], hi[(i + 1) % sides], hi[i]] for i in range(sides)]
        self.solid(material, polys)

    def cone(self, material, x, z, y0, radius, height, sides=6, top_radius=0.0):
        base = [(x + math.cos(2 * math.pi * i / sides) * radius, y0, z + math.sin(2 * math.pi * i / sides) * radius)
                for i in range(sides)]
        if top_radius <= 0:
            apex = (x, y0 + height, z)
            polys = [base] + [[base[i], base[(i + 1) % sides], apex] for i in range(sides)]
        else:
            top = [(x + math.cos(2 * math.pi * i / sides) * top_radius, y0 + height,
                    z + math.sin(2 * math.pi * i / sides) * top_radius) for i in range(sides)]
            polys = [base, top] + [[base[i], base[(i + 1) % sides], top[(i + 1) % sides], top[i]] for i in range(sides)]
        self.solid(material, polys)


def write_glb(builder: MeshBuilder, path: str, name: str):
    bin_data = bytearray()
    buffer_views, accessors, primitives, materials = [], [], [], []
    mat_index: dict[str, int] = {}

    def add_view(data: bytes, target: int) -> int:
        while len(bin_data) % 4:
            bin_data.append(0)
        buffer_views.append({"buffer": 0, "byteOffset": len(bin_data), "byteLength": len(data), "target": target})
        bin_data.extend(data)
        return len(buffer_views) - 1

    for mat_name, part in builder.parts.items():
        if mat_name not in mat_index:
            color, metallic, rough = MATERIALS[mat_name]
            materials.append({
                "name": mat_name,
                "pbrMetallicRoughness": {"baseColorFactor": color, "metallicFactor": metallic,
                                         "roughnessFactor": rough},
            })
            mat_index[mat_name] = len(materials) - 1

        pos, nrm, idx = part["pos"], part["nrm"], part["idx"]
        pos_view = add_view(b"".join(struct.pack("<3f", *v) for v in pos), 34962)
        nrm_view = add_view(b"".join(struct.pack("<3f", *v) for v in nrm), 34962)
        idx_view = add_view(b"".join(struct.pack("<I", i) for i in idx), 34963)
        mins = [min(v[k] for v in pos) for k in range(3)]
        maxs = [max(v[k] for v in pos) for k in range(3)]
        accessors.append({"bufferView": pos_view, "componentType": 5126, "count": len(pos), "type": "VEC3",
                          "min": mins, "max": maxs})
        accessors.append({"bufferView": nrm_view, "componentType": 5126, "count": len(nrm), "type": "VEC3"})
        accessors.append({"bufferView": idx_view, "componentType": 5125, "count": len(idx), "type": "SCALAR"})
        a = len(accessors)
        primitives.append({"attributes": {"POSITION": a - 3, "NORMAL": a - 2}, "indices": a - 1,
                           "material": mat_index[mat_name], "mode": 4})

    gltf = {
        "asset": {"version": "2.0", "generator": "transport_manager make_depot_glb.py"},
        "scene": 0,
        "scenes": [{"name": name, "nodes": [0]}],
        "nodes": [{"name": name, "mesh": 0}],
        "meshes": [{"name": name, "primitives": primitives}],
        "materials": materials,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(bin_data)}],
    }
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode()
    json_bytes += b" " * ((4 - len(json_bytes) % 4) % 4)
    while len(bin_data) % 4:
        bin_data.append(0)
    total = 12 + 8 + len(json_bytes) + 8 + len(bin_data)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        f.write(json_bytes)
        f.write(struct.pack("<II", len(bin_data), 0x004E4942))
        f.write(bin_data)
    return sum(len(p["idx"]) // 3 for p in builder.parts.values())


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
        "parking": (-9.0, -10.5),
        "gate": (8.5, 11.0),
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
# Semua kendaraan menghadap +X. Bak paling belakang ≤ 2.7 m dari origin agar
# berhenti tepat di depan platform dock (DOCK_Z).

def _cab(m: MeshBuilder, body: str, x0: float, x1: float, height: float, width: float, base_y: float = 1.3):
    """Kabin dengan kaca depan miring, dari x0 (belakang) ke x1 (depan)."""
    hw = width / 2
    y0, y1 = base_y, base_y + height
    slope = 0.3
    m.box_on_ground(body, (x0 + x1) / 2, 0, (x1 - x0, y0 - 0.55, width), y0=0.55)
    m.solid(body, [
        [(x0, y0, -hw), (x1, y0, -hw), (x1 - slope, y1, -hw + 0.04), (x0, y1, -hw + 0.04)],
        [(x0, y0, hw), (x1, y0, hw), (x1 - slope, y1, hw - 0.04), (x0, y1, hw - 0.04)],
        [(x0, y0, -hw), (x0, y0, hw), (x0, y1, hw - 0.04), (x0, y1, -hw + 0.04)],
        [(x1, y0, -hw), (x1, y0, hw), (x1 - slope, y1, hw - 0.04), (x1 - slope, y1, -hw + 0.04)],
        [(x0, y1, -hw + 0.04), (x1 - slope, y1, -hw + 0.04), (x1 - slope, y1, hw - 0.04), (x0, y1, hw - 0.04)],
        [(x0, y0, -hw), (x1, y0, -hw), (x1, y0, hw), (x0, y0, hw)],
    ])
    m.solid("window", [
        [(x1 + 0.01, y0 + 0.06, -hw + 0.12), (x1 - slope + 0.03, y1 - 0.04, -hw + 0.14),
         (x1 - slope + 0.03, y1 - 0.04, hw - 0.14), (x1 + 0.01, y0 + 0.06, hw - 0.12)],
        [(x1 - 0.02, y0 + 0.06, -hw + 0.12), (x1 - slope, y1 - 0.04, -hw + 0.14),
         (x1 - slope, y1 - 0.04, hw - 0.14), (x1 - 0.02, y0 + 0.06, hw - 0.12)],
        [(x1 - 0.02, y0 + 0.06, -hw + 0.12), (x1 + 0.01, y0 + 0.06, -hw + 0.12),
         (x1 - slope + 0.03, y1 - 0.04, -hw + 0.14), (x1 - slope, y1 - 0.04, -hw + 0.14)],
        [(x1 - 0.02, y0 + 0.06, hw - 0.12), (x1 + 0.01, y0 + 0.06, hw - 0.12),
         (x1 - slope + 0.03, y1 - 0.04, hw - 0.14), (x1 - slope, y1 - 0.04, hw - 0.14)],
    ])
    for side in (-1, 1):
        m.box("window", ((x0 + x1) / 2 - 0.1, y0 + height * 0.5, side * hw), (x1 - x0 - 0.6, height * 0.6, 0.03))
        m.box("frame", (x1 - 0.05, y0 + 0.25, side * (hw + 0.1)), (0.1, 0.12, 0.18))
    m.box("chassis", (x1 + 0.06, 0.62, 0), (0.12, 0.3, width + 0.02))
    for side in (-1, 1):
        m.box("headlight", (x1 + 0.03, y0 - 0.32, side * (hw - 0.25)), (0.05, 0.18, 0.32))


def _wheels(m: MeshBuilder, xs, half_track: float, radius: float = 0.36):
    for x in xs:
        for z in (-half_track, half_track):
            m.cylinder("tire", (x, radius, z), radius, 0.26, axis="z", sides=10)
            m.cylinder("hub", (x, radius, z + (0.135 if z > 0 else -0.135)), radius * 0.47, 0.02, axis="z", sides=8)


def _taillights(m: MeshBuilder, x, half):
    for side in (-1, 1):
        m.box("taillight", (x, 0.85, side * half), (0.04, 0.22, 0.2))


def build_pickup_open() -> MeshBuilder:
    """Pikap losbak (bak terbuka, muatan karton terlihat). ±4.6 m."""
    m = MeshBuilder()
    m.box_on_ground("chassis", 0.0, 0, (4.4, 0.3, 1.5), y0=0.32)
    _cab(m, "body_white", 1.0, 2.1, 0.7, 1.72)
    m.box_on_ground("bed", -0.6, 0, (2.9, 0.12, 1.8), y0=0.62)
    for side in (-1, 1):
        m.box_on_ground("bed", -0.6, side * 0.86, (2.9, 0.45, 0.08), y0=0.74)
    m.box_on_ground("bed", -2.02, 0, (0.08, 0.45, 1.8), y0=0.74)
    m.box_on_ground("bed", 0.82, 0, (0.08, 0.6, 1.8), y0=0.74)
    for dx, dz, h in ((-1.3, -0.35, 0.5), (-1.3, 0.4, 0.4), (-0.4, 0.0, 0.55)):
        m.box_on_ground("carton", dx, dz, (0.7, h, 0.7), y0=0.74)
    m.box("chassis", (-2.12, 0.55, 0), (0.12, 0.24, 1.7))
    _taillights(m, -2.08, 0.7)
    _wheels(m, (1.55, -1.1), 0.78)
    return m


def build_pickup() -> MeshBuilder:
    """Pikap box (kotak tertutup putih + pita oranye). ±4.7 m."""
    m = MeshBuilder()
    m.box_on_ground("chassis", 0.0, 0, (4.5, 0.3, 1.5), y0=0.32)
    _cab(m, "body_white", 1.0, 2.1, 0.7, 1.72)
    m.box_on_ground("box_body", -0.6, 0, (2.95, 1.75, 1.82), y0=0.62)
    for side in (-1, 1):
        m.box("stripe", (-0.6, 1.15, side * 0.915), (2.95, 0.22, 0.02))
    m.box("stripe", (-2.08, 1.15, 0), (0.02, 0.22, 1.82))
    m.box("chassis", (-2.16, 0.55, 0), (0.12, 0.24, 1.7))
    _taillights(m, -2.11, 0.7)
    _wheels(m, (1.6, -1.1), 0.78)
    return m


def build_mini_truck() -> MeshBuilder:
    """Mini truck box (kabin biru di depan, box lebih tinggi). ±5.3 m."""
    m = MeshBuilder()
    m.box_on_ground("chassis", 0.2, 0, (5.0, 0.32, 1.6), y0=0.36)
    _cab(m, "cab_blue", 1.6, 2.65, 0.85, 1.85, base_y=1.35)
    m.box_on_ground("box_body", -0.5, 0, (3.9, 2.15, 1.98), y0=0.68)
    for side in (-1, 1):
        m.box("stripe", (-0.5, 1.3, side * 0.995), (3.9, 0.28, 0.02))
        m.box("cab_blue", (-0.5, 0.82, side * 0.995), (3.9, 0.1, 0.02))
    m.box("chassis", (-2.55, 0.6, 0), (0.12, 0.24, 1.8))
    _taillights(m, -2.52, 0.75)
    _wheels(m, (2.0, -1.3), 0.82, 0.4)
    return m


def build_container_truck() -> MeshBuilder:
    """Truk engkel pembawa kontainer 10 ft (kabin merah, kontainer hijau toska
    bergelombang, roda belakang ganda). ±6.2 m."""
    m = MeshBuilder()
    m.box_on_ground("chassis", 0.75, 0, (6.0, 0.36, 1.7), y0=0.42)
    _cab(m, "cab_red", 2.2, 3.45, 1.0, 2.0, base_y=1.45)
    m.box_on_ground("bed", -0.35, 0, (4.4, 0.16, 2.1), y0=0.78)   # dek datar
    cx, cl, ch, cw = -0.45, 3.4, 2.3, 2.1                          # kontainer 10 ft
    m.box_on_ground("container", cx, 0, (cl, ch, cw), y0=0.94)
    for i in range(9):                                             # gelombang dinding
        x = cx - cl / 2 + 0.2 + i * (cl - 0.4) / 8
        for side in (-1, 1):
            m.box("container_rib", (x, 0.94 + ch / 2, side * (cw / 2 + 0.015)), (0.12, ch - 0.2, 0.03))
    m.box("container_rib", (cx, 0.94 + ch - 0.06, 0), (cl + 0.02, 0.12, cw + 0.02))  # rangka atas
    m.box("container_rib", (cx - cl / 2 - 0.02, 0.94 + ch / 2, 0), (0.04, ch, cw))   # pintu belakang
    for dz in (-0.55, -0.2, 0.2, 0.55):
        m.box("lock", (cx - cl / 2 - 0.05, 0.94 + ch / 2, dz), (0.04, ch - 0.3, 0.05))
    m.box("chassis", (-2.6, 0.62, 0), (0.12, 0.26, 2.0))
    _taillights(m, -2.57, 0.85)
    _wheels(m, (2.75,), 0.88, 0.42)
    _wheels(m, (-1.1, -1.75), 0.92, 0.42)
    return m


def build_worker() -> MeshBuilder:
    m = MeshBuilder()
    for dz in (-0.1, 0.1):
        m.box_on_ground("boots", 0.03, dz, (0.26, 0.1, 0.14))
        m.box_on_ground("pants", 0, dz, (0.17, 0.78, 0.16), y0=0.1)
    m.box_on_ground("shirt", 0, 0, (0.26, 0.6, 0.44), y0=0.86)
    m.box_on_ground("vest", 0, 0, (0.28, 0.5, 0.46), y0=0.92)
    m.box("reflect", (0, 1.15, 0), (0.29, 0.06, 0.47))
    for dz in (-0.29, 0.29):
        m.box_on_ground("shirt", 0, dz, (0.13, 0.55, 0.12), y0=0.9)
        m.box_on_ground("skin", 0, dz, (0.12, 0.12, 0.11), y0=0.8)
    m.box_on_ground("skin", 0, 0, (0.22, 0.24, 0.22), y0=1.48)
    m.cone("helmet", 0, 0, 1.68, 0.17, 0.14, sides=8, top_radius=0.11)
    m.box("helmet", (0.1, 1.69, 0), (0.12, 0.03, 0.3))
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
    return merge(build_base(), build_parking(1), build_gate(1), boom, build_dock(1), build_warehouse(1), build_office(1))


VEHICLES = ("pickup_open", "pickup", "mini_truck", "container_truck")


def models() -> dict:
    out = {"base": build_base(), "construction": build_construction()}
    for lvl in (1, 2, 3):
        out[f"parking_{lvl}"] = build_parking(lvl)
        out[f"gate_{lvl}"] = build_gate(lvl)
        out[f"dock_{lvl}"] = build_dock(lvl)
        out[f"warehouse_{lvl}"] = build_warehouse(lvl)
        out[f"office_{lvl}"] = build_office(lvl)
    out["boom_long"] = build_boom(7.0, 1)
    out["boom_short"] = build_boom(4.0, 1)
    out["boom_short_r"] = build_boom(4.0, -1)
    out["pickup_open"] = build_pickup_open()
    out["pickup"] = build_pickup()
    out["mini_truck"] = build_mini_truck()
    out["container_truck"] = build_container_truck()
    out["worker"] = build_worker()
    out["depot"] = build_depot()
    return out


def bounds_xz(builder: MeshBuilder):
    pts = [v for p in builder.parts.values() for v in p["pos"]]
    return [round(min(v[0] for v in pts), 3), round(max(v[0] for v in pts), 3),
            round(min(v[2] for v in pts), 3), round(max(v[2] for v in pts), 3)]


# Anggaran segitiga (diuji) agar aset tetap ringan di HP kelas menengah.
BUDGET = {"base": 6000, "depot": 9000, "construction": 400, "worker": 300, "pickup": 900,
          "pickup_open": 900, "mini_truck": 1000, "container_truck": 1400}
MODULE_BUDGET = 2500


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
    with open(os.path.join(out_dir, "depot_layout.json"), "w") as f:
        json.dump(layout, f, indent=1)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "out")
