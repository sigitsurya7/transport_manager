import 'dart:convert';

import 'package:sim_core/sim_core.dart';
import 'package:test/test.dart';

import 'depot_simulation_test.dart' show addCash;
import 'support/test_world.dart';

/// Jalankan trip sampai selesai sambil mencatat fase yang dilewati.
List<TripPhase> runToEnd(SimWorld w, Trip trip) {
  final seen = <TripPhase>[];
  var guard = 0;
  while (trip.isActive && guard++ < 200) {
    seen.add(trip.phase);
    w.advanceTo(trip.phase.waiting ? w.now + 60 : trip.phaseEnd);
  }
  return seen;
}

Supplier supplierSelling(SimWorld w, String cargoId) =>
    w.suppliersFor(1).firstWhere((s) => s.sells.contains(cargoId));

/// Pesanan toko manual: [lines] dari supplier yang menjual barang pertama.
Contract storeOrder(SimWorld w, List<OrderLine> lines, {int destinationNode = 20}) {
  final supplier = supplierSelling(w, lines.first.cargoId);
  final id = 5000 + w.contracts.length;
  final goods = lines.fold(0, (s, l) => s + l.units * w.content.economy.storePrice(w.content.cargoTypes[l.cargoId]!.priceIdr));
  return w.contracts[id] = Contract(
    id: id,
    kind: ContractKind.storeOrder,
    customer: 'Toko Indojuni',
    cargoId: lines.first.cargoId,
    units: lines.first.units,
    lines: lines,
    weightKg: w.linesWeightKg(lines),
    pickupNode: supplier.node,
    pickupName: supplier.name,
    supplierId: supplier.id,
    destinationNode: destinationNode,
    destinationName: 'Toko Indojuni',
    scope: DeliveryScope.storeToStore,
    goodsValueIdr: goods,
    payIdr: goods + 300000,
    offeredAt: w.now,
    allowedS: 12 * 3600,
    latePenaltyPerHourIdr: 30000,
  );
}

