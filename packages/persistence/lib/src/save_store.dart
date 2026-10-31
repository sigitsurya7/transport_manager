import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// Ringkasan satu save slot (untuk layar Load tanpa memuat seluruh dunia).
class SaveMeta {
  const SaveMeta({
    required this.slotId,
    required this.slotName,
    required this.companyName,
    required this.cityId,
    required this.depotSiteId,
    required this.mapPackId,
    required this.simTime,
    required this.cashIdr,
    required this.lastWallClockMs,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.lastMonotonicMs,
    this.bootId,
  });

  final int slotId;
  final String slotName;
  final String companyName;
  final String cityId;
  final String depotSiteId;
  final String mapPackId;

  /// Detik game.
  final int simTime;
  final int cashIdr;

  /// Jam dinding & monotonic saat terakhir disimpan (validasi waktu offline).
  final int lastWallClockMs;
  final int? lastMonotonicMs;
  final String? bootId;

  final int createdAtMs;
  final int updatedAtMs;

  SaveMeta copyWith({
    int? simTime,
    int? cashIdr,
    int? lastWallClockMs,
    int? lastMonotonicMs,
    String? bootId,
    int? updatedAtMs,
  }) =>
      SaveMeta(
        slotId: slotId,
        slotName: slotName,
        companyName: companyName,
        cityId: cityId,
        depotSiteId: depotSiteId,
        mapPackId: mapPackId,
        simTime: simTime ?? this.simTime,
        cashIdr: cashIdr ?? this.cashIdr,
        lastWallClockMs: lastWallClockMs ?? this.lastWallClockMs,
        lastMonotonicMs: lastMonotonicMs ?? this.lastMonotonicMs,
        bootId: bootId ?? this.bootId,
        createdAtMs: createdAtMs,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      );
}

/// Save tidak bisa dibuka (rusak atau dari versi game yang lebih baru).
class SaveException implements Exception {
  const SaveException(this.message);

  final String message;

  @override
  String toString() => 'SaveException: $message';
}

/// Penyimpanan save slot: **satu file SQLite per slot** (`slot_<id>.db`) di
/// [directory], sehingga backup, hapus, dan salin cukup operasi file.
///
/// Isi: tabel `save_meta` (satu baris) + `world_state` (dokumen JSON
/// `SimWorld`). Skema berversi lewat `PRAGMA user_version`; sebelum migrasi
/// file disalin ke `backups/`.
class SaveStore {
  SaveStore(this.directory) {
    directory.createSync(recursive: true);
  }

  static const schemaVersion = 1;
  static const _maxBackupsPerSlot = 3;

  final Directory directory;

  Directory get backupDirectory => Directory('${directory.path}/backups');

  File slotFile(int slotId) => File('${directory.path}/slot_$slotId.db');

  bool exists(int slotId) => slotFile(slotId).existsSync();

  /// Semua slot yang ada, terbaru lebih dulu. Slot rusak dilewati.
  List<SaveMeta> listSlots() {
    final metas = <SaveMeta>[];
    for (final f in directory.listSync().whereType<File>()) {
      final m = RegExp(r'slot_(\d+)\.db$').firstMatch(f.path.replaceAll('\\', '/'));
      if (m == null) continue;
      try {
        metas.add(readMeta(int.parse(m.group(1)!)));
      } on Object {
        // Slot rusak tidak boleh membuat layar Load gagal.
      }
    }
    metas.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    return metas;
  }

  int nextFreeSlotId() {
    var id = 1;
    while (exists(id)) {
      id++;
    }
    return id;
  }

