import 'dart:math' as math;

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
import '../vehicle/vehicle_profile.dart';
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

enum VehicleActivity {
  /// Diam di slot parkir, siap dipakai.
  parked,

  /// Bergerak / bekerja / antre di depot (termasuk antre di jalan depan gerbang).
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
}

enum HireProblem { officeFull, noCandidate }

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
  })  : planner = RoutePlanner(graph),
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
        vehicleId: Vehicle(id: vehicleId, model: model, depotId: depotId, slotIndex: 0),
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

  /// Detik game per hari; detik 0 = Hari 1 pukul 06.00.
  static const daySeconds = 86400;
  static const dayStartOffset = 6 * 3600;

  /// Waktu simulasi saat ini (detik game).
  int get now => queue.processedUntil;

  int get cashIdr => ledger.cashIdr;

  // ---------------------------------------------------------------- fasilitas

  FacilityLevel facility(Depot depot, FacilityType type) =>
      content.facilities[type].level(depot.level(type));

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
      if (_depot(depotId).firstFreeSlot == null) PurchaseProblem.noFreeSlot,
      if (model != null && model.unlock.terminal) PurchaseProblem.needsTruckTerminal,
      if (model?.unlock.facilityId case final f?
          when _depot(depotId).level(FacilityType.parse(f)) < model!.unlock.level)
        PurchaseProblem.facilityLevelTooLow,
      if (model != null && cashIdr < model.priceIdr) PurchaseProblem.insufficientCash,
    ];
  }

  /// Beli kendaraan baru; langsung menempati slot parkir kosong pertama.
  Vehicle buyVehicle(int depotId, String modelId) {
    final problems = purchaseProblems(depotId, modelId);
    if (problems.isNotEmpty) throw CommandException(problems);
    final depot = _depot(depotId);
    final model = content.vehicleModels[modelId]!;
    final slot = depot.firstFreeSlot!;
    final vehicle = Vehicle(id: _nextId++, model: model, depotId: depot.id, slotIndex: slot);
    depot.slots[slot] = vehicle.id;
    vehicles[vehicle.id] = vehicle;
    ledger.post(LedgerEntry(
      time: now,
      account: LedgerAccount.vehiclePurchase,
      amountIdr: -model.priceIdr,
      ref: 'vehicle:${vehicle.id}',
    ));
    _log(WorldLogKind.vehiclePurchased, {'vehicle': vehicle.id, 'model': model.id});
    return vehicle;
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

  // ---------------------------------------------------------------- dispatch

  /// Periksa kelayakan & hitung estimasi tol / non-tol tanpa mengubah state.
  /// Estimasi mengasumsikan dock & gerbang kosong; antrean menambah waktu.
  DispatchCheck check({required int contractId, required int vehicleId, required int driverId}) {
    final contract = _contract(contractId);
    final vehicle = _vehicle(vehicleId);
    final driver = _driver(driverId);
    final problems = <DispatchProblem>[
      if (contract.status != ContractStatus.offered) DispatchProblem.contractNotOffered,
      if (vehicle.tripId != null) DispatchProblem.vehicleBusy,
      if (vehicle.maintenance != null) DispatchProblem.vehicleInWorkshop,
      if (!driver.isAvailable) DispatchProblem.driverBusy,
      if (driver.isAvailable && driver.fatigueAt(now, content.employees.driver) >= 1) DispatchProblem.driverNeedsRest,
      if (!content.tierRules.canDispatch(contract.scope, vehicle.model.vehicleClass))
        DispatchProblem.vehicleClassTooSmall,
      if (contract.weightKg > vehicle.model.payloadKg) DispatchProblem.overCapacity,
      if (!vehicle.model.canCarry(content.cargoTypes[contract.cargoId]!.kind)) DispatchProblem.cargoIncompatible,
    ];
    final viaToll = _quote(contract, vehicle, driver, RouteMode.toll);
    final nonToll = _quote(contract, vehicle, driver, RouteMode.nonToll);
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
      phase: TripPhase.waitDock,
      phaseStart: now,
      phaseEnd: now,
    );
    trips[trip.id] = trip;
    contract
      ..status = ContractStatus.inProgress
      ..deadline = quote.deadline;
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
    _serveDockQueue(_depot(vehicle.depotId));
    return trip;
  }

  DispatchQuote? _quote(Contract contract, Vehicle vehicle, Driver driver, RouteMode mode) {
    final depot = _depot(vehicle.depotId);
    final loaded = vehicleProfile(vehicle, cargoKg: contract.weightKg);
    final empty = vehicleProfile(vehicle);
    final out = planner.find(depot.roadNode, contract.destinationNode, loaded, mode);
    final back = planner.find(contract.destinationNode, depot.roadNode, empty, mode);
    if (out == null || back == null) return null;

    final ops = content.depotOps;
    final outS = travelTime.legSeconds(out, loaded);
    final backS = travelTime.legSeconds(back, empty);
    final deadline = now + contract.allowedS;
    final before = ops.slotToDockS + loadingS(depot, contract.weightKg) + ops.dockToGateS + gatePassS(depot);
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
      afterReturnS: gatePassS(depot) + ops.gateToSlotS + ops.inspectionS,
      dispatchAt: now,
      deadline: deadline,
      revenueIdr: contract.settlementAt(deliveryEta, deadline: deadline),
      fuelIdr: _fuelIdr(vehicle, driver, out.distanceM) + _fuelIdr(vehicle, driver, back.distanceM),
      fatigueAfter: driver.fatigueAt(now, content.employees.driver) + content.employees.driver.fatigueFor(outS + backS),
      tollIdr: out.tollCostIdr + back.tollCostIdr,
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

    switch (e.phase) {
      case TripPhase.toDock:
        _enter(trip, TripPhase.loading);
      case TripPhase.loading:
        trip.dock = null;
        _enter(trip, TripPhase.toGate);
        _serveDockQueue(depot);
      case TripPhase.toGate:
        _enter(trip, TripPhase.waitGateOut);
        _serveGateQueue(depot);
      case TripPhase.gateOut:
        trip.gateLane = null;
        _postCost(LedgerAccount.toll, trip.outbound.tollIdr, ref);
        _log(WorldLogKind.departedDepot, {'trip': trip.id, 'vehicle': vehicle.id});
        _enter(trip, TripPhase.outbound);
        _serveGateQueue(depot);
      case TripPhase.outbound:
        _finishLeg(trip.outbound, vehicle, driver, ref);
        _enter(trip, TripPhase.unloading);
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
        _enter(trip, TripPhase.inbound);
      case TripPhase.inbound:
        _finishLeg(trip.inbound, vehicle, driver, ref);
        // Keausan seluruh trip diterapkan setelah pulang agar biaya BBM kedua
        // leg sama persis dengan estimasi saat dispatch.
        _wear(vehicle, driver, trip.outbound.distanceM, contract.weightKg);
        _wear(vehicle, driver, trip.inbound.distanceM, 0);
        final rules = content.employees.driver;
        driver.skill = math.min(
          1.0,
          driver.skill + rules.skillGainPerHour * (trip.outbound.durationS + trip.inbound.durationS) / 3600,
        );
        _log(WorldLogKind.returnedToDepot, {'trip': trip.id, 'vehicle': vehicle.id});
        _enter(trip, TripPhase.waitGateIn);
        _serveGateQueue(depot);
      case TripPhase.gateIn:
        trip.gateLane = null;
        _enter(trip, TripPhase.toSlot);
        _serveGateQueue(depot);
      case TripPhase.toSlot:
        _enter(trip, TripPhase.inspection);
      case TripPhase.inspection:
        vehicle.tripId = null;
        driver
          ..tripId = null
          ..restingSince = now;
        _log(WorldLogKind.tripCompleted, {'trip': trip.id, 'vehicle': vehicle.id});
        _enter(trip, TripPhase.completed);
        _tracks.remove((trip.id, true));
        _tracks.remove((trip.id, false));
      case TripPhase.waitDock:
      case TripPhase.waitGateOut:
      case TripPhase.waitGateIn:
      case TripPhase.completed:
        break;
    }
  }

  /// Masuk ke fase [phase] sekarang; jadwalkan akhirnya bila bukan antrean.
  void _enter(Trip trip, TripPhase phase) {
    trip
      ..phase = phase
      ..phaseStart = now;
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
    final depot = _depot(_vehicle(trip.vehicleId).depotId);
    return switch (trip.phase) {
      TripPhase.toDock => ops.slotToDockS,
      TripPhase.loading => loadingS(depot, contract.weightKg),
      TripPhase.toGate => ops.dockToGateS,
      TripPhase.gateOut || TripPhase.gateIn => gatePassS(depot),
      TripPhase.outbound => trip.outbound.durationS,
      TripPhase.unloading => ops.unloadingS(contract.weightKg),
      TripPhase.inbound => trip.inbound.durationS,
      TripPhase.toSlot => ops.gateToSlotS,
      TripPhase.inspection => ops.inspectionS,
      TripPhase.waitDock || TripPhase.waitGateOut || TripPhase.waitGateIn || TripPhase.completed => 0,
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
    for (final trip in _waiting(depot, const {TripPhase.waitDock})) {
      final dock = _free(dockCount(depot), _activeTripsAt(depot).map((t) => t.dock));
      if (dock == null) return;
      trip.dock = dock;
      _enter(trip, TripPhase.toDock);
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
    if (trip.phase.onRoad) {
      activity = VehicleActivity.onRoad;
      final outbound = trip.phase == TripPhase.outbound;
      pose = _track(trip, vehicle, contract, outbound).poseAt(progress);
    } else if (trip.phase == TripPhase.unloading) {
      activity = VehicleActivity.atDestination;
      pose = TrackPose(graph.node(contract.destinationNode), 0);
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
  RouteTrack trackFor(int tripId, {required bool outbound}) {
    final trip = trips[tripId] ?? (throw ArgumentError.value(tripId, 'tripId'));
    return _track(trip, _vehicle(trip.vehicleId), _contract(trip.contractId), outbound);
  }

  RouteTrack _track(Trip trip, Vehicle vehicle, Contract contract, bool outbound) =>
      _tracks.putIfAbsent((trip.id, outbound), () {
        final leg = outbound ? trip.outbound : trip.inbound;
        final profile = vehicleProfile(vehicle, cargoKg: outbound ? contract.weightKg : 0);
        return RouteTrack.build(
          graph,
          leg.edges,
          startNode: leg.startNode,
          speedMps: (e) => planner.speedMps(e, profile),
        );
      });

  // ---------------------------------------------------------------- save

  /// Format 2: fasilitas ber-level, antrean, karyawan, gaji harian.
  static const saveFormat = 2;

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
    if (format != 1 && format != saveFormat) {
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
        for (final v in rows('vehicles').map((r) => Vehicle.fromJson(r, content.vehicleModels))) v.id: v,
      },
      drivers: {for (final d in rows('drivers').map((r) => Driver.fromJson(r, content.employees))) d.id: d},
      contracts: {for (final c in rows('contracts').map(Contract.fromJson)) c.id: c},
      trips: {for (final t in rows('trips').map(Trip.fromJson)) t.id: t},
      log: rows('log').map(WorldLogEntry.fromJson).toList(),
      nextId: json['next_id'] as int,
    );
    if (format == 1) world._migrateFromV1();
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
}
