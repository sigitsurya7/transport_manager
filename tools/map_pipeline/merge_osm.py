"""Gabungkan beberapa file OSM (mis. ubin Overpass yang saling tumpang tindih)
menjadi satu file, tanpa duplikat node/way, terurut node lalu way.

Pakai: python3 merge_osm.py <output.osm.pbf> <input.osm> [<input.osm> ...]
"""
import os
import sys

import osmium
from osmium.osm import mutable


def merge(output, inputs):
    nodes, ways = {}, {}
    for path in inputs:
        for o in osmium.FileProcessor(path):
            if o.is_node():
                nodes[o.id] = (o.location.lon, o.location.lat, dict(o.tags))
            elif o.is_way():
                ways[o.id] = ([n.ref for n in o.nodes], dict(o.tags))
    if os.path.exists(output):
        os.remove(output)
    with osmium.SimpleWriter(output) as w:
        for nid in sorted(nodes):
            lon, lat, tags = nodes[nid]
            w.add_node(mutable.Node(id=nid, location=(lon, lat), tags=tags))
        for wid in sorted(ways):
            refs, tags = ways[wid]
            w.add_way(mutable.Way(id=wid, nodes=refs, tags=tags))
    return len(nodes), len(ways)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    n, w = merge(sys.argv[1], sys.argv[2:])
    print(f"{sys.argv[1]}: {n} node, {w} way")


if __name__ == "__main__":
    main()
