#!/usr/bin/env python3
"""Generator aset GLB low-poly bergaya untuk depot Transport Manager.

Menghasilkan:
  depot.glb          — depot awal (lahan 40×30 m, 3 slot parkir, gerbang + pos jaga,
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


# ---------------------------------------------------------------- model

# Titik penting depot (dipakai app untuk jalur kendaraan di dalam depot).
LAYOUT = {
    "outside": (0.0, 24.0),          # di jalan umum, depan gerbang
    "gate": (0.0, 15.0),
    "lane_z": 6.0,                    # jalur utama di depan slot parkir
    "parking_slots": [(-12.0, -4.0), (-6.0, -4.0), (0.0, -4.0)],
    "loading_dock": (11.0, -6.0),
    "dock_stop": (11.0, -1.8),        # posisi pikap saat dimuat (hidung ke dock)
}

ROAD_Z = 24.0


def tree(m: MeshBuilder, x, z, s=1.0, light=False):
    m.cylinder("trunk", (x, 0.9 * s, z), 0.18 * s, 1.8 * s, sides=6)
    leaf = "leaf_light" if light else "leaf"
    m.cone(leaf, x, z, 1.4 * s, 1.5 * s, 2.2 * s, sides=7)
    m.cone(leaf, x, z, 2.6 * s, 1.1 * s, 1.9 * s, sides=7)


def bush(m: MeshBuilder, x, z, s=1.0):
    m.cone("leaf_light", x, z, 0.0, 0.8 * s, 0.9 * s, sides=6, top_radius=0.35 * s)


def lamp(m: MeshBuilder, x, z, facing_x=1.0):
    m.cylinder("pole", (x, 3.0, z), 0.08, 6.0, sides=6)
    m.box("pole", (x + 0.5 * facing_x, 6.0, z), (1.1, 0.1, 0.12))
    m.box("lamp", (x + 0.95 * facing_x, 5.92, z), (0.45, 0.08, 0.3))


def house(m: MeshBuilder, x, z, w, d, wall):
    m.box_on_ground(wall, x, z, (w, 3.0, d))
    m.gable_roof("tile", x, z, w + 0.6, d + 0.6, 3.0, 1.6)
    m.box_on_ground("frame", x, z - d / 2 - 0.02, (1.0, 2.0, 0.06))      # pintu menghadap jalan
    for dx in (-w / 4 - 0.4, w / 4 + 0.4):
        m.box_on_ground("glass", x + dx, z - d / 2 - 0.02, (1.1, 0.9, 0.05), y0=1.2)


def build_depot() -> MeshBuilder:
    m = MeshBuilder()

    # --- tanah & lingkungan
    m.box("grass", (0, -0.1, 4), (130, 0.2, 110))
    m.box("yard", (0, 0.0, 0), (40, 0.04, 30))                     # lantai lahan depot
    # jalan umum di depan gerbang, trotoar, marka
    m.box("asphalt", (0, 0.01, ROAD_Z), (130, 0.04, 7))
    for side in (-1, 1):
        m.box("curb", (0, 0.08, ROAD_Z + side * 4.25), (130, 0.16, 1.5))
    for i in range(-16, 17):
        m.box("marking", (i * 4.0, 0.035, ROAD_Z), (2.0, 0.01, 0.15))
    # akses gerbang → jalan
    m.box("asphalt", (0, 0.02, 18.5), (7, 0.04, 7))

    # --- jalur & parkir di dalam depot
    m.box("asphalt", (0, 0.025, 6), (38, 0.03, 6))                  # jalur utama
    m.box("asphalt", (0, 0.025, 12.05), (7, 0.03, 6.1))             # menuju gerbang
    m.box("asphalt", (11, 0.025, -1), (7, 0.03, 8))                 # menuju loading dock
    m.box("concrete", (-6, 0.025, -4), (19, 0.03, 8))               # area parkir
    for x in (-15, -9, -3, 3):
        m.box("marking", (x, 0.045, -4), (0.15, 0.01, 6.5))
    m.box("marking_y", (0, 0.045, 2.95), (38, 0.01, 0.15))
    m.box("marking_y", (0, 0.045, 9.05), (14, 0.01, 0.15))

    # --- pagar keliling (tiang + 2 rel), celah di gerbang
    def fence_run(x0, z0, x1, z1):
        length = math.hypot(x1 - x0, z1 - z0)
        n = max(1, int(length // 3.5))
        for i in range(n + 1):
            t = i / n
            m.box_on_ground("fence", x0 + (x1 - x0) * t, z0 + (z1 - z0) * t, (0.12, 1.9, 0.12))
        cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
        along_x = abs(x1 - x0) > abs(z1 - z0)
        for y in (0.7, 1.6):
            size = (length, 0.06, 0.06) if along_x else (0.06, 0.06, length)
            m.box("fence", (cx, y, cz), size)

    fence_run(-20, 15, -4.2, 15)
    fence_run(4.2, 15, 20, 15)
    fence_run(-20, -15, 20, -15)
    fence_run(-20, -15, -20, 15)
    fence_run(20, -15, 20, 15)

    # --- gerbang: pilar bergaris + palang merah-putih + pos jaga
    for x in (-3.9, 3.9):
        m.box_on_ground("concrete", x, 15, (0.6, 2.6, 0.6))
        m.box_on_ground("gate_red", x, 15, (0.64, 0.3, 0.64), y0=2.0)
    for i in range(8):
        mat = "gate_red" if i % 2 == 0 else "gate_white"
        m.box(mat, (-3.3 + i * 0.85 + 0.42, 1.15, 15.0), (0.85, 0.14, 0.14))
    m.box_on_ground("office", 5.6, 13.0, (2.0, 2.4, 2.0))
    m.box_on_ground("glass", 5.6, 14.02, (1.4, 0.8, 0.04), y0=1.1)
    m.box("roof_dark", (5.6, 2.5, 13.0), (2.5, 0.18, 2.5))

    # --- gudang beratap pelana + loading dock
    wx, wz, ww, wd, wh = 11.0, -10.0, 14.0, 9.0, 5.6
    m.box_on_ground("wall_base", wx, wz, (ww + 0.1, 0.6, wd + 0.1))
    m.box_on_ground("wall", wx, wz, (ww, wh, wd))
    m.box("accent", (wx, wh - 0.35, wz + wd / 2 + 0.03), (ww, 0.5, 0.06))   # pita warna perusahaan
    m.gable_roof("roof", wx, wz, ww + 0.8, wd + 1.2, wh, 1.8)
    m.box("roof_dark", (wx, wh + 1.82, wz), (ww + 0.9, 0.12, 0.3))           # bubungan
    # pintu rol bergaris
    door_z = wz + wd / 2 + 0.04
    m.box_on_ground("door", wx, door_z, (4.0, 4.0, 0.06))
    for i in range(1, 8):
        m.box("door_line", (wx, i * 0.5, door_z + 0.035), (4.0, 0.05, 0.02))
    m.box_on_ground("frame", wx, door_z + 0.02, (4.4, 0.2, 0.1), y0=4.0)
    # dock: platform, tepi kuning, bumper karet
    m.box_on_ground("concrete", wx, -4.2, (6, 1.1, 2.5))
    m.box("marking_y", (wx, 1.11, -3.0), (6, 0.02, 0.15))
    for dx in (-1.4, 1.4):
        m.box_on_ground("rubber", wx + dx, -2.92, (0.35, 0.5, 0.18), y0=0.45)
    # palet & karton di dekat dock
    for i, (px, pz) in enumerate([(15.5, -4.2), (16.7, -4.2), (15.5, -3.0)]):
        m.box_on_ground("wood", px, pz, (1.0, 0.14, 1.0), y0=1.1)
        m.box_on_ground("carton", px, pz, (0.9, 0.5 + 0.2 * (i % 2), 0.9), y0=1.24)
    # jendela atas di sisi samping
    for dz in (-2.5, 0.0, 2.5):
        m.box_on_ground("glass", wx - ww / 2 - 0.03, wz + dz, (0.05, 0.7, 1.6), y0=3.8)

    # --- kantor
    ox, oz, ow, od, oh = -14.0, 9.5, 8.0, 6.0, 3.6
    m.box_on_ground("wall_base", ox, oz, (ow + 0.1, 0.4, od + 0.1))
    m.box_on_ground("office", ox, oz, (ow, oh, od))
    m.box("roof_dark", (ox, oh + 0.12, oz), (ow + 0.5, 0.24, od + 0.5))   # atap datar + lisplang
    m.box("accent", (ox, oh - 0.3, oz - od / 2 - 0.03), (ow, 0.35, 0.06))
    m.box_on_ground("glass", ox - 1.0, oz - od / 2 - 0.03, (4.6, 1.3, 0.05), y0=1.1)
    for dx in (-3.3, -1.0, 1.3):
        m.box_on_ground("frame", ox + dx, oz - od / 2 - 0.05, (0.08, 1.3, 0.06), y0=1.1)
    m.box_on_ground("frame", ox + 2.6, oz - od / 2 - 0.03, (1.0, 2.2, 0.06))       # pintu
    m.box_on_ground("door", ox + 2.0, oz + 0.8, (1.2, 0.7, 0.9), y0=oh + 0.24)     # unit AC di atap
    bush(m, ox - 3.2, oz - od / 2 - 1.0)
    bush(m, ox + 0.8, oz - od / 2 - 1.0, 0.8)

    # --- lampu halaman
    lamp(m, -18.5, 13.5)
    lamp(m, 18.5, 2.0, -1.0)
    lamp(m, -18.5, -8.0)

    # --- pohon di luar pagar
    for x, z, s, light in [
        (-26, -10, 1.2, False), (-27, 2, 1.0, True), (-25, 12, 1.1, False), (26, -12, 1.3, True),
        (27, -1, 1.0, False), (25, 10, 1.15, True), (-12, -21, 1.1, True), (2, -22, 1.25, False),
        (15, -21, 1.0, True), (-34, -18, 1.4, False), (35, 16, 1.2, False), (-38, 14, 1.0, True),
        (40, -10, 1.3, True),
    ]:
        tree(m, x, z, s, light)
    for x in (-30, -15, 15, 30):
        tree(m, x, ROAD_Z + 6.5, 0.9, light=x > 0)

    # --- rumah tetangga di seberang jalan
    for x, w, d, wall in [(-36, 9, 7, "house_a"), (-22, 8, 7, "house_b"), (21, 9, 7, "house_c"), (35, 8, 7, "house_a")]:
        house(m, x, ROAD_Z + 11.5, w, d, wall)
    return m


def build_pickup() -> MeshBuilder:
    """Pikap box ±4.7 m, menghadap +X."""
    m = MeshBuilder()
    m.box_on_ground("chassis", 0.0, 0, (4.5, 0.3, 1.5), y0=0.32)
    # kabin
    m.box_on_ground("body_white", 1.55, 0, (1.4, 0.75, 1.72), y0=0.55)
    m.solid("body_white", [  # bagian atas kabin dengan kaca depan miring
        [(0.85, 1.3, -0.84), (1.95, 1.3, -0.84), (1.65, 2.0, -0.8), (0.85, 2.0, -0.8)],
        [(0.85, 1.3, 0.84), (1.95, 1.3, 0.84), (1.65, 2.0, 0.8), (0.85, 2.0, 0.8)],
        [(0.85, 1.3, -0.84), (0.85, 1.3, 0.84), (0.85, 2.0, 0.8), (0.85, 2.0, -0.8)],
        [(1.95, 1.3, -0.84), (1.95, 1.3, 0.84), (1.65, 2.0, 0.8), (1.65, 2.0, -0.8)],
        [(0.85, 2.0, -0.8), (1.65, 2.0, -0.8), (1.65, 2.0, 0.8), (0.85, 2.0, 0.8)],
        [(0.85, 1.3, -0.84), (1.95, 1.3, -0.84), (1.95, 1.3, 0.84), (0.85, 1.3, 0.84)],
    ])
    m.solid("window", [  # kaca depan (lapisan tipis di atas kemiringan)
        [(1.96, 1.36, -0.72), (1.67, 1.96, -0.7), (1.67, 1.96, 0.7), (1.96, 1.36, 0.72)],
        [(1.93, 1.36, -0.72), (1.64, 1.96, -0.7), (1.64, 1.96, 0.7), (1.93, 1.36, 0.72)],
        [(1.93, 1.36, -0.72), (1.96, 1.36, -0.72), (1.67, 1.96, -0.7), (1.64, 1.96, -0.7)],
        [(1.93, 1.36, 0.72), (1.96, 1.36, 0.72), (1.67, 1.96, 0.7), (1.64, 1.96, 0.7)],
    ])
    for side in (-1, 1):
        m.box("window", (1.3, 1.65, side * 0.84), (0.75, 0.5, 0.03))
        m.box("frame", (1.92, 1.55, side * 0.95), (0.1, 0.12, 0.18))     # spion
    m.box("chassis", (2.27, 0.62, 0), (0.12, 0.3, 1.74))                  # bumper depan
    for side in (-1, 1):
        m.box("headlight", (2.24, 0.98, side * 0.62), (0.05, 0.18, 0.32))
    # box barang + pita warna
    m.box_on_ground("box_body", -0.75, 0, (2.95, 1.75, 1.82), y0=0.62)
    for side in (-1, 1):
        m.box("stripe", (-0.75, 1.15, side * 0.915), (2.95, 0.22, 0.02))
    m.box("stripe", (-2.23, 1.15, 0), (0.02, 0.22, 1.82))
    m.box("chassis", (-2.3, 0.55, 0), (0.12, 0.24, 1.7))                  # bumper belakang
    for side in (-1, 1):
        m.box("taillight", (-2.25, 0.85, side * 0.7), (0.04, 0.22, 0.2))
    # roda
    for x in (1.45, -1.25):
        for z in (-0.78, 0.78):
            m.cylinder("tire", (x, 0.36, z), 0.36, 0.26, axis="z", sides=10)
            m.cylinder("hub", (x, 0.36, z + (0.135 if z > 0 else -0.135)), 0.17, 0.02, axis="z", sides=8)
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
    m.box("helmet", (0.1, 1.69, 0), (0.12, 0.03, 0.3))                   # pinggiran helm
    return m


def main(out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    for name, builder in (("depot", build_depot()), ("pickup", build_pickup()), ("worker", build_worker())):
        tris = write_glb(builder, os.path.join(out_dir, f"{name}.glb"), name)
        print(f"{name}.glb: {tris} segitiga, {len(builder.parts)} material")
    with open(os.path.join(out_dir, "depot_layout.json"), "w") as f:
        json.dump(LAYOUT, f, indent=2)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "out")
