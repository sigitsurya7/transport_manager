import 'dart:convert';
import 'dart:math' as math;

import 'package:sim_core/sim_core.dart';

/// Titik di lantai depot (meter). x = timur, z = selatan; jalan umum di +z.
typedef FloorPoint = ({double x, double z});

/// Posisi + arah hadap. [heading] radian, 0 = menghadap +x (arah model kendaraan).
typedef FloorPose = ({double x, double z, double heading});

/// Arah hadap untuk hidung ke -z (masuk slot / menjauhi jalan).
const headingNorth = math.pi / 2;

/// Arah hadap untuk hidung ke +z (keluar dari dock / menuju jalan).
const headingSouth = -math.pi / 2;

class BoomSpec {
  const BoomSpec({required this.hinge, required this.model, required this.side});

  final FloorPoint hinge;
  final String model;

  /// +1 palang memanjang ke +x, -1 ke -x.
  final int side;
}

/// Titik penting depot dari `depot_layout.json` (dibuat bersama modul GLB).
class DepotLayout {
  DepotLayout._(this.json);

  factory DepotLayout.parse(String text) => DepotLayout._(jsonDecode(text) as Map<String, dynamic>);

  final Map<String, dynamic> json;

  static FloorPoint _pt(Object? v) {
    final l = (v as List).cast<num>();
    return (x: l[0].toDouble(), z: l[1].toDouble());
  }

  FloorPoint get outside => _pt(json['outside']);
  FloorPoint get gate => _pt(json['gate']);
  double get laneZ => (json['lane_z'] as num).toDouble();
  double get roadLaneZ => (json['road_lane_z'] as num).toDouble();
  List<FloorPoint> get slots => [for (final s in json['parking_slots'] as List) _pt(s)];

  /// Posisi z lampu lantai di mulut slot parkir.
  double get slotMarkerZ => (json['slot_marker_z'] as num).toDouble();

  List<FloorPoint> docks(int level) => [for (final d in (json['docks'] as Map)['$level'] as List) _pt(d)];

  List<double> gateLanes(int level) => [
    for (final x in (json['gate_lanes'] as Map)['$level'] as List) (x as num).toDouble(),
  ];

  List<BoomSpec> booms(int level) => [
    for (final b in ((json['booms'] as Map)['$level'] as List).cast<Map<String, dynamic>>())
      BoomSpec(hinge: _pt(b['hinge']), model: b['model'] as String, side: (b['side'] as num).toInt()),
  ];

  FloorPoint anchor(FacilityType type) => _pt((json['anchors'] as Map)[type.id]);

  /// Rintangan lantai per modul GLB: (x0, z0, x1, z1).
  List<(double, double, double, double)> obstacles(String model) => [
    for (final b in ((json['obstacles'] as Map)[model] as List?) ?? const [])
      ((b[0] as num).toDouble(), (b[1] as num).toDouble(), (b[2] as num).toDouble(), (b[3] as num).toDouble()),
  ];

  /// Titik palet muatan di lantai bak (koordinat model), depan → belakang.
  List<(double, double, double)> vehicleCargo(String visual) => [
    for (final c in ((json['vehicle_cargo'] as Map)[visual] as List?) ?? const [])
      ((c[0] as num).toDouble(), (c[1] as num).toDouble(), (c[2] as num).toDouble()),
  ];

  /// Kendaraan dengan pintu belakang (punya model `<visual>_open`).
  bool hasDoors(String visual) => ((json['vehicles_with_doors'] as List?) ?? const []).contains(visual);

  /// Tapak kendaraan (koordinat model): (xMin, xMax, zMin, zMax).
  (double, double, double, double) vehicleBounds(String visual) {
    final b = ((json['vehicle_bounds'] as Map)[visual] as List).cast<num>();
    return (b[0].toDouble(), b[1].toDouble(), b[2].toDouble(), b[3].toDouble());
  }
}

/// Satu titik jalur; [reverse] = segmen menuju titik ini ditempuh mundur.
typedef PathPoint = ({FloorPoint p, bool reverse});

PathPoint fw(double x, double z) => (p: (x: x, z: z), reverse: false);
PathPoint rv(double x, double z) => (p: (x: x, z: z), reverse: true);

