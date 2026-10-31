import 'dart:convert';

import 'package:sim_core/sim_core.dart';
import 'package:test/test.dart';

import 'support/test_world.dart';

/// Tambah modal (uji) lewat buku besar agar pembelian bisa dilakukan.
void addCash(SimWorld w, int idr) =>
    w.ledger.post(LedgerEntry(time: w.now, account: LedgerAccount.openingBalance, amountIdr: idr, ref: 'test'));

/// Dunia dengan [count] kendaraan + sopir siap jalan, masing-masing satu kontrak.
({SimWorld world, List<int> vehicles, List<int> drivers, List<Contract> contracts}) fleet(int count) {
  final w = newWorld();
  addCash(w, 2000000000);
  final vehicleIds = [vehicleId];
  final driverIds = [driverId];
  for (var i = 1; i < count; i++) {
    if (w.depots[1]!.firstFreeSlot == null) break;
    vehicleIds.add(w.buyVehicle(1, 'pickup_box_1t').id);
    w.hire(1, EmployeeRole.driver);
    driverIds.add(w.drivers.keys.last);
  }
  final contracts = [for (var i = 0; i < vehicleIds.length; i++) addContract(w, destinationNode: 20 + i)];
  return (world: w, vehicles: vehicleIds, drivers: driverIds, contracts: contracts);
}

void dispatchAll(SimWorld w, List<int> vehicles, List<int> drivers, List<Contract> contracts) {
  for (var i = 0; i < vehicles.length; i++) {
    w.dispatch(contractId: contracts[i].id, vehicleId: vehicles[i], driverId: drivers[i], mode: RouteMode.nonToll);
  }
}

Trip tripOf(SimWorld w, int vehicle) => w.trips.values.lastWhere((t) => t.vehicleId == vehicle);

/// Waktu (detik game) tiap trip memasuki fase [phase] dalam [within] detik ke depan.
Map<int, int> phaseStarts(SimWorld w, TripPhase phase, int within) {
  final until = w.now + within;
  final starts = <int, int>{};
  while (w.now < until) {
    for (final t in w.trips.values) {
      if (t.phase == phase) starts.putIfAbsent(t.id, () => t.phaseStart);
    }
    final next = w.queue.peek;
    if (next == null || next.time > until) break;
    w.advanceTo(next.time);
  }
  for (final t in w.trips.values) {
    if (t.phase == phase) starts.putIfAbsent(t.id, () => t.phaseStart);
  }
  return starts;
}

