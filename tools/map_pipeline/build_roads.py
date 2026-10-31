#!/usr/bin/env python3
"""OSM → road graph untuk Transport Manager.

Input : file OSM XML (.osm) atau PBF (.osm.pbf, butuh `pip install osmium`).
Output: roads.sqlite (dipakai game) dan opsional graph.json (untuk benchmark / test sim_core).

Graph yang dihasilkan:
- Node hanya di persimpangan dan ujung jalan (node OSM di tengah ruas menjadi geometri).
- Setiap edge berarah. Jalan dua arah menghasilkan dua edge.
- Atribut edge: panjang (m), kelas jalan, maxspeed (km/j), tol, batas berat (ton), geometri (polyline precision 6).

Contoh:
    python build_roads.py java-latest.osm.pbf --out out/id-jawa --bbox 106.6,-6.4,107.0,-6.0 --json
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import sqlite3
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field

# Kelas jalan yang masuk graph, beserta kecepatan default (km/j) bila tag maxspeed tidak ada.
ROAD_CLASSES = {
    "motorway": 100, "motorway_link": 60,
    "trunk": 70, "trunk_link": 50,
    "primary": 60, "primary_link": 40,
    "secondary": 50, "secondary_link": 35,
    "tertiary": 40, "tertiary_link": 30,
    "unclassified": 30,
    "residential": 25,
}
# Kelas yang hanya disertakan bila --detail (jalan dalam kota).
DETAIL_CLASSES = {"unclassified", "residential"}

ONEWAY_IMPLIED = {"motorway", "motorway_link"}


@dataclass
class Way:
    osm_id: int
    nodes: list[int]
    tags: dict[str, str] = field(default_factory=dict)


@dataclass
class Edge:
    from_node: int
    to_node: int
    length_m: float
    road_class: str
    maxspeed_kmh: int
    toll: bool
    maxweight_t: float | None
    geometry: list[tuple[float, float]]
    osm_way_id: int


# ---------------------------------------------------------------- util

def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6_371_008.8
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def encode_polyline(points: list[tuple[float, float]], precision: int = 6) -> str:
    """Google encoded polyline. Precision 6 (~10 cm)."""
    factor = 10 ** precision
    out = []
    prev_lat = prev_lon = 0
    for lat, lon in points:
        ilat, ilon = round(lat * factor), round(lon * factor)
        for delta in (ilat - prev_lat, ilon - prev_lon):
            v = ~(delta << 1) if delta < 0 else (delta << 1)
            while v >= 0x20:
                out.append(chr((0x20 | (v & 0x1F)) + 63))
                v >>= 5
            out.append(chr(v + 63))
        prev_lat, prev_lon = ilat, ilon
    return "".join(out)


def decode_polyline(s: str, precision: int = 6) -> list[tuple[float, float]]:
    factor = 10 ** precision
    coords, i, lat, lon = [], 0, 0, 0
    while i < len(s):
        vals = []
        for _ in range(2):
            shift = result = 0
            while True:
                b = ord(s[i]) - 63
                i += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20:
                    break
            vals.append(~(result >> 1) if result & 1 else result >> 1)
        lat += vals[0]
        lon += vals[1]
        coords.append((lat / factor, lon / factor))
    return coords


def parse_maxspeed(value: str | None) -> int | None:
    if not value:
        return None
    m = re.match(r"\s*(\d+(?:\.\d+)?)\s*(mph)?", value)
    if not m:
        return None
    v = float(m.group(1))
    if m.group(2):
        v *= 1.609344
    return int(round(v)) if v > 0 else None


def parse_maxweight(value: str | None) -> float | None:
    if not value:
        return None
    m = re.match(r"\s*(\d+(?:\.\d+)?)\s*(t|kg)?", value)
    if not m:
        return None
    v = float(m.group(1))
    if m.group(2) == "kg":
        v /= 1000
    return v if v > 0 else None


def is_toll(tags: dict[str, str]) -> bool:
    toll = tags.get("toll")
    if toll is not None:
        return toll == "yes"
    # Di Indonesia, motorway hampir selalu jalan tol.
    return tags.get("highway") in ("motorway", "motorway_link")


def oneway_direction(tags: dict[str, str]) -> int:
    """1 = searah node, -1 = berlawanan, 0 = dua arah."""
    ow = tags.get("oneway")
    if ow in ("yes", "true", "1"):
        return 1
    if ow == "-1":
        return -1
    if ow == "no":
        return 0
    if tags.get("junction") == "roundabout" or tags.get("highway") in ONEWAY_IMPLIED:
        return 1
    return 0


def in_bbox(lat: float, lon: float, bbox: tuple[float, float, float, float] | None) -> bool:
    if bbox is None:
        return True
    min_lon, min_lat, max_lon, max_lat = bbox
    return min_lat <= lat <= max_lat and min_lon <= lon <= max_lon


# ---------------------------------------------------------------- reading

def accept_way(tags: dict[str, str], detail: bool) -> bool:
    hw = tags.get("highway")
    if hw not in ROAD_CLASSES:
        return False
    if hw in DETAIL_CLASSES and not detail:
        return False
    if tags.get("area") == "yes" or tags.get("access") in ("no", "private"):
        return False
    return True


def read_osm_xml(path: str, detail: bool) -> tuple[dict[int, tuple[float, float]], list[Way]]:
    coords: dict[int, tuple[float, float]] = {}
    ways: list[Way] = []
    for _, el in ET.iterparse(path, events=("end",)):
        if el.tag == "node":
            coords[int(el.get("id"))] = (float(el.get("lat")), float(el.get("lon")))
            el.clear()
        elif el.tag == "way":
            tags = {t.get("k"): t.get("v") for t in el.findall("tag")}
            if accept_way(tags, detail):
                ways.append(Way(int(el.get("id")), [int(n.get("ref")) for n in el.findall("nd")], tags))
            el.clear()
    return coords, ways


def read_osm_pbf(path: str, detail: bool) -> tuple[dict[int, tuple[float, float]], list[Way]]:
    try:
        import osmium  # type: ignore
    except ImportError:
        sys.exit("File PBF butuh pyosmium: pip install osmium")

    ways: list[Way] = []

    class WayHandler(osmium.SimpleHandler):
        def way(self, w):  # noqa: N802
            tags = {t.k: t.v for t in w.tags}
            if accept_way(tags, detail):
                ways.append(Way(w.id, [n.ref for n in w.nodes], tags))

    WayHandler().apply_file(path)
    needed = {n for w in ways for n in w.nodes}
    coords: dict[int, tuple[float, float]] = {}

    class NodeHandler(osmium.SimpleHandler):
        def node(self, n):  # noqa: N802
            if n.id in needed:
                coords[n.id] = (n.location.lat, n.location.lon)

    NodeHandler().apply_file(path)
    return coords, ways


# ---------------------------------------------------------------- graph

def build_graph(coords, ways, bbox=None):
    """Kembalikan (nodes: dict osm_id -> (lat, lon)), edges: list[Edge])."""
    # Buang node di luar bbox; potong way di titik keluar bbox.
    usage: dict[int, int] = {}
    clean_ways: list[Way] = []
    for w in ways:
        segment: list[int] = []
        for n in w.nodes:
            if n in coords and in_bbox(*coords[n], bbox):
                segment.append(n)
            else:
                if len(segment) >= 2:
                    clean_ways.append(Way(w.osm_id, segment, w.tags))
                segment = []
        if len(segment) >= 2:
            clean_ways.append(Way(w.osm_id, segment, w.tags))

    for w in clean_ways:
        for i, n in enumerate(w.nodes):
            # ujung way dihitung 2 agar selalu jadi node graph
            usage[n] = usage.get(n, 0) + (2 if i in (0, len(w.nodes) - 1) else 1)

    graph_nodes: dict[int, tuple[float, float]] = {}
    edges: list[Edge] = []
    for w in clean_ways:
        hw = w.tags["highway"]
        speed = parse_maxspeed(w.tags.get("maxspeed")) or ROAD_CLASSES[hw]
        toll = is_toll(w.tags)
        weight = parse_maxweight(w.tags.get("maxweight"))
        direction = oneway_direction(w.tags)

        start = 0
        for i in range(1, len(w.nodes)):
            if usage[w.nodes[i]] < 2 and i != len(w.nodes) - 1:
                continue
            part = w.nodes[start:i + 1]
            geom = [coords[n] for n in part]
            length = sum(haversine_m(*geom[k], *geom[k + 1]) for k in range(len(geom) - 1))
            a, b = part[0], part[-1]
            graph_nodes[a] = coords[a]
            graph_nodes[b] = coords[b]
            if a != b and length > 0:
                if direction in (0, 1):
                    edges.append(Edge(a, b, length, hw, speed, toll, weight, geom, w.osm_id))
                if direction in (0, -1):
                    edges.append(Edge(b, a, length, hw, speed, toll, weight, list(reversed(geom)), w.osm_id))
            start = i
    return graph_nodes, edges


# ---------------------------------------------------------------- output

SCHEMA = """
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE nodes (id INTEGER PRIMARY KEY, osm_id INTEGER NOT NULL, lat REAL NOT NULL, lon REAL NOT NULL);
CREATE TABLE edges (
  id INTEGER PRIMARY KEY,
  from_node INTEGER NOT NULL REFERENCES nodes(id),
  to_node INTEGER NOT NULL REFERENCES nodes(id),
  length_m REAL NOT NULL,
  road_class TEXT NOT NULL,
  maxspeed_kmh INTEGER NOT NULL,
  toll INTEGER NOT NULL,
  maxweight_t REAL,
  geometry TEXT NOT NULL,
  osm_way_id INTEGER NOT NULL
);
CREATE INDEX edges_from ON edges(from_node);
"""


def write_outputs(nodes, edges, out_dir: str, source: str, write_json: bool) -> dict:
    os.makedirs(out_dir, exist_ok=True)
    ids = {osm: i for i, osm in enumerate(sorted(nodes))}
    db_path = os.path.join(out_dir, "roads.sqlite")
    if os.path.exists(db_path):
        os.remove(db_path)
    con = sqlite3.connect(db_path)
    con.executescript(SCHEMA)
    has_rtree = True
    try:
        con.execute("CREATE VIRTUAL TABLE nodes_rtree USING rtree(id, min_lat, max_lat, min_lon, max_lon)")
    except sqlite3.OperationalError:
        has_rtree = False
    con.executemany("INSERT INTO nodes VALUES (?,?,?,?)",
                    [(ids[o], o, lat, lon) for o, (lat, lon) in nodes.items()])
    if has_rtree:
        con.executemany("INSERT INTO nodes_rtree VALUES (?,?,?,?,?)",
                        [(ids[o], lat, lat, lon, lon) for o, (lat, lon) in nodes.items()])
    rows = [(i, ids[e.from_node], ids[e.to_node], round(e.length_m, 2), e.road_class, e.maxspeed_kmh,
             int(e.toll), e.maxweight_t, encode_polyline(e.geometry), e.osm_way_id)
            for i, e in enumerate(edges)]
    con.executemany("INSERT INTO edges VALUES (?,?,?,?,?,?,?,?,?,?)", rows)
    stats = {"nodes": len(nodes), "edges": len(edges), "toll_edges": sum(e.toll for e in edges),
             "source": os.path.basename(source), "graph_format": "1", "rtree": str(has_rtree)}
    con.executemany("INSERT INTO meta VALUES (?,?)", [(k, str(v)) for k, v in stats.items()])
    con.commit()
    con.close()

    if write_json:
        data = {
            "format": 1,
            "nodes": [[ids[o], round(lat, 7), round(lon, 7)] for o, (lat, lon) in sorted(nodes.items(), key=lambda x: ids[x[0]])],
            "edges": [list(r[1:9]) for r in rows],
        }
        with open(os.path.join(out_dir, "graph.json"), "w") as f:
            json.dump(data, f, separators=(",", ":"))
    return stats


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", help=".osm atau .osm.pbf")
    ap.add_argument("--out", required=True, help="folder output")
    ap.add_argument("--bbox", help="min_lon,min_lat,max_lon,max_lat")
    ap.add_argument("--detail", action="store_true", help="sertakan jalan residential/unclassified")
    ap.add_argument("--json", action="store_true", help="tulis juga graph.json")
    args = ap.parse_args(argv)

    bbox = tuple(float(x) for x in args.bbox.split(",")) if args.bbox else None
    reader = read_osm_pbf if args.input.endswith(".pbf") else read_osm_xml
    coords, ways = reader(args.input, args.detail)
    nodes, edges = build_graph(coords, ways, bbox)
    stats = write_outputs(nodes, edges, args.out, args.input, args.json)
    print(json.dumps(stats, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
