import 'maintenance.dart';
import 'vehicle_class.dart';
import 'vehicle_profile.dart';

/// Spesifikasi model kendaraan dari katalog (`content/vehicle_models.json`).
class VehicleModel {
  const VehicleModel({
    required this.id,
    required this.name,
    required this.vehicleClass,
    required this.maxSpeedKmh,
    required this.emptyWeightKg,
    required this.payloadKg,
    required this.tollGolongan,
    required this.fuelLPer100Km,
    required this.priceIdr,
    required this.visual,
  });

  factory VehicleModel.fromJson(Map<String, dynamic> j) => VehicleModel(
        id: j['id'] as String,
        name: j['name'] as String,
        vehicleClass: VehicleClass.parse(j['class'] as String),
        maxSpeedKmh: (j['max_speed_kmh'] as num).toInt(),
        emptyWeightKg: (j['empty_weight_kg'] as num).toInt(),
        payloadKg: (j['payload_kg'] as num).toInt(),
        tollGolongan: (j['toll_golongan'] as num).toInt(),
        fuelLPer100Km: (j['fuel_l_per_100km'] as num).toDouble(),
        priceIdr: (j['price_idr'] as num).toInt(),
        visual: j['visual'] as String,
      );

  static Map<String, VehicleModel> catalogFromJson(Map<String, dynamic> json) => {
        for (final m in json['models'] as List)
          (m as Map<String, dynamic>)['id'] as String: VehicleModel.fromJson(m),
      };

  final String id;
  final String name;
  final VehicleClass vehicleClass;
  final int maxSpeedKmh;
  final int emptyWeightKg;
  final int payloadKg;
  final int tollGolongan;
  final double fuelLPer100Km;
  final int priceIdr;

  /// Nama model 3D (GLB) untuk renderer.
  final String visual;

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
  }) : condition = condition ?? {for (final c in VehicleComponent.values) c: 1.0};

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

  bool get isAvailable => tripId == null && maintenance == null;

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
      };

  factory Vehicle.fromJson(Map<String, dynamic> j, Map<String, VehicleModel> models) {
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
    );
  }
}
