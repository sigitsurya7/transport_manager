import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.dirname(HERE))

import build_roads as br  # noqa: E402
import merge_osm  # noqa: E402

FIXTURE = os.path.join(HERE, "fixtures", "mini.osm")


class MergeTest(unittest.TestCase):
    def test_overlap_tanpa_duplikat(self):
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "merged.osm.pbf")
            once = merge_osm.merge(out, [FIXTURE])
            twice = merge_osm.merge(out, [FIXTURE, FIXTURE])
            self.assertEqual(once, twice)

    def test_hasil_bisa_dibaca_build_roads(self):
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "merged.osm.pbf")
            merge_osm.merge(out, [FIXTURE, FIXTURE])
            nodes_xml, edges_xml = br.build_graph(*br.read_osm_xml(FIXTURE, False), None)
            nodes_pbf, edges_pbf = br.build_graph(*br.read_osm_pbf(out, False), None)
            self.assertEqual(len(nodes_xml), len(nodes_pbf))
            self.assertEqual(len(edges_xml), len(edges_pbf))


if __name__ == "__main__":
    unittest.main()
