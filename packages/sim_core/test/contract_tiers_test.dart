import 'dart:convert';
import 'dart:io';

import 'package:sim_core/sim_core.dart';
import 'package:test/test.dart';

void main() {
  final rules = ContractTierRules.fromJson(jsonDecode(
          File('../../content/contract_tiers.json').readAsStringSync())
      as Map<String, dynamic>);

  test('toko ke toko boleh pakai pikap', () {
    expect(rules.canDispatch(DeliveryScope.storeToStore, VehicleClass.pickupOpen), isTrue);
  });

  test('antarkota minimal mini truck', () {
    expect(rules.canDispatch(DeliveryScope.intercity, VehicleClass.pickupOpen), isFalse);
    expect(rules.canDispatch(DeliveryScope.intercity, VehicleClass.pickupBox), isFalse);
    expect(rules.canDispatch(DeliveryScope.intercity, VehicleClass.miniTruck), isTrue);
    expect(rules.canDispatch(DeliveryScope.intercity, VehicleClass.tractorHead), isTrue);
  });

  test('distribusi kawasan minimal pikap box', () {
    expect(rules.canDispatch(DeliveryScope.district, VehicleClass.pickupOpen), isFalse);
    expect(rules.canDispatch(DeliveryScope.district, VehicleClass.pickupBox), isTrue);
  });

  test('klasifikasi dari geografi', () {
    expect(rules.classify(sameCity: true, distanceKm: 5), DeliveryScope.storeToStore);
    expect(rules.classify(sameCity: true, distanceKm: 30), DeliveryScope.district);
    expect(rules.classify(sameCity: false, distanceKm: 150), DeliveryScope.intercity);
  });

  test('tier yang hilang ditolak', () {
    expect(
      () => ContractTierRules(storeToStoreMaxKm: 10, tiers: const []),
      throwsFormatException,
    );
  });
}
