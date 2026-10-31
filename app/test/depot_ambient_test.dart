import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sim_core/sim_core.dart';
import 'package:transport_manager/features/depot/depot_ambient.dart';
import 'package:transport_manager/features/depot/depot_paths.dart';

/// Depot hidup: orang tidak menembus bangunan/properti dan tidak berdiri di
/// lintasan kendaraan.
void main() {
  final layout = DepotLayout.parse(File('assets/models/depot_layout.json').readAsStringSync());
  final motion = DepotMotion(layout);
  const person = 0.3;

  final obstacles = <String, List<(double, double, double, double)>>{
    for (final m in [
      'base',
      'props',
      for (final l in [1, 2, 3]) ...['gate_$l', 'office_$l', 'workshop_$l', 'warehouse_$l', 'parking_$l', 'dock_$l'],
    ])
      m: layout.obstacles(m),
  };

  String? blocked(FloorPoint p) {
    for (final e in obstacles.entries) {
      for (final b in e.value) {
        if (p.x > b.$1 - person && p.x < b.$3 + person && p.z > b.$2 - person && p.z < b.$4 + person) {
          return '${e.key} $b';
        }
      }
    }
    return null;
  }

  test('jalur patroli satpam bebas rintangan', () {
    for (var t = 0.0; t < 400; t += 0.25) {
      final p = DepotAmbient.guardPatrol(t);
      expect(blocked((x: p.x, z: p.z)), isNull, reason: 't=$t (${p.x}, ${p.z})');
    }
  });

  test('tempat istirahat sopir & siaga mekanik bebas rintangan', () {
    for (final p in [...DepotAmbient.restSpots, ...DepotAmbient.mechanicSpots]) {
      expect(blocked(p), isNull, reason: '$p');
    }
  });

  test('patroli & tempat istirahat tidak di lintasan kendaraan', () {
    // Ambil sampel lintasan pikap di semua fase depot & semua tier.
    final bounds = layout.vehicleBounds('pickup_box_1t');
    final spots = <FloorPoint>[
      ...DepotAmbient.restSpots,
      for (var t = 0.0; t < 200; t += 0.5) (x: DepotAmbient.guardPatrol(t).x, z: DepotAmbient.guardPatrol(t).z),
    ];
    for (final tier in [1, 2, 3]) {
      for (final phase in [
        TripPhase.toDock,
        TripPhase.toGate,
        TripPhase.toGateDirect,
        TripPhase.gateIn,
        TripPhase.toSlot,
        TripPhase.dockToSlot,
      ]) {
        for (var i = 0; i <= 60; i++) {
          final pose = motion.pose(
            VehicleSnapshot(
              vehicleId: 1,
              activity: VehicleActivity.inDepot,
              slotIndex: 0,
              phase: phase,
              phaseProgress: i / 60,
              dock: 0,
              gateLane: 0,
            ),
            dockLevel: tier,
            gateLevel: tier,
          )!;
          final reach = math.max(bounds.$2.abs(), bounds.$1.abs()) + person;
          for (final s in spots) {
            final d = math.sqrt(math.pow(s.x - pose.x, 2) + math.pow(s.z - pose.z, 2));
            expect(d, greaterThan(reach), reason: '${phase.name} tier $tier @${i / 60} dekat $s');
          }
        }
      }
    }
  });

  test('staf merapikan stok tetap di platform dock', () {
    for (final tier in [1, 2, 3]) {
      final docks = layout.docks(tier);
      for (var i = 0; i < 6; i++) {
        for (var t = 0.0; t < 30; t += 0.5) {
          final dock = docks[i % docks.length];
          final p = DepotAmbient.stockKeeper(i, t, dock).pose;
          expect((p.x - dock.x).abs(), lessThanOrEqualTo(1.6 + 1e-9));
          expect(p.z, inInclusiveRange(-5.05, -3.2));
        }
      }
    }
  });

  test('jam kerja 06.00–19.00', () {
    // Detik 0 = Hari 1 pukul 06.00.
    expect(DepotAmbient.isWorkHour(0), isTrue);
    expect(DepotAmbient.isWorkHour(12 * 3600), isTrue);
    expect(DepotAmbient.isWorkHour(13 * 3600), isFalse);
    expect(DepotAmbient.isWorkHour(24 * 3600), isTrue);
  });
}
