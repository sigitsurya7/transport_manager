import 'dart:math' as math;

import '../contracts/contract.dart';
import '../contracts/contract_tiers.dart';
import '../depot/depot.dart';
import '../employees/driver.dart';
import '../engine/deterministic_rng.dart';
import '../engine/event_queue.dart';
import '../finance/ledger.dart';
import '../routing/geo.dart';
import '../routing/road_graph.dart';
import '../routing/route_planner.dart';
import '../trips/dispatch.dart';
import '../trips/route_track.dart';
import '../trips/travel_time_model.dart';
import '../trips/trip.dart';
import '../vehicle/vehicle.dart';
import '../vehicle/vehicle_profile.dart';
import 'game_content.dart';
import 'world_log.dart';

/// Akhir satu fase trip.
class TripPhaseEnded extends SimEvent {
  const TripPhaseEnded(this.tripId, this.phase);

  static const typeName = 'trip_phase_ended';

  final int tripId;
  final TripPhase phase;

  @override
  String get type => typeName;

  Map<String, dynamic> toJson() => {'trip': tripId, 'phase': phase.name};

  factory TripPhaseEnded.fromJson(Map<String, dynamic> j) =>
      TripPhaseEnded(j['trip'] as int, TripPhase.values.byName(j['phase'] as String));
}

enum VehicleActivity {
  /// Diam di slot parkir, siap dipakai.
  parked,

  /// Bergerak / bekerja di dalam depot (ke dock, muat, gerbang, parkir, inspeksi).
  inDepot,

  /// Di jalan.
  onRoad,

  /// Bongkar muat di lokasi pelanggan.
  atDestination,
}

/// Keadaan kendaraan pada satu waktu, untuk renderer & UI (read-only).
class VehicleSnapshot {
  const VehicleSnapshot({
    required this.vehicleId,
    required this.activity,
    required this.slotIndex,
    this.tripId,
    this.phase,
    this.phaseProgress = 0,
    this.pose,
  });

  final int vehicleId;
  final VehicleActivity activity;
  final int slotIndex;
  final int? tripId;
  final TripPhase? phase;

  /// 0..1 di dalam fase saat ini.
  final double phaseProgress;

  /// Posisi geografis saat di jalan atau di lokasi pelanggan.
  final TrackPose? pose;
}

/// Dunia simulasi satu save: state perusahaan + antrean event.
///
/// Satu-satunya sumber kebenaran. UI memanggil perintah ([check],
/// [dispatch], [offerStoreContract]) dan membaca snapshot; waktu maju lewat
/// [advanceTo] (dipakai sama persis saat bermain aktif maupun catch-up offline).
class SimWorld {
  SimWorld._({
    required this.graph,
    required this.content,
    required this.travelTime,
    required this.seed,
    required this.companyName,
    required this.queue,
    required this.ledger,
    required this.depots,
    required this.vehicles,
    required this.drivers,
    required this.contracts,
    required this.trips,
    required this.log,
    required int nextId,
  })  : planner = RoutePlanner(graph),
        _nextId = nextId;

