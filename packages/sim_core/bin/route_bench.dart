// Benchmark routing Tahap 2a.
//
// Pakai:
//   dart run bin/route_bench.dart <graph.json> [--cities ../../tools/map_pipeline/data/id-jawa.cities.json] [--pairs 200]
//
// - Rute acak: waktu A* (rata-rata, p95, maks) untuk mode tol dan non-tol.
// - --cities: rute antar ibu kota yang ada di dalam graph (tol vs non-tol).
//
// Jalankan juga dengan `dart compile exe` untuk angka yang mendekati AOT di HP.
import 'dart:convert';
import 'dart:io';

import 'package:sim_core/sim_core.dart';

const profiles = {
  'pikap': VehicleProfile(
      vehicleClass: VehicleClass.pickupBox, maxSpeedKmh: 80, grossWeightT: 2.5, tollGolongan: 1),
  'mini-truck': VehicleProfile(
      vehicleClass: VehicleClass.miniTruck, maxSpeedKmh: 80, grossWeightT: 5, tollGolongan: 1),
};

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Pakai: dart run bin/route_bench.dart <graph.json> [--cities file] [--pairs N]');
    exit(64);
  }
  String? citiesPath;
  var pairs = 200;
  for (var i = 1; i < args.length; i++) {
    if (args[i] == '--cities') citiesPath = args[++i];
    if (args[i] == '--pairs') pairs = int.parse(args[++i]);
  }

  final load = Stopwatch()..start();
  final graph = RoadGraph.fromJson(
      jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>);
  load.stop();
  stdout.writeln('Graph: ${graph.nodeCount} node, ${graph.edgeCount} edge, '
      'load ${load.elapsedMilliseconds} ms');

  final planner = RoutePlanner(graph);
  final rng = DeterministicRng(2026);

  for (final mode in RouteMode.values) {
    final times = <int>[];
    var found = 0;
    for (var i = 0; i < pairs; i++) {
      final a = rng.nextInt(graph.nodeCount);
      final b = rng.nextInt(graph.nodeCount);
      final sw = Stopwatch()..start();
      final r = planner.find(a, b, profiles['pikap']!, mode);
      sw.stop();
      times.add(sw.elapsedMicroseconds);
      if (r != null) found++;
    }
    times.sort();
    final avg = times.reduce((a, b) => a + b) / times.length / 1000;
    final p95 = times[(times.length * 0.95).floor().clamp(0, times.length - 1)] / 1000;
    stdout.writeln('${mode.name.padRight(7)} acak: $pairs pasang, $found terjangkau, '
        'rata ${avg.toStringAsFixed(1)} ms, p95 ${p95.toStringAsFixed(1)} ms, '
        'maks ${(times.last / 1000).toStringAsFixed(1)} ms');
  }

  if (citiesPath == null) return;
  final cities = (jsonDecode(File(citiesPath).readAsStringSync()) as Map)['cities'] as List;
  final inGraph = <String, int>{};
  for (final c in cities) {
    final center = (c as Map)['center'] as List;
    final p = LatLng((center[0] as num).toDouble(), (center[1] as num).toDouble());
    final node = graph.nearestNode(p);
    if (haversineMeters(p, graph.node(node)) < 3000) inGraph[c['name'] as String] = node;
  }
  stdout.writeln('\nIbu kota dalam graph: ${inGraph.keys.join(', ')}');
  final names = inGraph.keys.toList();
  final truck = profiles['mini-truck']!;
  for (var i = 0; i < names.length; i++) {
    for (var j = i + 1; j < names.length; j++) {
      final sw = Stopwatch()..start();
      final o = planner.options(inGraph[names[i]]!, inGraph[names[j]]!, truck);
      sw.stop();
      String fmt(Route? r) => r == null
          ? 'tidak terjangkau'
          : '${(r.distanceM / 1000).toStringAsFixed(1)} km, '
              '${(r.durationS / 3600).toStringAsFixed(2)} j game '
              '(${(r.durationS / const TimeConfig().timeScale / 60).toStringAsFixed(1)} mnt nyata), '
              'tol Rp${r.tollCostIdr}';
      stdout.writeln('${names[i]} → ${names[j]} [${sw.elapsedMilliseconds} ms]\n'
          '  tol    : ${fmt(o.viaToll)}\n  non-tol: ${fmt(o.nonToll)}');
    }
  }
}
