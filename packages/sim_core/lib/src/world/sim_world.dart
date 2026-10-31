import 'dart:math' as math;

import '../contracts/agreement.dart';
import '../contracts/contract.dart';
import '../contracts/contract_tiers.dart';
import '../depot/depot.dart';
import '../depot/facilities.dart';
import '../employees/driver.dart';
import '../employees/employee_config.dart';
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
import '../vehicle/maintenance.dart';
import '../vehicle/vehicle.dart';
import '../vehicle/vehicle_class.dart';
import '../vehicle/vehicle_profile.dart';
import '../vehicle/vehicle_valuation.dart';
import 'game_content.dart';
import 'world_log.dart';

/// Event dunia yang bisa disimpan.
sealed class WorldEvent extends SimEvent {
  const WorldEvent();

  Map<String, dynamic> toJson();

  static WorldEvent fromJson(String type, Map<String, dynamic> j) => switch (type) {
        TripPhaseEnded.typeName => TripPhaseEnded(j['trip'] as int, TripPhase.values.byName(j['phase'] as String)),
        ConstructionFinished.typeName => ConstructionFinished(j['depot'] as int),
        PayrollDue.typeName => const PayrollDue(),
        MaintenanceFinished.typeName => MaintenanceFinished(j['vehicle'] as int),
        AgreementRunDue.typeName => AgreementRunDue(j['agreement'] as int),
        _ => throw FormatException('Tipe event tidak dikenal: $type'),
      };
}

/// Akhir satu fase trip.
class TripPhaseEnded extends WorldEvent {
  const TripPhaseEnded(this.tripId, this.phase);

  static const typeName = 'trip_phase_ended';

  final int tripId;
  final TripPhase phase;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {'trip': tripId, 'phase': phase.name};
}

/// Konstruksi upgrade fasilitas selesai.
class ConstructionFinished extends WorldEvent {
  const ConstructionFinished(this.depotId);

  static const typeName = 'construction_finished';

  final int depotId;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {'depot': depotId};
}

/// Pergantian hari: upah harian karyawan.
class PayrollDue extends WorldEvent {
  const PayrollDue();

  static const typeName = 'payroll_due';

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => const {};
}

/// Pekerjaan bengkel pada satu kendaraan selesai.
class MaintenanceFinished extends WorldEvent {
  const MaintenanceFinished(this.vehicleId);

  static const typeName = 'maintenance_finished';

  final int vehicleId;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {'vehicle': vehicleId};
}

/// Jadwal (atau percobaan ulang) satu pengiriman kontrak berulang.
class AgreementRunDue extends WorldEvent {
  const AgreementRunDue(this.agreementId);

  static const typeName = 'agreement_run_due';

  final int agreementId;

  @override
  String get type => typeName;

  @override
  Map<String, dynamic> toJson() => {'agreement': agreementId};
}

enum VehicleActivity {
  /// Diam di slot parkir, siap dipakai.
  parked,

  /// Bergerak / bekerja / antre di depot (termasuk antre di jalan depan gerbang).
  inDepot,

  /// Di jalan.
  onRoad,

  /// Bongkar muat di lokasi pelanggan / supplier.
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
    this.dock,
    this.gateLane,
    this.queuePosition,
    this.inWorkshop = false,
  });

  final int vehicleId;
  final VehicleActivity activity;
  final int slotIndex;
  final int? tripId;
  final TripPhase? phase;

  /// 0..1 di dalam fase saat ini (0 untuk fase antrean).
  final double phaseProgress;

  /// Posisi geografis saat di jalan atau di lokasi pelanggan.
  final TrackPose? pose;

  final int? dock;
  final int? gateLane;

  /// Urutan di antrean (0 = terdepan) untuk fase `wait*`.
  final int? queuePosition;

  /// Sedang diservis / antre bengkel (di slot parkirnya).
  final bool inWorkshop;
}

enum UpgradeProblem { maxLevel, constructionBusy, insufficientCash }

enum PurchaseProblem {
  noFreeSlot,
  insufficientCash,
  unknownModel,

  /// Fasilitas depot belum mencapai level yang disyaratkan model.
  facilityLevelTooLow,

  /// Kendaraan terlalu panjang untuk depot kota; butuh terminal truk.
  needsTruckTerminal,

  /// Penawaran kendaraan bekas sudah tidak ada (terjual / berganti hari).
  listingGone,
}

enum HireProblem { officeFull, noCandidate }

enum SellProblem {
  /// Sedang bertugas / di bengkel.
  vehicleBusy,

  /// Ditetapkan untuk kontrak berulang yang masih berjalan.
  inAgreement,

  /// Kendaraan terakhir perusahaan.
  lastVehicle,
}

enum MaintenanceProblem { vehicleBusy, insufficientCash, notNeeded }

class CommandException<T extends Enum> implements Exception {
  const CommandException(this.problems);

  final List<T> problems;

  @override
  String toString() => 'CommandException(${problems.map((p) => p.name).join(', ')})';
}

