#!/usr/bin/env python3
"""Generator aset GLB low-poly untuk spike 3D Tahap 2a.

Menghasilkan scene yang SAMA untuk flutter_scene dan Thermion:
  depot.glb   — depot awal: lahan, 3 slot parkir, gerbang, loading area, gudang, kantor
  pickup.glb  — pikap box (kabin + bak box + roda)
  worker.glb  — pekerja sederhana (badan + kepala + helm)

Koordinat: Y ke atas, satuan meter, origin di tengah lahan.
Lahan 40 m (X) × 30 m (Z). Gerbang di sisi +Z.

Ini aset placeholder untuk mengukur performa, bukan aset final.
"""
from __future__ import annotations

import json
import os
import struct
import sys

# ---------------------------------------------------------------- palet (sRGB → linear kira-kira)

def srgb(hex_color: str, alpha: float = 1.0) -> list[float]:
    h = hex_color.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [round(x ** 2.2, 4) for x in c] + [alpha]


MATERIALS = {
    "ground":     (srgb("#7d7f7a"), 0.0, 0.95),
    "asphalt":    (srgb("#3b3d40"), 0.0, 0.9),
    "marking":    (srgb("#f2f2ee"), 0.0, 0.6),
    "marking_y":  (srgb("#f2c230"), 0.0, 0.6),
    "concrete":   (srgb("#b9b5ac"), 0.0, 0.85),
    "wall":       (srgb("#d9d4c7"), 0.0, 0.8),
    "roof":       (srgb("#5d7183"), 0.6, 0.45),
    "door":       (srgb("#8a9196"), 0.7, 0.4),
    "office":     (srgb("#e8e2d3"), 0.0, 0.8),
    "glass":      (srgb("#7fb2d1"), 0.1, 0.1),
    "gate":       (srgb("#c9372c"), 0.3, 0.5),
    "fence":      (srgb("#6b7378"), 0.8, 0.4),
    "body_white": (srgb("#f4f4f2"), 0.3, 0.35),
    "box_body":   (srgb("#2f6db5"), 0.2, 0.5),
    "tire":       (srgb("#1c1c1c"), 0.0, 0.9),
    "window":     (srgb("#20262b"), 0.2, 0.15),
    "skin":       (srgb("#c68b59"), 0.0, 0.7),
    "uniform":    (srgb("#e07b22"), 0.0, 0.8),
    "pants":      (srgb("#2e3a4a"), 0.0, 0.9),
    "helmet":     (srgb("#f5d000"), 0.1, 0.4),
}

# ---------------------------------------------------------------- geometri

FACES = [
    # normal, 4 sudut (dalam satuan -1/1)
    ((1, 0, 0), [(1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)]),
    ((-1, 0, 0), [(-1, -1, 1), (-1, 1, 1), (-1, 1, -1), (-1, -1, -1)]),
    ((0, 1, 0), [(-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1)]),
    ((0, -1, 0), [(-1, -1, 1), (-1, -1, -1), (1, -1, -1), (1, -1, 1)]),
    ((0, 0, 1), [(1, -1, 1), (1, 1, 1), (-1, 1, 1), (-1, -1, 1)]),
    ((0, 0, -1), [(-1, -1, -1), (-1, 1, -1), (1, 1, -1), (1, -1, -1)]),
]


class MeshBuilder:
    """Kumpulkan kotak per material → satu primitive per material."""

    def __init__(self):
        self.parts: dict[str, dict[str, list]] = {}

    def box(self, material: str, center, size):
        cx, cy, cz = center
        hx, hy, hz = (s / 2 for s in size)
        p = self.parts.setdefault(material, {"pos": [], "nrm": [], "idx": []})
        for normal, corners in FACES:
            base = len(p["pos"])
            for sx, sy, sz in corners:
                p["pos"].append((cx + sx * hx, cy + sy * hy, cz + sz * hz))
                p["nrm"].append(normal)
            p["idx"] += [base, base + 1, base + 2, base, base + 2, base + 3]

    def box_on_ground(self, material, x, z, size, y0=0.0):
        """Kotak dengan alas di ketinggian y0."""
        self.box(material, (x, y0 + size[1] / 2, z), size)


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

