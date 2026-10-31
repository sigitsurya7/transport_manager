import 'dart:convert';
import 'dart:math' as math;

import 'package:sim_core/sim_core.dart';

/// Titik di lantai depot (meter). x = timur, z = selatan (gerbang di +z).
typedef FloorPoint = ({double x, double z});

/// Posisi + arah hadap. [heading] radian, 0 = menghadap +x (arah model pikap).
typedef FloorPose = ({double x, double z, double heading});

/// Titik-titik penting depot dari `depot_layout.json` (dibuat bersama depot.glb).
class DepotLayout {
  DepotLayout._(this.json);

  factory DepotLayout.parse(String text) => DepotLayout._(jsonDecode(text) as Map<String, dynamic>);

  final Map<String, dynamic> json;

  FloorPoint _p(String key) {
    final l = (json[key] as List).cast<num>();
    return (x: l[0].toDouble(), z: l[1].toDouble());
  }

  FloorPoint get outside => _p('outside');
  FloorPoint get gate => _p('gate');
  double get laneZ => (json['lane_z'] as num).toDouble();
  FloorPoint get dockStop => _p('dock_stop');
  List<FloorPoint> get slots => [
        for (final s in (json['parking_slots'] as List).cast<List>())
          (x: (s[0] as num).toDouble(), z: (s[1] as num).toDouble()),
      ];
}

/// Satu titik jalur; [reverse] = segmen menuju titik ini ditempuh mundur.
typedef PathPoint = ({FloorPoint p, bool reverse});

/// Jalur terbuka, posisi sebagai fungsi fraksi jarak (0..1) dengan
/// percepatan/perlambatan halus dan belokan yang tidak patah.
class DepotPath {
  DepotPath(this.start, this.points) {
    var prev = start;
    for (final pt in points) {
      final len = math.sqrt(math.pow(pt.p.x - prev.x, 2) + math.pow(pt.p.z - prev.z, 2));
      _lengths.add(len);
      _headings.add(_heading(prev, pt.p, pt.reverse));
      prev = pt.p;
    }
    length = _lengths.fold(0.0, (a, b) => a + b);
  }

  final FloorPoint start;
  final List<PathPoint> points;
  final _lengths = <double>[];
  final _headings = <double>[];
  late final double length;

  static const _turnBlendM = 2.0;

  static double _heading(FloorPoint a, FloorPoint b, bool reverse) {
    final h = math.atan2(-(b.z - a.z), b.x - a.x);
    return reverse ? h + math.pi : h;
  }

  FloorPose poseAt(double fraction) {
    if (points.isEmpty || length == 0) return (x: start.x, z: start.z, heading: _headings.isEmpty ? math.pi / 2 : _headings.first);
    final f = fraction.clamp(0.0, 1.0);
    final eased = f * f * (3 - 2 * f); // smoothstep: mulai & berhenti pelan
    var d = eased * length;
    var prev = start;
    for (var i = 0; i < points.length; i++) {
      final seg = _lengths[i];
      if (d <= seg || i == points.length - 1) {
        final t = seg == 0 ? 1.0 : (d / seg).clamp(0.0, 1.0);
        final p = points[i].p;
        var heading = _headings[i];
        if (i > 0 && d < _turnBlendM) {
          heading = _lerpAngle(_headings[i - 1], heading, 0.5 + 0.5 * d / _turnBlendM);
        } else if (i < points.length - 1 && seg - d < _turnBlendM) {
          heading = _lerpAngle(heading, _headings[i + 1], 0.5 * (1 - (seg - d) / _turnBlendM));
        }
        return (x: prev.x + (p.x - prev.x) * t, z: prev.z + (p.z - prev.z) * t, heading: heading);
      }
      d -= seg;
      prev = points[i].p;
    }
    throw StateError('tidak tercapai');
  }

  static double _lerpAngle(double a, double b, double t) {
    var diff = (b - a) % (2 * math.pi);
    if (diff > math.pi) diff -= 2 * math.pi;
    if (diff < -math.pi) diff += 2 * math.pi;
    return a + diff * t;
  }
}

/// Pose kendaraan di dalam depot untuk tiap fase trip. Fase di jalan / di
/// pelanggan → `null` (kendaraan tidak terlihat di depot).
class DepotMotion {
  DepotMotion(this.layout);

  final DepotLayout layout;

  /// Parkir: hidung menghadap jalur (+z) agar siap keluar.
  static const parkedHeading = -math.pi / 2;

  FloorPose parked(int slot) {
    final s = layout.slots[slot];
    return (x: s.x, z: s.z, heading: parkedHeading);
  }

  FloorPose? pose(int slot, TripPhase? phase, double progress) {
    final s = layout.slots[slot];
    final lane = layout.laneZ;
    final dock = layout.dockStop;
    final gate = layout.gate;
    final out = layout.outside;
    PathPoint fw(double x, double z) => (p: (x: x, z: z), reverse: false);
    PathPoint rv(double x, double z) => (p: (x: x, z: z), reverse: true);

    return switch (phase) {
      null || TripPhase.completed => parked(slot),
      TripPhase.inspection => parked(slot),
      TripPhase.toDock => DepotPath(s, [fw(s.x, lane), fw(dock.x, lane), fw(dock.x, dock.z)]).poseAt(progress),
      TripPhase.loading => (x: dock.x, z: dock.z, heading: math.pi / 2),
      TripPhase.toGate => DepotPath(dock, [rv(dock.x, lane), fw(gate.x, lane), fw(gate.x, gate.z), fw(out.x, out.z)])
          .poseAt(progress),
      TripPhase.outbound || TripPhase.unloading || TripPhase.inbound => null,
      TripPhase.gateIn => DepotPath(out, [fw(gate.x, gate.z), fw(gate.x, lane + 1)]).poseAt(progress),
      TripPhase.toSlot => DepotPath((x: gate.x, z: lane + 1), [
          fw(gate.x, lane),
          fw(s.x - 5, lane),
          rv(s.x, lane - 2),
          rv(s.x, s.z),
        ]).poseAt(progress),
    };
  }
}