  /// Perusahaan baru: satu depot, satu kendaraan di slot 0, satu sopir,
  /// modal awal dari `economy.json`.
  factory SimWorld.newGame({
    required RoadGraph graph,
    required GameContent content,
    required int seed,
    required String companyName,
    required String cityId,
    required String depotName,
    required int depotNode,
    required String starterVehicleModelId,
    required String driverName,
    int parkingSlots = 3,
    int startTime = 0,
    TravelTimeModel travelTime = const RouteEstimateTravelTime(),
  }) {
    final model = content.vehicleModels[starterVehicleModelId];
    if (model == null) throw ArgumentError.value(starterVehicleModelId, 'starterVehicleModelId');
    if (depotNode < 0 || depotNode >= graph.nodeCount) {
      throw ArgumentError.value(depotNode, 'depotNode', 'di luar graph');
    }
    const depotId = 1, vehicleId = 2, driverId = 3;
    final depot = Depot(
      id: depotId,
      name: depotName,
      cityId: cityId,
      roadNode: depotNode,
      parkingSlots: parkingSlots,
    )..slots[0] = vehicleId;
    final world = SimWorld._(
      graph: graph,
      content: content,
      travelTime: travelTime,
      seed: seed,
      companyName: companyName,
      queue: EventQueue(processedUntil: startTime),
      ledger: Ledger([
        LedgerEntry(
          time: startTime,
          account: LedgerAccount.openingBalance,
          amountIdr: content.economy.startingCashIdr,
          ref: 'company',
        ),
      ]),
      depots: {depotId: depot},
      vehicles: {
        vehicleId: Vehicle(id: vehicleId, model: model, depotId: depotId, slotIndex: 0),
      },
      drivers: {driverId: Driver(id: driverId, name: driverName, depotId: depotId)},
      contracts: {},
      trips: {},
      log: [],
      nextId: 4,
    );
    return world;
  }

  final RoadGraph graph;
  final GameContent content;
  final TravelTimeModel travelTime;
  final RoutePlanner planner;
  final int seed;
  final String companyName;
  final EventQueue queue;
  final Ledger ledger;
  final Map<int, Depot> depots;
  final Map<int, Vehicle> vehicles;
  final Map<int, Driver> drivers;
  final Map<int, Contract> contracts;
  final Map<int, Trip> trips;
  final List<WorldLogEntry> log;
  int _nextId;

  final Map<(int, bool), RouteTrack> _tracks = {};

  /// Waktu simulasi saat ini (detik game).
  int get now => queue.processedUntil;

  int get cashIdr => ledger.cashIdr;

  // ---------------------------------------------------------------- kontrak

