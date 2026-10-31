import 'dart:math' as math;
import 'dart:ui';

import 'package:sim_core/sim_core.dart';

import '../../app/theme.dart';

/// Proyeksi equirectangular lokal: lat/lon → meter (x timur, y selatan) di
/// sekitar titik acuan. Cukup akurat untuk satu kota.
class LocalProjection {
  LocalProjection(this.origin) : _kx = 111320 * math.cos(origin.lat * math.pi / 180);

  final LatLng origin;
  final double _kx;
  static const _ky = 110540.0;

  Offset project(LatLng p) => Offset((p.lon - origin.lon) * _kx, -(p.lat - origin.lat) * _ky);
}

/// Gaya per kelompok kelas jalan, digambar dari bawah ke atas.
class RoadStyle {
  const RoadStyle(this.color, this.widthPx, this.minScale);

  final Color color;
  final double widthPx;

  /// Skala (px per meter) minimum agar kelompok ini digambar (LOD).
  final double minScale;
}

enum RoadGroup { minor, tertiary, secondary, primary }

const roadStyles = {
  RoadGroup.minor: RoadStyle(Color(0xFF34414E), 1.0, 0.25),
  RoadGroup.tertiary: RoadStyle(Color(0xFF465665), 1.4, 0.06),
  RoadGroup.secondary: RoadStyle(AppColors.road, 1.8, 0.0),
  RoadGroup.primary: RoadStyle(Color(0xFF8C9AA8), 2.4, 0.0),
};

RoadGroup groupOf(RoadEdge e) {
  // Jalan tol digambar seperti jalan utama: peta netral, sorotan hanya untuk rute aktif.
  return switch (e.roadClass) {
    RoadClass.motorway ||
    RoadClass.motorwayLink ||
    RoadClass.trunk ||
    RoadClass.trunkLink ||
    RoadClass.primary ||
    RoadClass.primaryLink => RoadGroup.primary,
    RoadClass.secondary || RoadClass.secondaryLink => RoadGroup.secondary,
    RoadClass.tertiary || RoadClass.tertiaryLink => RoadGroup.tertiary,
    RoadClass.unclassified || RoadClass.residential => RoadGroup.minor,
  };
}

/// Jaringan jalan kota sebagai [Path] dalam meter, dibuat sekali per graph.
class RoadLayer {
  RoadLayer._(this.projection, this.paths, this.bounds);

  factory RoadLayer.build(RoadGraph graph, LatLng origin) {
    final projection = LocalProjection(origin);
    final paths = {for (final g in RoadGroup.values) g: Path()};
    final seen = <String>{};
    var bounds = Rect.zero;
    for (var i = 0; i < graph.edgeCount; i++) {
      final e = graph.edge(i);
      // Jalan dua arah = dua edge; gambar sekali. Panjang ikut jadi kunci agar
      // dua ruas berbeda di antara persimpangan yang sama tetap tergambar.
      final key = e.from < e.to ? '${e.from}-${e.to}-${e.lengthM.round()}' : '${e.to}-${e.from}-${e.lengthM.round()}';
      if (!seen.add(key)) continue;
      var geom = e.geometry;
      if (geom.length < 2) geom = [graph.node(e.from), graph.node(e.to)];
      final path = paths[groupOf(e)]!;
      final first = projection.project(geom.first);
      path.moveTo(first.dx, first.dy);
      for (var k = 1; k < geom.length; k++) {
        final p = projection.project(geom[k]);
        path.lineTo(p.dx, p.dy);
      }
      bounds = bounds.expandToInclude(Rect.fromPoints(first, projection.project(geom.last)));
    }
    return RoadLayer._(projection, paths, bounds);
  }

  final LocalProjection projection;
  final Map<RoadGroup, Path> paths;
  final Rect bounds;
}
