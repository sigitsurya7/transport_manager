/// Jenis fasilitas depot. Urutan = urutan tampilan.
enum FacilityType {
  parking('parking'),
  gate('gate'),
  loadingDock('loading_dock'),
  workshop('workshop'),
  warehouse('warehouse'),
  office('office');

  const FacilityType(this.id);

  final String id;

  static FacilityType parse(String id) => FacilityType.values.firstWhere(
        (t) => t.id == id,
        orElse: () => throw FormatException('Fasilitas tidak dikenal: $id'),
      );
}

/// Satu level fasilitas: statistik, biaya, lama konstruksi, dan modul visual.
class FacilityLevel {
  const FacilityLevel({
    required this.level,
    required this.label,
    required this.model,
    required this.stats,
    this.costIdr = 0,
    this.buildMinutes = 0,
    int? tier,
  }) : tier = tier ?? level;

  /// 1-based.
  final int level;
  final String label;

  /// Nama modul GLB untuk renderer (statistik & visual dari data yang sama).
  final String model;
  final Map<String, num> stats;
  final int costIdr;
  /// Lama konstruksi (menit game).
  final int buildMinutes;

  /// Tahap visual (layout & modul 3D). Level dengan tier sama hanya menaikkan
  /// statistik; tier naik = tampilan berubah.
  final int tier;

  int intStat(String key) => (stats[key] ?? (throw StateError('Stat "$key" tidak ada di level $level'))).toInt();
  double doubleStat(String key) => (stats[key] ?? (throw StateError('Stat "$key" tidak ada di level $level'))).toDouble();
}

class FacilitySpec {
  const FacilitySpec({required this.type, required this.name, required this.levels});

  final FacilityType type;
  final String name;
  final List<FacilityLevel> levels;

  int get maxLevel => levels.length;
  FacilityLevel level(int level) => levels[level - 1];

  /// Upgrade ke [level] mengganti tampilan (tier visual berubah).
  bool changesLook(int level) => level > 1 && this.level(level).tier != this.level(level - 1).tier;
}

/// Katalog fasilitas (`content/facilities.json`).
class FacilityCatalog {
  FacilityCatalog(this._specs) {
    for (final t in FacilityType.values) {
      if (!_specs.containsKey(t)) throw FormatException('Fasilitas ${t.id} tidak didefinisikan');
    }
    _requireStat(FacilityType.parking, 'slots');
    _requireStat(FacilityType.gate, 'lanes');
    _requireStat(FacilityType.gate, 'pass_s');
    _requireStat(FacilityType.loadingDock, 'docks');
    _requireStat(FacilityType.loadingDock, 'speed');
    _requireStat(FacilityType.workshop, 'bays');
    _requireStat(FacilityType.workshop, 'speed');
    _requireStat(FacilityType.workshop, 'cost_factor');
    _requireStat(FacilityType.warehouse, 'capacity_m3');
    _requireStat(FacilityType.office, 'staff_max');
    for (final s in _specs.values) {
      for (var i = 1; i < s.levels.length; i++) {
        if (s.levels[i].costIdr <= 0 || s.levels[i].buildMinutes <= 0) {
          throw FormatException('${s.type.id} level ${i + 1}: biaya & lama konstruksi wajib');
        }
      }
    }
    for (final s in _specs.values) {
      for (var i = 1; i < s.levels.length; i++) {
        if (s.levels[i].tier < s.levels[i - 1].tier) {
          throw FormatException('${s.type.id} level ${i + 1}: tier visual tidak boleh turun');
        }
      }
    }
    final slots = _specs[FacilityType.parking]!.levels.map((l) => l.intStat('slots')).toList();
    for (var i = 1; i < slots.length; i++) {
      if (slots[i] < slots[i - 1]) throw const FormatException('Slot parkir tidak boleh berkurang saat upgrade');
    }
  }

  factory FacilityCatalog.fromJson(Map<String, dynamic> json) => FacilityCatalog({
        for (final raw in (json['facilities'] as List).cast<Map<String, dynamic>>())
          FacilityType.parse(raw['id'] as String): FacilitySpec(
            type: FacilityType.parse(raw['id'] as String),
            name: raw['name'] as String,
            levels: [
              for (final (i, l) in (raw['levels'] as List).cast<Map<String, dynamic>>().indexed)
                FacilityLevel(
                  level: i + 1,
                  label: l['label'] as String,
                  model: l['model'] as String,
                  costIdr: (l['cost_idr'] as num?)?.toInt() ?? 0,
                  buildMinutes: (l['build_minutes'] as num?)?.toInt() ?? 0,
                  tier: (l['tier'] as num?)?.toInt(),
                  stats: {
                    for (final e in l.entries)
                      if (e.value is num && !const {'cost_idr', 'build_minutes', 'tier'}.contains(e.key))
                        e.key: e.value as num,
                  },
                ),
            ],
          ),
      });

  final Map<FacilityType, FacilitySpec> _specs;

  FacilitySpec operator [](FacilityType type) => _specs[type]!;

  void _requireStat(FacilityType type, String key) {
    for (final l in _specs[type]!.levels) {
      if (!l.stats.containsKey(key)) throw FormatException('${type.id} level ${l.level}: stat "$key" wajib');
    }
  }
}
