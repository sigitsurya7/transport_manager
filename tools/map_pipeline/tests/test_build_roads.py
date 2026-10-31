import json
import os
import sqlite3
import sys
import tempfile
import unittest

HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.dirname(HERE))

import build_roads as br  # noqa: E402

FIXTURE = os.path.join(HERE, "fixtures", "mini.osm")
BBOX = (106.7, -6.3, 107.0, -6.1)


def load(detail=False, bbox=BBOX):
    coords, ways = br.read_osm_xml(FIXTURE, detail)
    return br.build_graph(coords, ways, bbox)


class PolylineTest(unittest.TestCase):
    def test_roundtrip(self):
        pts = [(-6.2, 106.8), (-6.2000013, 106.8500021), (-7.2575, 112.7521)]
        decoded = br.decode_polyline(br.encode_polyline(pts))
        for (a, b), (c, d) in zip(pts, decoded):
            self.assertAlmostEqual(a, c, places=6)
            self.assertAlmostEqual(b, d, places=6)

    def test_known_vector(self):
        # Vektor uji ini juga dipakai di test Dart (polyline_test.dart).
        self.assertEqual(br.encode_polyline([(-6.2, 106.8), (-6.2, 106.85)]), "~jlyJ_wpujE?_t`B")


class ParseTest(unittest.TestCase):
    def test_maxspeed(self):
        self.assertEqual(br.parse_maxspeed("80"), 80)
        self.assertEqual(br.parse_maxspeed("50 mph"), 80)
        self.assertIsNone(br.parse_maxspeed("signals"))

    def test_maxweight(self):
        self.assertEqual(br.parse_maxweight("20"), 20)
        self.assertEqual(br.parse_maxweight("8000 kg"), 8)

    def test_toll(self):
        self.assertTrue(br.is_toll({"highway": "motorway"}))
        self.assertFalse(br.is_toll({"highway": "motorway", "toll": "no"}))
        self.assertFalse(br.is_toll({"highway": "primary"}))


class GraphTest(unittest.TestCase):
    def test_without_detail(self):
        nodes, edges = load()
        self.assertEqual(set(nodes), {1, 3, 11, 12})
        pairs = sorted((e.from_node, e.to_node) for e in edges)
        self.assertEqual(pairs, [(1, 3), (1, 11), (3, 11), (11, 1), (11, 3), (11, 12)])

    def test_interior_node_becomes_geometry(self):
        _, edges = load()
        toll = [e for e in edges if e.toll]
        self.assertEqual(len(toll), 1)
        self.assertEqual(len(toll[0].geometry), 3)  # 1 -> 2 -> 3
        self.assertAlmostEqual(toll[0].length_m, 11_055, delta=20)  # 0.1° bujur pada lintang -6.2°
        self.assertEqual(toll[0].maxspeed_kmh, 100)

    def test_oneway_and_weight(self):
        _, edges = load()
        self.assertFalse(any(e.from_node == 12 and e.to_node == 11 for e in edges))
        primary = [e for e in edges if e.osm_way_id == 200]
        self.assertTrue(all(e.maxweight_t == 20 for e in primary))

    def test_detail_adds_residential(self):
        nodes, edges = load(detail=True)
        self.assertEqual(set(nodes), {1, 3, 10, 11, 12, 20})
        self.assertEqual(len(edges), 10)

    def test_footway_ignored(self):
        _, edges = load(detail=True)
        self.assertFalse(any(e.osm_way_id == 600 for e in edges))

    def test_outputs(self):
        nodes, edges = load()
        with tempfile.TemporaryDirectory() as d:
            stats = br.write_outputs(nodes, edges, d, FIXTURE, write_json=True)
            self.assertEqual(stats["edges"], 6)
            con = sqlite3.connect(os.path.join(d, "roads.sqlite"))
            self.assertEqual(con.execute("SELECT COUNT(*) FROM edges").fetchone()[0], 6)
            self.assertEqual(con.execute("SELECT COUNT(*) FROM edges WHERE toll=1").fetchone()[0], 1)
            geom = con.execute("SELECT geometry FROM edges WHERE toll=1").fetchone()[0]
            self.assertEqual(len(br.decode_polyline(geom)), 3)
            with open(os.path.join(d, "graph.json")) as f:
                g = json.load(f)
            self.assertEqual(len(g["nodes"]), 4)
            self.assertEqual(len(g["edges"]), 6)
            # format edge: from, to, length_m, class, maxspeed, toll, maxweight, geometry
            self.assertEqual(len(g["edges"][0]), 8)


if __name__ == "__main__":
    unittest.main()
