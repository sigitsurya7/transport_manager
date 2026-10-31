import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sim_core/sim_core.dart';

class DepotSite {
  const DepotSite({required this.id, required this.name, required this.position});

  final String id;
  final String name;
  final LatLng position;
}

class City {
  const City({
    required this.id,
    required this.name,
    required this.province,
    required this.center,
    required this.depotSites,
    required this.hasMapPack,
  });

  final String id;
  final String name;
  final String province;
  final LatLng center;
  final List<DepotSite> depotSites;

  /// Hanya kota dengan paket peta lokal yang boleh dipilih.
  final bool hasMapPack;
}

class Region {
  const Region({required this.id, required this.name, required this.mapPackId, required this.cities});

  final String id;
  final String name;
  final String mapPackId;
  final List<City> cities;

  bool get available => cities.any((c) => c.hasMapPack);
}

class Country {
  const Country({required this.id, required this.name, required this.regions});

  final String id;
  final String name;
  final List<Region> regions;
}

/// Data statis game: konten, daftar negara/wilayah/kota, paket peta.
/// Dimuat sekali dari aset; graph kota dimuat saat dibutuhkan lalu di-cache.
class GameData {
  GameData._(this.content, this.countries);

  final GameContent content;
  final List<Country> countries;
  final Map<String, RoadGraph> _graphs = {};

  static Future<GameData> load(AssetBundle bundle) async {
    Future<Map<String, dynamic>> json(String path) async =>
        jsonDecode(await bundle.loadString(path)) as Map<String, dynamic>;

    final content = GameContent.fromJsonFiles({
      for (final name in GameContent.fileNames) name: await json('assets/content/$name'),
    });
    final packs = ((await json('assets/data/packs.json'))['cities'] as List).cast<String>().toSet();
    final c = await json('assets/data/cities.json');
    final region = c['region'] as Map<String, dynamic>;
    final cities = [
      for (final raw in (c['cities'] as List).cast<Map<String, dynamic>>())
        City(
          id: raw['id'] as String,
          name: raw['name'] as String,
          province: raw['province'] as String,
          center: _latLng(raw['center']),
          hasMapPack: packs.contains(raw['id']),
          depotSites: [
            for (final s in (raw['depot_sites'] as List).cast<Map<String, dynamic>>())
              DepotSite(id: s['id'] as String, name: s['name'] as String, position: _latLng(s['approx'])),
          ],
        ),
    ];
    // Wilayah lain ditampilkan tetapi terkunci sampai paket petanya ada.
    const lockedRegions = ['Sumatra', 'Kalimantan', 'Sulawesi', 'Bali dan Nusa Tenggara', 'Papua'];
    final country = Country(
      id: (c['country'] as Map)['id'] as String,
      name: (c['country'] as Map)['name'] as String,
      regions: [
        Region(
          id: region['id'] as String,
          name: region['name'] as String,
          mapPackId: region['map_pack'] as String,
          cities: cities,
        ),
        for (final name in lockedRegions) Region(id: 'locked-$name', name: name, mapPackId: '', cities: const []),
      ],
    );
    return GameData._(content, [country]);
  }

  City city(String id) => countries
      .expand((c) => c.regions)
      .expand((r) => r.cities)
      .firstWhere((c) => c.id == id, orElse: () => throw ArgumentError.value(id, 'cityId'));

  Region regionOf(String cityId) =>
      countries.expand((c) => c.regions).firstWhere((r) => r.cities.any((c) => c.id == cityId));

  Future<RoadGraph> graph(AssetBundle bundle, String cityId) async {
    final cached = _graphs[cityId];
    if (cached != null) return cached;
    final text = await bundle.loadString('assets/packs/$cityId.graph.json');
    // Parsing graph berukuran MB di isolate agar UI tidak tersendat.
    final graph = RoadGraph.fromJson(await compute((String t) => jsonDecode(t) as Map<String, dynamic>, text));
    return _graphs[cityId] = graph;
  }

  static LatLng _latLng(Object? v) {
    final l = (v as List).cast<num>();
    return LatLng(l[0].toDouble(), l[1].toDouble());
  }
}
