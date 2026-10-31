"""Inti geometri low-poly: palet material, MeshBuilder (solid cembung), penulis GLB."""
from __future__ import annotations

import json
import math
import struct

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
    "silver":     (srgb("#b7bec6"), 0.6, 0.3),
    "alu":        (srgb("#e9ecef"), 0.5, 0.35),
    "cargo_floor": (srgb("#5a5047"), 0.0, 0.9),
    "cab_yellow": (srgb("#e8a623"), 0.3, 0.35),
    "wood_dark":  (srgb("#7a5634"), 0.0, 0.85),
    "carton_light": (srgb("#d9b37c"), 0.0, 0.9),
    "tape":       (srgb("#e6d6a8"), 0.0, 0.6),
    "galon":      (srgb("#6fb7e8"), 0.1, 0.15),
    "car_teal":   (srgb("#2e8b9a"), 0.5, 0.3),
    "container_red": (srgb("#a4452c"), 0.4, 0.55),
    "container_red_rib": (srgb("#86361f"), 0.4, 0.6),
    "tank":       (srgb("#4f7fa8"), 0.5, 0.4),
    "genset":     (srgb("#3f8f5a"), 0.4, 0.5),
    "bin_green":  (srgb("#3b9b4f"), 0.1, 0.6),
    "bin_orange": (srgb("#e47b25"), 0.1, 0.6),
    # kendaraan (katalog diperluas)
    "shadow":     (srgb("#2b2d30"), 0.0, 1.0),
    "car_red":    (srgb("#c43a31"), 0.4, 0.3),
    "car_grey":   (srgb("#7d868f"), 0.5, 0.3),
    "reefer_unit": (srgb("#d9dde1"), 0.3, 0.4),
    "reefer_grill": (srgb("#4a525a"), 0.4, 0.5),
    "curtain_blue": (srgb("#2b5fa3"), 0.0, 0.7),
    "curtain_green": (srgb("#2f7d4f"), 0.0, 0.7),
    "curtain_yellow": (srgb("#e2a72a"), 0.0, 0.7),
    "strap":      (srgb("#d8dadc"), 0.2, 0.5),
    "tank_steel": (srgb("#c9cfd5"), 0.8, 0.25),
    "log":        (srgb("#8a6440"), 0.0, 0.9),
    "brick":      (srgb("#b5583c"), 0.0, 0.85),
    "plate":      (srgb("#f2cc2e"), 0.1, 0.5),
    "amber":      (srgb("#f39a1e"), 0.0, 0.3),
    "fairing":    (srgb("#e9eaec"), 0.3, 0.35),
    "exhaust":    (srgb("#c0c4c8"), 0.9, 0.2),
    # depot (perombakan visual)
    "panel_line": (srgb("#9ea19c"), 0.0, 0.9),
    "slot_free":  (srgb("#3fbf6a"), 0.0, 0.5),
    "slot_taken": (srgb("#e2902a"), 0.0, 0.5),
    "hazard":     (srgb("#1f2226"), 0.0, 0.7),
    "wall_rib":   (srgb("#ddd3bd"), 0.0, 0.85),
    "precast":    (srgb("#b9b5aa"), 0.0, 0.9),
    "sign_blue":  (srgb("#245ea8"), 0.1, 0.5),
    "sign_white": (srgb("#f7f7f2"), 0.0, 0.6),
    "seal":       (srgb("#26292d"), 0.0, 0.95),
    "planter":    (srgb("#8c8a83"), 0.0, 0.9),
    "drum_blue":  (srgb("#2f5f9e"), 0.4, 0.5),
    "ac_unit":    (srgb("#e6e8ea"), 0.3, 0.5),
    "shade":      (srgb("#3e4a57"), 0.4, 0.5),
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
