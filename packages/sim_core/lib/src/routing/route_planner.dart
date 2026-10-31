import 'dart:math' as math;

import '../vehicle/vehicle_profile.dart';
import 'geo.dart';
import 'road_graph.dart';
import 'toll_tariff.dart';

enum RouteMode {
  /// Jalan tol boleh dipakai.
  toll,

  /// Jalan tol dilarang.
  nonToll,
}

class Route {
  const Route({
    required this.mode,
    required this.nodes,
    required this.edges,
    required this.distanceM,
    required this.durationS,
    required this.tollDistanceM,
    required this.tollCostIdr,
  });

  final RouteMode mode;
  final List<int> nodes;
  final List<int> edges;
  final double distanceM;

  /// Waktu tempuh dalam detik game.
  final double durationS;

  final double tollDistanceM;
  final int tollCostIdr;

  bool get usesToll => tollDistanceM > 0;
}

/// Dua kandidat rute untuk ditampilkan berdampingan saat dispatch.
class RouteOptions {
  const RouteOptions({this.viaToll, this.nonToll});

  /// Rute tercepat dengan tol diizinkan. Bisa saja tidak melewati tol bila
  /// rute non-tol lebih cepat; cek [Route.usesToll].
  final Route? viaToll;
  final Route? nonToll;
}

/// Routing A* berbasis waktu tempuh untuk profil kendaraan tertentu.
class RoutePlanner {
  RoutePlanner(this.graph, {this.tariff = const TollTariff.approximate()});

  final RoadGraph graph;
  final TollTariff tariff;

  RouteOptions options(int from, int to, VehicleProfile vehicle) => RouteOptions(
        viaToll: find(from, to, vehicle, RouteMode.toll),
        nonToll: find(from, to, vehicle, RouteMode.nonToll),
      );

  bool isAllowed(RoadEdge edge, VehicleProfile vehicle, RouteMode mode) {
    if (mode == RouteMode.nonToll && edge.isToll) return false;
    final limit = edge.maxWeightT;
    if (limit != null && vehicle.grossWeightT > limit) return false;
    return true;
  }

  double speedMps(RoadEdge edge, VehicleProfile vehicle) =>
      math.min(edge.maxSpeedKmh, vehicle.maxSpeedKmh) * vehicle.speedFactor / 3.6;

  /// Cari rute tercepat dari [from] ke [to]. `null` bila tidak terjangkau.
  Route? find(int from, int to, VehicleProfile vehicle, RouteMode mode) {
    final n = graph.nodeCount;
    if (from < 0 || from >= n || to < 0 || to >= n) {
      throw RangeError('Node di luar graph: $from → $to');
    }
    if (from == to) {
      return Route(
        mode: mode,
        nodes: [from],
        edges: const [],
        distanceM: 0,
        durationS: 0,
        tollDistanceM: 0,
        tollCostIdr: 0,
      );
    }

    // Kecepatan tertinggi yang mungkin → heuristik admissible.
    final vmax =
        math.min(graph.maxSpeedKmh, vehicle.maxSpeedKmh) * vehicle.speedFactor / 3.6;
    final target = graph.node(to);
    double h(int node) => haversineMeters(graph.node(node), target) / vmax;

    final g = List<double>.filled(n, double.infinity);
    final viaEdge = List<int>.filled(n, -1);
    final closed = List<bool>.filled(n, false);
    final open = _MinHeap();

    g[from] = 0;
    open.push(h(from), from);

    while (open.isNotEmpty) {
      final current = open.pop();
      if (closed[current]) continue;
      if (current == to) break;
      closed[current] = true;

      for (final edge in graph.outgoing(current)) {
        if (closed[edge.to] || !isAllowed(edge, vehicle, mode)) continue;
        final cost = g[current] + edge.lengthM / speedMps(edge, vehicle);
        if (cost < g[edge.to]) {
          g[edge.to] = cost;
          viaEdge[edge.to] = edge.id;
          open.push(cost + h(edge.to), edge.to);
        }
      }
    }

    if (g[to] == double.infinity) return null;

    final edges = <int>[];
    var node = to;
    while (node != from) {
      final e = graph.edge(viaEdge[node]);
      edges.add(e.id);
      node = e.from;
    }
    final orderedEdges = edges.reversed.toList();

    var distance = 0.0;
    var tollDistance = 0.0;
    final nodes = <int>[from];
    for (final id in orderedEdges) {
      final e = graph.edge(id);
      distance += e.lengthM;
      if (e.isToll) tollDistance += e.lengthM;
      nodes.add(e.to);
    }

    return Route(
      mode: mode,
      nodes: nodes,
      edges: orderedEdges,
      distanceM: distance,
      durationS: g[to],
      tollDistanceM: tollDistance,
      tollCostIdr: tollDistance > 0 ? tariff.cost(tollDistance, vehicle.tollGolongan) : 0,
    );
  }
}

/// Min-heap sederhana (prioritas double, nilai int) untuk A*.
class _MinHeap {
  final List<double> _keys = [];
  final List<int> _values = [];

  bool get isNotEmpty => _keys.isNotEmpty;

  void push(double key, int value) {
    _keys.add(key);
    _values.add(value);
    var i = _keys.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_keys[p] <= _keys[i]) break;
      _swap(i, p);
      i = p;
    }
  }

  int pop() {
    final top = _values.first;
    final lastKey = _keys.removeLast();
    final lastValue = _values.removeLast();
    if (_keys.isNotEmpty) {
      _keys[0] = lastKey;
      _values[0] = lastValue;
      var i = 0;
      while (true) {
        final l = 2 * i + 1;
        final r = l + 1;
        var m = i;
        if (l < _keys.length && _keys[l] < _keys[m]) m = l;
        if (r < _keys.length && _keys[r] < _keys[m]) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return top;
  }

  void _swap(int a, int b) {
    final k = _keys[a];
    _keys[a] = _keys[b];
    _keys[b] = k;
    final v = _values[a];
    _values[a] = _values[b];
    _values[b] = v;
  }
}
