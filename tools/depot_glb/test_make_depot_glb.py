"""Validasi struktural GLB (tanpa dependensi): header, chunk, bufferView, accessor, indeks, winding."""
import json
import os
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import make_depot_glb as g  # noqa: E402

SIZES = {5126: 4, 5125: 4}
COMPS = {"VEC3": 3, "SCALAR": 1}


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67 and version == 2 and length == len(data)
    jlen, jtype = struct.unpack_from("<II", data, 12)
    assert jtype == 0x4E4F534A and jlen % 4 == 0
    doc = json.loads(data[20:20 + jlen])
    blen, btype = struct.unpack_from("<II", data, 20 + jlen)
    assert btype == 0x004E4942 and blen % 4 == 0
    blob = data[28 + jlen:28 + jlen + blen]
    assert len(blob) == blen
    return doc, blob


class GlbTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp()
        g.main(cls.dir)

    def test_winding_matches_normals(self):
        for n, c in g.FACES:
            a = [c[1][i] - c[0][i] for i in range(3)]
            b = [c[2][i] - c[0][i] for i in range(3)]
            cross = (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
            for i in range(3):
                self.assertEqual((cross[i] > 0) - (cross[i] < 0), n[i])

    def test_files_valid(self):
        for name in g.models():
            with self.subTest(name=name):
                doc, blob = read_glb(os.path.join(self.dir, f"{name}.glb"))
                self.assertEqual(doc["buffers"][0]["byteLength"], len(blob))
                for bv in doc["bufferViews"]:
                    self.assertEqual(bv["byteOffset"] % 4, 0)
                    self.assertLessEqual(bv["byteOffset"] + bv["byteLength"], len(blob))
                for acc in doc["accessors"]:
                    bv = doc["bufferViews"][acc["bufferView"]]
                    need = acc["count"] * SIZES[acc["componentType"]] * COMPS[acc["type"]]
                    self.assertEqual(need, bv["byteLength"])
                for prim in doc["meshes"][0]["primitives"]:
                    vcount = doc["accessors"][prim["attributes"]["POSITION"]]["count"]
                    ia = doc["accessors"][prim["indices"]]
                    bv = doc["bufferViews"][ia["bufferView"]]
                    idx = struct.unpack_from(f"<{ia['count']}I", blob, bv["byteOffset"])
                    self.assertLess(max(idx), vcount)
                    self.assertEqual(ia["count"] % 3, 0)
                    self.assertLess(prim["material"], len(doc["materials"]))

    def test_triangles_face_their_normals(self):
        """Winding setiap segitiga searah normal verteksnya (tidak ada sisi terbalik)."""
        for name in g.models():
            doc, blob = read_glb(os.path.join(self.dir, f"{name}.glb"))
            for prim in doc["meshes"][0]["primitives"]:
                def floats(acc_id):
                    acc = doc["accessors"][acc_id]
                    bv = doc["bufferViews"][acc["bufferView"]]
                    flat = struct.unpack_from(f"<{acc['count'] * 3}f", blob, bv["byteOffset"])
                    return [flat[i:i + 3] for i in range(0, len(flat), 3)]
                pos = floats(prim["attributes"]["POSITION"])
                nrm = floats(prim["attributes"]["NORMAL"])
                ia = doc["accessors"][prim["indices"]]
                idx = struct.unpack_from(f"<{ia['count']}I", blob, doc["bufferViews"][ia["bufferView"]]["byteOffset"])
                for t in range(0, len(idx), 3):
                    a, b, c = (pos[i] for i in idx[t:t + 3])
                    n = g.cross(g.sub(b, a), g.sub(c, a))
                    if g.dot(n, n) < 1e-12:
                        continue  # segitiga degenerate
                    with self.subTest(name=name, tri=t // 3):
                        self.assertGreater(g.dot(n, nrm[idx[t]]), 0)

    def test_budget_segitiga(self):
        """Aset harus tetap ringan untuk HP kelas menengah."""
        for name, builder in g.models().items():
            tris = sum(len(p["idx"]) // 3 for p in builder.parts.values())
            self.assertLessEqual(tris, g.budget(name), name)

    def test_model_fasilitas_sesuai_konten(self):
        """Setiap level di content/facilities.json punya modul GLB."""
        root = os.path.join(os.path.dirname(__file__), "..", "..", "content", "facilities.json")
        facilities = json.load(open(root, encoding="utf-8"))["facilities"]
        names = set(g.models())
        for f in facilities:
            for level in f["levels"]:
                self.assertIn(level["model"], names)

    def test_layout(self):
        layout = json.load(open(os.path.join(self.dir, "depot_layout.json")))
        self.assertEqual(len(layout["parking_slots"]), 8)
        for key in ("outside", "road_lane_z", "gate", "lane_z", "docks", "gate_lanes", "booms", "anchors"):
            self.assertIn(key, layout)
        for level in ("1", "2", "3"):
            self.assertEqual(len(layout["docks"][level]), len(g.DOCKS[int(level)]))
        for name in g.VEHICLES:
            self.assertGreaterEqual(len(layout["vehicle_cargo"][name]), 4, name)
            xmin = layout["vehicle_bounds"][name][0]
            self.assertGreaterEqual(xmin, -2.7, f"{name}: bak terlalu panjang untuk posisi dock")


if __name__ == "__main__":
    unittest.main()