# Posisi penting di depot (dipakai juga oleh aplikasi spike untuk jalur kendaraan).
LAYOUT = {
    "gate": (0.0, 15.0),
    "parking_slots": [(-12.0, -4.0), (-6.0, -4.0), (0.0, -4.0)],
    "loading_dock": (11.0, -6.0),
}


def build_depot() -> MeshBuilder:
    m = MeshBuilder()
    # lahan & jalan internal
    m.box("ground", (0, -0.05, 0), (40, 0.1, 30))
    m.box("asphalt", (0, 0.005, 6), (40, 0.01, 8))        # jalur utama di depan slot
    m.box("asphalt", (0, 0.005, 12), (6, 0.01, 6))        # menuju gerbang
    m.box("concrete", (-6, 0.005, -4), (19, 0.01, 8))     # area parkir
    # marka 3 slot parkir (4 garis)
    for x in (-15, -9, -3, 3):
        m.box("marking", (x, 0.02, -4), (0.15, 0.01, 7))
    m.box("marking_y", (0, 0.02, 2.2), (40, 0.01, 0.15))  # garis tepi jalur
    # gerbang (2 tiang + palang)
    for x in (-3.2, 3.2):
        m.box_on_ground("gate", x, 15, (0.4, 2.4, 0.4))
    m.box("gate", (0, 2.2, 15), (6.0, 0.2, 0.2))
    # pagar keliling (kecuali celah gerbang)
    m.box_on_ground("fence", -11.75, 15, (16.5, 1.8, 0.1))
    m.box_on_ground("fence", 11.75, 15, (16.5, 1.8, 0.1))
    m.box_on_ground("fence", 0, -15, (40, 1.8, 0.1))
    m.box_on_ground("fence", -20, 0, (0.1, 1.8, 30))
    m.box_on_ground("fence", 20, 0, (0.1, 1.8, 30))
    # gudang sederhana + 1 loading area
    m.box_on_ground("wall", 11, -10, (14, 6, 9))
    m.box("roof", (11, 6.15, -10), (14.6, 0.3, 9.6))
    m.box_on_ground("door", 11, -5.45, (4, 4.2, 0.1))
    m.box_on_ground("concrete", 11, -4.2, (6, 1.1, 2.5))  # dock platform
    m.box("marking_y", (11, 1.12, -3.0), (6, 0.01, 0.15))
    # kantor kecil
    m.box_on_ground("office", -14, 9.5, (8, 3.5, 6))
    m.box("roof", (-14, 3.6, 9.5), (8.4, 0.2, 6.4))
    m.box_on_ground("glass", -14, 6.45, (5, 1.4, 0.05), y0=1.2)
    m.box_on_ground("door", -11, 6.45, (1.0, 2.2, 0.06))
    return m


def build_pickup() -> MeshBuilder:
    """Pikap box ±4.7 m. Menghadap +X."""
    m = MeshBuilder()
    m.box_on_ground("body_white", 1.6, 0, (1.5, 1.35, 1.7), y0=0.45)   # kabin
    m.box_on_ground("window", 2.36, 0, (0.02, 0.55, 1.5), y0=1.15)    # kaca depan
    m.box_on_ground("body_white", -0.35, 0, (2.6, 0.2, 1.75), y0=0.55)  # sasis bak
    m.box_on_ground("box_body", -0.4, 0, (2.7, 1.6, 1.8), y0=0.75)    # box
    for x in (1.55, -1.1):
        for z in (-0.82, 0.82):
            m.box("tire", (x, 0.35, z), (0.7, 0.7, 0.25))
    return m


def build_worker() -> MeshBuilder:
    m = MeshBuilder()
    m.box_on_ground("pants", 0, 0, (0.35, 0.85, 0.25))
    m.box_on_ground("uniform", 0, 0, (0.45, 0.65, 0.28), y0=0.85)
    m.box_on_ground("skin", 0, 0, (0.22, 0.24, 0.22), y0=1.5)
    m.box_on_ground("helmet", 0, 0, (0.26, 0.1, 0.26), y0=1.72)
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
