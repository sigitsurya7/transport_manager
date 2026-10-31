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
        for name in ("depot", "pickup", "worker"):
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

    def test_layout(self):
        layout = json.load(open(os.path.join(self.dir, "depot_layout.json")))
        self.assertEqual(len(layout["parking_slots"]), 3)


if __name__ == "__main__":
    unittest.main()