void main() {
  group('supplier', () {
    test('game baru: supplier dari konten di kota depot, deterministik', () {
      final a = newWorld(), b = newWorld();
      expect(a.suppliersFor(1), hasLength(a.content.suppliers.length));
      expect(jsonEncode([for (final s in a.suppliers.values) s.toJson()]),
          jsonEncode([for (final s in b.suppliers.values) s.toJson()]));
      for (final s in a.suppliers.values) {
        expect(s.node, isNot(a.depots[1]!.roadNode));
        expect(s.cityId, 'jakarta');
      }
    });

    test('save lama tanpa supplier dibuatkan saat dimuat', () {
      final w = newWorld();
      final json = jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>..remove('suppliers');
      final loaded = SimWorld.fromJson(json, graph: w.graph, content: w.content);
      expect(jsonEncode([for (final s in loaded.suppliers.values) s.toJson()]),
          jsonEncode([for (final s in w.suppliers.values) s.toJson()]));
    });
  });

  group('jasa angkut: depot → supplier → toko → depot', () {
    late SimWorld w;
    late Contract c;
    late DispatchQuote quote;
    late int cash;

    setUp(() {
      w = newWorld();
      c = w.offerHaulContract(depotId: 1, capacityKg: 950)!;
      final check = w.check(contractId: c.id, vehicleId: vehicleId, driverId: driverId);
      expect(check.problems, isEmpty);
      quote = check.viaToll!;
      cash = w.cashIdr;
      w.dispatch(contractId: c.id, vehicleId: vehicleId, driverId: driverId, mode: RouteMode.toll);
    });

    test('tidak memuat di depot; menjemput di supplier', () {
      final trip = w.trips.values.single;
      expect(c.kind, ContractKind.haul);
      expect(c.pickupNode, isNotNull);
      expect(trip.plan, TripPlans.pickup);
      expect(quote.pickupRoute, isNotNull);
      final seen = runToEnd(w, trip);
      expect(seen, trip.plan.where((p) => p != TripPhase.completed && !p.waiting).toList());
      expect(seen, isNot(contains(TripPhase.loading)));
      expect(seen, isNot(contains(TripPhase.toDock)));
    });

    test('hasil akhir sama dengan estimasi; tidak ada pembelian barang', () {
      w.advanceTo(quote.completionEta);
      expect(c.status, ContractStatus.delivered);
      expect(c.deliveredAt, quote.deliveryEta);
      expect(w.cashIdr, cash + quote.profitIdr);
      expect(w.ledger.total(LedgerAccount.goodsPurchase), 0);
      expect(w.vehicles[vehicleId]!.odometerM, quote.distanceM);
      expect(w.depots[1]!.stock, isEmpty);
      expect(w.log.map((e) => e.kind), containsAllInOrder([
        WorldLogKind.departedDepot,
        WorldLogKind.pickedUp,
        WorldLogKind.delivered,
        WorldLogKind.returnedToDepot,
      ]));
    });

    test('di supplier: kendaraan tampil di lokasi supplier', () {
      final trip = w.trips.values.single;
      while (trip.phase != TripPhase.pickupLoading) {
        w.advanceTo(trip.phaseEnd);
      }
      final snap = w.vehicleSnapshot(vehicleId);
      expect(snap.activity, VehicleActivity.atDestination);
      expect(haversineMeters(snap.pose!.position, w.graph.node(c.pickupNode!)), lessThan(1));
      final pickupTrack = w.trackForLeg(trip.id, LegKind.pickup);
      expect(haversineMeters(pickupTrack.points.last, w.graph.node(c.pickupNode!)), lessThan(1));
    });
  });

  group('pesanan toko & gudang', () {
    late SimWorld w;
    setUp(() {
      w = newWorld();
      addCash(w, 1000000000);
    });

    test('tanpa stok: semua dibeli di supplier', () {
      final c = storeOrder(w, const [OrderLine('beras_25', 20)]);
      final q = w.check(contractId: c.id, vehicleId: vehicleId, driverId: driverId).viaToll!;
      expect(q.plan, TripPlans.pickup);
      expect(q.purchaseIdr, 20 * w.content.cargoTypes['beras_25']!.priceIdr);
      final cash = w.cashIdr;
      w.dispatch(contractId: c.id, vehicleId: vehicleId, driverId: driverId, mode: RouteMode.toll);
      w.advanceTo(q.completionEta);
      expect(c.status, ContractStatus.delivered);
      expect(w.ledger.total(LedgerAccount.goodsPurchase), -q.purchaseIdr);
      expect(c.settledIdr, c.payIdr);
      expect(w.cashIdr, cash + q.profitIdr);
      expect(q.profitIdr, greaterThan(0), reason: 'harga jual barang di atas harga beli');
    });

    test('stok cukup: muat di dock depot, tanpa ke supplier', () {
      w.depots[1]!.addStock('beras_25', 30);
      final c = storeOrder(w, const [OrderLine('beras_25', 20)]);
      final q = w.check(contractId: c.id, vehicleId: vehicleId, driverId: driverId).viaToll!;
      expect(q.plan, TripPlans.depotLoad);
      expect(q.purchaseIdr, 0);
      expect(q.pickupRoute, isNull);
      expect(q.stockValueIdr, greaterThan(0));
      final trip = w.dispatch(contractId: c.id, vehicleId: vehicleId, driverId: driverId, mode: RouteMode.toll);
      expect(w.depots[1]!.stockOf('beras_25'), 10, reason: 'stok dialokasikan saat dispatch');
      final seen = runToEnd(w, trip);
      expect(seen, contains(TripPhase.loading));
      expect(seen, isNot(contains(TripPhase.pickupLoading)));
      expect(w.ledger.total(LedgerAccount.goodsPurchase), 0);
    });

    test('stok sebagian: muat yang ada, beli sisanya di supplier', () {
      w.depots[1]!.addStock('beras_25', 5);
      final c = storeOrder(w, const [OrderLine('beras_25', 20), OrderLine('minyak_goreng', 10)]);
      final check = w.check(contractId: c.id, vehicleId: vehicleId, driverId: driverId);
      expect(check.problems, isEmpty);
      final q = check.viaToll!;
      expect(q.plan, TripPlans.depotLoadThenPickup);
      expect(q.fulfillment!.fromStock, const [OrderLine('beras_25', 5)]);
      expect(q.fulfillment!.toBuy, const [OrderLine('beras_25', 15), OrderLine('minyak_goreng', 10)]);
      final prices = w.content.cargoTypes;
      expect(q.purchaseIdr, 15 * prices['beras_25']!.priceIdr + 10 * prices['minyak_goreng']!.priceIdr);
      w.dispatch(contractId: c.id, vehicleId: vehicleId, driverId: driverId, mode: RouteMode.toll);
      w.advanceTo(q.completionEta);
      expect(c.status, ContractStatus.delivered);
      expect(w.depots[1]!.stockOf('beras_25'), 0);
      expect(w.ledger.total(LedgerAccount.goodsPurchase), -q.purchaseIdr);
    });

    test('kas kurang untuk membeli barang ditolak', () {
      final c = storeOrder(w, const [OrderLine('beras_25', 30)]);
      w.ledger.post(LedgerEntry(time: w.now, account: LedgerAccount.wages, amountIdr: -w.cashIdr, ref: 'test'));
      expect(w.check(contractId: c.id, vehicleId: vehicleId, driverId: driverId).problems,
          contains(DispatchProblem.insufficientCash));
    });

    test('isi stok: beli grosir di supplier, bongkar di dock ke gudang', () {
      final supplier = supplierSelling(w, 'beras_25');
      final c = w.planRestock(depotId: 1, supplierId: supplier.id, lines: const [OrderLine('beras_25', 30)]);
      final check = w.check(contractId: c.id, vehicleId: vehicleId, driverId: driverId);
      expect(check.problems, isEmpty);
      final q = check.viaToll!;
      expect(q.plan, TripPlans.restock);
      expect(q.outboundRoute, isNull);
      expect(q.revenueIdr, 0);
      expect(q.purchaseIdr, 30 * w.content.economy.restockPrice(w.content.cargoTypes['beras_25']!.priceIdr));
      expect(q.purchaseIdr, lessThan(30 * w.content.cargoTypes['beras_25']!.priceIdr));
      final trip = w.dispatch(contractId: c.id, vehicleId: vehicleId, driverId: driverId, mode: RouteMode.toll);
      expect(w.incomingVolumeM3(w.depots[1]!), closeTo(30 * w.content.cargoTypes['beras_25']!.unitVolumeM3, 1e-9));
      final seen = runToEnd(w, trip);
      expect(seen, containsAllInOrder([TripPhase.pickupLoading, TripPhase.inbound, TripPhase.unloadDock]));
      expect(seen, isNot(contains(TripPhase.outbound)));
      expect(w.depots[1]!.stockOf('beras_25'), 30);
      expect(w.incomingVolumeM3(w.depots[1]!), 0);
      expect(w.ledger.total(LedgerAccount.goodsPurchase), -q.purchaseIdr);
      expect(c.status, ContractStatus.delivered);
      expect(w.vehicles[vehicleId]!.isAvailable, isTrue);
    });

    test('isi stok ditolak bila gudang penuh', () {
      final cap = w.warehouseCapacityM3(w.depots[1]!);
      final vol = w.content.cargoTypes['mi_instan']!.unitVolumeM3;
      w.depots[1]!.addStock('mi_instan', ((cap - 0.5) / vol).floor());
      final supplier = supplierSelling(w, 'beras_25');
      final c = w.planRestock(depotId: 1, supplierId: supplier.id, lines: const [OrderLine('beras_25', 30)]);
      expect(w.check(contractId: c.id, vehicleId: vehicleId, driverId: driverId).problems,
          contains(DispatchProblem.warehouseFull));
      w.discardRestock(c.id);
      expect(w.contracts.containsKey(c.id), isFalse);
    });

    test('tawaran pesanan toko memakai barang gudang dari satu supplier', () {
      for (var i = 0; i < 20; i++) {
        final c = w.offerStoreOrder(depotId: 1, capacityKg: 950);
        if (c == null) continue;
        expect(c.kind, ContractKind.storeOrder);
        expect(c.lines.length, inInclusiveRange(1, 3));
        final s = w.suppliers[c.supplierId]!;
        for (final l in c.lines) {
          expect(s.sells, contains(l.cargoId));
          expect(w.content.cargoTypes[l.cargoId]!.storable, isTrue);
        }
        expect(c.goodsValueIdr, greaterThan(0));
        expect(c.payIdr, greaterThan(c.goodsValueIdr));
        expect(c.weightKg, lessThanOrEqualTo(950));
      }
    });
  });

  group('kontrak berulang', () {
    late SimWorld w;
    late Agreement a;
    setUp(() {
      w = newWorld();
      addCash(w, 1000000000);
      a = w.offerAgreement(depotId: 1, capacityKg: 950)!;
    });

    test('terima: pengiriman pertama langsung, berikutnya sesuai jadwal dengan kendaraan sama', () {
      expect(a.status, AgreementStatus.offered);
      final first = w.acceptAgreement(agreementId: a.id, vehicleId: vehicleId, driverId: driverId, mode: RouteMode.toll);
      expect(a.status, AgreementStatus.active);
      expect(a.runsDispatched, 1);
      expect(first.vehicleId, vehicleId);
      expect(w.contracts[first.contractId]!.agreementId, a.id);
      final second = a.nextRunAt!;
      expect(second, first.startedAt + a.intervalS);
      w.advanceTo(second);
      expect(a.runsDispatched, 2);
      final trips = w.trips.values.where((t) => w.contracts[t.contractId]!.agreementId == a.id).toList();
      expect(trips, hasLength(2));
      expect(trips.map((t) => t.vehicleId).toSet(), {vehicleId});
      expect(trips.last.startedAt, second);
    });

    test('selesai setelah semua pengiriman; bayaran tiap pengiriman', () {
      w.acceptAgreement(agreementId: a.id, vehicleId: vehicleId, driverId: driverId, mode: RouteMode.toll);
      w.advanceTo(a.offeredAt + a.intervalS * (a.runsTotal + 1));
      expect(a.status, AgreementStatus.finished);
      expect(a.runsDispatched, a.runsTotal);
      final delivered = w.contracts.values.where((c) => c.agreementId == a.id && c.status == ContractStatus.delivered);
      expect(delivered, hasLength(a.runsTotal - a.runsMissed));
    });

    test('kendaraan tidak siap melewati batas toleransi → terlewat; 3× terlewat → putus', () {
      final first = w.acceptAgreement(agreementId: a.id, vehicleId: vehicleId, driverId: driverId, mode: RouteMode.toll);
      runToEnd(w, first);
      // Kendaraan tertahan di bengkel tanpa batas waktu.
      w.vehicles[vehicleId]!.maintenance =
          MaintenanceJob(actionId: 'service', requestedAt: w.now, costIdr: 0, durationS: 60);
      w.advanceTo(a.offeredAt + a.intervalS * 5);
      expect(a.runsMissed, w.content.economy.agreement.maxMissed);
      expect(a.status, AgreementStatus.cancelled);
      expect(w.log.where((e) => e.kind == WorldLogKind.agreementRunMissed), hasLength(3));
    });

    test('putus oleh pemain: denda satu pengiriman; tawaran yang ditolak hilang', () {
      w.acceptAgreement(agreementId: a.id, vehicleId: vehicleId, driverId: driverId, mode: RouteMode.toll);
      final fine = w.cancelPenaltyIdr(a.id);
      w.cancelAgreement(a.id);
      expect(a.status, AgreementStatus.cancelled);
      expect(w.ledger.total(LedgerAccount.agreementPenalty), -fine);
      final before = a.runsDispatched;
      w.advanceTo(a.offeredAt + a.intervalS * 3);
      expect(a.runsDispatched, before, reason: 'tidak ada pengiriman setelah diputus');

      final other = w.offerAgreement(depotId: 1, capacityKg: 950)!;
      w.cancelAgreement(other.id);
      expect(w.agreements.containsKey(other.id), isFalse);
    });

    test('pratinjau tidak mengubah state maupun id', () {
      final json = jsonEncode(w.toJson());
      w.checkAgreement(agreementId: a.id, vehicleId: vehicleId, driverId: driverId);
      expect(jsonEncode(w.toJson()), json);
    });

    test('save di tengah kontrak berulang → load → akhir sama', () {
      w.acceptAgreement(agreementId: a.id, vehicleId: vehicleId, driverId: driverId, mode: RouteMode.toll);
      w.advanceTo(w.now + 3600);
      final loaded = SimWorld.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
          graph: w.graph, content: w.content);
      final end = a.offeredAt + a.intervalS * 3 + 7200;
      w.advanceTo(end);
      loaded.advanceTo(end);
      expect(jsonEncode(loaded.toJson()), jsonEncode(w.toJson()));
    });
  });

  group('jual-beli armada', () {
    late SimWorld w;
    setUp(() {
      w = newWorld();
      addCash(w, 10000000000);
    });

    test('nilai pasar turun karena umur, odometer, dan kondisi', () {
      final model = w.content.vehicleModels['pickup_box_1t']!;
      int value(int age, int km, double c) =>
          w.marketValueIdrFor(model, ageYears: age, odometerM: km * 1000, averageCondition: c);
      expect(value(0, 0, 1), model.priceIdr);
      expect(value(1, 0, 1), lessThan(value(0, 0, 1)));
      expect(value(5, 0, 1), lessThan(value(1, 0, 1)));
      expect(value(1, 200000, 1), lessThan(value(1, 0, 1)));
      expect(value(1, 0, 0.5), lessThan(value(1, 0, 1)));
      expect(value(40, 5000000, 0), greaterThanOrEqualTo(model.priceIdr ~/ 10));
    });

    test('jual: kas bertambah, slot kosong; kendaraan terakhir tidak bisa dijual', () {
      expect(w.sellProblems(vehicleId), [SellProblem.lastVehicle]);
      final second = w.buyVehicle(1, 'pickup_open_1t');
      expect(second.builtYear, w.currentYear);
      final cash = w.cashIdr;
      final price = w.saleValueIdr(second);
      expect(price, lessThan(second.purchasePriceIdr), reason: 'dealer membeli di bawah nilai pasar');
      expect(w.sellVehicle(second.id), price);
      expect(w.cashIdr, cash + price);
      expect(w.vehicles.containsKey(second.id), isFalse);
      expect(w.depots[1]!.slots, [vehicleId, null, null]);
      expect(w.ledger.total(LedgerAccount.vehicleSale), price);
    });

    test('kendaraan bertugas atau terikat kontrak berulang tidak bisa dijual', () {
      final second = w.buyVehicle(1, 'pickup_box_1t');
      final c = w.offerHaulContract(depotId: 1, capacityKg: 950)!;
      w.dispatch(contractId: c.id, vehicleId: second.id, driverId: driverId, mode: RouteMode.toll);
      expect(w.sellProblems(second.id), contains(SellProblem.vehicleBusy));
      final a = w.offerAgreement(depotId: 1, capacityKg: 950)!;
      w.hire(1, EmployeeRole.driver);
      w.acceptAgreement(agreementId: a.id, vehicleId: vehicleId, driverId: w.drivers.keys.last, mode: RouteMode.toll);
      w.advanceTo(w.now + 24 * 3600);
      expect(w.sellProblems(vehicleId), contains(SellProblem.inAgreement));
    });

    test('pasar bekas: deterministik per hari, beli sekali, berganti esok hari', () {
      final today = w.usedListings(1);
      expect(today, hasLength(w.content.economy.vehicleMarket.usedListings));
      expect([for (final l in newWorld().usedListings(1)) l.key], [for (final l in today) l.key]);
      final pick = today.first;
      expect(pick.builtYear, lessThan(w.currentYear));
      expect(pick.odometerM, greaterThan(0));
      final v = w.buyUsedVehicle(1, pick.key);
      expect(v.model.id, pick.model.id);
      expect(v.odometerM, pick.odometerM);
      expect(v.builtYear, pick.builtYear);
      expect(v.purchasePriceIdr, pick.priceIdr);
      expect(v.condition, pick.condition);
      expect(w.usedListings(1).map((l) => l.key), isNot(contains(pick.key)));
      expect(w.usedPurchaseProblems(1, pick.key), [PurchaseProblem.listingGone]);
      w.advanceTo(w.now + SimWorld.daySeconds);
      expect(w.usedListings(1).first.key, isNot(pick.key));
    });

    test('kendaraan bekas tersimpan & termuat utuh', () {
      final pick = w.usedListings(1).first;
      w.buyUsedVehicle(1, pick.key);
      final json = jsonEncode(w.toJson());
      final loaded = SimWorld.fromJson(jsonDecode(json) as Map<String, dynamic>, graph: w.graph, content: w.content);
      expect(jsonEncode(loaded.toJson()), json);
    });
  });

  group('fasilitas 15 level', () {
    test('semua fasilitas 15 level; tier visual naik di level 4 & 8', () {
      final w = newWorld();
      for (final t in FacilityType.values) {
        final spec = w.content.facilities[t];
        expect(spec.maxLevel, 15, reason: t.id);
        expect(spec.changesLook(2), isFalse, reason: '${t.id}: level 2 hanya statistik');
        expect(spec.changesLook(4), isTrue, reason: t.id);
        expect(spec.changesLook(8), isTrue, reason: t.id);
        expect(spec.level(2).model, spec.level(1).model);
        expect(spec.level(4).model, isNot(spec.level(3).model));
      }
    });

    test('upgrade statistik saja: jalur internal lebih cepat, slot tetap', () {
      final w = newWorld();
      addCash(w, 1000000000);
      final depot = w.depots[1]!;
      final before = w.yardS(depot, 600);
      upgradeTo(w, FacilityType.parking, 2);
      expect(depot.parkingSlots, 3);
      expect(w.yardS(depot, 600), lessThan(before));
      expect(w.tier(depot, FacilityType.parking), 1);
      upgradeTo(w, FacilityType.parking, 4);
      expect(depot.parkingSlots, 5);
      expect(w.tier(depot, FacilityType.parking), 2);
    });

    test('save format 2: level 1/2/3 dipetakan ke 1/4/8', () {
      final w = newWorld();
      final json = jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>;
      json['format'] = 2;
      final d = (json['depots'] as List).single as Map<String, dynamic>;
      d['levels'] = {'parking': 3, 'gate': 2, 'loading_dock': 1, 'workshop': 2, 'warehouse': 1, 'office': 3};
      d['slots'] = [vehicleId, null, null, null, null, null, null, null];
      final loaded = SimWorld.fromJson(json, graph: w.graph, content: w.content);
      final depot = loaded.depots[1]!;
      expect(depot.level(FacilityType.parking), 8);
      expect(depot.level(FacilityType.gate), 4);
      expect(depot.level(FacilityType.loadingDock), 1);
      expect(depot.level(FacilityType.workshop), 4);
      expect(depot.level(FacilityType.office), 8);
      expect(depot.parkingSlots, 8);
      expect(loaded.workshopBays(depot), 1);
      expect(loaded.gateLaneCount(depot), 1);
      expect(loaded.toJson()['format'], SimWorld.saveFormat);
    });
  });
}
