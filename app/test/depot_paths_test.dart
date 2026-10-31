import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sim_core/sim_core.dart';
import 'package:transport_manager/features/depot/depot_paths.dart';

/// Layout asli hasil generator (aset yang dipakai app).
DepotLayout loadLayout() => DepotLayout.parse(File('assets/models/depot_layout.json').readAsStringSync());

VehicleSnapshot snap(TripPhase? phase, double progress, {int slot = 0, int? dock, int? lane, int? queue}) =>
    VehicleSnapshot(
      vehicleId: 1,
      activity: VehicleActivity.inDepot,
      slotIndex: slot,
      phase: phase,
      phaseProgress: progress,
      dock: dock,
      gateLane: lane,
      queuePosition: queue,
    );

void expectAt(FloorPose? p, FloorPoint at) {
  expect(p, isNotNull);
  expect(p!.x, closeTo(at.x, 1e-6));
  expect(p.z, closeTo(at.z, 1e-6));
}

double angleDiff(double a, double b) {
  final d = (a - b) % (2 * math.pi);
  return math.min(d, 2 * math.pi - d);
}

void main() {
  final layout = loadLayout();
  final motion = DepotMotion(layout);
  FloorPose? pose(VehicleSnapshot s, {int dockLevel = 1, int gateLevel = 1}) =>
      motion.pose(s, dockLevel: dockLevel, gateLevel: gateLevel);

  test('layout punya 8 slot, dock & jalur gerbang per level', () {
    expect(layout.slots, hasLength(8));
    expect(layout.docks(3), hasLength(3));
    expect(layout.gateLanes(3), hasLength(2));
    expect(layout.booms(3), hasLength(2));
  });

  test('parkir: maju masuk slot, hidung menjauhi jalur', () {
    final p = pose(snap(null, 0, slot: 1))!;
    expectAt(p, layout.slots[1]);
    expect(angleDiff(p.heading, headingNorth), lessThan(1e-9));
  });

  test('masuk slot berakhir di slot menghadap sama dengan parkir (maju, bukan mundur)', () {
    for (var slot = 0; slot < 8; slot++) {
      final end = pose(snap(TripPhase.toSlot, 1, slot: slot))!;
      expectAt(end, layout.slots[slot]);
      expect(angleDiff(end.heading, headingNorth), lessThan(0.05), reason: 'slot $slot');
    }
  });

  test('ke dock: mundur ke dock sehingga bak menghadap pintu gudang', () {
    for (final level in [1, 2, 3]) {
      for (var d = 0; d < layout.docks(level).length; d++) {
        final end = pose(snap(TripPhase.toDock, 1, dock: d), dockLevel: level)!;
        expectAt(end, layout.docks(level)[d]);
        expect(angleDiff(end.heading, headingSouth), lessThan(0.3), reason: 'level $level dock $d');
      }
    }
    expect(pose(snap(TripPhase.loading, 0.5))!.heading, headingSouth);
  });

  test('lewat gerbang: berhenti di depan palang saat pemeriksaan, palang terbuka sebelum lewat', () {
    final atCheck = pose(snap(TripPhase.gateOut, 0.45))!;
    expect(atCheck.z, lessThan(layout.gate.z - 2), reason: 'menunggu di dalam, sebelum palang');
    expect(boomOpenAt(0.2), 0);
    expect(boomOpenAt(0.7), 1);
    expect(boomOpenAt(1.0), 0);
    final gateIn = pose(snap(TripPhase.gateIn, 0.45))!;
    expect(gateIn.z, greaterThan(layout.gate.z + 2), reason: 'menunggu di luar, sebelum palang');
  });

  test('di jalan & di pelanggan tidak terlihat di depot; antrean masuk ada di jalan', () {
    expect(pose(snap(TripPhase.outbound, 0.5)), isNull);
    expect(pose(snap(TripPhase.unloading, 0.5)), isNull);
    expect(pose(snap(TripPhase.inbound, 0.5)), isNull);
    final q0 = pose(snap(TripPhase.waitGateIn, 0, queue: 0))!;
    final q1 = pose(snap(TripPhase.waitGateIn, 0, queue: 1))!;
    expect(q0.z, layout.roadLaneZ);
    expect(q1.x, lessThan(q0.x - 4), reason: 'antrean berbaris ke belakang');
  });

  test('multi-gate: jalur kedua dipakai saat gateLane = 1', () {
    final a = pose(snap(TripPhase.gateIn, 1, lane: 0), gateLevel: 3)!;
    final b = pose(snap(TripPhase.gateIn, 1, lane: 1), gateLevel: 3)!;
    expect(a.x, isNot(closeTo(b.x, 1)));
  });

  test('gerak kontinu: tidak ada lompatan posisi di dalam fase', () {
    for (final phase in [TripPhase.toDock, TripPhase.toGate, TripPhase.gateOut, TripPhase.gateIn, TripPhase.toSlot]) {
      for (final slot in [0, 4, 7]) {
        var prev = pose(snap(phase, 0, slot: slot), dockLevel: 3, gateLevel: 3)!;
        for (var i = 1; i <= 400; i++) {
          final p = pose(snap(phase, i / 400, slot: slot), dockLevel: 3, gateLevel: 3)!;
          expect(math.sqrt(math.pow(p.x - prev.x, 2) + math.pow(p.z - prev.z, 2)), lessThan(1.0),
              reason: '$phase slot $slot @ $i');
          prev = p;
        }
      }
    }
  });
}
