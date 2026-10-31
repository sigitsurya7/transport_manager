import 'vehicle.dart';

/// Sasis / kabin kendaraan. Bodi hanya bisa dipasang bila `mount` cocok dan
/// panjangnya tidak melebihi [bodyMaxM].
class VehicleChassis {
  const VehicleChassis({required this.id, required this.name, required this.mount, required this.bodyMaxM});

  factory VehicleChassis.fromJson(Map<String, dynamic> j) => VehicleChassis(
        id: j['id'] as String,
        name: j['name'] as String,
        mount: j['mount'] as String,
        bodyMaxM: (j['body_max_m'] as num).toDouble(),
      );

  final String id;
  final String name;

  /// Jenis dudukan bodi: pickup, van, mini_k, mini, light, medium, heavy, fifth_wheel.
  final String mount;
  final double bodyMaxM;
}

/// Bodi muatan, semitrailer, atau kontainer.
class VehicleBody {
  const VehicleBody({
    required this.id,
    required this.name,
    required this.kind,
    required this.mounts,
    required this.lengthM,
    required this.cargoKinds,
    required this.doors,
  });

  factory VehicleBody.fromJson(Map<String, dynamic> j) => VehicleBody(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: j['kind'] as String,
        mounts: (j['mounts'] as List).cast<String>().toSet(),
        lengthM: (j['length_m'] as num).toDouble(),
        cargoKinds: (j['cargo_kinds'] as List).cast<String>().toSet(),
        doors: j['doors'] as bool,
      );

  final String id;
  final String name;

  /// open, canopy, box, van, reefer, curtain, flatbed, dump, tanker, container,
  /// car_carrier, crane, logs, trailer_*.
  final String kind;
  final Set<String> mounts;
  final double lengthM;
  final Set<String> cargoKinds;

  /// Punya pintu belakang (ada model `<visual>_open` untuk animasi muat).
  final bool doors;

  bool fits(VehicleChassis chassis) => mounts.contains(chassis.mount) && lengthM <= chassis.bodyMaxM + 1e-9;
}

/// Syarat membeli kendaraan.
class VehicleUnlock {
  const VehicleUnlock({this.facilityId, this.level = 1, this.terminal = false});

  factory VehicleUnlock.fromJson(Map<String, dynamic>? j) => j == null
      ? const VehicleUnlock()
      : VehicleUnlock(
          facilityId: j['facility'] as String?,
          level: (j['level'] as num?)?.toInt() ?? 1,
          terminal: j['terminal'] as bool? ?? false,
        );

  /// Id fasilitas depot yang harus mencapai [level] (mis. `parking`).
  final String? facilityId;
  final int level;

  /// Butuh terminal truk: kendaraan terlalu panjang untuk depot kota.
  final bool terminal;

  bool get isFree => facilityId == null && !terminal;
}

class VehicleCategory {
  const VehicleCategory(this.id, this.name);

  final String id;
  final String name;
}

/// Katalog lengkap: kategori, jenis muatan, sasis, bodi, dan model jadi.
/// Dibangun dari `content/vehicle_models.json` dengan validasi menyeluruh.
class VehicleCatalog {
  VehicleCatalog._({
    required this.categories,
    required this.cargoKindNames,
    required this.chassis,
    required this.bodies,
    required this.models,
  });

  factory VehicleCatalog.fromJson(Map<String, dynamic> json) {
    final categories = [
      for (final c in (json['categories'] as List).cast<Map<String, dynamic>>())
        VehicleCategory(c['id'] as String, c['name'] as String),
    ];
    final kinds = (json['cargo_kinds'] as Map).cast<String, String>();
    final chassis = _unique(
      (json['chassis'] as List).cast<Map<String, dynamic>>().map(VehicleChassis.fromJson),
      (c) => c.id,
      'sasis',
    );
    final bodies = _unique(
      (json['bodies'] as List).cast<Map<String, dynamic>>().map(VehicleBody.fromJson),
      (b) => b.id,
      'bodi',
    );
    for (final b in bodies.values) {
      final unknown = b.cargoKinds.difference(kinds.keys.toSet());
      if (unknown.isNotEmpty) throw FormatException('Bodi ${b.id}: jenis muatan tidak dikenal $unknown');
    }
    final categoryIds = categories.map((c) => c.id).toSet();
    final models = _unique(
      (json['models'] as List).cast<Map<String, dynamic>>().map((j) {
        final c = chassis[j['chassis']];
        final b = bodies[j['body']];
        if (c == null || b == null) {
          throw FormatException('Model ${j['id']}: sasis/bodi tidak dikenal (${j['chassis']} + ${j['body']})');
        }
        return VehicleModel.fromJson(j, chassis: c, body: b);
      }),
      (m) => m.id,
      'model',
    );
    for (final m in models.values) {
      if (!categoryIds.contains(m.category)) throw FormatException('Model ${m.id}: kategori ${m.category}');
      final problem = compatibilityProblem(m.chassis, m.body);
      if (problem != null) throw FormatException('Model ${m.id}: $problem');
      if (m.payloadKg <= 0 || m.priceIdr <= 0 || m.lengthM <= 0) {
        throw FormatException('Model ${m.id}: muatan, harga, dan dimensi wajib > 0');
      }
    }
    return VehicleCatalog._(
      categories: categories,
      cargoKindNames: kinds,
      chassis: chassis,
      bodies: bodies,
      models: models,
    );
  }

  /// Alasan bodi tidak bisa dipasang pada sasis, atau `null` bila cocok.
  static String? compatibilityProblem(VehicleChassis chassis, VehicleBody body) {
    if (!body.mounts.contains(chassis.mount)) {
      return '${body.name} tidak bisa dipasang pada ${chassis.name}';
    }
    if (body.lengthM > chassis.bodyMaxM + 1e-9) {
      return '${body.name} (${body.lengthM} m) terlalu panjang untuk ${chassis.name} (maks ${chassis.bodyMaxM} m)';
    }
    return null;
  }

  static Map<String, T> _unique<T>(Iterable<T> items, String Function(T) id, String what) {
    final out = <String, T>{};
    for (final item in items) {
      if (out.containsKey(id(item))) throw FormatException('Id $what ganda: ${id(item)}');
      out[id(item)] = item;
    }
    return out;
  }

  final List<VehicleCategory> categories;
  final Map<String, String> cargoKindNames;
  final Map<String, VehicleChassis> chassis;
  final Map<String, VehicleBody> bodies;
  final Map<String, VehicleModel> models;
}
