import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:persistence/persistence.dart';
import 'package:sim_core/sim_core.dart';

import '../data/game_data.dart';
import '../platform/device_clock.dart';

/// Ringkasan kejadian selama game ditutup / di background.
class OfflineSummary {
  const OfflineSummary({
    required this.realElapsed,
    required this.applied,
    required this.anomaly,
    required this.entries,
  });

  final Duration realElapsed;

  /// Waktu nyata yang benar-benar diproses (dibatasi 48 jam).
  final Duration applied;
  final TimeAnomaly anomaly;
  final List<WorldLogEntry> entries;

  bool get truncated => applied < realElapsed;
}

/// Satu sesi permainan: memegang [SimWorld], memajukan jam, dan menyimpan.
///
/// UI hanya membaca state dan memanggil perintah di sini; tidak ada logika
/// game di widget. Waktu maju lewat jalur yang sama dengan catch-up offline
/// ([SimWorld.advanceTo]).
class GameSession extends ChangeNotifier with WidgetsBindingObserver {
  GameSession._({
    required this.data,
    required this.world,
    required this.store,
    required SaveMeta initialMeta,
    required this.deviceClock,
  })  : _meta = initialMeta,
        clock = SimClock(
          startSimSeconds: world.now,
          entitlement: devTools ? const DevSpeedEntitlement() : const FreeSpeedEntitlement(),
        );

  /// Alat pengujian (pengali kecepatan waktu) hanya di build
  /// `--dart-define=DEV_TOOLS=true`, bukan untuk pemain.
  static const devTools = bool.fromEnvironment('DEV_TOOLS');

  static const offerCount = 3;
  static const _autosaveEvery = Duration(seconds: 60);
  static const _tickEvery = Duration(milliseconds: 200);

  /// Ringkasan offline tanpa kejadian hanya ditampilkan setelah jeda ini.
  static const _summaryMinOffline = Duration(minutes: 10);

  final GameData data;
  final SimWorld world;
  final SaveStore store;
  final DeviceClock deviceClock;
  final SimClock clock;
  SaveMeta _meta;

  OfflineSummary? _pendingSummary;
  Timer? _ticker;
  final Stopwatch _sinceTick = Stopwatch();
  DateTime _lastSaved = DateTime.now();
  int _savedLogLength = 0;
  Future<void>? _saveInFlight;
  bool _saveRequested = false;
  ClockSample? _pendingSample;
  bool _disposed = false;

  SaveMeta get meta => _meta;

  /// Waktu game untuk render: [SimWorld.now] ditambah waktu nyata sejak tick
  /// terakhir, agar animasi halus di antara tick 200 ms. Tidak memengaruhi
  /// simulasi.
  double get displayTime {
    if (_ticker == null) return world.now.toDouble();
    final extra = _sinceTick.elapsedMicroseconds / 1e6 * timeScale * clock.speedMultiplier;
    return world.now + extra.clamp(0, _tickEvery.inMilliseconds / 1000 * timeScale * 2);
  }
  City get city => data.city(_meta.cityId);
  int get timeScale => clock.config.timeScale;

  /// Ringkasan offline yang belum ditampilkan (sekali ambil).
  OfflineSummary? takeOfflineSummary() {
    final s = _pendingSummary;
    _pendingSummary = null;
    return s;
  }

  // ------------------------------------------------------------- pembuatan

  static Future<GameSession> newGame({
    required GameData data,
    required SaveStore store,
    required RoadGraph graph,
    required City city,
    required DepotSite site,
    required String companyName,
    DeviceClock deviceClock = const DeviceClock(),
  }) async {
    final seed = math.Random.secure().nextInt(1 << 32);
    final world = SimWorld.newGame(
      graph: graph,
      content: data.content,
      seed: seed,
      companyName: companyName,
      cityId: city.id,
      depotName: 'Depot ${site.name}',
      depotNode: graph.nearestNode(site.position),
      starterVehicleModelId: 'pickup_box_1t',
      driverName: 'Pak Slamet',
    );
    final sample = await deviceClock.sample();
    final now = sample.wallClock.millisecondsSinceEpoch;
    final session = GameSession._(
      data: data,
      world: world,
      store: store,
      deviceClock: deviceClock,
      initialMeta: SaveMeta(
        slotId: store.nextFreeSlotId(),
        slotName: companyName,
        companyName: companyName,
        cityId: city.id,
        depotSiteId: site.id,
        mapPackId: data.regionOf(city.id).mapPackId,
        simTime: world.now,
        cashIdr: world.cashIdr,
        lastWallClockMs: now,
        lastMonotonicMs: sample.monotonic.inMilliseconds,
        bootId: sample.bootId,
        createdAtMs: now,
        updatedAtMs: now,
      ),
    );
    session.refreshOffers();
    await session.save();
    return session;
  }

  static Future<GameSession> load({
    required GameData data,
    required SaveStore store,
    required AssetBundle bundle,
    required int slotId,
    DeviceClock deviceClock = const DeviceClock(),
  }) async {
    final saved = store.read(slotId);
    final graph = await data.graph(bundle, saved.meta.cityId);
    final world = SimWorld.fromJson(saved.world, graph: graph, content: data.content);
    final session = GameSession._(
      data: data,
      world: world,
      store: store,
      deviceClock: deviceClock,
      initialMeta: saved.meta,
    ).._savedLogLength = world.log.length;
    await session._catchUp();
    return session;
  }

