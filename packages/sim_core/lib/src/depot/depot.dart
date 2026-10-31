import 'facilities.dart';

/// Upgrade fasilitas yang sedang dibangun. Selama konstruksi fasilitas tetap
/// beroperasi pada level lama.
class FacilityConstruction {
  const FacilityConstruction({
    required this.type,
    required this.toLevel,
    required this.startedAt,
    required this.finishAt,
  });

  final FacilityType type;
  final int toLevel;
  final int startedAt;
  final int finishAt;

  Map<String, dynamic> toJson() =>
      {'type': type.id, 'to_level': toLevel, 'started_at': startedAt, 'finish_at': finishAt};

  factory FacilityConstruction.fromJson(Map<String, dynamic> j) => FacilityConstruction(
        type: FacilityType.parse(j['type'] as String),
        toLevel: j['to_level'] as int,
        startedAt: j['started_at'] as int,
        finishAt: j['finish_at'] as int,
      );
}

/// Depot perusahaan: fasilitas ber-level, slot parkir, staf gudang.
class Depot {
  Depot({
    required this.id,
    required this.name,
    required this.cityId,
    required this.roadNode,
    required int parkingSlots,
    List<int?>? slots,
    Map<FacilityType, int>? levels,
    this.construction,
    this.warehouseStaff = 0,
  })  : slots = slots ?? List<int?>.filled(parkingSlots, null, growable: true),
        levels = levels ?? {for (final t in FacilityType.values) t: 1} {
    if (this.slots.length != parkingSlots) {
      throw ArgumentError('Jumlah slot tidak cocok: ${this.slots.length} ≠ $parkingSlots');
    }
  }

  final int id;
  final String name;
  final String cityId;

  /// Node graph jalan terdekat dengan gerbang depot.
  final int roadNode;

  /// Isi tiap slot parkir: id kendaraan atau `null` bila kosong.
  final List<int?> slots;

  /// Level tiap fasilitas (1-based).
  final Map<FacilityType, int> levels;

  FacilityConstruction? construction;

  int warehouseStaff;

  int get parkingSlots => slots.length;

  int level(FacilityType type) => levels[type]!;

  int? get firstFreeSlot {
    final i = slots.indexOf(null);
    return i < 0 ? null : i;
  }

  /// Tambah slot kosong sampai [count] (upgrade parkir).
  void growSlots(int count) {
    while (slots.length < count) {
      slots.add(null);
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'city': cityId,
        'road_node': roadNode,
        'slots': slots,
        'levels': {for (final e in levels.entries) e.key.id: e.value},
        'construction': construction?.toJson(),
        'warehouse_staff': warehouseStaff,
      };

  /// Save format 1 belum punya level/staf: semua fasilitas level 1.
  factory Depot.fromJson(Map<String, dynamic> j) {
    final slots = (j['slots'] as List).cast<int?>();
    final rawLevels = (j['levels'] as Map?)?.cast<String, int>() ?? const {};
    return Depot(
      id: j['id'] as int,
      name: j['name'] as String,
      cityId: j['city'] as String,
      roadNode: j['road_node'] as int,
      parkingSlots: slots.length,
      slots: List.of(slots, growable: true),
      levels: {for (final t in FacilityType.values) t: rawLevels[t.id] ?? 1},
      construction: j['construction'] == null
          ? null
          : FacilityConstruction.fromJson(j['construction'] as Map<String, dynamic>),
      warehouseStaff: j['warehouse_staff'] as int? ?? 0,
    );
  }
}