  /// Buat tawaran kontrak toko ke toko dari [depotId] dengan tujuan acak
  /// (deterministik dari seed) berjarak [minKm]–[maxKm] garis lurus. Muatan
  /// diatur agar muat di kendaraan berkapasitas [capacityKg].
  /// `null` bila tidak ada tujuan yang terjangkau.
  Contract? offerStoreContract({
    required int depotId,
    required int capacityKg,
    double minKm = 2,
    double maxKm = 10,
    int maxAttempts = 300,
  }) {
    final depot = _depot(depotId);
    final id = _nextId++;
    final rng = DeterministicRng.derive(seed, id, 0);
    final origin = graph.node(depot.roadNode);

    final cargoIds = content.cargoTypes.keys.toList()..sort();
    final cargo = content.cargoTypes[cargoIds[rng.nextInt(cargoIds.length)]]!;
    final targetKg = capacityKg * (0.4 + 0.5 * rng.nextDouble());
    final units = math.max(1, targetKg ~/ cargo.unitWeightKg);
    final weightKg = units * cargo.unitWeightKg;

    // Profil acuan untuk memastikan tujuan terjangkau pergi-pulang.
    final reference = VehicleProfile(
      vehicleClass: content.tierRules.tierFor(DeliveryScope.storeToStore).minVehicleClass,
      maxSpeedKmh: 80,
      grossWeightT: 1.5 + weightKg / 1000,
      tollGolongan: 1,
    );

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final dest = rng.nextInt(graph.nodeCount);
      final km = haversineMeters(origin, graph.node(dest)) / 1000;
      if (km < minKm || km > maxKm) continue;
      final out = planner.find(depot.roadNode, dest, reference, RouteMode.nonToll) ??
          planner.find(depot.roadNode, dest, reference, RouteMode.toll);
      final back = planner.find(dest, depot.roadNode, reference, RouteMode.toll);
      if (out == null || back == null) continue;

      final eco = content.economy;
      final routeKm = out.distanceM / 1000;
      final pay = eco.contractBaseFeeIdr +
          (eco.contractPerKmIdr * routeKm).round() +
          (eco.contractPerTonKmIdr * weightKg / 1000 * routeKm).round();
      final ops = content.depotOps;
      final estimate = ops.slotToDockS +
          ops.loadingS(weightKg) +
          ops.dockToGateS +
          travelTime.legSeconds(out, reference) +
          ops.unloadingS(weightKg);
      final allowed = math.max(eco.deadlineMinS, (estimate * eco.deadlineSlack).round());
      final customer = content.storeCustomers[rng.nextInt(content.storeCustomers.length)];

      final contract = Contract(
        id: id,
        customer: customer,
        cargoId: cargo.id,
        units: units,
        weightKg: weightKg,
        destinationNode: dest,
        destinationName: customer,
        scope: content.tierRules.classify(sameCity: true, distanceKm: routeKm),
        payIdr: pay,
        offeredAt: now,
        allowedS: allowed,
        latePenaltyPerHourIdr: (pay * eco.latePenaltyPerHourPct / 100).round(),
      );
      contracts[id] = contract;
      _log(WorldLogKind.contractOffered, {'contract': id});
      return contract;
    }
    return null;
  }

  // ---------------------------------------------------------------- dispatch

  /// Periksa kelayakan & hitung estimasi tol / non-tol tanpa mengubah state.
  DispatchCheck check({required int contractId, required int vehicleId, required int driverId}) {
    final contract = _contract(contractId);
    final vehicle = _vehicle(vehicleId);
    final driver = _driver(driverId);
    final problems = <DispatchProblem>[
      if (contract.status != ContractStatus.offered) DispatchProblem.contractNotOffered,
      if (!vehicle.isAvailable) DispatchProblem.vehicleBusy,
      if (!driver.isAvailable) DispatchProblem.driverBusy,
      if (!content.tierRules.canDispatch(contract.scope, vehicle.model.vehicleClass))
        DispatchProblem.vehicleClassTooSmall,
      if (contract.weightKg > vehicle.model.payloadKg) DispatchProblem.overCapacity,
    ];
    final viaToll = _quote(contract, vehicle, RouteMode.toll);
    final nonToll = _quote(contract, vehicle, RouteMode.nonToll);
    if (viaToll == null && nonToll == null) problems.add(DispatchProblem.noRoute);
    return DispatchCheck(problems: problems, viaToll: viaToll, nonToll: nonToll);
  }

  /// Terima kontrak dan berangkatkan kendaraan + sopir dengan rute [mode].
  Trip dispatch({
    required int contractId,
    required int vehicleId,
    required int driverId,
    required RouteMode mode,
  }) {
    final result = check(contractId: contractId, vehicleId: vehicleId, driverId: driverId);
    if (!result.canDispatch) throw DispatchException(result.problems);
    final quote = result.quote(mode);
    if (quote == null) throw const DispatchException([DispatchProblem.noRoute]);

    final contract = _contract(contractId);
    final vehicle = _vehicle(vehicleId);
    final driver = _driver(driverId);
    final trip = Trip(
      id: _nextId++,
      contractId: contractId,
      vehicleId: vehicleId,
      driverId: driverId,
      mode: mode,
      outbound: TripLeg.fromRoute(quote.outboundRoute, quote.outboundS),
      inbound: TripLeg.fromRoute(quote.inboundRoute, quote.inboundS),
      startedAt: now,
      phase: TripPhase.toDock,
      phaseStart: now,
      phaseEnd: now + content.depotOps.slotToDockS,
    );
    trips[trip.id] = trip;
    contract
      ..status = ContractStatus.inProgress
      ..deadline = quote.deadline;
    vehicle.tripId = trip.id;
    driver.tripId = trip.id;
    queue.schedule(trip.phaseEnd, TripPhaseEnded(trip.id, trip.phase));
    _log(WorldLogKind.dispatched, {
      'trip': trip.id,
      'contract': contractId,
      'vehicle': vehicleId,
      'driver': driverId,
      'mode': mode.name,
    });
    return trip;
  }

  DispatchQuote? _quote(Contract contract, Vehicle vehicle, RouteMode mode) {
    final depot = _depot(vehicle.depotId);
    final loaded = vehicle.model.profile(cargoKg: contract.weightKg);
    final empty = vehicle.model.profile();
    final out = planner.find(depot.roadNode, contract.destinationNode, loaded, mode);
    final back = planner.find(contract.destinationNode, depot.roadNode, empty, mode);
    if (out == null || back == null) return null;

    final ops = content.depotOps;
    final outS = travelTime.legSeconds(out, loaded);
    final backS = travelTime.legSeconds(back, empty);
    final deadline = now + contract.allowedS;
    final before = ops.slotToDockS + ops.loadingS(contract.weightKg) + ops.dockToGateS;
    final unloading = ops.unloadingS(contract.weightKg);
    final deliveryEta = now + before + outS + unloading;
    return DispatchQuote(
      mode: mode,
      outboundRoute: out,
      inboundRoute: back,
      outboundS: outS,
      inboundS: backS,
      beforeDepartureS: before,
      unloadingS: unloading,
      afterReturnS: ops.gateInS + ops.gateToSlotS + ops.inspectionS,
      dispatchAt: now,
      deadline: deadline,
      revenueIdr: contract.settlementAt(deliveryEta, deadline: deadline),
      fuelIdr: _fuelIdr(vehicle, out.distanceM) + _fuelIdr(vehicle, back.distanceM),
      tollIdr: out.tollCostIdr + back.tollCostIdr,
    );
  }

  int _fuelIdr(Vehicle vehicle, num distanceM) =>
      content.economy.fuelCostIdr(distanceM.round().toDouble(), vehicle.model.fuelLPer100Km);

  // ---------------------------------------------------------------- waktu

  /// Proses semua event sampai detik game [time]. Mengembalikan jumlah event.
  int advanceTo(int time) => queue.runUntil(time, _handle);

  void _handle(ScheduledEvent scheduled, EventQueue queue) {
    final event = scheduled.event;
    if (event is TripPhaseEnded) _onPhaseEnded(event);
  }

  void _onPhaseEnded(TripPhaseEnded e) {
    final trip = trips[e.tripId];
    if (trip == null || trip.phase != e.phase) return;
    final contract = _contract(trip.contractId);
    final vehicle = _vehicle(trip.vehicleId);
    final driver = _driver(trip.driverId);
    final ref = 'trip:${trip.id}';

    switch (e.phase) {
      case TripPhase.toGate:
        _postCost(LedgerAccount.toll, trip.outbound.tollIdr, ref);
        _log(WorldLogKind.departedDepot, {'trip': trip.id, 'vehicle': vehicle.id});
      case TripPhase.outbound:
        _finishLeg(trip.outbound, vehicle, driver, ref);
      case TripPhase.unloading:
        final settled = contract.settlementAt(now, deadline: contract.deadline!);
        contract
          ..status = ContractStatus.delivered
          ..deliveredAt = now
          ..settledIdr = settled;
        ledger.post(LedgerEntry(
          time: now,
          account: LedgerAccount.contractRevenue,
          amountIdr: settled,
          ref: 'contract:${contract.id}',
        ));
        _log(WorldLogKind.delivered, {
          'trip': trip.id,
          'contract': contract.id,
          'settled_idr': settled,
          'late': now > contract.deadline!,
        });
        _postCost(LedgerAccount.toll, trip.inbound.tollIdr, ref);
      case TripPhase.inbound:
        _finishLeg(trip.inbound, vehicle, driver, ref);
        _log(WorldLogKind.returnedToDepot, {'trip': trip.id, 'vehicle': vehicle.id});
      case TripPhase.inspection:
        vehicle.tripId = null;
        driver.tripId = null;
        _log(WorldLogKind.tripCompleted, {'trip': trip.id, 'vehicle': vehicle.id});
      case TripPhase.toDock:
      case TripPhase.loading:
      case TripPhase.gateIn:
      case TripPhase.toSlot:
      case TripPhase.completed:
        break;
    }

    trip
      ..phase = e.phase.next
      ..phaseStart = now;
    if (trip.phase == TripPhase.completed) {
      trip.phaseEnd = now;
      _tracks.remove((trip.id, true));
      _tracks.remove((trip.id, false));
      return;
    }
    trip.phaseEnd = now + _phaseDuration(trip, contract);
    queue.schedule(trip.phaseEnd, TripPhaseEnded(trip.id, trip.phase));
  }

  int _phaseDuration(Trip trip, Contract contract) {
    final ops = content.depotOps;
    return switch (trip.phase) {
      TripPhase.toDock => ops.slotToDockS,
      TripPhase.loading => ops.loadingS(contract.weightKg),
      TripPhase.toGate => ops.dockToGateS,
      TripPhase.outbound => trip.outbound.durationS,
      TripPhase.unloading => ops.unloadingS(contract.weightKg),
      TripPhase.inbound => trip.inbound.durationS,
      TripPhase.gateIn => ops.gateInS,
      TripPhase.toSlot => ops.gateToSlotS,
      TripPhase.inspection => ops.inspectionS,
      TripPhase.completed => 0,
    };
  }

  void _finishLeg(TripLeg leg, Vehicle vehicle, Driver driver, String ref) {
    vehicle.odometerM += leg.distanceM;
    driver.drivingSeconds += leg.durationS;
    _postCost(LedgerAccount.fuel, _fuelIdr(vehicle, leg.distanceM), ref);
  }

  void _postCost(LedgerAccount account, int amountIdr, String ref) {
    if (amountIdr == 0) return;
    ledger.post(LedgerEntry(time: now, account: account, amountIdr: -amountIdr, ref: ref));
  }

  // ---------------------------------------------------------------- snapshot

  /// Keadaan kendaraan pada waktu [at] (default: [now]; boleh pecahan detik
  /// untuk animasi halus di antara tick). Posisi di jalan dihitung dari rute &
  /// waktu, bukan disimpan per frame.
  VehicleSnapshot vehicleSnapshot(int vehicleId, {num? at}) {
    final vehicle = _vehicle(vehicleId);
    final trip = vehicle.tripId == null ? null : trips[vehicle.tripId];
    if (trip == null) {
      return VehicleSnapshot(
        vehicleId: vehicleId,
        activity: VehicleActivity.parked,
        slotIndex: vehicle.slotIndex,
      );
    }
    final t = at ?? now;
    final span = trip.phaseEnd - trip.phaseStart;
    final progress = span <= 0 ? 1.0 : ((t - trip.phaseStart) / span).clamp(0.0, 1.0);
    final contract = _contract(trip.contractId);

    TrackPose? pose;
    var activity = VehicleActivity.inDepot;
    if (trip.phase.onRoad) {
      activity = VehicleActivity.onRoad;
      final outbound = trip.phase == TripPhase.outbound;
      pose = _track(trip, vehicle, contract, outbound).poseAt(progress);
    } else if (trip.phase == TripPhase.unloading) {
      activity = VehicleActivity.atDestination;
      pose = TrackPose(graph.node(contract.destinationNode), 0);
    }
    return VehicleSnapshot(
      vehicleId: vehicleId,
      activity: activity,
      slotIndex: vehicle.slotIndex,
      tripId: trip.id,
      phase: trip.phase,
      phaseProgress: progress,
      pose: pose,
    );
  }

  /// Polyline & pembagian waktu leg pergi/pulang sebuah trip (untuk peta).
  RouteTrack trackFor(int tripId, {required bool outbound}) {
    final trip = trips[tripId] ?? (throw ArgumentError.value(tripId, 'tripId'));
    return _track(trip, _vehicle(trip.vehicleId), _contract(trip.contractId), outbound);
  }

  RouteTrack _track(Trip trip, Vehicle vehicle, Contract contract, bool outbound) =>
      _tracks.putIfAbsent((trip.id, outbound), () {
        final leg = outbound ? trip.outbound : trip.inbound;
        final profile = vehicle.model.profile(cargoKg: outbound ? contract.weightKg : 0);
        return RouteTrack.build(
          graph,
          leg.edges,
          startNode: leg.startNode,
          speedMps: (e) => planner.speedMps(e, profile),
        );
      });

  // ---------------------------------------------------------------- save

  static const saveFormat = 1;

  Map<String, dynamic> toJson() => {
        'format': saveFormat,
        'seed': seed,
        'company': companyName,
        'now': now,
        'next_seq': queue.nextSeq,
        'next_id': _nextId,
        'depots': [for (final d in depots.values) d.toJson()],
        'vehicles': [for (final v in vehicles.values) v.toJson()],
        'drivers': [for (final d in drivers.values) d.toJson()],
        'contracts': [for (final c in contracts.values) c.toJson()],
        'trips': [for (final t in trips.values) t.toJson()],
        'ledger': ledger.toJson(),
        'log': [for (final l in log) l.toJson()],
        'events': [
          for (final e in queue.snapshot())
            {
              't': e.time,
              'p': e.priority,
              'seq': e.seq,
              'type': e.event.type,
              'data': (e.event as TripPhaseEnded).toJson(),
            },
        ],
      };

  factory SimWorld.fromJson(
    Map<String, dynamic> json, {
    required RoadGraph graph,
    required GameContent content,
    TravelTimeModel travelTime = const RouteEstimateTravelTime(),
  }) {
    if (json['format'] != saveFormat) {
      throw FormatException('Format save tidak didukung: ${json['format']}');
    }
    List<Map<String, dynamic>> rows(String key) => (json[key] as List).cast<Map<String, dynamic>>();
    final queue = EventQueue(nextSeq: json['next_seq'] as int, processedUntil: json['now'] as int);
    queue.restore([
      for (final e in rows('events'))
        ScheduledEvent(
          time: e['t'] as int,
          priority: e['p'] as int,
          seq: e['seq'] as int,
          event: switch (e['type']) {
            TripPhaseEnded.typeName => TripPhaseEnded.fromJson(e['data'] as Map<String, dynamic>),
            final other => throw FormatException('Tipe event tidak dikenal: $other'),
          },
        ),
    ]);
    return SimWorld._(
      graph: graph,
      content: content,
      travelTime: travelTime,
      seed: json['seed'] as int,
      companyName: json['company'] as String,
      queue: queue,
      ledger: Ledger.fromJson(json['ledger'] as List),
      depots: {for (final d in rows('depots').map(Depot.fromJson)) d.id: d},
      vehicles: {
        for (final v in rows('vehicles').map((r) => Vehicle.fromJson(r, content.vehicleModels))) v.id: v,
      },
      drivers: {for (final d in rows('drivers').map(Driver.fromJson)) d.id: d},
      contracts: {for (final c in rows('contracts').map(Contract.fromJson)) c.id: c},
      trips: {for (final t in rows('trips').map(Trip.fromJson)) t.id: t},
      log: rows('log').map(WorldLogEntry.fromJson).toList(),
      nextId: json['next_id'] as int,
    );
  }

  // ---------------------------------------------------------------- util

  void _log(WorldLogKind kind, Map<String, Object?> data) =>
      log.add(WorldLogEntry(now, kind, data));

  Depot _depot(int id) => depots[id] ?? (throw ArgumentError.value(id, 'depotId'));
  Vehicle _vehicle(int id) => vehicles[id] ?? (throw ArgumentError.value(id, 'vehicleId'));
  Driver _driver(int id) => drivers[id] ?? (throw ArgumentError.value(id, 'driverId'));
  Contract _contract(int id) => contracts[id] ?? (throw ArgumentError.value(id, 'contractId'));
}
