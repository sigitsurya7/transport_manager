import '../contracts/contract.dart';
import '../contracts/contract_tiers.dart';
import '../depot/facilities.dart';
import '../employees/employee_config.dart';
import '../finance/economy_config.dart';
import '../trips/depot_ops_config.dart';
import '../vehicle/maintenance.dart';
import '../vehicle/vehicle.dart';
import '../vehicle/vehicle_catalog.dart';

/// Semua katalog data-driven yang dibutuhkan simulasi (folder `content/`).
/// Dimuat sekali; tidak disimpan di save (save hanya menyimpan id).
class GameContent {
  const GameContent({
    required this.tierRules,
    required this.vehicleCatalog,
    required this.cargoTypes,
    required this.storeCustomers,
    required this.economy,
    required this.depotOps,
    required this.facilities,
    required this.employees,
    required this.maintenance,
  });

  /// [files]: isi JSON per nama file di `content/`.
  factory GameContent.fromJsonFiles(Map<String, Map<String, dynamic>> files) {
    Map<String, dynamic> f(String name) =>
        files[name] ?? (throw FormatException('Konten hilang: $name'));
    final content = GameContent(
      tierRules: ContractTierRules.fromJson(f('contract_tiers.json')),
      vehicleCatalog: VehicleCatalog.fromJson(f('vehicle_models.json')),
      cargoTypes: CargoType.catalogFromJson(f('cargo_types.json')),
      storeCustomers: (f('customers.json')['store_to_store'] as List).cast<String>(),
      economy: EconomyConfig.fromJson(f('economy.json')),
      depotOps: DepotOpsConfig.fromJson(f('depot_ops.json')),
      facilities: FacilityCatalog.fromJson(f('facilities.json')),
      employees: EmployeeConfig.fromJson(f('employees.json')),
      maintenance: MaintenanceConfig.fromJson(f('maintenance.json')),
    );
    if (content.storeCustomers.isEmpty) throw const FormatException('Daftar pelanggan kosong');
    if (content.cargoTypes.isEmpty) throw const FormatException('Katalog barang kosong');
    for (final m in content.vehicleModels.values) {
      final f = m.unlock.facilityId;
      if (f != null && m.unlock.level > content.facilities[FacilityType.parse(f)].maxLevel) {
        throw FormatException('Model ${m.id}: syarat $f level ${m.unlock.level} melebihi level maksimum');
      }
    }
    for (final c in content.cargoTypes.values) {
      if (!content.vehicleCatalog.cargoKindNames.containsKey(c.kind)) {
        throw FormatException('Barang ${c.id}: jenis muatan tidak dikenal ${c.kind}');
      }
    }
    return content;
  }

  static const fileNames = [
    'contract_tiers.json',
    'vehicle_models.json',
    'cargo_types.json',
    'customers.json',
    'economy.json',
    'depot_ops.json',
    'facilities.json',
    'employees.json',
    'maintenance.json',
  ];

  final ContractTierRules tierRules;
  final VehicleCatalog vehicleCatalog;
  Map<String, VehicleModel> get vehicleModels => vehicleCatalog.models;
  final Map<String, CargoType> cargoTypes;
  final List<String> storeCustomers;
  final EconomyConfig economy;
  final DepotOpsConfig depotOps;
  final FacilityCatalog facilities;
  final EmployeeConfig employees;
  final MaintenanceConfig maintenance;
}