  // ------------------------------------------------------------- jam

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _sinceTick
      ..reset()
      ..start();
    _ticker = Timer.periodic(_tickEvery, (_) => _tick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _sinceTick.stop();
  }

  void _tick() {
    final real = _sinceTick.elapsed;
    _sinceTick
      ..reset()
      ..start();
    clock.advanceActive(real);
    world.advanceTo(clock.now);
    if (world.log.length != _savedLogLength ||
        DateTime.now().difference(_lastSaved) >= _autosaveEvery) {
      unawaited(save());
    }
    notifyListeners();
  }

  /// Proses waktu yang terlewat sejak save terakhir (app ditutup / di background).
  Future<void> _catchUp() async {
    final last = ClockSample(
      wallClock: DateTime.fromMillisecondsSinceEpoch(_meta.lastWallClockMs),
      monotonic: Duration(milliseconds: _meta.lastMonotonicMs ?? 0),
      bootId: _meta.bootId ?? 'unknown',
    );
    final now = await deviceClock.sample();
    final estimate = const OfflineTimeValidator().estimate(last, now);
    final logStart = world.log.length;
    final result = clock.catchUpOffline(estimate.elapsed);
    world.advanceTo(clock.now);
    final entries = world.log.sublist(logStart);
    if (entries.isNotEmpty || result.requested >= _summaryMinOffline) {
      _pendingSummary = OfflineSummary(
        realElapsed: result.requested,
        applied: result.applied,
        anomaly: estimate.anomaly,
        entries: entries,
      );
    }
    await save(sample: now);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        if (_ticker != null) {
          _stopTicker();
          unawaited(save());
        }
      case AppLifecycleState.resumed:
        if (_ticker == null) {
          unawaited(_catchUp().then((_) {
            if (!_disposed) {
              _startTicker();
              notifyListeners();
            }
          }));
        }
      case AppLifecycleState.inactive:
        break;
    }
  }

  // ------------------------------------------------------------- perintah

  List<Contract> get offers => world.contracts.values
      .where((c) => c.status == ContractStatus.offered)
      .toList()
    ..sort((a, b) => a.id.compareTo(b.id));

  /// Lengkapi tawaran kontrak sampai [offerCount].
  void refreshOffers() {
    final depot = world.depots.values.first;
    final capacity = world.vehicles.values.map((v) => v.model.payloadKg).reduce(math.max);
    var attempts = 0;
    while (offers.length < offerCount && attempts++ < offerCount * 2) {
      world.offerStoreContract(depotId: depot.id, capacityKg: capacity);
    }
    notifyListeners();
  }

  Depot get depot => world.depots.values.first;

  /// Ganti pengali kecepatan ke nilai berikutnya yang diizinkan.
  void cycleSpeed() {
    final allowed = clock.entitlement.allowedMultipliers.toList()..sort();
    final i = allowed.indexOf(clock.speedMultiplier);
    clock.setSpeedMultiplier(allowed[(i + 1) % allowed.length]);
    notifyListeners();
  }

  /// Mode pengembang (build DEV_TOOLS): tambah kas.
  void devAddCash(int amountIdr) {
    assert(devTools, 'devAddCash hanya untuk build DEV_TOOLS');
    _command(() => world.devGrant(amountIdr));
  }

  void startUpgrade(FacilityType type) => _command(() => world.startUpgrade(depot.id, type));
  void buyVehicle(String modelId) => _command(() => world.buyVehicle(depot.id, modelId));
  void hire(EmployeeRole role) => _command(() => world.hire(depot.id, role));
  void releaseWarehouseStaff() => _command(() => world.releaseWarehouseStaff(depot.id));

  void _command(void Function() action) {
    action();
    unawaited(save());
    notifyListeners();
  }

  DispatchCheck check(Contract contract, Vehicle vehicle, Driver driver) =>
      world.check(contractId: contract.id, vehicleId: vehicle.id, driverId: driver.id);

  Trip dispatch(Contract contract, Vehicle vehicle, Driver driver, RouteMode mode) {
    final trip = world.dispatch(
        contractId: contract.id, vehicleId: vehicle.id, driverId: driver.id, mode: mode);
    unawaited(save());
    notifyListeners();
    return trip;
  }

  // ------------------------------------------------------------- save

  /// Simpan state terbaru. Bila save lain sedang berjalan, permintaan ini
  /// diantrekan: future selesai setelah state terbaru benar-benar tertulis
  /// (penting saat keluar tepat ketika autosave berlangsung).
  Future<void> save({ClockSample? sample}) {
    _saveRequested = true;
    _pendingSample = sample ?? _pendingSample;
    return _saveInFlight ??= _drainSaves().whenComplete(() => _saveInFlight = null);
  }

  Future<void> _drainSaves() async {
    while (_saveRequested) {
      _saveRequested = false;
      final s = _pendingSample ?? await deviceClock.sample();
      _pendingSample = null;
      _meta = _meta.copyWith(
        simTime: world.now,
        cashIdr: world.cashIdr,
        lastWallClockMs: s.wallClock.millisecondsSinceEpoch,
        lastMonotonicMs: s.monotonic.inMilliseconds,
        bootId: s.bootId,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      store.write(_meta, world.toJson(), worldFormat: SimWorld.saveFormat);
      _lastSaved = DateTime.now();
      _savedLogLength = world.log.length;
    }
  }

  /// Simpan lalu hentikan sesi (kembali ke menu utama).
  Future<void> close() async {
    _stopTicker();
    WidgetsBinding.instance.removeObserver(this);
    await save();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTicker();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
