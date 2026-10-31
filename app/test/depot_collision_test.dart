import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sim_core/sim_core.dart';
import 'package:transport_manager/features/depot/depot_paths.dart';

/// Jaminan: kendaraan apa pun, di fase apa pun, di level fasilitas apa pun,
/// tidak menembus bangunan, pagar, lampu, platform, palet, atau properti lain.
/// Rintangan & tapak kendaraan berasal dari generator aset (depot_layout.json).
void main() {
  final layout = DepotLayout.parse(File('assets/models/depot_layout.json').readAsStringSync());
  final motion = DepotMotion(layout);
  const vehicles = ['pickup_open', 'box_car', 'mini_truck', 'engkel_truck', 'container_truck'];
  const slotsPerLevel = {1: 3, 2: 5, 3: 8};
  const samples = 120;

  List<(double, double)> footprint(FloorPose p, (double, double, double, double) b) {
    // Arah maju (konvensi DepotPath) & arah samping.
    final fx = math.cos(p.heading), fz = -math.sin(p.heading);
    final sx = -fz, sz = fx;
    return [
      for (final (lx, lz) in [(b.$1, b.$3), (b.$2, b.$3), (b.$2, b.$4), (b.$1, b.$4)])
        (p.x + fx * lx + sx * lz, p.z + fz * lx + sz * lz),
    ];
  }

  /// SAT: poligon cembung (kendaraan) vs kotak sejajar sumbu (rintangan).
  bool overlaps(List<(double, double)> poly, (double, double, double, double) box) {
    const eps = 1e-6;
    final xs = poly.map((p) => p.$1), zs = poly.map((p) => p.$2);
    if (xs.reduce(math.max) <= box.$1 + eps || xs.reduce(math.min) >= box.$3 - eps) return false;
    if (zs.reduce(math.max) <= box.$2 + eps || zs.reduce(math.min) >= box.$4 - eps) return false;
    final corners = [(box.$1, box.$2), (box.$3, box.$2), (box.$3, box.$4), (box.$1, box.$4)];
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      final ax = -(b.$2 - a.$2), az = b.$1 - a.$1;
      double proj((double, double) p) => p.$1 * ax + p.$2 * az;
      final pv = poly.map(proj), cv = corners.map(proj);
      if (pv.reduce(math.max) <= cv.reduce(math.min) + eps || cv.reduce(math.max) <= pv.reduce(math.min) + eps) {
        return false;
      }
    }
    return true;
  }

  String? hit(List<(double, double)> poly, Map<String, List<(double, double, double, double)>> obstacles) {
    for (final e in obstacles.entries) {
      for (final box in e.value) {
        if (overlaps(poly, box)) return '${e.key} $box';
      }
    }
    return null;
  }

  VehicleSnapshot snap(TripPhase? phase, double p, {required int slot, int? dock, int? lane, int? queue}) =>
      VehicleSnapshot(
        vehicleId: 1,
        activity: VehicleActivity.inDepot,
        slotIndex: slot,
        phase: phase,
        phaseProgress: p,
        dock: dock,
        gateLane: lane,
        queuePosition: queue,
      );

  for (final visual in vehicles) {
    test('$visual tidak menabrak properti apa pun', () {
      final bounds = layout.vehicleBounds(visual);
      final failures = <String>[];
      for (final dockLevel in [1, 2, 3]) {
        for (final gateLevel in [1, 2, 3]) {
          for (final parkingLevel in [1, 2, 3]) {
            // Gudang & kantor: uji terhadap semua level sekaligus (paling ketat).
            final obstacles = {
              'base': layout.obstacles('base'),
              'props': layout.obstacles('props'),
              'parking_$parkingLevel': layout.obstacles('parking_$parkingLevel'),
              'gate_$gateLevel': layout.obstacles('gate_$gateLevel'),
              'dock_$dockLevel': layout.obstacles('dock_$dockLevel'),
              for (final l in [1, 2, 3]) 'warehouse_$l': layout.obstacles('warehouse_$l'),
              for (final l in [1, 2, 3]) 'office_$l': layout.obstacles('office_$l'),
              for (final l in [1, 2, 3]) 'workshop_$l': layout.obstacles('workshop_$l'),
            };
            final docks = layout.docks(dockLevel).length;
            final lanes = layout.gateLanes(gateLevel).length;
            for (var slot = 0; slot < slotsPerLevel[parkingLevel]!; slot++) {
              void check(TripPhase? phase, {int? dock, int? lane, int? queue, int outQueue = 0}) {
                for (var i = 0; i <= samples; i++) {
                  final pose = motion.pose(
                    snap(phase, i / samples, slot: slot, dock: dock, lane: lane, queue: queue),
                    dockLevel: dockLevel,
                    gateLevel: gateLevel,
                    outQueueAhead: outQueue,
                  );
                  if (pose == null) return;
                  final h = hit(footprint(pose, bounds), obstacles);
                  if (h != null) {
                    failures.add('dock L$dockLevel gate L$gateLevel parkir L$parkingLevel slot $slot '
                        '${phase?.name ?? 'parkir'} dock=$dock jalur=$lane antre=$queue @${i / samples}: $h');
                    return;
                  }
                  if (phase == null || phase.waiting || phase == TripPhase.loading) return;
                }
              }

              check(null);
              for (var d = 0; d < docks; d++) {
                check(TripPhase.toDock, dock: d);
                check(TripPhase.loading, dock: d);
                for (var q = 0; q < 2; q++) {
                  check(TripPhase.toGate, dock: d, outQueue: q);
                }
              }
              for (var q = 0; q < 2; q++) {
                check(TripPhase.waitGateOut, queue: q);
              }
              for (var q = 0; q < 3; q++) {
                check(TripPhase.waitGateIn, queue: q);
              }
              for (var l = 0; l < lanes; l++) {
                check(TripPhase.gateOut, lane: l);
                check(TripPhase.gateIn, lane: l);
                check(TripPhase.toSlot, lane: l);
              }
            }
          }
        }
      }
      expect(failures, isEmpty, reason: failures.take(15).join('\n'));
    });
  }

  test('penanda konstruksi tidak berada di jalur kendaraan', () {
    final pickup = layout.vehicleBounds('box_car');
    final marker = layout.obstacles('construction').single;
    for (final type in FacilityType.values) {
      final a = layout.anchor(type);
      final box = (a.x + marker.$1, a.z + marker.$2, a.x + marker.$3, a.z + marker.$4);
      for (final phase in [TripPhase.toDock, TripPhase.toGate, TripPhase.gateOut, TripPhase.gateIn, TripPhase.toSlot]) {
        for (var slot = 0; slot < 8; slot++) {
          for (var i = 0; i <= samples; i++) {
            final pose = motion.pose(snap(phase, i / samples, slot: slot, dock: 0, lane: 0), dockLevel: 3, gateLevel: 1)!;
            expect(hit(footprint(pose, pickup), {'konstruksi ${type.id}': [box]}), isNull,
                reason: '${phase.name} slot $slot @${i / samples}');
          }
        }
      }
    }
  });
}