  /// Tulis meta + dunia dalam satu transaksi (atomik: save lama tetap utuh
  /// bila proses mati di tengah jalan).
  void write(SaveMeta meta, Map<String, dynamic> world, {required int worldFormat}) {
    final db = _open(meta.slotId, create: true);
    try {
      db.execute('BEGIN IMMEDIATE');
      try {
        db.execute('DELETE FROM save_meta');
        db.execute(
          'INSERT INTO save_meta (id, slot_name, company_name, city_id, depot_site_id, map_pack_id, '
          'sim_time, cash_idr, last_wall_clock_ms, last_monotonic_ms, boot_id, created_at_ms, updated_at_ms) '
          'VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            meta.slotName,
            meta.companyName,
            meta.cityId,
            meta.depotSiteId,
            meta.mapPackId,
            meta.simTime,
            meta.cashIdr,
            meta.lastWallClockMs,
            meta.lastMonotonicMs,
            meta.bootId,
            meta.createdAtMs,
            meta.updatedAtMs,
          ],
        );
        db.execute('DELETE FROM world_state');
        db.execute(
          'INSERT INTO world_state (id, format, json) VALUES (1, ?, ?)',
          [worldFormat, jsonEncode(world)],
        );
        db.execute('COMMIT');
      } on Object {
        db.execute('ROLLBACK');
        rethrow;
      }
    } finally {
      db.close();
    }
  }

  SaveMeta readMeta(int slotId) {
    final db = _open(slotId);
    try {
      return _meta(slotId, db);
    } finally {
      db.close();
    }
  }

  /// Meta + dokumen dunia (JSON) + versi format dunia.
  ({SaveMeta meta, Map<String, dynamic> world, int worldFormat}) read(int slotId) {
    final db = _open(slotId);
    try {
      final rows = db.select('SELECT format, json FROM world_state WHERE id = 1');
      if (rows.isEmpty) throw SaveException('Slot $slotId tidak berisi data dunia');
      return (
        meta: _meta(slotId, db),
        world: jsonDecode(rows.first['json'] as String) as Map<String, dynamic>,
        worldFormat: rows.first['format'] as int,
      );
    } finally {
      db.close();
    }
  }

  void delete(int slotId) {
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final f = File('${slotFile(slotId).path}$suffix');
      if (f.existsSync()) f.deleteSync();
    }
  }

  /// Salin slot ke `backups/`, simpan maksimal tiga cadangan terbaru per slot.
  File backup(int slotId, {DateTime? now}) {
    final src = slotFile(slotId);
    if (!src.existsSync()) throw SaveException('Slot $slotId tidak ada');
    backupDirectory.createSync(recursive: true);
    final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final dest = src.copySync('${backupDirectory.path}/slot_${slotId}_$stamp.db');
    final old = backupDirectory
        .listSync()
        .whereType<File>()
        .where((f) => RegExp('slot_${slotId}_\\d+\\.db\$').hasMatch(f.path.replaceAll('\\', '/')))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final f in old.skip(_maxBackupsPerSlot)) {
      f.deleteSync();
    }
    return dest;
  }

  // ------------------------------------------------------------------ intern

  Database _open(int slotId, {bool create = false}) {
    final file = slotFile(slotId);
    if (!create && !file.existsSync()) throw SaveException('Slot $slotId tidak ada');
    var db = sqlite3.open(file.path);
    try {
      final version = db.select('PRAGMA user_version').first.values.first as int;
      if (version > schemaVersion) {
        throw SaveException('Save dibuat oleh versi game yang lebih baru (skema $version)');
      }
      if (version < schemaVersion) {
        if (version > 0) {
          // Save lama dari versi game sebelumnya: cadangkan dulu sebelum diubah.
          db.close();
          backup(slotId);
          db = sqlite3.open(file.path);
        }
        _migrate(db, from: version);
      }
      return db;
    } on Object {
      db.close();
      rethrow;
    }
  }

  void _migrate(Database db, {required int from}) {
    db.execute('BEGIN');
    if (from < 1) {
      db.execute('''
        CREATE TABLE save_meta (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          slot_name TEXT NOT NULL,
          company_name TEXT NOT NULL,
          city_id TEXT NOT NULL,
          depot_site_id TEXT NOT NULL,
          map_pack_id TEXT NOT NULL,
          sim_time INTEGER NOT NULL,
          cash_idr INTEGER NOT NULL,
          last_wall_clock_ms INTEGER NOT NULL,
          last_monotonic_ms INTEGER,
          boot_id TEXT,
          created_at_ms INTEGER NOT NULL,
          updated_at_ms INTEGER NOT NULL
        )''');
      db.execute('''
        CREATE TABLE world_state (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          format INTEGER NOT NULL,
          json TEXT NOT NULL
        )''');
    }
    // Migrasi versi berikutnya ditambahkan di sini: if (from < 2) { ... }
    db.execute('PRAGMA user_version = $schemaVersion');
    db.execute('COMMIT');
  }

  SaveMeta _meta(int slotId, Database db) {
    final rows = db.select('SELECT * FROM save_meta WHERE id = 1');
    if (rows.isEmpty) throw SaveException('Slot $slotId tidak berisi meta');
    final r = rows.first;
    return SaveMeta(
      slotId: slotId,
      slotName: r['slot_name'] as String,
      companyName: r['company_name'] as String,
      cityId: r['city_id'] as String,
      depotSiteId: r['depot_site_id'] as String,
      mapPackId: r['map_pack_id'] as String,
      simTime: r['sim_time'] as int,
      cashIdr: r['cash_idr'] as int,
      lastWallClockMs: r['last_wall_clock_ms'] as int,
      lastMonotonicMs: r['last_monotonic_ms'] as int?,
      bootId: r['boot_id'] as String?,
      createdAtMs: r['created_at_ms'] as int,
      updatedAtMs: r['updated_at_ms'] as int,
    );
  }
}
