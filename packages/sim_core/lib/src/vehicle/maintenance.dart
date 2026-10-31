import 'vehicle_class.dart';

/// Komponen kendaraan yang aus. Kondisi 0 (rusak) .. 1 (baru).
enum VehicleComponent {
  engine('engine'),
  transmission('transmission'),
  brakes('brakes'),
  tires('tires'),
  suspension('suspension'),
  cooling('cooling'),
  electrical('electrical');

  const VehicleComponent(this.id);

  final String id;

  static VehicleComponent parse(String id) => VehicleComponent.values.firstWhere(
        (c) => c.id == id,
        orElse: () => throw FormatException('Komponen tidak dikenal: $id'),
      );
}

/// Satu jenis tindakan perawatan (`content/maintenance.json`).
class MaintenanceAction {
  const MaintenanceAction({
    required this.id,
    required this.name,
    required this.costIdr,
    required this.minutes,
    required this.restore,
  });

  final String id;
  final String name;

  /// Biaya dasar (sebelum faktor kelas kendaraan & bengkel).
  final int costIdr;

  /// Durasi dasar (menit game, sebelum faktor kecepatan bengkel).
  final int minutes;

  /// Pemulihan per komponen: kondisi ditambah nilai ini (maks. 1).
  final Map<VehicleComponent, double> restore;
}

class MaintenanceConfig {
  const MaintenanceConfig({
    required this.componentNames,
    required this.wearPer1000Km,
    required this.loadedWearFactor,
    required this.fuelPerEngineWear,
    required this.fuelPerTireWear,
    required this.minSpeedFactor,
    required this.classCostFactor,
    required this.actions,
  });

  factory MaintenanceConfig.fromJson(Map<String, dynamic> j) {
    final comps = (j['components'] as List).cast<Map<String, dynamic>>();
    final byId = {for (final c in comps) VehicleComponent.parse(c['id'] as String): c};
    for (final c in VehicleComponent.values) {
      if (!byId.containsKey(c)) throw FormatException('Komponen ${c.id} tidak didefinisikan');
    }
    final effects = j['effects'] as Map<String, dynamic>;
    final actions = [
      for (final a in (j['actions'] as List).cast<Map<String, dynamic>>())
        MaintenanceAction(
          id: a['id'] as String,
          name: a['name'] as String,
          costIdr: (a['cost_idr'] as num).toInt(),
          minutes: (a['minutes'] as num).toInt(),
          restore: {
            for (final e in (a['restore'] as Map<String, dynamic>).entries)
              VehicleComponent.parse(e.key): (e.value as num).toDouble(),
          },
        ),
    ];
    return MaintenanceConfig(
      componentNames: {for (final e in byId.entries) e.key: e.value['name'] as String},
      wearPer1000Km: {for (final e in byId.entries) e.key: (e.value['wear_per_1000km'] as num).toDouble()},
      loadedWearFactor: (j['loaded_wear_factor'] as num).toDouble(),
      fuelPerEngineWear: (effects['fuel_per_engine_wear'] as num).toDouble(),
      fuelPerTireWear: (effects['fuel_per_tire_wear'] as num).toDouble(),
      minSpeedFactor: (effects['min_speed_factor'] as num).toDouble(),
      classCostFactor: {
        for (final e in (j['class_cost_factor'] as Map<String, dynamic>).entries)
          VehicleClass.parse(e.key): (e.value as num).toDouble(),
      },
      actions: {for (final a in actions) a.id: a},
    );
  }

  final Map<VehicleComponent, String> componentNames;
  final Map<VehicleComponent, double> wearPer1000Km;

  /// Tambahan keausan saat bermuatan penuh (proporsional rasio muatan).
  final double loadedWearFactor;
  final double fuelPerEngineWear;
  final double fuelPerTireWear;
  final double minSpeedFactor;
  final Map<VehicleClass, double> classCostFactor;
  final Map<String, MaintenanceAction> actions;

  MaintenanceAction action(String id) => actions[id] ?? (throw ArgumentError.value(id, 'actionId'));
}

/// Pekerjaan perawatan pada satu kendaraan. Menunggu bay bengkel bila semua
/// terpakai ([startedAt] null), lalu dikerjakan sampai [finishAt].
class MaintenanceJob {
  MaintenanceJob({
    required this.actionId,
    required this.requestedAt,
    required this.costIdr,
    required this.durationS,
    this.startedAt,
    this.bay,
  });

  final String actionId;
  final int requestedAt;
  final int costIdr;
  final int durationS;
  int? startedAt;

  /// Bay bengkel yang dipakai; `null` = antre, atau dikerjakan bengkel luar.
  int? bay;

  bool get waiting => startedAt == null;
  int? get finishAt => startedAt == null ? null : startedAt! + durationS;

  Map<String, dynamic> toJson() => {
        'action': actionId,
        'requested_at': requestedAt,
        'cost_idr': costIdr,
        'duration_s': durationS,
        'started_at': startedAt,
        'bay': bay,
      };

  factory MaintenanceJob.fromJson(Map<String, dynamic> j) => MaintenanceJob(
        actionId: j['action'] as String,
        requestedAt: j['requested_at'] as int,
        costIdr: j['cost_idr'] as int,
        durationS: j['duration_s'] as int,
        startedAt: j['started_at'] as int?,
        bay: j['bay'] as int?,
      );
}
