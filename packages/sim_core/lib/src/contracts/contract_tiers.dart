import '../vehicle/vehicle_class.dart';

/// Jangkauan sebuah kontrak pengiriman.
enum DeliveryScope {
  /// Toko ke toko di dalam kota, jarak dekat.
  storeToStore('store_to_store'),

  /// Dalam kota sampai pinggiran.
  district('district'),

  /// Keluar kota (mis. Jakarta → Bandung).
  intercity('intercity');

  const DeliveryScope(this.id);

  final String id;

  static DeliveryScope parse(String id) => DeliveryScope.values.firstWhere(
        (s) => s.id == id,
        orElse: () => throw FormatException('Scope tidak dikenal: $id'),
      );
}

class ContractTier {
  const ContractTier({required this.scope, required this.label, required this.minVehicleClass});

  final DeliveryScope scope;
  final String label;
  final VehicleClass minVehicleClass;
}

/// Aturan kelas kendaraan minimal per jangkauan pengiriman (data-driven,
/// dari `content/contract_tiers.json`).
class ContractTierRules {
  ContractTierRules({required this.storeToStoreMaxKm, required List<ContractTier> tiers})
      : _tiers = {for (final t in tiers) t.scope: t} {
    for (final scope in DeliveryScope.values) {
      if (!_tiers.containsKey(scope)) {
        throw FormatException('Tier untuk ${scope.id} tidak didefinisikan');
      }
    }
  }

  factory ContractTierRules.fromJson(Map<String, dynamic> json) => ContractTierRules(
        storeToStoreMaxKm: (json['store_to_store_max_km'] as num).toDouble(),
        tiers: [
          for (final t in json['tiers'] as List)
            ContractTier(
              scope: DeliveryScope.parse((t as Map)['scope'] as String),
              label: t['label'] as String,
              minVehicleClass: VehicleClass.parse(t['min_vehicle_class'] as String),
            ),
        ],
      );

  final double storeToStoreMaxKm;
  final Map<DeliveryScope, ContractTier> _tiers;

  ContractTier tierFor(DeliveryScope scope) => _tiers[scope]!;

  bool canDispatch(DeliveryScope scope, VehicleClass vehicle) =>
      vehicle.isAtLeast(tierFor(scope).minVehicleClass);

  /// Tentukan jangkauan dari geografi kontrak.
  DeliveryScope classify({required bool sameCity, required double distanceKm}) {
    if (!sameCity) return DeliveryScope.intercity;
    return distanceKm <= storeToStoreMaxKm ? DeliveryScope.storeToStore : DeliveryScope.district;
  }
}
