import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:sim_core/sim_core.dart';
import 'package:test/test.dart';

const pickup = VehicleProfile(
  vehicleClass: VehicleClass.pickupBox,
  maxSpeedKmh: 80,
  grossWeightT: 2.5,
  tollGolongan: 1,
);

const heavy = VehicleProfile(
  vehicleClass: VehicleClass.heavyRigid,
  maxSpeedKmh: 70,
  grossWeightT: 25,
  tollGolongan: 3,
);

RoadGraph loadMini() => RoadGraph.fromJson(
    jsonDecode(File('test/fixtures/mini_graph.json').readAsStringSync()) as Map<String, dynamic>);

void main() {
  test('polyline kompatibel dengan pipeline Python', () {
    final pts = decodePolyline('~jlyJ_wpujE?_t`B');
    expect(pts.length, 2);
    expect(pts[0].lat, closeTo(-6.2, 1e-9));
    expect(pts[0].lon, closeTo(106.8, 1e-9));
    expect(pts[1].lon, closeTo(106.85, 1e-9));
  });

  group('mini graph dari pipeline', () {
    final graph = loadMini();
    final planner = RoutePlanner(graph);

    test('graph termuat', () {
      expect(graph.nodeCount, 4);
      expect(graph.edgeCount, 6);
      expect(graph.edge(0).isToll, isTrue);
      expect(graph.edge(0).geometry.length, 3);
    });

    test('mode tol memilih motorway', () {
      final r = planner.find(0, 1, pickup, RouteMode.toll)!;
      expect(r.edges, [0]);
      expect(r.usesToll, isTrue);
      expect(r.distanceM, closeTo(11054.47, 0.01));
      expect(r.durationS, closeTo(11054.47 / (80 / 3.6), 0.01));
      expect(r.tollCostIdr, 11054);
    });

    test('mode non-tol memutar lewat jalan primary', () {
      final r = planner.find(0, 1, pickup, RouteMode.nonToll)!;
      expect(r.nodes, [0, 2, 1]);
      expect(r.usesToll, isFalse);
      expect(r.tollCostIdr, 0);
      expect(r.distanceM, closeTo(14389.69 + 3335.85, 0.01));
      expect(r.durationS, closeTo((14389.69 + 3335.85) / (60 / 3.6), 0.01));
    });

    test('options memberi dua kandidat; tol lebih cepat', () {
      final o = planner.options(0, 1, pickup);
      expect(o.viaToll!.durationS, lessThan(o.nonToll!.durationS));
    });

    test('batas berat jalan menutup rute non-tol untuk truk berat', () {
      expect(planner.find(0, 1, heavy, RouteMode.nonToll), isNull);
      final viaToll = planner.find(0, 1, heavy, RouteMode.toll)!;
      expect(viaToll.tollCostIdr, (11054.47 / 1000 * 1500).round());
    });

    test('tidak terjangkau → null (node 3 tidak punya jalan keluar)', () {
      expect(planner.find(3, 0, pickup, RouteMode.toll), isNull);
    });

    test('asal = tujuan', () {
      final r = planner.find(2, 2, pickup, RouteMode.toll)!;
      expect(r.distanceM, 0);
      expect(r.edges, isEmpty);
    });
  });

  test('A* sama optimalnya dengan Dijkstra pada grid acak', () {
    final rng = DeterministicRng(2026);
    const size = 12;
    final nodes = <LatLng>[];
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        nodes.add(LatLng(-6.9 + y * 0.01, 107.6 + x * 0.01));
      }
    }
    final edges = <RoadEdge>[];
    void link(int a, int b) {
      final len = haversineMeters(nodes[a], nodes[b]);
      final cls = RoadClass.values[rng.nextInt(RoadClass.values.length)];
      final speed = 20 + rng.nextInt(80);
      final toll = rng.nextBool(0.2);
      for (final pair in [(a, b), (b, a)]) {
        edges.add(RoadEdge(
          id: edges.length,
          from: pair.$1,
          to: pair.$2,
          lengthM: len,
          roadClass: cls,
          maxSpeedKmh: speed,
          isToll: toll,
        ));
      }
    }

    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final i = y * size + x;
        if (x + 1 < size) link(i, i + 1);
        if (y + 1 < size) link(i, i + size);
      }
    }
    final graph = RoadGraph(nodes: nodes, edges: edges);
    final planner = RoutePlanner(graph);

    double dijkstra(int from, int to, RouteMode mode) {
      final dist = List<double>.filled(graph.nodeCount, double.infinity);
      final done = List<bool>.filled(graph.nodeCount, false);
      dist[from] = 0;
      for (var k = 0; k < graph.nodeCount; k++) {
        var u = -1;
        for (var i = 0; i < graph.nodeCount; i++) {
          if (!done[i] && (u == -1 || dist[i] < dist[u])) u = i;
        }
        if (u == -1 || dist[u] == double.infinity) break;
        done[u] = true;
        for (final e in graph.outgoing(u)) {
          if (!planner.isAllowed(e, pickup, mode)) continue;
          final c = dist[u] + e.lengthM / planner.speedMps(e, pickup);
          dist[e.to] = math.min(dist[e.to], c);
        }
      }
      return dist[to];
    }

    for (var t = 0; t < 30; t++) {
      final a = rng.nextInt(graph.nodeCount);
      final b = rng.nextInt(graph.nodeCount);
      for (final mode in RouteMode.values) {
        final expected = dijkstra(a, b, mode);
        final r = planner.find(a, b, pickup, mode);
        if (expected == double.infinity) {
          expect(r, isNull);
        } else {
          expect(r!.durationS, closeTo(expected, 1e-6), reason: '$a→$b $mode');
          if (mode == RouteMode.nonToll) expect(r.usesToll, isFalse);
        }
      }
    }
  });
}
