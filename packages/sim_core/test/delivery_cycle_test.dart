import 'dart:convert';

import 'package:sim_core/sim_core.dart';
import 'package:test/test.dart';

import 'support/test_world.dart';

void main() {
  test('konten bawaan termuat dan valid', () {
    final content = loadContent();
    expect(content.vehicleModels['pickup_box_1t']!.vehicleClass, VehicleClass.pickupBox);
    expect(content.cargoTypes, isNotEmpty);
    expect(content.economy.startingCashIdr, greaterThan(0));
  });

  test('game baru: 1 depot 3 slot, 1 kendaraan di slot 0, 1 sopir, modal awal', () {
    final world = newWorld();
    final depot = world.depots.values.single;
    expect(depot.parkingSlots, 3);
    expect(depot.slots, [vehicleId, null, null]);
    expect(world.vehicles[vehicleId]!.isAvailable, isTrue);
    expect(world.drivers[driverId]!.isAvailable, isTrue);
    expect(world.cashIdr, world.content.economy.startingCashIdr);
    expect(world.vehicleSnapshot(vehicleId).activity, VehicleActivity.parked);
  });

  group('satu siklus pengiriman penuh', () {
    late SimWorld world;
    late Contract contract;
    late DispatchQuote quote;
    late int startCash;

    setUp(() {
      world = newWorld();
      contract = world.offerStoreContract(depotId: 1, capacityKg: 950)!;
      final check = world.check(contractId: contract.id, vehicleId: vehicleId, driverId: driverId);
      expect(check.problems, isEmpty);
      quote = check.nonToll!;
      startCash = world.cashIdr;
      world.dispatch(
          contractId: contract.id, vehicleId: vehicleId, driverId: driverId, mode: RouteMode.nonToll);
    });

    test('hasil akhir persis sama dengan estimasi sebelum dispatch', () {
      world.advanceTo(quote.completionEta);

      expect(contract.status, ContractStatus.delivered);
      expect(contract.deliveredAt, quote.deliveryEta);
      expect(contract.settledIdr, quote.revenueIdr);
      expect(world.cashIdr, startCash + quote.profitIdr);
      expect(world.vehicles[vehicleId]!.odometerM, quote.distanceM);
      expect(world.vehicles[vehicleId]!.isAvailable, isTrue);
      expect(world.drivers[driverId]!.isAvailable, isTrue);
      expect(world.drivers[driverId]!.drivingSeconds, quote.outboundS + quote.inboundS);
      expect(world.vehicleSnapshot(vehicleId).activity, VehicleActivity.parked);
      expect(world.queue.isEmpty, isTrue);
    });

    test('kas tidak berubah tanpa entri buku besar', () {
      world.advanceTo(quote.completionEta);
      final sum = world.ledger.entries.fold(0, (s, e) => s + e.amountIdr);
      expect(world.cashIdr, sum);
      expect(world.ledger.total(LedgerAccount.contractRevenue), quote.revenueIdr);
      expect(world.ledger.total(LedgerAccount.fuel), -quote.fuelIdr);
    });

    test('urutan log kejadian', () {
      world.advanceTo(quote.completionEta);
      expect(world.log.map((e) => e.kind), [
        WorldLogKind.contractOffered,
        WorldLogKind.dispatched,
        WorldLogKind.departedDepot,
        WorldLogKind.delivered,
        WorldLogKind.returnedToDepot,
        WorldLogKind.tripCompleted,
      ]);
    });

    test('kendaraan melewati setiap fase, tidak muncul/hilang tiba-tiba', () {
      final seen = <TripPhase>[];
      final trip = world.trips.values.single;
      while (trip.isActive) {
        seen.add(trip.phase);
        world.advanceTo(trip.phaseEnd);
      }
      expect(seen, TripPhase.values.where((p) => p != TripPhase.completed).toList());
    });

    test('posisi di jalan mengikuti rute: berangkat dari depot, tiba di tujuan', () {
      final trip = world.trips.values.single;
      while (trip.phase != TripPhase.outbound) {
        world.advanceTo(trip.phaseEnd);
      }
      final depotPos = world.graph.node(world.depots[1]!.roadNode);
      final destPos = world.graph.node(contract.destinationNode);

      final start = world.vehicleSnapshot(vehicleId, at: trip.phaseStart);
      expect(start.activity, VehicleActivity.onRoad);
      expect(haversineMeters(start.pose!.position, depotPos), lessThan(1));

      final mid = world.vehicleSnapshot(vehicleId, at: (trip.phaseStart + trip.phaseEnd) ~/ 2);
      expect(mid.phaseProgress, closeTo(0.5, 0.01));
      expect(haversineMeters(mid.pose!.position, depotPos), greaterThan(1));

      final end = world.vehicleSnapshot(vehicleId, at: trip.phaseEnd);
      expect(haversineMeters(end.pose!.position, destPos), lessThan(1));

      world.advanceTo(trip.phaseEnd);
      expect(world.vehicleSnapshot(vehicleId).activity, VehicleActivity.atDestination);
    });

    test('kendaraan & sopir yang sedang bertugas tidak bisa di-dispatch lagi', () {
      final other = world.offerStoreContract(depotId: 1, capacityKg: 950)!;
      final check = world.check(contractId: other.id, vehicleId: vehicleId, driverId: driverId);
      expect(check.problems, containsAll([DispatchProblem.vehicleBusy, DispatchProblem.driverBusy]));
      expect(
        () => world.dispatch(
            contractId: other.id, vehicleId: vehicleId, driverId: driverId, mode: RouteMode.toll),
        throwsA(isA<DispatchException>()),
      );
    });
  });

  group('aturan dispatch', () {
    test('pikap tidak boleh mengambil kontrak antarkota', () {
      final world = newWorld();
      final c = addContract(world, destinationNode: 20, scope: DeliveryScope.intercity);
      final check = world.check(contractId: c.id, vehicleId: vehicleId, driverId: driverId);
      expect(check.problems, [DispatchProblem.vehicleClassTooSmall]);
    });

    test('muatan melebihi kapasitas ditolak', () {
      final world = newWorld();
      final c = addContract(world, destinationNode: 20, weightKg: 2000);
      final check = world.check(contractId: c.id, vehicleId: vehicleId, driverId: driverId);
      expect(check.problems, [DispatchProblem.overCapacity]);
    });

    test('tol vs non-tol: tol lebih cepat tetapi berbayar', () {
      final world = newWorld();
      final c = addContract(world, destinationNode: 7); // ujung baris 0, sejajar ruas tol
      final check = world.check(contractId: c.id, vehicleId: vehicleId, driverId: driverId);
      final toll = check.viaToll!, free = check.nonToll!;
      expect(toll.outboundRoute.usesToll, isTrue);
      expect(toll.tollIdr, greaterThan(0));
      expect(free.tollIdr, 0);
      expect(toll.outboundS, lessThan(free.outboundS));
    });

    test('terlambat dikenai penalti per jam, tidak pernah negatif', () {
      final world = newWorld();
      final c = addContract(world, destinationNode: 63, allowedS: 60, payIdr: 100000);
      final quote = world.check(contractId: c.id, vehicleId: vehicleId, driverId: driverId).nonToll!;
      expect(quote.onTime, isFalse);
      expect(quote.revenueIdr, lessThan(c.payIdr));
      expect(c.settlementAt(1 << 40, deadline: 0), 0);
    });
  });

  group('determinisme & save', () {
    test('kontrak yang ditawarkan sama untuk seed yang sama', () {
      final a = newWorld(seed: 7).offerStoreContract(depotId: 1, capacityKg: 950)!;
      final b = newWorld(seed: 7).offerStoreContract(depotId: 1, capacityKg: 950)!;
      expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
    });

    SimWorld dispatched() {
      final world = newWorld();
      final c = world.offerStoreContract(depotId: 1, capacityKg: 950)!;
      world.dispatch(contractId: c.id, vehicleId: vehicleId, driverId: driverId, mode: RouteMode.toll);
      return world;
    }

    test('satu lompatan waktu panjang == banyak langkah pendek', () {
      final a = dispatched(), b = dispatched();
      const end = 24 * 3600;
      a.advanceTo(end);
      for (var t = 0; t <= end; t += 37) {
        b.advanceTo(t);
      }
      b.advanceTo(end);
      expect(jsonEncode(b.toJson()), jsonEncode(a.toJson()));
    });

    test('save di tengah perjalanan lalu load menghasilkan akhir yang sama', () {
      final original = dispatched();
      final trip = original.trips.values.single;
      while (trip.phase != TripPhase.outbound) {
        original.advanceTo(trip.phaseEnd);
      }
      original.advanceTo(trip.phaseStart + 100);

      final saved = jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>;
      final loaded = SimWorld.fromJson(saved, graph: original.graph, content: original.content);
      expect(jsonEncode(loaded.toJson()), jsonEncode(original.toJson()));
      expect(loaded.vehicleSnapshot(vehicleId).pose!.position,
          original.vehicleSnapshot(vehicleId).pose!.position);

      original.advanceTo(24 * 3600);
      loaded.advanceTo(24 * 3600);
      expect(jsonEncode(loaded.toJson()), jsonEncode(original.toJson()));
      expect(loaded.vehicles[vehicleId]!.isAvailable, isTrue);
    });
  });
}