/// Jalur terbuka, posisi sebagai fungsi fraksi (0..1) dengan percepatan /
/// perlambatan halus dan belokan yang tidak patah.
class DepotPath {
  DepotPath(this.start, this.points, {double? startHeading}) {
    var prev = start;
    for (final pt in points) {
      final len = math.sqrt(math.pow(pt.p.x - prev.x, 2) + math.pow(pt.p.z - prev.z, 2));
      _lengths.add(len);
      _headings.add(len < 1e-6 && _headings.isNotEmpty ? _headings.last : _heading(prev, pt.p, pt.reverse));
      prev = pt.p;
    }
    _startHeading = startHeading ?? (_headings.isEmpty ? 0 : _headings.first);
    length = _lengths.fold(0.0, (a, b) => a + b);
  }

  final FloorPoint start;
  final List<PathPoint> points;
  final _lengths = <double>[];
  final _headings = <double>[];
  late final double _startHeading;
  late final double length;

  FloorPoint get end => points.isEmpty ? start : points.last.p;
  double get endHeading => _headings.isEmpty ? _startHeading : _headings.last;

  static const _turnBlendM = 2.0;

  static double _heading(FloorPoint a, FloorPoint b, bool reverse) {
    final h = math.atan2(-(b.z - a.z), b.x - a.x);
    return reverse ? h + math.pi : h;
  }