void main() {
  test('katalog fasilitas: game baru semua level 1, statistik dari data', () {
    final w = newWorld();
    final depot = w.depots[1]!;
    for (final t in FacilityType.values) {
      expect(depot.level(t), 1);
    }
    expect(w.dockCount(depot), 1);
    expect(w.gateLaneCount(depot), 1);
    expect(depot.parkingSlots, w.content.facilities[FacilityType.parking].level(1).intStat('slots'));
  });

  group('upgrade fasilitas', () {
    test('bayar, bangun selama waktu konstruksi, lalu level naik', () {
      final w = newWorld();
      final next = w.content.facilities[FacilityType.parking].level(2);
      final cash = w.cashIdr;
      final c = w.startUpgrade(1, FacilityType.parking);
      expect(w.cashIdr, cash - next.costIdr);
      expect(c.finishAt - c.startedAt, next.buildHours * 3600);
      expect(w.upgradeProblems(1, FacilityType.gate), contains(UpgradeProblem.constructionBusy));

      w.advanceTo(c.finishAt - 1);
      expect(w.depots[1]!.level(FacilityType.parking), 1);
      w.advanceTo(c.finishAt);
      expect(w.depots[1]!.level(FacilityType.parking), 2);
      expect(w.depots[1]!.parkingSlots, next.intStat('slots'));
      expect(w.depots[1]!.construction, isNull);
      expect(w.log.map((e) => e.kind), containsAllInOrder([WorldLogKind.upgradeStarted, WorldLogKind.upgradeFinished]));
    });

    test('kas kurang & level maksimum ditolak', () {
      final w = newWorld();
      w.ledger.post(LedgerEntry(time: 0, account: LedgerAccount.wages, amountIdr: -w.cashIdr, ref: 'test'));
      expect(w.upgradeProblems(1, FacilityType.gate), [UpgradeProblem.insufficientCash]);
      expect(() => w.startUpgrade(1, FacilityType.gate), throwsA(isA<CommandException>()));
      addCash(w, 1000000000);
      for (var i = 0; i < 2; i++) {
        w.advanceTo(w.startUpgrade(1, FacilityType.gate).finishAt);
      }
      expect(w.upgradeProblems(1, FacilityType.gate), [UpgradeProblem.maxLevel]);
    });
  });

  group('antrean memengaruhi waktu', () {
    test('1 dock: kendaraan kedua menunggu sampai dock kosong', () {
      final f = fleet(2);
      dispatchAll(f.world, f.vehicles, f.drivers, f.contracts);
      final first = tripOf(f.world, f.vehicles[0]), second = tripOf(f.world, f.vehicles[1]);
      expect(first.phase, TripPhase.toDock);
      expect(second.phase, TripPhase.waitDock);
      expect(f.world.vehicleSnapshot(f.vehicles[1]).queuePosition, 0);

      final loadingStarts = phaseStarts(f.world, TripPhase.toDock, 6 * 3600);
      final firstLeavesDock = first.startedAt +
          f.world.content.depotOps.slotToDockS +
          f.world.loadingS(f.world.depots[1]!, f.contracts[0].weightKg);
      expect(loadingStarts[second.id], firstLeavesDock);
    });

    test('upgrade ke 2 dock menghapus antrean dock', () {
      final f = fleet(2);
      f.world.advanceTo(f.world.startUpgrade(1, FacilityType.loadingDock).finishAt);
      dispatchAll(f.world, f.vehicles, f.drivers, f.contracts);
      expect(tripOf(f.world, f.vehicles[0]).phase, TripPhase.toDock);
      expect(tripOf(f.world, f.vehicles[1]).phase, TripPhase.toDock);
      expect({tripOf(f.world, f.vehicles[0]).dock, tripOf(f.world, f.vehicles[1]).dock}, {0, 1});
    });

    test('gerbang 1 jalur: kendaraan lewat gerbang bergantian', () {
      final f = fleet(2);
      f.world.advanceTo(f.world.startUpgrade(1, FacilityType.loadingDock).finishAt);
      dispatchAll(f.world, f.vehicles, f.drivers, f.contracts);
      final gateOut = phaseStarts(f.world, TripPhase.gateOut, 6 * 3600);
      final times = gateOut.values.toList()..sort();
      expect(times, hasLength(2));
      expect(times[1] - times[0], greaterThanOrEqualTo(f.world.gatePassS(f.world.depots[1]!)));
    });

    test('gerbang otomatis lebih cepat dari gerbang manual', () {
      final w = newWorld();
      final manual = w.gatePassS(w.depots[1]!);
      w.advanceTo(w.startUpgrade(1, FacilityType.gate).finishAt);
      expect(w.gatePassS(w.depots[1]!), lessThan(manual));
    });
  });

  group('pekerja', () {
    test('staf gudang mempercepat muat sampai batas efektif', () {
      final w = newWorld();
      final depot = w.depots[1]!;
      final times = <int>[w.loadingS(depot, 800)];
      for (var i = 0; i < 3; i++) {
        w.hire(1, EmployeeRole.warehouseStaff);
        times.add(w.loadingS(depot, 800));
      }
      expect(times[1], lessThan(times[0]), reason: 'tanpa staf sopir memuat sendiri');
      expect(times[2], lessThan(times[1]));
      expect(times[3], lessThan(times[2]));
      final cfg = w.content.employees;
      expect(cfg.loadingFactor(cfg.loadingStaffMaxEffective + 1), cfg.loadingFactor(cfg.loadingStaffMaxEffective),
          reason: 'staf di atas batas efektif tidak menambah kecepatan');
    });

    test('kapasitas kantor membatasi jumlah karyawan', () {
      final w = newWorld();
      final max = w.staffMax(w.depots[1]!);
      while (w.hireProblems(1).isEmpty) {
        w.hire(1, EmployeeRole.warehouseStaff);
      }
      expect(w.staffCount(w.depots[1]!), max);
      expect(() => w.hire(1, EmployeeRole.driver), throwsA(isA<CommandException>()));
    });

    test('gaji harian dibayar tiap pergantian hari', () {
      final w = newWorld();
      w.hire(1, EmployeeRole.warehouseStaff);
      final wage = w.content.employees.dailyWageIdr;
      final perDay = wage[EmployeeRole.driver]! + wage[EmployeeRole.warehouseStaff]!;
      w.advanceTo(3 * SimWorld.daySeconds);
      expect(w.ledger.total(LedgerAccount.wages), -3 * perDay);
      // Hari 2 pukul 00.00 = detik 18 jam.
      expect(w.ledger.entries.firstWhere((e) => e.account == LedgerAccount.wages).time, 18 * 3600);
    });
  });

  test('beli kendaraan menempati slot kosong; parkir penuh ditolak', () {
    final w = newWorld();
    addCash(w, 2000000000);
    w.buyVehicle(1, 'pickup_box_1t');
    w.buyVehicle(1, 'mini_truck_2t');
    expect(w.depots[1]!.slots.whereType<int>(), hasLength(3));
    expect(w.purchaseProblems(1, 'pickup_box_1t'), [PurchaseProblem.noFreeSlot]);
    expect(w.ledger.total(LedgerAccount.vehiclePurchase), -(215000000 + 290000000));
  });

  group('save', () {
    test('save di tengah antrean lalu load menghasilkan akhir yang sama', () {
      final f = fleet(3);
      dispatchAll(f.world, f.vehicles, f.drivers, f.contracts);
      f.world.advanceTo(30 * 60);
      expect(f.world.trips.values.where((t) => t.phase.waiting), isNotEmpty);

      final loaded = SimWorld.fromJson(
        jsonDecode(jsonEncode(f.world.toJson())) as Map<String, dynamic>,
        graph: f.world.graph,
        content: f.world.content,
      );
      f.world.advanceTo(2 * SimWorld.daySeconds);
      loaded.advanceTo(2 * SimWorld.daySeconds);
      expect(jsonEncode(loaded.toJson()), jsonEncode(f.world.toJson()));
      expect(loaded.trips.values.every((t) => !t.isActive), isTrue);
    });

    test('save format 1 (Tahap 2b) dimuat: fasilitas level 1 & gaji dijadwalkan', () {
      final w = newWorld();
      final c = addContract(w, destinationNode: 20);
      w.dispatch(contractId: c.id, vehicleId: vehicleId, driverId: driverId, mode: RouteMode.nonToll);
      final json = jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>;
      json['format'] = 1;
      (json['events'] as List).removeWhere((e) => (e as Map)['type'] == PayrollDue.typeName);
      for (final d in (json['depots'] as List).cast<Map<String, dynamic>>()) {
        d.remove('levels');
        d.remove('construction');
        d.remove('warehouse_staff');
      }
      final loaded = SimWorld.fromJson(json, graph: w.graph, content: w.content);
      expect(loaded.depots[1]!.level(FacilityType.gate), 1);
      expect(loaded.queue.snapshot().where((e) => e.event is PayrollDue), hasLength(1));
      loaded.advanceTo(SimWorld.daySeconds);
      expect(loaded.contracts[c.id]!.status, ContractStatus.delivered);
      expect(loaded.toJson()['format'], SimWorld.saveFormat);
    });
  });
}
