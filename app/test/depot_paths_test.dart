import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sim_core/sim_core.dart';
import 'package:transport_manager/features/depot/depot_paths.dart';

const _layout = '''
{"outside": [0, 24], "gate": [0, 15], "lane_z": 6, "dock_stop": [11, -1.8],
 "parking_slots": [[-12, -4], [-6, -4], [0, -4]]}
''';

void expectAt(FloorPose p, double x, double z) {
  expect(p.x, closeTo(x, 1e-9));
  expect(p.z, closeTo(z, 1e-9));
}

void main() {
  final motion = DepotMotion(DepotLayout.parse(_layout));

  test('parkir menghadap jalur', () {
    final p = motion.pose(1, null, 0)!;
    expectAt(p, -6, -4);
    expect(p.heading, DepotMotion.parkedHeading);
  });

  test('ke dock: mulai di slot, berakhir di dock', () {
    final a = motion.pose(0, TripPhase.toDock, 0)!;
    final b = motion.pose(0, TripPhase.toDock, 1)!;
    expectAt(a, -12, -4);
    expectAt(b, 11, -1.8);
  });

  test('keluar gerbang lalu tidak terlihat selama di jalan', () {
    final end = motion.pose(0, TripPhase.toGate, 1)!;
    expectAt(end, 0, 24);
    expect(motion.pose(0, TripPhase.outbound, 0.5), isNull);
    expect(motion.pose(0, TripPhase.unloading, 0.5), isNull);
    expect(motion.pose(0, TripPhase.inbound, 0.5), isNull);
  });

  test('masuk slot mundur sehingga kembali menghadap jalur', () {
    final end = motion.pose(2, TripPhase.toSlot, 1)!;
    expectAt(end, 0, -4);
    final diff = ((end.heading - DepotMotion.parkedHeading) % (2 * math.pi));
    expect(math.min(diff, 2 * math.pi - diff), closeTo(0, 1e-9));
  });

  test('gerak kontinu: tidak ada lompatan posisi di dalam fase', () {
    for (final phase in [TripPhase.toDock, TripPhase.toGate, TripPhase.gateIn, TripPhase.toSlot]) {
      var prev = motion.pose(0, phase, 0)!;
      for (var i = 1; i <= 200; i++) {
        final p = motion.pose(0, phase, i / 200)!;
        expect(math.sqrt(math.pow(p.x - prev.x, 2) + math.pow(p.z - prev.z, 2)), lessThan(1.0), reason: '$phase @ $i');
        prev = p;
      }
    }
  });
}
