import 'maintenance.dart';
import 'vehicle_catalog.dart';
import 'vehicle_class.dart';
import 'vehicle_profile.dart';

/// Model kendaraan jadi dari katalog (`content/vehicle_models.json`):
/// sasis + bodi beserta angka operasional.
class VehicleModel {
  const VehicleModel({
    required this.id,
    required this.name,
    required this.category,
    required this.subcategory,
    required this.chassis,
    required this.body,
    required this.vehicleClass,
    required this.maxSpeedKmh,
    required this.emptyWeightKg,
    required this.payloadKg,
    required this.tollGolongan,
    required this.fuelLPer100Km,
    required this.priceIdr,
    required this.lengthM,
    required this.widthM,
    required this.heightM,
    required this.unlock,
    required this.visual,
  });

  factory VehicleModel.fromJson(Map<String, dynamic> j, {required VehicleChassis chassis, required VehicleBody body}) =>
      VehicleModel(
        id: j['id'] as String,
        name: j['name'] as String,
        category: j['category'] as String,
        subcategory: j['subcategory'] as String,
        chassis: chassis,
        body: body,
        vehicleClass: VehicleClass.parse(j['class'] as String),
        maxSpeedKmh: (j['max_speed_kmh'] as num).toInt(),
        emptyWeightKg: (j['empty_weight_kg'] as num).toInt(),
        payloadKg: (j['payload_kg'] as num).toInt(),
        tollGolongan: (j['toll_golongan'] as num).toInt(),
        fuelLPer100Km: (j['fuel_l_per_100km'] as num).toDouble(),
        priceIdr: (j['price_idr'] as num).toInt(),
        lengthM: (j['length_m'] as num).toDouble(),
        widthM: (j['width_m'] as num).toDouble(),
        heightM: (j['height_m'] as num).toDouble(),
        unlock: VehicleUnlock.fromJson(j['unlock'] as Map<String, dynamic>?),
        // Model 3D bernama sama dengan id (dibuat tools/depot_glb).
        visual: j['visual'] as String? ?? j['id'] as String,
      );

  final String id;
  final String name;

  /// Id kategori dealer (pickup, van, mini_truck, …).
  final String category;
  final String subcategory;
  final VehicleChassis chassis;
  final VehicleBody body;
  final VehicleClass vehicleClass;
  final int maxSpeedKmh;
  final int emptyWeightKg;
  final int payloadKg;
  final int tollGolongan;
  final double fuelLPer100Km;
  final int priceIdr;
  final double lengthM;
  final double widthM;
  final double heightM;
  final VehicleUnlock unlock;

  /// Nama model 3D (GLB) & thumbnail untuk renderer.
  final String visual;

  Set<String> get cargoKinds => body.cargoKinds;

  bool canCarry(String cargoKind) => body.cargoKinds.contains(cargoKind);

  VehicleProfile profile({int cargoKg = 0}) => VehicleProfile(
        vehicleClass: vehicleClass,
        maxSpeedKmh: maxSpeedKmh,
        grossWeightT: (emptyWeightKg + cargoKg) / 1000,
        tollGolongan: tollGolongan,
      );
}

/// Kendaraan milik perusahaan.
class Vehicle {
  Vehicle({
    required this.id,
    required this.model,
    required this.depotId,
    required this.slotIndex,
    this.odometerM = 0,
    this.tripId,
    Map<VehicleComponent, double>? condition,
    this.maintenance,
    this.builtYear = 2026,
    int? purchasePriceIdr,
  })  : purchasePriceIdr = purchasePriceIdr ?? model.priceIdr,
        condition = condition ?? {for (final c in VehicleComponent.values) c: 1.0};

  final int id;
  final VehicleModel model;
  final int depotId;

  /// Slot parkir milik kendaraan ini. Tahap 2b: slot tetap dipegang selama
  /// trip; antrean parkir & perebutan slot masuk Tahap 3.
  int slotIndex;

  /// Odometer tidak pernah direset (juga saat ganti mesin).
  int odometerM;

  int? tripId;

  /// Kondisi tiap komponen (0 rusak .. 1 baru).
  final Map<VehicleComponent, double> condition;

  /// Pekerjaan bengkel yang sedang berjalan / antre; kendaraan tidak bisa ditugaskan.
  MaintenanceJob? maintenance;

  /// Tahun produksi (kendaraan bekas lebih tua dari tahun berjalan).
  final int builtYear;

  /// Harga yang dibayar perusahaan saat membeli.
  final int purchasePriceIdr;

  bool get isAvailable => tripId == null && maintenance == null;

  /// Rata-rata kondisi komponen.
  double get averageCondition => condition.values.reduce((a, b) => a + b) / condition.length;

  /// Kondisi terburuk (untuk ringkasan & risiko).
  double get worstCondition => condition.values.reduce((a, b) => a < b ? a : b);

  Map<String, dynamic> toJson() => {
        'id': id,
        'model': model.id,
        'depot': depotId,
        'slot': slotIndex,
        'odometer_m': odometerM,
        'trip': tripId,
        'condition': {for (final e in condition.entries) e.key.id: e.value},
        'maintenance': maintenance?.toJson(),
        'built_year': builtYear,
        'purchase_idr': purchasePriceIdr,
      };

  /// Save sebelum jual-beli armada: tahun produksi = [defaultYear], harga beli = harga baru.
  factory Vehicle.fromJson(Map<String, dynamic> j, Map<String, VehicleModel> models, {int defaultYear = 2026}) {
    final model = models[j['model']];
    if (model == null) throw FormatException('Model kendaraan tidak dikenal: ${j['model']}');
    return Vehicle(
      id: j['id'] as int,
      model: model,
      depotId: j['depot'] as int,
      slotIndex: j['slot'] as int,
      odometerM: j['odometer_m'] as int,
      tripId: j['trip'] as int?,
      // Save sebelum Tahap 4.1: semua komponen baru.
      condition: {
        for (final c in VehicleComponent.values)
          c: ((j['condition'] as Map?)?[c.id] as num?)?.toDouble() ?? 1.0,
      },
      maintenance: j['maintenance'] == null ? null : MaintenanceJob.fromJson(j['maintenance'] as Map<String, dynamic>),
      builtYear: j['built_year'] as int? ?? defaultYear,
      purchasePriceIdr: j['purchase_idr'] as int?,
    );
  }
}
