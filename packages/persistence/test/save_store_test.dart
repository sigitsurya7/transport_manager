import 'dart:io';

import 'package:persistence/persistence.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

SaveMeta meta(int slot, {int updated = 1000, int simTime = 3600}) => SaveMeta(
      slotId: slot,
      slotName: 'Slot $slot',
      companyName: 'PT Uji',
      cityId: 'bandung',
      depotSiteId: 'bandung-gedebage',
      mapPackId: 'id-jawa',
      simTime: simTime,
      cashIdr: 50000000,
      lastWallClockMs: 1700000000000,
      lastMonotonicMs: 123456,
      bootId: 'boot-a',
      createdAtMs: 900,
      updatedAtMs: updated,
    );

void main() {
  late Directory dir;
  late SaveStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('saves_');
    store = SaveStore(dir);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('tulis lalu baca kembali meta & dunia', () {
    final world = {
      'format': 1,
      'now': 3600,
      'trips': [
        {'id': 5, 'phase': 'outbound'},
      ],
    };
    store.write(meta(1), world, worldFormat: 1);
    final r = store.read(1);
    expect(r.world, world);
    expect(r.worldFormat, 1);
    expect(r.meta.companyName, 'PT Uji');
    expect(r.meta.lastMonotonicMs, 123456);
    expect(r.meta.bootId, 'boot-a');
  });

  test('menimpa save yang ada (autosave berulang)', () {
    store.write(meta(1, simTime: 10), {'now': 10}, worldFormat: 1);
    store.write(meta(1, simTime: 20), {'now': 20}, worldFormat: 1);
    expect(store.read(1).world['now'], 20);
    expect(store.readMeta(1).simTime, 20);
  });

  test('daftar slot terurut terbaru, slot kosong berikutnya, hapus', () {
    store.write(meta(1, updated: 100), {}, worldFormat: 1);
    store.write(meta(2, updated: 300), {}, worldFormat: 1);
    store.write(meta(3, updated: 200), {}, worldFormat: 1);
    expect(store.listSlots().map((m) => m.slotId), [2, 3, 1]);
    store.delete(2);
    expect(store.listSlots().map((m) => m.slotId), [3, 1]);
    expect(store.nextFreeSlotId(), 2);
  });

  test('slot rusak dilewati di daftar, tetapi gagal dibaca dengan jelas', () {
    store.write(meta(1), {}, worldFormat: 1);
    File('${dir.path}/slot_2.db').writeAsStringSync('bukan sqlite');
    expect(store.listSlots().map((m) => m.slotId), [1]);
    expect(() => store.read(2), throwsA(anything));
  });

  test('save dari versi game lebih baru ditolak', () {
    store.write(meta(1), {}, worldFormat: 1);
    final db = sqlite3.open(store.slotFile(1).path);
    db.execute('PRAGMA user_version = ${SaveStore.schemaVersion + 1}');
    db.close();
    expect(() => store.read(1), throwsA(isA<SaveException>()));
  });

  test('backup menyimpan maksimal tiga salinan terbaru', () {
    store.write(meta(1), {'now': 1}, worldFormat: 1);
    for (var i = 0; i < 5; i++) {
      store.backup(1, now: DateTime.fromMillisecondsSinceEpoch(1000 + i));
    }
    final backups = store.backupDirectory.listSync().whereType<File>().toList();
    expect(backups, hasLength(3));
  });

  test('baca slot yang tidak ada → SaveException', () {
    expect(() => store.read(9), throwsA(isA<SaveException>()));
  });
}
