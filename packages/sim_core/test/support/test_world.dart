import 'dart:convert';
import 'dart:io';

import 'package:sim_core/sim_core.dart';

GameContent loadContent() => GameContent.fromJsonFiles({
      for (final name in GameContent.fileNames)
        name: jsonDecode(File('../../content/$name').readAsStringSync()) as Map<String, dynamic>,
    });

/// Grid [size]×[size] berjarak ±1 km di sekitar Jakarta. Semua ruas jalan
/// biasa 40 km/h dua arah; baris 0 juga punya ruas tol 100 km/h sejajar.
RoadGraph gridGraph({int size = 8}) {
  const step = 0.009; // ±1 km
  final nodes = <LatLng>[
    for (var r = 0; r < size; r++)
      for (var c = 0; c < size; c++) LatLng(-6.2 + r * step, 106.8 + c * step),
  ];
  final edges = <RoadEdge>[];
  void link(int a, int b, {bool toll = false}) {
    for (final (from, to) in [(a, b), (b, a)]) {
      edges.add(RoadEdge(
        id: edges.length,
        from: from,
        to: to,
        lengthM: haversineMeters(nodes[from], nodes[to]),
        roadClass: toll ? RoadClass.motorway : RoadClass.secondary,
        maxSpeedKmh: toll ? 100 : 40,
        isToll: toll,
      ));
    }
  }

  for (var r = 0; r < size; r++) {
    for (var c = 0; c < size; c++) {
      final i = r * size + c;
      if (c + 1 < size) link(i, i + 1);
      if (r + 1 < size) link(i, i + size);
    }
  }
  for (var c = 0; c + 1 < size; c++) {
    link(c, c + 1, toll: true);
  }
  return RoadGraph(nodes: nodes, edges: edges);
}

SimWorld newWorld({RoadGraph? graph, int seed = 42, int depotNode = 0}) => SimWorld.newGame(
      graph: graph ?? gridGraph(),
      content: loadContent(),
      seed: seed,
      companyName: 'PT Uji Logistik',
      cityId: 'jakarta',
      depotName: 'Depot Uji',
      depotNode: depotNode,
      starterVehicleModelId: 'pickup_box_1t',
      driverName: 'Budi',
    );

/// Tambah kontrak manual (tujuan & jangkauan ditentukan test).
Contract addContract(
  SimWorld world, {
  required int destinationNode,
  int weightKg = 500,
  DeliveryScope scope = DeliveryScope.storeToStore,
  int payIdr = 300000,
  int allowedS = 4 * 3600,
}) {
  final id = 1000 + world.contracts.length;
  return world.contracts[id] = Contract(
    id: id,
    customer: 'Toko Uji',
    cargoId: 'beras_25',
    units: weightKg ~/ 25,
    weightKg: weightKg,
    destinationNode: destinationNode,
    destinationName: 'Toko Uji',
    scope: scope,
    payIdr: payIdr,
    offeredAt: world.now,
    allowedS: allowedS,
    latePenaltyPerHourIdr: payIdr ~/ 10,
  );
}

/// Naikkan fasilitas sampai [level] (menunggu tiap konstruksi selesai).
void upgradeTo(SimWorld world, FacilityType type, int level, {int depotId = 1}) {
  while (world.depots[depotId]!.level(type) < level) {
    world.advanceTo(world.startUpgrade(depotId, type).finishAt);
  }
}

/// Level pertama di mana stat [stat] fasilitas mencapai [value].
int levelWith(SimWorld world, FacilityType type, String stat, num value) {
  final spec = world.content.facilities[type];
  for (var l = 1; l <= spec.maxLevel; l++) {
    if ((spec.level(l).stats[stat] ?? 0) >= value) return l;
  }
  throw StateError('Tidak ada level ${type.id} dengan $stat >= $value');
}

const vehicleId = 2;
const driverId = 3;
