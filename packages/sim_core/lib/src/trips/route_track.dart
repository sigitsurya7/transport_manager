import 'dart:math' as math;

import '../routing/geo.dart';
import '../routing/road_graph.dart';

/// Posisi & arah kendaraan di jalan.
class TrackPose {
  const TrackPose(this.position, this.headingDeg);

  final LatLng position;

  /// Arah hadap, derajat dari utara searah jarum jam.
  final double headingDeg;
}

/// Polyline satu leg beserta pembagian waktunya, untuk menghitung posisi
/// kendaraan sebagai fungsi waktu (tanpa update per frame di simulasi).
///
/// Waktu leg dibagi ke tiap ruas sebanding dengan `panjang / kecepatan`,
/// lalu di dalam ruas sebanding dengan panjang segmen geometri.
class RouteTrack {
  RouteTrack._(this._points, this._timeAt);

  factory RouteTrack.build(
    RoadGraph graph,
    List<int> edges, {
    required int startNode,
    required double Function(RoadEdge edge) speedMps,
  }) {
    if (edges.isEmpty) {
      final p = graph.node(startNode);
      return RouteTrack._([p], [0]);
    }
    final points = <LatLng>[];
    final time = <double>[];
    var t = 0.0;
    for (final id in edges) {
      final e = graph.edge(id);
      var geom = e.geometry;
      if (geom.length < 2) geom = [graph.node(e.from), graph.node(e.to)];
      final segLengths = [
        for (var i = 1; i < geom.length; i++) haversineMeters(geom[i - 1], geom[i]),
      ];
      final geomLength = segLengths.fold(0.0, (a, b) => a + b);
      final edgeTime = e.lengthM / speedMps(e);
      if (points.isEmpty) {
        points.add(geom.first);
        time.add(0);
      }
      for (var i = 1; i < geom.length; i++) {
        t += geomLength == 0 ? edgeTime / segLengths.length : edgeTime * segLengths[i - 1] / geomLength;
        points.add(geom[i]);
        time.add(t);
      }
    }
    final total = t == 0 ? 1.0 : t;
    return RouteTrack._(points, [for (final x in time) x / total]);
  }

  final List<LatLng> _points;

  /// Fraksi waktu kumulatif (0..1) saat tiba di tiap titik.
  final List<double> _timeAt;

  List<LatLng> get points => List.unmodifiable(_points);

  /// Posisi pada fraksi waktu [progress] (0 = berangkat, 1 = tiba).
  TrackPose poseAt(double progress) {
    if (_points.length == 1) return TrackPose(_points.first, 0);
    final f = progress.clamp(0.0, 1.0);
    var lo = 0, hi = _timeAt.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_timeAt[mid] <= f) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = _points[lo], b = _points[hi];
    final span = _timeAt[hi] - _timeAt[lo];
    final u = span == 0 ? 0.0 : (f - _timeAt[lo]) / span;
    return TrackPose(
      LatLng(a.lat + (b.lat - a.lat) * u, a.lon + (b.lon - a.lon) * u),
      _bearing(a, b),
    );
  }

  static double _bearing(LatLng a, LatLng b) {
    final p1 = a.lat * math.pi / 180, p2 = b.lat * math.pi / 180;
    final dl = (b.lon - a.lon) * math.pi / 180;
    final y = math.sin(dl) * math.cos(p2);
    final x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
}