  FloorPose poseAt(double fraction) {
    if (points.isEmpty || length == 0) return (x: end.x, z: end.z, heading: endHeading);
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
        final before = i == 0 ? _startHeading : _headings[i - 1];
        if (d < _turnBlendM) {
          heading = _lerpAngle(before, heading, i == 0 ? d / _turnBlendM : 0.5 + 0.5 * d / _turnBlendM);
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

/// Lewat gerbang: mendekat & berhenti di depan palang, menunggu pemeriksaan,
/// lalu melaju setelah palang terbuka. Fraksi waktu per tahap:
const _approachEnd = 0.3, _checkEnd = 0.6;

/// Bukaan palang (0 tertutup, 1 terbuka) selama fase lewat gerbang.
double boomOpenAt(double progress) {
  double ramp(double a, double b, double x) => ((x - a) / (b - a)).clamp(0.0, 1.0);
  return ramp(_checkEnd - 0.1, _checkEnd, progress) * (1 - ramp(0.88, 1.0, progress));
}

FloorPose _staged(DepotPath approach, DepotPath drive, double progress) {
  if (progress < _approachEnd) return approach.poseAt(progress / _approachEnd);
  if (progress < _checkEnd) return approach.poseAt(1);
  return drive.poseAt((progress - _checkEnd) / (1 - _checkEnd));
}

/// Pose kendaraan di dalam & di depan depot untuk tiap fase trip. Fase di
/// jalan jauh / di pelanggan → `null` (tidak terlihat di depot).
class DepotMotion {
  DepotMotion(this.layout);

  final DepotLayout layout;

  /// Ujung depan kendaraan acuan jalur (truk engkel lama).
  static const defaultFront = 3.9;

  static const _outQueueX = 3.5, _outQueueGap = 5.5;
  static const _inQueueX = -9.0, _inQueueGap = 6.5;

  FloorPose parked(int slot) {
    final s = layout.slots[slot];
    return (x: s.x, z: s.z, heading: headingNorth);
  }

  FloorPoint _outQueueSpot(int q) => (x: _outQueueX + _outQueueGap * q, z: layout.laneZ);
  FloorPoint _inQueueSpot(int q) => (x: _inQueueX - _inQueueGap * q, z: layout.roadLaneZ);

  /// [snap]: keadaan kendaraan; [dockLevel]/[gateLevel]: level fasilitas saat
  /// ini; [outQueueAhead]: jumlah kendaraan yang sudah antre keluar (untuk
  /// menentukan tempat berhenti kendaraan yang sedang menuju antrean);
  /// [front]: jarak origin ke ujung depan kendaraan. Kendaraan panjang
  /// berbelok lebih awal dan berhenti lebih jauh dari palang agar ujung
  /// depannya tidak menyapu pos jaga, pulau jalur, atau kantor.
  FloorPose? pose(
    VehicleSnapshot snap, {
    required int dockLevel,
    required int gateLevel,
    int outQueueAhead = 0,
    double front = defaultFront,
  }) {
    final extra = math.max(0.0, front - defaultFront);
    final s = layout.slots[snap.slotIndex.clamp(0, layout.slots.length - 1)];
    final lane = layout.laneZ;
    final docks = layout.docks(dockLevel);
    final dock = docks[(snap.dock ?? 0).clamp(0, docks.length - 1)];
    final lanes = layout.gateLanes(gateLevel);
    final gx = lanes[(snap.gateLane ?? 0).clamp(0, lanes.length - 1)];
    final gz = layout.gate.z;
    final road = layout.roadLaneZ;
    final p = snap.phaseProgress;

    switch (snap.phase) {
      case null || TripPhase.completed || TripPhase.inspection || TripPhase.waitDock:
        return parked(snap.slotIndex);
      case TripPhase.toDock:
        // Mundur keluar slot, maju melewati dock, lalu mundur ke dock.
        return DepotPath(s, [
          rv(s.x, lane - 1.5),
          // Ayunan mundur kecil: bak tidak menyentuh pagar barat maupun kantor.
          rv(s.x - 1.0, lane),
          // Kendaraan panjang tidak boleh melewati pagar timur saat maju sebelum mundur ke dock.
          fw(math.min(dock.x + 1.8, 19.4 - front), lane),
          rv(dock.x + 0.2, lane - 2.0),
          // Bagian akhir lurus agar bak tepat di depan platform tanpa menyenggol.
          rv(dock.x, lane - 3.5),
          rv(dock.x, dock.z),
        ], startHeading: headingNorth).poseAt(p);
      case TripPhase.loading:
        return (x: dock.x, z: dock.z, heading: headingSouth);
      case TripPhase.toGate:
        final spot = _outQueueSpot(outQueueAhead);
        // Belok lebih awal bila panjang: moncong tidak menyapu area istirahat di utara jalur.
        return DepotPath(dock, [
          fw(dock.x, lane - 1.5 - 1.5 * extra),
          fw(spot.x, spot.z),
        ], startHeading: headingSouth).poseAt(p);
      case TripPhase.waitGateOut:
        final spot = _outQueueSpot(snap.queuePosition ?? 0);
        return (x: spot.x, z: spot.z, heading: math.pi);
      case TripPhase.gateOut:
        final spot = _outQueueSpot(0);
        final stop = gz - 3.2 - extra;
        // Kendaraan panjang berbelok di sisi selatan jalur agar moncongnya
        // selesai menyapu sebelum mendekati kantor & pos jaga.
        final approach = DepotPath(spot, [
          fw(gx + 1.5 + 2 * extra, lane - 1.5 * extra),
          fw(gx, lane + 2.0 - 3 * extra),
          fw(gx, stop),
        ]);
        // Lurus melewati gerbang sampai bak lepas dari pilar, baru belok ke lajur kiri.
        final drive = DepotPath((x: gx, z: stop), [fw(gx, gz + 4.2), fw(gx + 4.0, road), fw(gx + 40, road)]);
        return _staged(approach, drive, p);
      case TripPhase.outbound || TripPhase.unloading || TripPhase.inbound:
        return null;
      case TripPhase.waitGateIn:
        final spot = _inQueueSpot(snap.queuePosition ?? 0);
        return (x: spot.x, z: spot.z, heading: 0);
      case TripPhase.gateIn:
        final start = _inQueueSpot(0);
        // Belok dari lajur kiri, lalu lurus beberapa meter sebelum berhenti di palang.
        final stop = gz + 3.2 + extra;
        // Kendaraan panjang melebar ke lajur jauh dulu, sehingga sudah lurus
        // sebelum moncongnya mencapai pilar & pulau jalur.
        final corner = extra == 0 ? road - 0.4 : 16.9 + front + 3.2;
        final approach = DepotPath(start, [
          if (extra > 0) ...[fw(gx - 5.0 - 2 * extra, road), fw(gx - 1.0, corner)],
          if (extra == 0) fw(gx - 5.0, road),
          fw(gx, corner - (extra > 0 ? 1.0 : 0.0)),
          fw(gx, stop),
        ], startHeading: 0);
        final drive = DepotPath((x: gx, z: stop), [fw(gx, gz - 2.5), fw(gx, lane + 1.5)]);
        return _staged(approach, drive, p);
      case TripPhase.toSlot:
        final start = (x: gx, z: lane + 1.5);
        final pts = <PathPoint>[fw(gx, lane + 0.5)];
        if (s.x + 3.5 < gx - 1) pts.add(fw(s.x + 3.5, lane));
        pts
          ..add(fw(s.x, lane - 3.0))
          ..add(fw(s.x, s.z));
        return DepotPath(start, pts, startHeading: headingNorth).poseAt(p);
    }
  }
}
