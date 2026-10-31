import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:persistence/persistence.dart';
import 'package:sim_core/sim_core.dart';
import 'package:transport_manager/data/game_data.dart';
import 'package:transport_manager/game/game_session.dart';

/// Integrasi dengan aset nyata: konten, data kota, dan graph jalan Bandung.
/// Paket peta tidak di-commit; tanpa paket Bandung test perjalanan di-skip.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bandungPack = File('assets/packs/bandung.graph.json').existsSync();

  late Directory dir;
  late SaveStore store;
  late GameData data;

  setUpAll(() async {
    data = await GameData.load(rootBundle);
  });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tm_saves_');
    store = SaveStore(dir);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('hanya kota dengan paket peta yang bisa dipilih', () {
    final jawa = data.countries.single.regions.first;
    expect(jawa.cities, hasLength(6));
    for (final c in jawa.cities) {
      expect(c.hasMapPack, File('assets/packs/${c.id}.graph.json').existsSync(), reason: c.id);
    }
    expect(data.countries.single.regions.where((r) => !r.available), isNotEmpty);
  });

  test('game baru di Bandung → kontrak → pengiriman penuh → save → load', skip: !bandungPack, () async {
    final city = data.city('bandung');
    final graph = await data.graph(rootBundle, city.id);
    final session = await GameSession.newGame(
      data: data,
      store: store,
      graph: graph,
      city: city,
      site: city.depotSites.first,
      companyName: 'PT Uji Bandung',
    );
    expect(session.offers, hasLength(GameSession.offerCount));
    expect(store.listSlots().single.companyName, 'PT Uji Bandung');

    final world = session.world;
    final vehicle = world.vehicles.values.single;
    final driver = world.drivers.values.single;
    final offer = session.offers.first;
    final check = session.check(offer, vehicle, driver);
    expect(check.problems, isEmpty);
    final quote = check.nonToll ?? check.viaToll!;
    final cashBefore = world.cashIdr;

    session.dispatch(offer, vehicle, driver, quote.mode);
    world.advanceTo(quote.completionEta);
    expect(world.contracts[offer.id]!.status, ContractStatus.delivered);
    expect(world.cashIdr, cashBefore + quote.profitIdr);
    expect(vehicle.odometerM, greaterThan(0));
    await session.save();

    final loaded = await GameSession.load(data: data, store: store, bundle: rootBundle, slotId: session.meta.slotId);
    expect(loaded.world.cashIdr, world.cashIdr);
    expect(loaded.world.vehicles.values.single.odometerM, vehicle.odometerM);
    expect(loaded.world.contracts[offer.id]!.status, ContractStatus.delivered);
    session.dispose();
    loaded.dispose();
  });
}