/// Dunia simulasi satu save: state perusahaan + antrean event.
///
/// Satu-satunya sumber kebenaran. UI memanggil perintah ([check],
/// [dispatch], [startUpgrade], [buyVehicle], [hire], …) dan membaca
/// snapshot; waktu maju lewat [advanceTo] (dipakai sama persis saat bermain
/// aktif maupun catch-up offline).
///
/// Loading dock & jalur gerbang adalah sumber daya terbatas. Kendaraan yang
/// tidak kebagian masuk fase antrean (`wait*`) dan dilayani FIFO saat sumber
/// daya lepas, sehingga antrean benar-benar memperpanjang waktu operasi.
/// Isi antrean tidak disimpan terpisah: dibangun ulang dari fase trip.
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
    Map<int, Supplier>? suppliers,
    Map<int, Agreement>? agreements,
    Set<String>? usedBought,
  })  : planner = RoutePlanner(graph),
        suppliers = suppliers ?? {},
        agreements = agreements ?? {},
        usedBought = usedBought ?? {},
        _nextId = nextId;

  /// Perusahaan baru: satu depot (semua fasilitas level 1), satu kendaraan di
  /// slot 0, satu sopir, modal awal dari `economy.json`.
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
    int startTime = 0,
    TravelTimeModel travelTime = const RouteEstimateTravelTime(),
  }) {
    final model = content.vehicleModels[starterVehicleModelId];
    if (model == null) throw ArgumentError.value(starterVehicleModelId, 'starterVehicleModelId');
    if (depotNode < 0 || depotNode >= graph.nodeCount) {
      throw ArgumentError.value(depotNode, 'depotNode', 'di luar graph');
    }
    const depotId = 1, vehicleId = 2, driverId = 3;
    final slots = content.facilities[FacilityType.parking].level(1).intStat('slots');
    final depot = Depot(
      id: depotId,
      name: depotName,
      cityId: cityId,
      roadNode: depotNode,
      parkingSlots: slots,
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
        vehicleId: Vehicle(
          id: vehicleId,
          model: model,
          depotId: depotId,
          slotIndex: 0,
          builtYear: content.economy.vehicleMarket.startYear,
        ),
      },
      drivers: {
        driverId: Driver(
          id: driverId,
          name: driverName,
          depotId: depotId,
          skill: content.employees.driver.defaultSkill,
          dailyWageIdr: content.employees.driver.wageIdr(
            content.employees.dailyWageIdr[EmployeeRole.driver]!,
            content.employees.driver.defaultSkill,
          ),
          restingSince: startTime,
        ),
      },
      contracts: {},
      trips: {},
      log: [],
      nextId: 4,
    );
    world._schedulePayroll();
    world._ensureSuppliers();
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

  /// Supplier per kota depot (id terpisah dari [_nextId]).
  final Map<int, Supplier> suppliers;

  /// Kontrak berulang (ditawarkan / berjalan / selesai).
  final Map<int, Agreement> agreements;

  /// Kunci penawaran kendaraan bekas yang sudah dibeli (`hari:indeks`).
  final Set<String> usedBought;

  int _nextId;

  final Map<(int, LegKind), RouteTrack> _tracks = {};

  /// Detik game per hari; detik 0 = Hari 1 pukul 06.00.
  static const daySeconds = 86400;
  static const dayStartOffset = 6 * 3600;

  /// Waktu simulasi saat ini (detik game).
  int get now => queue.processedUntil;

  int get cashIdr => ledger.cashIdr;

  /// Hari ke-n sejak awal permainan (0 = Hari 1).
  int get dayIndex => (now + dayStartOffset) ~/ daySeconds;

  /// Tahun kalender berjalan (Hari 1 = 1 Januari `start_year`).
  int get currentYear => content.economy.vehicleMarket.startYear + dayIndex ~/ 365;

  // ---------------------------------------------------------------- fasilitas

  FacilityLevel facility(Depot depot, FacilityType type) =>
      content.facilities[type].level(depot.level(type));

  /// Tahap visual fasilitas (untuk renderer: layout & modul 3D).
  int tier(Depot depot, FacilityType type) => facility(depot, type).tier;

  /// Durasi perpindahan di dalam depot, dipercepat jalur internal parkir.
  int yardS(Depot depot, int seconds) {
    final speed = facility(depot, FacilityType.parking).stats['yard_speed']?.toDouble() ?? 1.0;
    return (seconds / speed).round();
  }

  int dockCount(Depot depot) => facility(depot, FacilityType.loadingDock).intStat('docks');
  int gateLaneCount(Depot depot) => facility(depot, FacilityType.gate).intStat('lanes');
  int gatePassS(Depot depot) => facility(depot, FacilityType.gate).intStat('pass_s');
  int staffMax(Depot depot) => facility(depot, FacilityType.office).intStat('staff_max');

  /// Karyawan yang dihitung terhadap kapasitas kantor: sopir, staf gudang, mekanik.
  int staffCount(Depot depot) =>
      drivers.values.where((d) => d.depotId == depot.id).length + depot.warehouseStaff + depot.mechanics;

  /// Durasi muat di depot: dipercepat oleh level dock & jumlah staf gudang.
  int loadingS(Depot depot, int cargoKg) {
    final speed = facility(depot, FacilityType.loadingDock).doubleStat('speed') *
        content.employees.loadingFactor(depot.warehouseStaff);
    return (content.depotOps.loadingS(cargoKg) / speed).round();
  }

  List<UpgradeProblem> upgradeProblems(int depotId, FacilityType type) {
    final depot = _depot(depotId);
    final spec = content.facilities[type];
    final current = depot.level(type);
    return [
      if (current >= spec.maxLevel) UpgradeProblem.maxLevel,
      if (depot.construction != null) UpgradeProblem.constructionBusy,
      if (current < spec.maxLevel && cashIdr < spec.level(current + 1).costIdr) UpgradeProblem.insufficientCash,
    ];
  }

  /// Bayar & mulai konstruksi level berikutnya. Satu konstruksi per depot.
  FacilityConstruction startUpgrade(int depotId, FacilityType type) {
    final problems = upgradeProblems(depotId, type);
    if (problems.isNotEmpty) throw CommandException(problems);
    final depot = _depot(depotId);
    final next = content.facilities[type].level(depot.level(type) + 1);
    ledger.post(LedgerEntry(
      time: now,
      account: LedgerAccount.facilityUpgrade,
      amountIdr: -next.costIdr,
      ref: 'depot:${depot.id}:${type.id}',
    ));
    final construction = FacilityConstruction(
      type: type,
      toLevel: next.level,
      startedAt: now,
      finishAt: now + next.buildMinutes * 60,
    );
    depot.construction = construction;
    queue.schedule(construction.finishAt, ConstructionFinished(depot.id));
    _log(WorldLogKind.upgradeStarted, {'depot': depot.id, 'facility': type.id, 'level': next.level});
    return construction;
  }

  void _onConstructionFinished(ConstructionFinished e) {
    final depot = _depot(e.depotId);
    final c = depot.construction;
    // Jadwal usang (mis. konstruksi dipercepat setelah update konten) diabaikan.
    if (c == null || now < c.finishAt) return;
    depot
      ..levels[c.type] = c.toLevel
      ..construction = null;
    if (c.type == FacilityType.parking) {
      depot.growSlots(facility(depot, FacilityType.parking).intStat('slots'));
    }
    _log(WorldLogKind.upgradeFinished, {'depot': depot.id, 'facility': c.type.id, 'level': c.toLevel});
    // Kapasitas dock / gerbang bertambah: layani antrean yang menunggu.
    _serveDockQueue(depot);
    _serveGateQueue(depot);
    _serveWorkshop(depot);
  }

  /// Mode pengembang: tambah kas lewat buku besar (akun terpisah, ikut tersimpan).
  void devGrant(int amountIdr) {
    if (amountIdr <= 0) throw ArgumentError.value(amountIdr, 'amountIdr');
    ledger.post(LedgerEntry(time: now, account: LedgerAccount.devAdjustment, amountIdr: amountIdr, ref: 'dev'));
  }

  // ---------------------------------------------------------------- perawatan

  /// Biaya & durasi tindakan untuk kendaraan ini di bengkel depotnya saat ini.
  ({int costIdr, int durationS}) maintenanceQuote(int vehicleId, String actionId) {
    final vehicle = _vehicle(vehicleId);
    final action = content.maintenance.action(actionId);
    final shop = facility(_depot(vehicle.depotId), FacilityType.workshop);
    final classFactor = content.maintenance.classCostFactor[vehicle.model.vehicleClass] ?? 1.0;
    return (
      costIdr: (action.costIdr * classFactor * shop.doubleStat('cost_factor')).round(),
      durationS: (action.minutes * 60 / (shop.doubleStat('speed') * _mechanicFactor(_depot(vehicle.depotId)))).round(),
    );
  }

  List<MaintenanceProblem> maintenanceProblems(int vehicleId, String actionId) {
    final vehicle = _vehicle(vehicleId);
    final action = content.maintenance.action(actionId);
    return [
      if (!vehicle.isAvailable) MaintenanceProblem.vehicleBusy,
      if (cashIdr < maintenanceQuote(vehicleId, actionId).costIdr) MaintenanceProblem.insufficientCash,
      if (action.restore.keys.every((c) => vehicle.condition[c]! >= 0.999)) MaintenanceProblem.notNeeded,
    ];
  }

  /// Bayar & kirim kendaraan ke bengkel. Antre bila semua bay terpakai;
  /// tanpa bengkel sendiri, dikerjakan bengkel luar (langsung, lebih lama & mahal).
  MaintenanceJob startMaintenance(int vehicleId, String actionId) {
    final problems = maintenanceProblems(vehicleId, actionId);
    if (problems.isNotEmpty) throw CommandException(problems);
    final vehicle = _vehicle(vehicleId);
    final q = maintenanceQuote(vehicleId, actionId);
    ledger.post(LedgerEntry(
      time: now,
      account: LedgerAccount.maintenance,
      amountIdr: -q.costIdr,
      ref: 'vehicle:${vehicle.id}:$actionId',
    ));
    final job = MaintenanceJob(actionId: actionId, requestedAt: now, costIdr: q.costIdr, durationS: q.durationS);
    vehicle.maintenance = job;
    _log(WorldLogKind.maintenanceStarted, {'vehicle': vehicle.id, 'action': actionId});
    _serveWorkshop(_depot(vehicle.depotId));
    return job;
  }

  int workshopBays(Depot depot) => facility(depot, FacilityType.workshop).intStat('bays');

  /// Mekanik hanya berpengaruh di bengkel sendiri; bengkel luar punya stafnya sendiri.
  double _mechanicFactor(Depot depot) {
    final bays = workshopBays(depot);
    return bays == 0 ? 1.0 : content.employees.mechanicFactor(depot.mechanics, bays);
  }

  void _serveWorkshop(Depot depot) {
    final jobs = vehicles.values
        .where((v) => v.depotId == depot.id && v.maintenance != null)
        .toList()
      ..sort((a, b) {
        final ja = a.maintenance!, jb = b.maintenance!;
        return ja.requestedAt != jb.requestedAt ? ja.requestedAt.compareTo(jb.requestedAt) : a.id.compareTo(b.id);
      });
    final bays = workshopBays(depot);
    for (final v in jobs) {
      final job = v.maintenance!;
      if (!job.waiting) continue;
      if (bays > 0) {
        final bay = _free(bays, jobs.map((x) => x.maintenance!.waiting ? null : x.maintenance!.bay));
        if (bay == null) return;
        job.bay = bay;
      }
      job.startedAt = now;
      queue.schedule(job.finishAt!, MaintenanceFinished(v.id));
    }
  }

  void _onMaintenanceFinished(MaintenanceFinished e) {
    final vehicle = vehicles[e.vehicleId];
    final job = vehicle?.maintenance;
    if (vehicle == null || job == null || job.finishAt != now) return;
    for (final r in content.maintenance.action(job.actionId).restore.entries) {
      vehicle.condition[r.key] = math.min(1.0, vehicle.condition[r.key]! + r.value);
    }
    vehicle.maintenance = null;
    _log(WorldLogKind.maintenanceFinished, {'vehicle': vehicle.id, 'action': job.actionId});
    _serveWorkshop(_depot(vehicle.depotId));
  }

  // ---------------------------------------------------------------- armada & karyawan

  List<PurchaseProblem> purchaseProblems(int depotId, String modelId) {
    final model = content.vehicleModels[modelId];
    return [
      if (model == null) PurchaseProblem.unknownModel,
      ..._purchaseProblems(depotId, model, model?.priceIdr ?? 0),
    ];
  }

  List<PurchaseProblem> _purchaseProblems(int depotId, VehicleModel? model, int priceIdr) => [
        if (_depot(depotId).firstFreeSlot == null) PurchaseProblem.noFreeSlot,
        if (model != null && model.unlock.terminal) PurchaseProblem.needsTruckTerminal,
        if (model?.unlock.facilityId case final f?
            when _depot(depotId).level(FacilityType.parse(f)) < model!.unlock.level)
          PurchaseProblem.facilityLevelTooLow,
        if (model != null && cashIdr < priceIdr) PurchaseProblem.insufficientCash,
      ];

  /// Beli kendaraan baru; langsung menempati slot parkir kosong pertama.
  Vehicle buyVehicle(int depotId, String modelId) {
    final problems = purchaseProblems(depotId, modelId);
    if (problems.isNotEmpty) throw CommandException(problems);
    final model = content.vehicleModels[modelId]!;
    return _addVehicle(_depot(depotId), model, priceIdr: model.priceIdr, builtYear: currentYear);
  }

  Vehicle _addVehicle(
    Depot depot,
    VehicleModel model, {
    required int priceIdr,
    required int builtYear,
    int odometerM = 0,
    Map<VehicleComponent, double>? condition,
    bool used = false,
  }) {
    final slot = depot.firstFreeSlot!;
    final vehicle = Vehicle(
      id: _nextId++,
      model: model,
      depotId: depot.id,
      slotIndex: slot,
      odometerM: odometerM,
      condition: condition == null ? null : Map.of(condition),
      builtYear: builtYear,
      purchasePriceIdr: priceIdr,
    );
    depot.slots[slot] = vehicle.id;
    vehicles[vehicle.id] = vehicle;
    ledger.post(LedgerEntry(
      time: now,
      account: LedgerAccount.vehiclePurchase,
      amountIdr: -priceIdr,
      ref: 'vehicle:${vehicle.id}',
    ));
    _log(WorldLogKind.vehiclePurchased, {'vehicle': vehicle.id, 'model': model.id, 'used': used, 'price_idr': priceIdr});
    return vehicle;
  }

  int vehicleAgeYears(Vehicle vehicle) => math.max(0, currentYear - vehicle.builtYear);

  /// Nilai pasar saat ini (umur, odometer, kondisi).
  int marketValueIdr(Vehicle vehicle) => marketValueIdrFor(
        vehicle.model,
        ageYears: vehicleAgeYears(vehicle),
        odometerM: vehicle.odometerM,
        averageCondition: vehicle.averageCondition,
      );

  int marketValueIdrFor(VehicleModel model,
          {required int ageYears, required int odometerM, required double averageCondition}) =>
      estimateMarketValueIdr(
        model: model,
        ageYears: ageYears,
        odometerM: odometerM,
        averageCondition: averageCondition,
        cfg: content.economy.vehicleMarket,
      );

  /// Harga yang dibayar dealer bila kendaraan dijual.
  int saleValueIdr(Vehicle vehicle) =>
      (marketValueIdr(vehicle) * content.economy.vehicleMarket.dealerBuyPct / 100).round();

  List<SellProblem> sellProblems(int vehicleId) {
    final vehicle = _vehicle(vehicleId);
    return [
      if (!vehicle.isAvailable) SellProblem.vehicleBusy,
      if (agreements.values.any((a) => a.isActive && a.vehicleId == vehicleId)) SellProblem.inAgreement,
      if (vehicles.length <= 1) SellProblem.lastVehicle,
    ];
  }

  /// Jual kendaraan ke dealer; slot parkirnya kosong kembali.
  int sellVehicle(int vehicleId) {
    final problems = sellProblems(vehicleId);
    if (problems.isNotEmpty) throw CommandException(problems);
    final vehicle = _vehicle(vehicleId);
    final price = saleValueIdr(vehicle);
    final depot = _depot(vehicle.depotId);
    if (depot.slots[vehicle.slotIndex] == vehicle.id) depot.slots[vehicle.slotIndex] = null;
    vehicles.remove(vehicleId);
    for (final a in agreements.values.where((a) => a.vehicleId == vehicleId)) {
      a.vehicleId = null;
    }
    ledger.post(LedgerEntry(time: now, account: LedgerAccount.vehicleSale, amountIdr: price, ref: 'vehicle:$vehicleId'));
    _log(WorldLogKind.vehicleSold, {'vehicle': vehicleId, 'model': vehicle.model.id, 'price_idr': price});
    return price;
  }

  /// Penawaran kendaraan bekas hari ini di dealer depot (deterministik per hari).
  List<UsedListing> usedListings(int depotId) {
    final cfg = content.economy.vehicleMarket;
    final models = content.vehicleModels.values.where((m) => !m.unlock.terminal).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    if (models.isEmpty) return const [];
    final day = dayIndex;
    final result = <UsedListing>[];
    for (var i = 0; i < cfg.usedListings; i++) {
      final key = '$day:$i';
      if (usedBought.contains(key)) continue;
      final rng = DeterministicRng.derive(seed, 800000 + depotId * 1000, day * 100 + i);
      final model = models[rng.nextInt(models.length)];
      final age = cfg.usedAgeMin + rng.nextInt(cfg.usedAgeMax - cfg.usedAgeMin + 1);
      final kmPerYear = cfg.usedKmPerYearMin + rng.nextInt(cfg.usedKmPerYearMax - cfg.usedKmPerYearMin + 1);
      final condition = {
        for (final c in VehicleComponent.values)
          c: ((cfg.usedConditionMin + (cfg.usedConditionMax - cfg.usedConditionMin) * rng.nextDouble()) * 100).round() /
              100,
      };
      final odometerM = age * kmPerYear * 1000;
      final avg = condition.values.reduce((a, b) => a + b) / condition.length;
      final value = marketValueIdrFor(model, ageYears: age, odometerM: odometerM, averageCondition: avg);
      result.add(UsedListing(
        key: key,
        model: model,
        builtYear: currentYear - age,
        odometerM: odometerM,
        condition: condition,
        priceIdr: (value * (100 + cfg.usedMarkupPct) / 100 / 100000).round() * 100000,
      ));
    }
    return result;
  }

  List<PurchaseProblem> usedPurchaseProblems(int depotId, String key) {
    final listing = usedListings(depotId).where((l) => l.key == key).firstOrNull;
    if (listing == null) return const [PurchaseProblem.listingGone];
    return _purchaseProblems(depotId, listing.model, listing.priceIdr);
  }

  /// Beli kendaraan bekas dari [usedListings].
  Vehicle buyUsedVehicle(int depotId, String key) {
    final problems = usedPurchaseProblems(depotId, key);
    if (problems.isNotEmpty) throw CommandException(problems);
    final listing = usedListings(depotId).firstWhere((l) => l.key == key);
    usedBought
      ..removeWhere((k) => int.parse(k.split(':').first) < dayIndex)
      ..add(key);
    return _addVehicle(
      _depot(depotId),
      listing.model,
      priceIdr: listing.priceIdr,
      builtYear: listing.builtYear,
      odometerM: listing.odometerM,
      condition: listing.condition,
      used: true,
    );
  }

  /// Calon sopir hari ini (deterministik per hari & depot; yang sudah
  /// direkrut tidak muncul lagi).
  List<DriverCandidate> driverCandidates(int depotId) {
    final cfg = content.employees;
    final rules = cfg.driver;
    final day = (now + dayStartOffset) ~/ daySeconds;
    final used = drivers.values.map((d) => d.name).toSet();
    final result = <DriverCandidate>[];
    for (var i = 0; i < rules.candidates; i++) {
      final rng = DeterministicRng.derive(seed, depotId * 100000 + day, i);
      final start = rng.nextInt(cfg.names.length);
      final skill = rules.hireSkillMin + (rules.hireSkillMax - rules.hireSkillMin) * rng.nextDouble();
      String? name;
      for (var k = 0; k < cfg.names.length; k++) {
        final n = cfg.names[(start + k) % cfg.names.length];
        if (!used.contains(n) && !result.any((c) => c.name == n)) {
          name = n;
          break;
        }
      }
      if (name == null) break;
      final rounded = (skill * 100).round() / 100;
      result.add(DriverCandidate(
        name: name,
        skill: rounded,
        dailyWageIdr: rules.wageIdr(cfg.dailyWageIdr[EmployeeRole.driver]!, rounded),
      ));
    }
    return result;
  }

  List<HireProblem> hireProblems(int depotId, {EmployeeRole role = EmployeeRole.warehouseStaff, int candidate = 0}) {
    final depot = _depot(depotId);
    return [
      if (staffCount(depot) >= staffMax(depot)) HireProblem.officeFull,
      if (role == EmployeeRole.driver && candidate >= driverCandidates(depotId).length) HireProblem.noCandidate,
    ];
  }

  /// Rekrut karyawan. Sopir dipilih dari [driverCandidates] (indeks [candidate]).
  void hire(int depotId, EmployeeRole role, {int candidate = 0}) {
    final problems = hireProblems(depotId, role: role, candidate: candidate);
    if (problems.isNotEmpty) throw CommandException(problems);
    final depot = _depot(depotId);
    switch (role) {
      case EmployeeRole.driver:
        final c = driverCandidates(depotId)[candidate];
        final id = _nextId++;
        drivers[id] = Driver(
          id: id,
          name: c.name,
          depotId: depot.id,
          skill: c.skill,
          dailyWageIdr: c.dailyWageIdr,
          restingSince: now,
        );
        _log(WorldLogKind.employeeHired, {'role': role.id, 'driver': id});
      case EmployeeRole.warehouseStaff:
        depot.warehouseStaff++;
        _log(WorldLogKind.employeeHired, {'role': role.id, 'count': depot.warehouseStaff});
      case EmployeeRole.mechanic:
        depot.mechanics++;
        _log(WorldLogKind.employeeHired, {'role': role.id, 'count': depot.mechanics});
    }
  }

  /// Berhentikan satu staf gudang / mekanik (bila ada).
  void releaseStaff(int depotId, EmployeeRole role) {
    final depot = _depot(depotId);
    switch (role) {
      case EmployeeRole.warehouseStaff when depot.warehouseStaff > 0:
        depot.warehouseStaff--;
        _log(WorldLogKind.employeeReleased, {'role': role.id, 'count': depot.warehouseStaff});
      case EmployeeRole.mechanic when depot.mechanics > 0:
        depot.mechanics--;
        _log(WorldLogKind.employeeReleased, {'role': role.id, 'count': depot.mechanics});
      default:
        break;
    }
  }

  /// Sopir bisa diberhentikan bila tidak bertugas dan bukan satu-satunya.
  bool canReleaseDriver(int driverId) => _driver(driverId).isAvailable && drivers.length > 1;

  void releaseDriver(int driverId) {
    if (!canReleaseDriver(driverId)) throw ArgumentError.value(driverId, 'driverId', 'tidak bisa diberhentikan');
    final d = drivers.remove(driverId)!;
    _log(WorldLogKind.employeeReleased, {'role': EmployeeRole.driver.id, 'name': d.name});
  }

  double driverFatigue(int driverId) => _driver(driverId).fatigueAt(now, content.employees.driver);

  int dailyPayrollIdr() {
    final wage = content.employees.dailyWageIdr;
    final staff = depots.values.fold(0, (s, d) => s + d.warehouseStaff);
    final mechanics = depots.values.fold(0, (s, d) => s + d.mechanics);
    return drivers.values.fold(0, (s, d) => s + d.dailyWageIdr) +
        staff * wage[EmployeeRole.warehouseStaff]! +
        mechanics * wage[EmployeeRole.mechanic]!;
  }

  void _schedulePayroll() {
    final sinceDayStart = (now + dayStartOffset) % daySeconds;
    queue.schedule(now + daySeconds - sinceDayStart, const PayrollDue());
  }

  void _onPayroll() {
    final amount = dailyPayrollIdr();
    if (amount > 0) {
      ledger.post(LedgerEntry(time: now, account: LedgerAccount.wages, amountIdr: -amount, ref: 'payroll'));
      _log(WorldLogKind.payrollPaid, {'amount_idr': amount});
    }
    queue.schedule(now + daySeconds, const PayrollDue());
  }

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

    // Hanya barang yang bisa diangkut armada depot ini.
    final kinds = {
      for (final v in vehicles.values)
        if (v.depotId == depotId) ...v.model.cargoKinds,
    };
    final cargoIds = content.cargoTypes.values.where((c) => kinds.contains(c.kind)).map((c) => c.id).toList()
      ..sort();
    if (cargoIds.isEmpty) return null;
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
          gatePassS(depot) +
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

  // ---------------------------------------------------------------- supplier

  /// Buat supplier untuk kota setiap depot yang belum punya (game baru & save lama).
  void _ensureSuppliers() {
    for (final depot in depots.values) {
      if (suppliers.values.any((s) => s.cityId == depot.cityId)) continue;
      final origin = graph.node(depot.roadNode);
      for (final (i, template) in content.suppliers.indexed) {
        final rng = DeterministicRng.derive(seed, 900000 + depot.id, i);
        int? found;
        int? fallback;
        for (var attempt = 0; attempt < 300 && found == null; attempt++) {
          final node = rng.nextInt(graph.nodeCount);
          if (node == depot.roadNode) continue;
          final km = haversineMeters(origin, graph.node(node)) / 1000;
          if (!_reachableBothWays(depot.roadNode, node)) continue;
          fallback ??= node;
          if (km >= 2 && km <= 12) found = node;
        }
        final node = found ?? fallback;
        if (node == null) continue;
        final id = suppliers.isEmpty ? 1 : suppliers.keys.reduce(math.max) + 1;
        suppliers[id] = Supplier(id: id, name: template.name, cityId: depot.cityId, node: node, sells: template.sells);
      }
    }
  }

  static const _referenceProfile = VehicleProfile(
    vehicleClass: VehicleClass.pickupOpen,
    maxSpeedKmh: 80,
    grossWeightT: 2.5,
    tollGolongan: 1,
  );

  bool _reachableBothWays(int a, int b) =>
      planner.find(a, b, _referenceProfile, RouteMode.toll) != null &&
      planner.find(b, a, _referenceProfile, RouteMode.toll) != null;

  List<Supplier> suppliersFor(int depotId) {
    final city = _depot(depotId).cityId;
    return suppliers.values.where((s) => s.cityId == city).toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  /// Jenis muatan yang sanggup diangkut armada depot.
  Set<String> _fleetKinds(int depotId) => {
        for (final v in vehicles.values)
          if (v.depotId == depotId) ...v.model.cargoKinds,
      };

  int linesWeightKg(Iterable<OrderLine> lines) =>
      lines.fold(0, (s, l) => s + l.units * content.cargoTypes[l.cargoId]!.unitWeightKg);

  double linesVolumeM3(Iterable<OrderLine> lines) =>
      lines.fold(0.0, (s, l) => s + l.units * content.cargoTypes[l.cargoId]!.unitVolumeM3);

  /// Tujuan acak (deterministik dari [rng]) berjarak [minKm]–[maxKm] dari [fromNode]
  /// yang terjangkau pergi-pulang dari depot.
  int? _pickDestination(DeterministicRng rng, Depot depot, int fromNode, double minKm, double maxKm) {
    final from = graph.node(fromNode);
    for (var attempt = 0; attempt < 300; attempt++) {
      final dest = rng.nextInt(graph.nodeCount);
      if (dest == fromNode || dest == depot.roadNode) continue;
      final km = haversineMeters(from, graph.node(dest)) / 1000;
      if (km < minKm || km > maxKm) continue;
      if (planner.find(fromNode, dest, _referenceProfile, RouteMode.toll) == null) continue;
      if (planner.find(dest, depot.roadNode, _referenceProfile, RouteMode.toll) == null) continue;
      return dest;
    }
    return null;
  }

  /// Barang acak dari supplier yang sanggup diangkut armada, berat ±40–90% [capacityKg].
  List<OrderLine>? _pickLines(
    DeterministicRng rng,
    Supplier supplier,
    Set<String> kinds,
    int capacityKg, {
    int maxLines = 1,
    bool storableOnly = false,
  }) {
    final options = supplier.sells.where((id) {
      final c = content.cargoTypes[id]!;
      return kinds.contains(c.kind) && (!storableOnly || c.storable) && c.unitWeightKg <= capacityKg;
    }).toList()
      ..sort();
    if (options.isEmpty) return null;
    final count = math.min(options.length, 1 + rng.nextInt(maxLines));
    final chosen = <String>[];
    while (chosen.length < count) {
      final id = options[rng.nextInt(options.length)];
      if (!chosen.contains(id)) chosen.add(id);
    }
    final targetKg = capacityKg * (0.4 + 0.5 * rng.nextDouble());
    final perLine = targetKg / chosen.length;
    return [
      for (final id in chosen)
        OrderLine(id, math.max(1, perLine ~/ content.cargoTypes[id]!.unitWeightKg)),
    ];
  }

  ({int allowedS, int penaltyIdr}) _deadlineTerms(Depot depot, int payIdr, int routeS, int weightKg) {
    final eco = content.economy;
    final ops = content.depotOps;
    final estimate = yardS(depot, ops.slotToDockS + ops.dockToGateS) +
        gatePassS(depot) +
        routeS +
        ops.loadingS(weightKg) +
        ops.unloadingS(weightKg);
    return (
      allowedS: math.max(eco.deadlineMinS, (estimate * eco.deadlineSlack).round()),
      penaltyIdr: (payIdr * eco.latePenaltyPerHourPct / 100).round(),
    );
  }

  int _routeSeconds(int from, int to, int weightKg) {
    final profile = _referenceProfile.copyWith(grossWeightT: 1.5 + weightKg / 1000);
    final r = planner.find(from, to, profile, RouteMode.toll);
    return r == null ? 0 : travelTime.legSeconds(r, profile);
  }

  double _routeM(int from, int to) =>
      (planner.find(from, to, _referenceProfile, RouteMode.nonToll) ??
                  planner.find(from, to, _referenceProfile, RouteMode.toll))
              ?.distanceM ??
          0;

  /// Tawaran jasa angkut: jemput di supplier, antar ke toko berjarak
  /// [minKm]–[maxKm] dari supplier. `null` bila tidak ada pasangan yang cocok.
  Contract? offerHaulContract({
    required int depotId,
    required int capacityKg,
    double minKm = 2,
    double maxKm = 10,
  }) {
    final depot = _depot(depotId);
    final id = _nextId++;
    final rng = DeterministicRng.derive(seed, id, 1);
    final picked = _pickHaul(rng, depot, capacityKg, minKm, maxKm);
    if (picked == null) return null;
    final (supplier, lines, dest) = picked;
    final weight = linesWeightKg(lines);
    final km = _routeM(supplier.node, dest) / 1000;
    final pay = content.economy.deliveryFeeIdr(km, weight);
    final terms = _deadlineTerms(depot, pay, _routeSeconds(depot.roadNode, supplier.node, 0) +
        _routeSeconds(supplier.node, dest, weight), weight);
    final customer = content.storeCustomers[rng.nextInt(content.storeCustomers.length)];
    final contract = Contract(
      id: id,
      kind: ContractKind.haul,
      customer: customer,
      cargoId: lines.first.cargoId,
      units: lines.first.units,
      lines: lines,
      weightKg: weight,
      pickupNode: supplier.node,
      pickupName: supplier.name,
      supplierId: supplier.id,
      destinationNode: dest,
      destinationName: customer,
      scope: content.tierRules.classify(sameCity: true, distanceKm: km),
      payIdr: pay,
      offeredAt: now,
      allowedS: terms.allowedS,
      latePenaltyPerHourIdr: terms.penaltyIdr,
    );
    contracts[id] = contract;
    _log(WorldLogKind.contractOffered, {'contract': id});
    return contract;
  }

  (Supplier, List<OrderLine>, int)? _pickHaul(
      DeterministicRng rng, Depot depot, int capacityKg, double minKm, double maxKm) {
    final kinds = _fleetKinds(depot.id);
    final candidates = suppliersFor(depot.id).where((s) => s.sells.any((id) => kinds.contains(content.cargoTypes[id]!.kind))).toList();
    if (candidates.isEmpty) return null;
    final supplier = candidates[rng.nextInt(candidates.length)];
    final lines = _pickLines(rng, supplier, kinds, capacityKg);
    if (lines == null) return null;
    final dest = _pickDestination(rng, depot, supplier.node, minKm, maxKm);
    if (dest == null) return null;
    return (supplier, lines, dest);
  }

  /// Tawaran pesanan toko: toko membeli 1–3 jenis barang gudang (harga barang +
  /// ongkos kirim). Barang diambil dari stok, sisanya dibeli di supplier.
  Contract? offerStoreOrder({
    required int depotId,
    required int capacityKg,
    double minKm = 2,
    double maxKm = 10,
  }) {
    final depot = _depot(depotId);
    final id = _nextId++;
    final rng = DeterministicRng.derive(seed, id, 2);
    final kinds = _fleetKinds(depotId);
    final candidates = suppliersFor(depotId)
        .where((s) => s.sells.any((c) => content.cargoTypes[c]!.storable && kinds.contains(content.cargoTypes[c]!.kind)))
        .toList();
    if (candidates.isEmpty) return null;
    final supplier = candidates[rng.nextInt(candidates.length)];
    final lines = _pickLines(rng, supplier, kinds, capacityKg, maxLines: 3, storableOnly: true);
    if (lines == null) return null;
    final dest = _pickDestination(rng, depot, depot.roadNode, minKm, maxKm);
    if (dest == null) return null;
    final weight = linesWeightKg(lines);
    final km = _routeM(depot.roadNode, dest) / 1000;
    final goods = lines.fold(0, (s, l) => s + l.units * content.economy.storePrice(content.cargoTypes[l.cargoId]!.priceIdr));
    final fee = content.economy.deliveryFeeIdr(km, weight);
    final terms = _deadlineTerms(
        depot,
        fee,
        _routeSeconds(depot.roadNode, supplier.node, 0) + _routeSeconds(supplier.node, dest, weight),
        weight);
    final customer = content.storeCustomers[rng.nextInt(content.storeCustomers.length)];
    final contract = Contract(
      id: id,
      kind: ContractKind.storeOrder,
      customer: customer,
      cargoId: lines.first.cargoId,
      units: lines.first.units,
      lines: lines,
      weightKg: weight,
      pickupNode: supplier.node,
      pickupName: supplier.name,
      supplierId: supplier.id,
      destinationNode: dest,
      destinationName: customer,
      scope: content.tierRules.classify(sameCity: true, distanceKm: km),
      goodsValueIdr: goods,
      payIdr: goods + fee,
      offeredAt: now,
      allowedS: terms.allowedS,
      latePenaltyPerHourIdr: terms.penaltyIdr,
    );
    contracts[id] = contract;
    _log(WorldLogKind.contractOffered, {'contract': id});
    return contract;
  }

  /// Tawaran kontrak berulang jasa angkut.
  Agreement? offerAgreement({
    required int depotId,
    required int capacityKg,
    double minKm = 2,
    double maxKm = 10,
  }) {
    final depot = _depot(depotId);
    final id = _nextId++;
    final rng = DeterministicRng.derive(seed, id, 3);
    final picked = _pickHaul(rng, depot, capacityKg, minKm, maxKm);
    if (picked == null) return null;
    final (supplier, lines, dest) = picked;
    final cfg = content.economy.agreement;
    final weight = linesWeightKg(lines);
    final km = _routeM(supplier.node, dest) / 1000;
    final pay = (content.economy.deliveryFeeIdr(km, weight) * (100 - cfg.payDiscountPct) / 100).round();
    final terms = _deadlineTerms(
        depot, pay, _routeSeconds(depot.roadNode, supplier.node, 0) + _routeSeconds(supplier.node, dest, weight), weight);
    final customer = content.storeCustomers[rng.nextInt(content.storeCustomers.length)];
    final agreement = Agreement(
      id: id,
      customer: customer,
      supplierId: supplier.id,
      pickupNode: supplier.node,
      pickupName: supplier.name,
      destinationNode: dest,
      destinationName: customer,
      scope: content.tierRules.classify(sameCity: true, distanceKm: km),
      lines: lines,
      weightKg: weight,
      payPerRunIdr: pay,
      allowedS: terms.allowedS,
      latePenaltyPerHourIdr: terms.penaltyIdr,
      intervalS: cfg.intervalDays[rng.nextInt(cfg.intervalDays.length)] * daySeconds,
      runsTotal: cfg.runsMin + rng.nextInt(cfg.runsMax - cfg.runsMin + 1),
      offeredAt: now,
    );
    agreements[id] = agreement;
    _log(WorldLogKind.agreementOffered, {'agreement': id});
    return agreement;
  }

  Contract _agreementChild(Agreement a, int id) => Contract(
        id: id,
        kind: ContractKind.haul,
        customer: a.customer,
        cargoId: a.lines.first.cargoId,
        units: a.lines.first.units,
        lines: a.lines,
        weightKg: a.weightKg,
        pickupNode: a.pickupNode,
        pickupName: a.pickupName,
        supplierId: a.supplierId,
        agreementId: a.id,
        destinationNode: a.destinationNode,
        destinationName: a.destinationName,
        scope: a.scope,
        payIdr: a.payPerRunIdr,
        offeredAt: now,
        allowedS: a.allowedS,
        latePenaltyPerHourIdr: a.latePenaltyPerHourIdr,
      );

  /// Periksa satu pengiriman kontrak berulang dengan kendaraan & sopir ini
  /// (tanpa mengubah state; tidak memakai id baru).
  DispatchCheck checkAgreement({required int agreementId, required int vehicleId, required int driverId}) {
    final a = _agreement(agreementId);
    final previewId = -a.id;
    contracts[previewId] = _agreementChild(a, previewId);
    try {
      final result = check(contractId: previewId, vehicleId: vehicleId, driverId: driverId);
      final status = a.status == AgreementStatus.offered || a.isActive;
      return status
          ? result
          : DispatchCheck(problems: [...result.problems, DispatchProblem.contractNotOffered], viaToll: result.viaToll, nonToll: result.nonToll);
    } finally {
      contracts.remove(previewId);
    }
  }

  /// Terima kontrak berulang: pengiriman pertama langsung berangkat, berikutnya
  /// tiap `intervalS` memakai kendaraan yang sama.
  Trip acceptAgreement({
    required int agreementId,
    required int vehicleId,
    required int driverId,
    required RouteMode mode,
  }) {
    final a = _agreement(agreementId);
    if (a.status != AgreementStatus.offered) throw const DispatchException([DispatchProblem.contractNotOffered]);
    final result = checkAgreement(agreementId: agreementId, vehicleId: vehicleId, driverId: driverId);
    if (!result.canDispatch) throw DispatchException(result.problems);
    if (result.quote(mode) == null) throw const DispatchException([DispatchProblem.noRoute]);
    a
      ..status = AgreementStatus.active
      ..vehicleId = vehicleId
      ..driverId = driverId
      ..mode = mode
      ..nextRunAt = now;
    _log(WorldLogKind.agreementAccepted, {'agreement': a.id, 'vehicle': vehicleId});
    return _runAgreement(a, driverId)!;
  }

  /// Tolak tawaran, atau putus kontrak berjalan (denda satu pengiriman).
  void cancelAgreement(int agreementId) {
    final a = _agreement(agreementId);
    switch (a.status) {
      case AgreementStatus.offered:
        agreements.remove(agreementId);
      case AgreementStatus.active:
        a.status = AgreementStatus.cancelled;
        final fine = (a.payPerRunIdr * content.economy.agreement.cancelPenaltyPct / 100).round();
        _postCost(LedgerAccount.agreementPenalty, fine, 'agreement:${a.id}');
        _log(WorldLogKind.agreementCancelled, {'agreement': a.id, 'penalty_idr': fine, 'by_player': true});
      case AgreementStatus.finished:
      case AgreementStatus.cancelled:
        break;
    }
  }

  int cancelPenaltyIdr(int agreementId) =>
      (_agreement(agreementId).payPerRunIdr * content.economy.agreement.cancelPenaltyPct / 100).round();

  /// Berangkatkan satu pengiriman sekarang. `null` bila belum bisa (sibuk/lelah).
  Trip? _runAgreement(Agreement a, int driverId) {
    final vehicleId = a.vehicleId;
    if (vehicleId == null) return null;
    final preview = checkAgreement(agreementId: a.id, vehicleId: vehicleId, driverId: driverId);
    if (!preview.canDispatch) return null;
    final mode = preview.quote(a.mode) != null ? a.mode : (a.mode == RouteMode.toll ? RouteMode.nonToll : RouteMode.toll);
    final child = _agreementChild(a, _nextId++);
    contracts[child.id] = child;
    final trip = dispatch(contractId: child.id, vehicleId: vehicleId, driverId: driverId, mode: mode);
    a.runsDispatched++;
    _scheduleNextRun(a);
    return trip;
  }

  void _scheduleNextRun(Agreement a) {
    if (a.runsDispatched >= a.runsTotal) {
      a
        ..status = AgreementStatus.finished
        ..nextRunAt = null;
      _log(WorldLogKind.agreementFinished, {'agreement': a.id});
      return;
    }
    a.nextRunAt = a.nextRunAt! + a.intervalS;
    if (a.nextRunAt! < now) a.nextRunAt = now;
    queue.schedule(a.nextRunAt!, AgreementRunDue(a.id));
  }

  void _onAgreementRunDue(AgreementRunDue e) {
    final a = agreements[e.agreementId];
    if (a == null || !a.isActive || a.nextRunAt == null || now < a.nextRunAt!) return;
    final driver = _agreementDriver(a);
    if (driver != null && _runAgreement(a, driver) != null) return;
    final cfg = content.economy.agreement;
    if (now + cfg.retryS <= a.nextRunAt! + cfg.graceS) {
      queue.schedule(now + cfg.retryS, AgreementRunDue(a.id));
      return;
    }
    a
      ..runsDispatched++
      ..runsMissed++;
    _log(WorldLogKind.agreementRunMissed, {'agreement': a.id, 'missed': a.runsMissed});
    if (a.runsMissed >= cfg.maxMissed) {
      a
        ..status = AgreementStatus.cancelled
        ..nextRunAt = null;
      _log(WorldLogKind.agreementCancelled, {'agreement': a.id, 'penalty_idr': 0, 'by_player': false});
      return;
    }
    _scheduleNextRun(a);
  }

  /// Sopir utama bila siap, selain itu sopir siap lain di depot kendaraan.
  int? _agreementDriver(Agreement a) {
    final vehicle = vehicles[a.vehicleId];
    if (vehicle == null) return null;
    bool ready(Driver d) =>
        d.depotId == vehicle.depotId && d.isAvailable && d.fatigueAt(now, content.employees.driver) < 1;
    final main = drivers[a.driverId];
    if (main != null && ready(main)) return main.id;
    final others = drivers.values.where(ready).toList()..sort((x, y) => x.id.compareTo(y.id));
    return others.isEmpty ? null : others.first.id;
  }

  // ---------------------------------------------------------------- gudang

  double stockVolumeM3(Depot depot) =>
      linesVolumeM3(depot.stock.entries.map((e) => OrderLine(e.key, e.value)));

  /// Volume barang isi stok yang sedang dalam perjalanan ke gudang (sudah dipesan).
  double incomingVolumeM3(Depot depot) {
    var total = 0.0;
    for (final t in _activeTripsAt(depot)) {
      final c = contracts[t.contractId];
      if (c == null || c.kind != ContractKind.restock) continue;
      if (t.plan.indexOf(t.phase) <= t.plan.indexOf(TripPhase.unloadDock)) total += linesVolumeM3(c.lines);
    }
    return total;
  }

  double warehouseCapacityM3(Depot depot) => facility(depot, FacilityType.warehouse).doubleStat('capacity_m3');

  double warehouseFreeM3(Depot depot) => warehouseCapacityM3(depot) - stockVolumeM3(depot) - incomingVolumeM3(depot);

  /// Nilai stok gudang (harga grosir).
  int stockValueIdr(Depot depot) => depot.stock.entries
      .fold(0, (s, e) => s + e.value * content.economy.restockPrice(content.cargoTypes[e.key]!.priceIdr));

  /// Siapkan pekerjaan isi stok gudang dari [supplierId]. Berangkatkan dengan
  /// [dispatch] (atau batalkan dengan [discardRestock]).
  Contract planRestock({required int depotId, required int supplierId, required List<OrderLine> lines}) {
    final depot = _depot(depotId);
    final supplier = suppliers[supplierId] ?? (throw ArgumentError.value(supplierId, 'supplierId'));
    for (final l in lines) {
      if (!supplier.sells.contains(l.cargoId)) throw ArgumentError('${supplier.name} tidak menjual ${l.cargoId}');
      if (!content.cargoTypes[l.cargoId]!.storable) throw ArgumentError('${l.cargoId} tidak bisa disimpan di gudang');
      if (l.units <= 0) throw ArgumentError.value(l.units, 'units');
    }
    final id = _nextId++;
    final contract = Contract(
      id: id,
      kind: ContractKind.restock,
      customer: depot.name,
      cargoId: lines.first.cargoId,
      units: lines.first.units,
      lines: lines,
      weightKg: linesWeightKg(lines),
      pickupNode: supplier.node,
      pickupName: supplier.name,
      supplierId: supplier.id,
      destinationNode: depot.roadNode,
      destinationName: depot.name,
      scope: DeliveryScope.storeToStore,
      payIdr: 0,
      offeredAt: now,
      allowedS: 0,
      latePenaltyPerHourIdr: 0,
    );
    contracts[id] = contract;
    return contract;
  }

  /// Buang rencana isi stok yang belum diberangkatkan.
  void discardRestock(int contractId) {
    final c = contracts[contractId];
    if (c != null && c.kind == ContractKind.restock && c.status == ContractStatus.offered) contracts.remove(contractId);
  }

  /// Pembagian pesanan toko: ambil dari stok sebanyak mungkin, sisanya dibeli.
  Fulfillment? fulfillmentFor(Contract c, Depot depot) {
    if (c.kind != ContractKind.storeOrder) return null;
    final fromStock = <OrderLine>[];
    final toBuy = <OrderLine>[];
    for (final l in c.lines) {
      final take = math.min(l.units, depot.stockOf(l.cargoId));
      if (take > 0) fromStock.add(OrderLine(l.cargoId, take));
      if (l.units - take > 0) toBuy.add(OrderLine(l.cargoId, l.units - take));
    }
    return Fulfillment(fromStock: fromStock, toBuy: toBuy);
  }

  /// Modal barang yang dibeli di supplier untuk pekerjaan ini.
  int purchaseIdr(Contract c, Fulfillment? f) => switch (c.kind) {
        ContractKind.storeOrder =>
          (f?.toBuy ?? c.lines).fold(0, (s, l) => s + l.units * content.cargoTypes[l.cargoId]!.priceIdr),
        ContractKind.restock => c.lines
            .fold(0, (s, l) => s + l.units * content.economy.restockPrice(content.cargoTypes[l.cargoId]!.priceIdr)),
        ContractKind.haul || ContractKind.legacy => 0,
      };

  List<TripPhase> _planFor(Contract c, Fulfillment? f) => switch (c.kind) {
        ContractKind.legacy => TripPlans.depotLoad,
        ContractKind.haul => TripPlans.pickup,
        ContractKind.restock => TripPlans.restock,
        ContractKind.storeOrder => f != null && f.usesStock
            ? (f.needsPickup ? TripPlans.depotLoadThenPickup : TripPlans.depotLoad)
            : TripPlans.pickup,
      };

  /// Berat yang dimuat di depot (dari gudang / kontrak lama).
  int _depotLoadKg(Contract c, Fulfillment? f) => switch (c.kind) {
        ContractKind.legacy => c.weightKg,
        ContractKind.storeOrder => linesWeightKg(f?.fromStock ?? const []),
        _ => 0,
      };

  /// Berat yang dimuat di supplier.
  int _pickupLoadKg(Contract c, Fulfillment? f) => switch (c.kind) {
        ContractKind.storeOrder => linesWeightKg(f?.toBuy ?? c.lines),
        ContractKind.haul || ContractKind.restock => c.weightKg,
        ContractKind.legacy => 0,
      };

  /// Muatan di kendaraan selama leg [kind].
  int _legKg(Contract c, Fulfillment? f, LegKind kind) => switch (kind) {
        LegKind.pickup => _depotLoadKg(c, f),
        LegKind.outbound => c.weightKg,
        LegKind.inbound => c.kind == ContractKind.restock ? c.weightKg : 0,
      };

  // ---------------------------------------------------------------- dispatch

  /// Periksa kelayakan & hitung estimasi tol / non-tol tanpa mengubah state.
  /// Estimasi mengasumsikan dock & gerbang kosong; antrean menambah waktu.
  DispatchCheck check({required int contractId, required int vehicleId, required int driverId}) {
    final contract = _contract(contractId);
    final vehicle = _vehicle(vehicleId);
    final driver = _driver(driverId);
    final depot = _depot(vehicle.depotId);
    final f = fulfillmentFor(contract, depot);
    final agreement = contract.agreementId == null ? null : agreements[contract.agreementId];
    final problems = <DispatchProblem>[
      if (contract.status != ContractStatus.offered) DispatchProblem.contractNotOffered,
      if (vehicle.tripId != null) DispatchProblem.vehicleBusy,
      if (vehicle.maintenance != null) DispatchProblem.vehicleInWorkshop,
      if (!driver.isAvailable) DispatchProblem.driverBusy,
      if (driver.isAvailable && driver.fatigueAt(now, content.employees.driver) >= 1) DispatchProblem.driverNeedsRest,
      if (!content.tierRules.canDispatch(contract.scope, vehicle.model.vehicleClass))
        DispatchProblem.vehicleClassTooSmall,
      if (contract.weightKg > vehicle.model.payloadKg) DispatchProblem.overCapacity,
      if (!contract.lines.every((l) => vehicle.model.canCarry(content.cargoTypes[l.cargoId]!.kind)))
        DispatchProblem.cargoIncompatible,
      if (cashIdr < purchaseIdr(contract, f)) DispatchProblem.insufficientCash,
      if (contract.kind == ContractKind.restock && linesVolumeM3(contract.lines) > warehouseFreeM3(depot) + 1e-9)
        DispatchProblem.warehouseFull,
      if (agreement?.vehicleId case final v? when v != vehicleId) DispatchProblem.wrongVehicle,
    ];
    final viaToll = _quote(contract, vehicle, driver, RouteMode.toll, f);
    final nonToll = _quote(contract, vehicle, driver, RouteMode.nonToll, f);
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
    final depot = _depot(vehicle.depotId);
    final pickupRoute = quote.pickupRoute;
    final outboundRoute = quote.outboundRoute;
    final trip = Trip(
      id: _nextId++,
      contractId: contractId,
      vehicleId: vehicleId,
      driverId: driverId,
      mode: mode,
      plan: quote.plan,
      pickup: pickupRoute == null ? null : TripLeg.fromRoute(pickupRoute, quote.pickupS),
      outbound: outboundRoute == null
          ? TripLeg.none(contract.pickupNode ?? depot.roadNode)
          : TripLeg.fromRoute(outboundRoute, quote.outboundS),
      inbound: TripLeg.fromRoute(quote.inboundRoute, quote.inboundS),
      startedAt: now,
      phase: quote.plan.first,
      phaseStart: now,
      phaseEnd: now,
    );
    trips[trip.id] = trip;
    contract
      ..status = ContractStatus.inProgress
      ..deadline = quote.deadline
      ..fulfillment = quote.fulfillment;
    // Stok dialokasikan sekarang agar tidak dipakai pesanan lain.
    for (final l in quote.fulfillment?.fromStock ?? const <OrderLine>[]) {
      depot.addStock(l.cargoId, -l.units);
    }
    vehicle.tripId = trip.id;
    driver
      ..fatigue = driver.fatigueAt(now, content.employees.driver)
      ..tripId = trip.id;
    _log(WorldLogKind.dispatched, {
      'trip': trip.id,
      'contract': contractId,
      'vehicle': vehicleId,
      'driver': driverId,
      'mode': mode.name,
    });
    _enter(trip, trip.plan.first);
    _serveDockQueue(depot);
    return trip;
  }

  DispatchQuote? _quote(Contract contract, Vehicle vehicle, Driver driver, RouteMode mode, Fulfillment? f) {
    final depot = _depot(vehicle.depotId);
    final plan = _planFor(contract, f);
    final ops = content.depotOps;

    Route? pickup;
    var pickupS = 0;
    if (plan.contains(TripPhase.toPickup)) {
      final node = contract.pickupNode;
      if (node == null) return null;
      final profile = vehicleProfile(vehicle, cargoKg: _legKg(contract, f, LegKind.pickup));
      pickup = planner.find(depot.roadNode, node, profile, mode);
      if (pickup == null) return null;
      pickupS = travelTime.legSeconds(pickup, profile);
    }
    final fromNode = pickup == null ? depot.roadNode : contract.pickupNode!;

    Route? out;
    var outS = 0;
    if (plan.contains(TripPhase.outbound)) {
      final profile = vehicleProfile(vehicle, cargoKg: _legKg(contract, f, LegKind.outbound));
      out = planner.find(fromNode, contract.destinationNode, profile, mode);
      if (out == null) return null;
      outS = travelTime.legSeconds(out, profile);
    }
    final backFrom = out == null ? fromNode : contract.destinationNode;
    final backProfile = vehicleProfile(vehicle, cargoKg: _legKg(contract, f, LegKind.inbound));
    final back = planner.find(backFrom, depot.roadNode, backProfile, mode);
    if (back == null) return null;
    final backS = travelTime.legSeconds(back, backProfile);

    final before = plan.contains(TripPhase.loading)
        ? yardS(depot, ops.slotToDockS) +
            loadingS(depot, _depotLoadKg(contract, f)) +
            yardS(depot, ops.dockToGateS) +
            gatePassS(depot)
        : yardS(depot, ops.slotToDockS + ops.dockToGateS) + gatePassS(depot);
    final pickupLoading = pickup == null ? 0 : ops.loadingS(_pickupLoadKg(contract, f));
    final unloading = out == null ? 0 : ops.unloadingS(contract.weightKg);
    final dockUnload = plan.contains(TripPhase.unloadDock)
        ? yardS(depot, ops.slotToDockS) + loadingS(depot, contract.weightKg) + yardS(depot, ops.gateToSlotS)
        : 0;
    final deadline = contract.hasDeadline ? now + contract.allowedS : now + 365 * daySeconds;
    final deliveryEta = now + before + pickupS + pickupLoading + outS + unloading;
    return DispatchQuote(
      mode: mode,
      plan: plan,
      pickupRoute: pickup,
      outboundRoute: out,
      inboundRoute: back,
      pickupS: pickupS,
      pickupLoadingS: pickupLoading,
      outboundS: outS,
      inboundS: backS,
      beforeDepartureS: before,
      unloadingS: unloading,
      afterReturnS: gatePassS(depot) + yardS(depot, ops.gateToSlotS) + dockUnload + ops.inspectionS,
      dispatchAt: now,
      deadline: deadline,
      revenueIdr: contract.settlementAt(deliveryEta, deadline: deadline),
      fuelIdr: (pickup == null ? 0 : _fuelIdr(vehicle, driver, pickup.distanceM)) +
          (out == null ? 0 : _fuelIdr(vehicle, driver, out.distanceM)) +
          _fuelIdr(vehicle, driver, back.distanceM),
      fatigueAfter:
          driver.fatigueAt(now, content.employees.driver) + content.employees.driver.fatigueFor(pickupS + outS + backS),
      tollIdr: (pickup?.tollCostIdr ?? 0) + (out?.tollCostIdr ?? 0) + back.tollCostIdr,
      purchaseIdr: purchaseIdr(contract, f),
      stockValueIdr: (f?.fromStock ?? const <OrderLine>[])
          .fold(0, (s, l) => s + l.units * content.economy.restockPrice(content.cargoTypes[l.cargoId]!.priceIdr)),
      fulfillment: f,
    );
  }

  int _fuelIdr(Vehicle vehicle, Driver driver, num distanceM) => content.economy.fuelCostIdr(
        distanceM.round().toDouble(),
        fuelLPer100Km(vehicle) * content.employees.driver.fuelFactor(driver.skill),
      );

  /// Konsumsi BBM aktual: naik bila mesin & ban aus.
  double fuelLPer100Km(Vehicle vehicle) {
    final m = content.maintenance;
    final c = vehicle.condition;
    return vehicle.model.fuelLPer100Km *
        (1 + m.fuelPerEngineWear * (1 - c[VehicleComponent.engine]!) + m.fuelPerTireWear * (1 - c[VehicleComponent.tires]!));
  }

  /// Profil routing aktual: kecepatan turun bila mesin/transmisi aus.
  VehicleProfile vehicleProfile(Vehicle vehicle, {int cargoKg = 0}) {
    final c = vehicle.condition;
    final drive = math.min(c[VehicleComponent.engine]!, c[VehicleComponent.transmission]!);
    final min = content.maintenance.minSpeedFactor;
    return vehicle.model.profile(cargoKg: cargoKg).copyWith(speedFactor: min + (1 - min) * drive);
  }

  // ---------------------------------------------------------------- waktu

  /// Proses semua event sampai detik game [time]. Mengembalikan jumlah event.
  int advanceTo(int time) => queue.runUntil(time, _handle);

  void _handle(ScheduledEvent scheduled, EventQueue queue) {
    switch (scheduled.event) {
      case final TripPhaseEnded e:
        _onPhaseEnded(e);
      case final ConstructionFinished e:
        _onConstructionFinished(e);
      case PayrollDue():
        _onPayroll();
      case final MaintenanceFinished e:
        _onMaintenanceFinished(e);
      case final AgreementRunDue e:
        _onAgreementRunDue(e);
    }
  }

  void _onPhaseEnded(TripPhaseEnded e) {
    final trip = trips[e.tripId];
    if (trip == null || trip.phase != e.phase) return;
    final contract = _contract(trip.contractId);
    final vehicle = _vehicle(trip.vehicleId);
    final driver = _driver(trip.driverId);
    final depot = _depot(vehicle.depotId);
    final ref = 'trip:${trip.id}';
    final next = trip.next(e.phase);

    switch (e.phase) {
      case TripPhase.loading:
      case TripPhase.unloadDock:
        if (e.phase == TripPhase.unloadDock) {
          for (final l in contract.lines) {
            depot.addStock(l.cargoId, l.units);
          }
          _log(WorldLogKind.restocked, {'trip': trip.id, 'contract': contract.id, 'depot': depot.id});
        }
        trip.dock = null;
        _enter(trip, next);
        _serveDockQueue(depot);
      case TripPhase.toGate:
      case TripPhase.toGateDirect:
        _enter(trip, next);
        _serveGateQueue(depot);
      case TripPhase.gateOut:
        trip.gateLane = null;
        _log(WorldLogKind.departedDepot, {'trip': trip.id, 'vehicle': vehicle.id});
        _enter(trip, next);
        _serveGateQueue(depot);
      case TripPhase.toPickup:
        _finishLeg(trip.pickup!, vehicle, driver, ref);
        _enter(trip, next);
      case TripPhase.pickupLoading:
        final cost = purchaseIdr(contract, contract.fulfillment);
        _postCost(LedgerAccount.goodsPurchase, cost, ref);
        _log(WorldLogKind.pickedUp, {
          'trip': trip.id,
          'contract': contract.id,
          'supplier': contract.supplierId,
          'cost_idr': cost,
        });
        _enter(trip, next);
      case TripPhase.outbound:
        _finishLeg(trip.outbound, vehicle, driver, ref);
        _enter(trip, next);
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
          if (contract.agreementId != null) 'agreement': contract.agreementId,
        });
        _enter(trip, next);
      case TripPhase.inbound:
        _finishLeg(trip.inbound, vehicle, driver, ref);
        // Keausan seluruh trip diterapkan setelah pulang agar biaya BBM tiap
        // leg sama persis dengan estimasi saat dispatch.
        for (final kind in LegKind.values) {
          final leg = trip.leg(kind);
          if (leg != null) _wear(vehicle, driver, leg.distanceM, _legKg(contract, contract.fulfillment, kind));
        }
        final rules = content.employees.driver;
        final roadS = (trip.pickup?.durationS ?? 0) + trip.outbound.durationS + trip.inbound.durationS;
        driver.skill = math.min(1.0, driver.skill + rules.skillGainPerHour * roadS / 3600);
        _log(WorldLogKind.returnedToDepot, {'trip': trip.id, 'vehicle': vehicle.id});
        _enter(trip, next);
        _serveGateQueue(depot);
      case TripPhase.gateIn:
        trip.gateLane = null;
        _enter(trip, next);
        _serveGateQueue(depot);
      case TripPhase.toSlot:
        _enter(trip, next);
        if (next == TripPhase.waitDockIn) _serveDockQueue(depot);
      case TripPhase.toDock:
      case TripPhase.toDockIn:
      case TripPhase.dockToSlot:
        _enter(trip, next);
      case TripPhase.inspection:
        vehicle.tripId = null;
        driver
          ..tripId = null
          ..restingSince = now;
        if (contract.status == ContractStatus.inProgress && contract.kind == ContractKind.restock) {
          contract
            ..status = ContractStatus.delivered
            ..deliveredAt = now
            ..settledIdr = 0;
        }
        _log(WorldLogKind.tripCompleted, {'trip': trip.id, 'vehicle': vehicle.id});
        _enter(trip, TripPhase.completed);
        for (final kind in LegKind.values) {
          _tracks.remove((trip.id, kind));
        }
      case TripPhase.waitDock:
      case TripPhase.waitGateOut:
      case TripPhase.waitGateIn:
      case TripPhase.waitDockIn:
      case TripPhase.completed:
        break;
    }
  }

  /// Masuk ke fase [phase] sekarang; jadwalkan akhirnya bila bukan antrean.
  /// Masuk leg di jalan = bayar tol leg itu.
  void _enter(Trip trip, TripPhase phase) {
    trip
      ..phase = phase
      ..phaseStart = now;
    final kind = trip.legKind;
    if (kind != null) _postCost(LedgerAccount.toll, trip.leg(kind)!.tollIdr, 'trip:${trip.id}');
    if (phase.waiting || phase == TripPhase.completed) {
      trip.phaseEnd = now;
      return;
    }
    trip.phaseEnd = now + _phaseDuration(trip);
    queue.schedule(trip.phaseEnd, TripPhaseEnded(trip.id, phase));
  }

  int _phaseDuration(Trip trip) {
    final ops = content.depotOps;
    final contract = _contract(trip.contractId);
    final f = contract.fulfillment;
    final depot = _depot(_vehicle(trip.vehicleId).depotId);
    return switch (trip.phase) {
      TripPhase.toDock || TripPhase.toDockIn => yardS(depot, ops.slotToDockS),
      TripPhase.loading => loadingS(depot, _depotLoadKg(contract, f)),
      TripPhase.toGate => yardS(depot, ops.dockToGateS),
      TripPhase.toGateDirect => yardS(depot, ops.slotToDockS + ops.dockToGateS),
      TripPhase.gateOut || TripPhase.gateIn => gatePassS(depot),
      TripPhase.toPickup => trip.pickup!.durationS,
      TripPhase.pickupLoading => ops.loadingS(_pickupLoadKg(contract, f)),
      TripPhase.outbound => trip.outbound.durationS,
      TripPhase.unloading => ops.unloadingS(contract.weightKg),
      TripPhase.inbound => trip.inbound.durationS,
      TripPhase.toSlot || TripPhase.dockToSlot => yardS(depot, ops.gateToSlotS),
      TripPhase.unloadDock => loadingS(depot, contract.weightKg),
      TripPhase.inspection => ops.inspectionS,
      TripPhase.waitDock ||
      TripPhase.waitGateOut ||
      TripPhase.waitGateIn ||
      TripPhase.waitDockIn ||
      TripPhase.completed =>
        0,
    };
  }

  Iterable<Trip> _activeTripsAt(Depot depot) =>
      trips.values.where((t) => t.isActive && vehicles[t.vehicleId]!.depotId == depot.id);

  /// Trip yang menunggu di antrean [phases], urut kedatangan (FIFO).
  List<Trip> _waiting(Depot depot, Set<TripPhase> phases) =>
      _activeTripsAt(depot).where((t) => phases.contains(t.phase)).toList()
        ..sort((a, b) => a.phaseStart != b.phaseStart ? a.phaseStart.compareTo(b.phaseStart) : a.id.compareTo(b.id));

  int? _free(int capacity, Iterable<int?> used) {
    final taken = used.whereType<int>().toSet();
    for (var i = 0; i < capacity; i++) {
      if (!taken.contains(i)) return i;
    }
    return null;
  }

  void _serveDockQueue(Depot depot) {
    for (final trip in _waiting(depot, const {TripPhase.waitDock, TripPhase.waitDockIn})) {
      final dock = _free(dockCount(depot), _activeTripsAt(depot).map((t) => t.dock));
      if (dock == null) return;
      trip.dock = dock;
      _enter(trip, trip.phase == TripPhase.waitDock ? TripPhase.toDock : TripPhase.toDockIn);
    }
  }

  void _serveGateQueue(Depot depot) {
    for (final trip in _waiting(depot, const {TripPhase.waitGateOut, TripPhase.waitGateIn})) {
      final lane = _free(gateLaneCount(depot), _activeTripsAt(depot).map((t) => t.gateLane));
      if (lane == null) return;
      trip.gateLane = lane;
      _enter(trip, trip.phase == TripPhase.waitGateOut ? TripPhase.gateOut : TripPhase.gateIn);
    }
  }

  void _finishLeg(TripLeg leg, Vehicle vehicle, Driver driver, String ref) {
    vehicle.odometerM += leg.distanceM;
    driver
      ..drivingSeconds += leg.durationS
      ..fatigue += content.employees.driver.fatigueFor(leg.durationS);
    _postCost(LedgerAccount.fuel, _fuelIdr(vehicle, driver, leg.distanceM), ref);
  }

  /// Keausan komponen sebanding jarak, lebih cepat saat bermuatan & bila
  /// sopir kurang terampil.
  void _wear(Vehicle vehicle, Driver driver, int distanceM, int cargoKg) {
    final m = content.maintenance;
    final load = (cargoKg / vehicle.model.payloadKg).clamp(0.0, 1.0);
    final factor = distanceM / 1000 * (1 + m.loadedWearFactor * load) * content.employees.driver.wearFactor(driver.skill);
    for (final c in VehicleComponent.values) {
      vehicle.condition[c] = math.max(0, vehicle.condition[c]! - m.wearPer1000Km[c]! / 1000 * factor);
    }
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
        inWorkshop: vehicle.maintenance != null,
      );
    }
    final t = at ?? now;
    final span = trip.phaseEnd - trip.phaseStart;
    final progress = trip.phase.waiting
        ? 0.0
        : span <= 0
            ? 1.0
            : ((t - trip.phaseStart) / span).clamp(0.0, 1.0);
    final contract = _contract(trip.contractId);

    TrackPose? pose;
    var activity = VehicleActivity.inDepot;
    final legKind = trip.legKind;
    if (legKind != null) {
      activity = VehicleActivity.onRoad;
      pose = _track(trip, vehicle, contract, legKind).poseAt(progress);
    } else if (trip.phase == TripPhase.unloading) {
      activity = VehicleActivity.atDestination;
      pose = TrackPose(graph.node(contract.destinationNode), 0);
    } else if (trip.phase == TripPhase.pickupLoading) {
      activity = VehicleActivity.atDestination;
      pose = TrackPose(graph.node(contract.pickupNode!), 0);
    }
    int? queuePosition;
    if (trip.phase.waiting) {
      final depot = _depot(vehicle.depotId);
      queuePosition = _waiting(depot, {trip.phase}).indexOf(trip);
    }
    return VehicleSnapshot(
      vehicleId: vehicleId,
      activity: activity,
      slotIndex: vehicle.slotIndex,
      tripId: trip.id,
      phase: trip.phase,
      phaseProgress: progress,
      pose: pose,
      dock: trip.dock,
      gateLane: trip.gateLane,
      queuePosition: queuePosition,
    );
  }

  /// Polyline & pembagian waktu leg pergi/pulang sebuah trip (untuk peta).
  RouteTrack trackFor(int tripId, {required bool outbound}) =>
      trackForLeg(tripId, outbound ? LegKind.outbound : LegKind.inbound);

  /// Polyline satu leg ([LegKind.pickup] = depot → supplier). Leg yang tidak
  /// ditempuh trip ini → track satu titik.
  RouteTrack trackForLeg(int tripId, LegKind kind) {
    final trip = trips[tripId] ?? (throw ArgumentError.value(tripId, 'tripId'));
    return _track(trip, _vehicle(trip.vehicleId), _contract(trip.contractId), kind);
  }

  RouteTrack _track(Trip trip, Vehicle vehicle, Contract contract, LegKind kind) =>
      _tracks.putIfAbsent((trip.id, kind), () {
        final leg = trip.leg(kind) ?? TripLeg.none(trip.inbound.startNode);
        final profile = vehicleProfile(vehicle, cargoKg: _legKg(contract, contract.fulfillment, kind));
        return RouteTrack.build(
          graph,
          leg.edges,
          startNode: leg.startNode,
          speedMps: (e) => planner.speedMps(e, profile),
        );
      });

  // ---------------------------------------------------------------- save

  /// Format 3: fasilitas level 1–15 (tier visual), supplier, kontrak berulang,
  /// stok gudang, rencana fase trip, tahun produksi kendaraan.
  /// Format 2: fasilitas ber-level (1–3), antrean, karyawan, gaji harian.
  static const saveFormat = 3;

  /// Level fasilitas save format ≤ 2 (1–3) → level baru dengan tampilan sama.
  static const legacyLevelMap = {1: 1, 2: 4, 3: 8};

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
        'suppliers': [for (final s in suppliers.values) s.toJson()],
        'agreements': [for (final a in agreements.values) a.toJson()],
        'used_bought': usedBought.toList()..sort(),
        'ledger': ledger.toJson(),
        'log': [for (final l in log) l.toJson()],
        'events': [
          for (final e in queue.snapshot())
            {
              't': e.time,
              'p': e.priority,
              'seq': e.seq,
              'type': e.event.type,
              'data': (e.event as WorldEvent).toJson(),
            },
        ],
      };

  factory SimWorld.fromJson(
    Map<String, dynamic> json, {
    required RoadGraph graph,
    required GameContent content,
    TravelTimeModel travelTime = const RouteEstimateTravelTime(),
  }) {
    final format = json['format'];
    if (format is! int || format < 1 || format > saveFormat) {
      throw FormatException('Format save tidak didukung: $format');
    }
    List<Map<String, dynamic>> rows(String key) => (json[key] as List).cast<Map<String, dynamic>>();
    final queue = EventQueue(nextSeq: json['next_seq'] as int, processedUntil: json['now'] as int);
    queue.restore([
      for (final e in rows('events'))
        ScheduledEvent(
          time: e['t'] as int,
          priority: e['p'] as int,
          seq: e['seq'] as int,
          event: WorldEvent.fromJson(e['type'] as String, e['data'] as Map<String, dynamic>),
        ),
    ]);
    final world = SimWorld._(
      graph: graph,
      content: content,
      travelTime: travelTime,
      seed: json['seed'] as int,
      companyName: json['company'] as String,
      queue: queue,
      ledger: Ledger.fromJson(json['ledger'] as List),
      depots: {for (final d in rows('depots').map(Depot.fromJson)) d.id: d},
      vehicles: {
        for (final v in rows('vehicles').map((r) =>
            Vehicle.fromJson(r, content.vehicleModels, defaultYear: content.economy.vehicleMarket.startYear)))
          v.id: v,
      },
      drivers: {for (final d in rows('drivers').map((r) => Driver.fromJson(r, content.employees))) d.id: d},
      contracts: {for (final c in rows('contracts').map(Contract.fromJson)) c.id: c},
      trips: {for (final t in rows('trips').map(Trip.fromJson)) t.id: t},
      log: rows('log').map(WorldLogEntry.fromJson).toList(),
      nextId: json['next_id'] as int,
      suppliers: {
        for (final s in ((json['suppliers'] as List?) ?? const []).cast<Map<String, dynamic>>().map(Supplier.fromJson))
          s.id: s,
      },
      agreements: {
        for (final a in ((json['agreements'] as List?) ?? const []).cast<Map<String, dynamic>>().map(Agreement.fromJson))
          a.id: a,
      },
      usedBought: {...((json['used_bought'] as List?) ?? const []).cast<String>()},
    );
    if (format == 1) world._migrateFromV1();
    if (format < 3) world._migrateLevelsFromV2();
    world._ensureSuppliers();
    world._applyBuildTimes();
    return world;
  }

  /// Konstruksi berjalan mengikuti lama bangun di konten terbaru bila lebih
  /// singkat (mis. setelah penyeimbangan), tanpa menunggu jadwal lama.
  void _applyBuildTimes() {
    for (final depot in depots.values) {
      final c = depot.construction;
      if (c == null) continue;
      final finish = c.startedAt + content.facilities[c.type].level(c.toLevel).buildMinutes * 60;
      if (finish >= c.finishAt) continue;
      final at = finish < now ? now : finish;
      depot.construction = FacilityConstruction(type: c.type, toLevel: c.toLevel, startedAt: c.startedAt, finishAt: at);
      queue.schedule(at, ConstructionFinished(depot.id));
    }
  }

  /// Save ≤ v2: level fasilitas 1–3 → 1 / 4 / 8 (tampilan sama, statistik
  /// mengikuti tabel 15 level). Slot parkir hanya bertambah, tidak berkurang.
  void _migrateLevelsFromV2() {
    for (final depot in depots.values) {
      for (final t in FacilityType.values) {
        depot.levels[t] = legacyLevelMap[depot.level(t)] ?? depot.level(t);
      }
      final c = depot.construction;
      if (c != null) {
        depot.construction = FacilityConstruction(
          type: c.type,
          toLevel: legacyLevelMap[c.toLevel] ?? c.toLevel,
          startedAt: c.startedAt,
          finishAt: c.finishAt,
        );
      }
      depot.growSlots(facility(depot, FacilityType.parking).intStat('slots'));
    }
  }

  /// Save v1 (Tahap 2b): belum ada gaji harian & dock/jalur gerbang di trip.
  void _migrateFromV1() {
    if (!queue.snapshot().any((e) => e.event is PayrollDue)) _schedulePayroll();
    for (final t in trips.values) {
      if (t.phase == TripPhase.toDock || t.phase == TripPhase.loading) t.dock ??= 0;
    }
  }

  // ---------------------------------------------------------------- util

  void _log(WorldLogKind kind, Map<String, Object?> data) =>
      log.add(WorldLogEntry(now, kind, data));

  Depot _depot(int id) => depots[id] ?? (throw ArgumentError.value(id, 'depotId'));
  Vehicle _vehicle(int id) => vehicles[id] ?? (throw ArgumentError.value(id, 'vehicleId'));
  Driver _driver(int id) => drivers[id] ?? (throw ArgumentError.value(id, 'driverId'));
  Contract _contract(int id) => contracts[id] ?? (throw ArgumentError.value(id, 'contractId'));
  Agreement _agreement(int id) => agreements[id] ?? (throw ArgumentError.value(id, 'agreementId'));
}
