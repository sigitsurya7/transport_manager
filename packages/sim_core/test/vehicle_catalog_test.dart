import 'dart:convert';
import 'dart:io';

import 'package:sim_core/sim_core.dart';
import 'package:test/test.dart';

import 'maintenance_test.dart' show addCash;
import 'support/test_world.dart';

Map<String, dynamic> rawCatalog() =>
    jsonDecode(File('../../content/vehicle_models.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  final catalog = loadContent().vehicleCatalog;

  group('katalog', () {
    test('setiap kategori punya beberapa model berbeda sasis/bodi', () {
      for (final c in catalog.categories) {
        final models = catalog.models.values.where((m) => m.category == c.id).toList();
        expect(models.length, greaterThanOrEqualTo(4), reason: c.id);
        // Bukan sekadar ganti warna: kombinasi sasis + bodi unik dalam kategori.
        expect(models.map((m) => '${m.chassis.id}+${m.body.id}').toSet(), hasLength(models.length), reason: c.id);
      }
      expect(catalog.models.length, greaterThanOrEqualTo(35));
    });

    test('semua model: bodi cocok dengan sasis, angka masuk akal', () {
      for (final m in catalog.models.values) {
        expect(VehicleCatalog.compatibilityProblem(m.chassis, m.body), isNull, reason: m.id);
        expect(m.payloadKg, greaterThan(0));
        expect(m.cargoKinds, isNotEmpty);
        expect(m.tollGolongan, inInclusiveRange(1, 5));
        expect(m.lengthM, greaterThan(m.body.lengthM), reason: '${m.id}: bodi lebih panjang dari kendaraan');
      }
    });

    test('kendaraan lebih besar: muatan & panjang naik per kategori', () {
      double avg(String cat, num Function(VehicleModel) f) {
        final ms = catalog.models.values.where((m) => m.category == cat);
        return ms.map(f).reduce((a, b) => a + b) / ms.length;
      }

      final order = ['pickup', 'mini_truck', 'light_truck', 'medium_truck', 'heavy_rigid', 'tractor'];
      for (var i = 1; i < order.length; i++) {
        expect(avg(order[i], (m) => m.payloadKg), greaterThan(avg(order[i - 1], (m) => m.payloadKg)), reason: order[i]);
        // Truk mini cab-over lebih pendek dari pikap bermoncong; mulai truk ringan panjang selalu naik.
        if (i >= 2) {
          expect(avg(order[i], (m) => m.lengthM), greaterThan(avg(order[i - 1], (m) => m.lengthM)), reason: order[i]);
        }
      }
    });

    test('kombinasi tidak kompatibel ditolak saat memuat katalog', () {
      Map<String, dynamic> withModel(String chassis, String body) {
        final raw = rawCatalog();
        final model = Map<String, dynamic>.of((raw['models'] as List).first as Map<String, dynamic>)
          ..['id'] = 'uji'
          ..['chassis'] = chassis
          ..['body'] = body;
        (raw['models'] as List).add(model);
        return raw;
      }

      // Kontainer 20 ft di pikap, tangki di van, semitrailer di truk sedang.
      for (final (c, b) in [
        ('pickup_single', 'container_20'),
        ('van_panel', 'tank_l'),
        ('medium_cabover', 'trailer_box')
      ]) {
        expect(() => VehicleCatalog.fromJson(withModel(c, b)), throwsFormatException, reason: '$c + $b');
      }
      // Bodi terlalu panjang untuk sasis meski dudukannya cocok.
      final pickup = catalog.chassis['pickup_double']!;
      final long = catalog.bodies['open_bed_l']!;
      expect(long.mounts, contains(pickup.mount));
      expect(VehicleCatalog.compatibilityProblem(pickup, long), contains('terlalu panjang'));
      // Kombinasi sah tetap diterima.
      expect(VehicleCatalog.fromJson(withModel('heavy_cabover', 'container_20')).models['uji'], isNotNull);
    });

    test('id ganda & jenis muatan tak dikenal ditolak', () {
      final dup = rawCatalog();
      (dup['models'] as List).add((dup['models'] as List).first);
      expect(() => VehicleCatalog.fromJson(dup), throwsFormatException);
      final kind = rawCatalog();
      ((kind['bodies'] as List).first as Map)['cargo_kinds'] = ['plutonium'];
      expect(() => VehicleCatalog.fromJson(kind), throwsFormatException);
    });
  });

  group('pembelian', () {
    test('syarat level fasilitas & terminal truk', () {
      final w = newWorld();
      addCash(w, 10000000000);
      expect(w.purchaseProblems(1, 'medium_box_80'), [PurchaseProblem.facilityLevelTooLow]);
      expect(w.purchaseProblems(1, 'heavy_box_15'), contains(PurchaseProblem.needsTruckTerminal));
      w.advanceTo(w.startUpgrade(1, FacilityType.parking).finishAt);
      expect(w.purchaseProblems(1, 'medium_box_80'), isEmpty);
      final v = w.buyVehicle(1, 'medium_box_80');
      expect(v.model.category, 'medium_truck');
      expect(() => w.buyVehicle(1, 'tractor_day_40ft'), throwsA(isA<CommandException>()));
    });

    test('semua model depot kota bisa dibeli setelah fasilitas memenuhi syarat', () {
      final w = newWorld();
      addCash(w, 100000000000);
      for (final level in [2, 3]) {
        w.advanceTo(w.startUpgrade(1, FacilityType.parking).finishAt);
        expect(w.depots[1]!.level(FacilityType.parking), level);
      }
      for (final m in w.content.vehicleModels.values.where((m) => !m.unlock.terminal)) {
        expect(w.purchaseProblems(1, m.id).where((p) => p != PurchaseProblem.noFreeSlot), isEmpty, reason: m.id);
      }
    });
  });

  group('jenis muatan', () {
    test('barang beku hanya untuk box berpendingin; tawaran mengikuti armada', () {
      final w = newWorld();
      addCash(w, 1000000000);
      final kinds = {for (final c in w.content.cargoTypes.values) c.id: c.kind};
      // Armada awal (box kering): tawaran hanya barang umum.
      for (var i = 0; i < 20; i++) {
        final c = w.offerStoreContract(depotId: 1, capacityKg: 900);
        if (c != null) expect(kinds[c.cargoId], 'general');
      }
      final reefer = w.buyVehicle(1, 'mini_reefer_19');
      final base = addContract(w, destinationNode: 20);
      final frozen = Contract(
        id: base.id + 1,
        customer: base.customer,
        cargoId: 'frozen_food',
        units: 50,
        weightKg: 500,
        destinationNode: 20,
        destinationName: base.destinationName,
        scope: base.scope,
        payIdr: base.payIdr,
        offeredAt: w.now,
        allowedS: base.allowedS,
        latePenaltyPerHourIdr: 0,
      );
      w.contracts[frozen.id] = frozen;
      expect(w.check(contractId: frozen.id, vehicleId: vehicleId, driverId: driverId).problems,
          contains(DispatchProblem.cargoIncompatible));
      expect(w.check(contractId: frozen.id, vehicleId: reefer.id, driverId: driverId).problems,
          isNot(contains(DispatchProblem.cargoIncompatible)));
      // Setelah punya truk berpendingin, barang beku bisa muncul di tawaran.
      final offered = {
        for (var i = 0; i < 60; i++) w.offerStoreContract(depotId: 1, capacityKg: 1800)?.cargoId,
      }.whereType<String>().map((id) => kinds[id]).toSet();
      expect(offered, contains('chilled'));
    });
  });
}
