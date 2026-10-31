import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:sim_core/sim_core.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../widgets/game_icons.dart';
import '../../app/theme.dart';
import '../../game/game_session.dart';
import '../../util/format.dart';
import '../contracts/trip_card.dart';
import 'depot_paths.dart';
import 'facilities_sheet.dart';

/// Koordinat depot (sama dengan GLB & `depot_layout.json`) → ruang engine.
/// Importer GLB flutter_scene membalik sumbu Z, jadi posisi node & kamera
/// ikut dibalik agar sejajar dengan geometri.
vm.Vector3 toEngine(double x, double y, double z) => vm.Vector3(x, y, -z);

/// Rotasi kendaraan/pekerja untuk arah hadap [heading] (konvensi DepotPath).
/// Sumbu Z engine terbalik (cermin) dan model menghadap -X setelah impor,
/// sehingga sudutnya `π - heading`. Diverifikasi di HP: rotasi 0 → hidung ke
/// -x depot; rotasi -π/2 → hidung ke +z (ke arah jalan).
vm.Quaternion headingRotation(double heading) => vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), math.pi - heading);

/// Kamera orbit di sekitar depot.
class _OrbitCamera {
  double yaw = 1.2;
  double pitch = 0.66;
  double distance = 54;

  /// Pusat pandang: cukup ke timur agar loading dock ikut terlihat.
  static const target = (x: 2.0, y: 0.0, z: 1.0);

  void drag(double dx, double dy) {
    yaw -= dx * 0.008;
    pitch = (pitch + dy * 0.005).clamp(0.32, 1.25);
  }

  void zoom(double factor) => distance = (distance / factor).clamp(18.0, 90.0);

  vm.Vector3 get position => toEngine(
    target.x + distance * math.cos(pitch) * math.cos(yaw),
    target.y + distance * math.sin(pitch),
    target.z + distance * math.cos(pitch) * math.sin(yaw),
  );
}

/// Depot 3D: lingkungan aktif yang menampilkan state simulasi. Renderer hanya
/// membaca snapshot; tidak mengubah state.
class DepotScreen extends StatefulWidget {
  const DepotScreen({super.key, required this.session, required this.active, required this.onOpenContracts});

  final GameSession session;
  final bool active;
  final VoidCallback onOpenContracts;

  @override
  State<DepotScreen> createState() => _DepotScreenState();
}

class _DepotScreenState extends State<DepotScreen> {
  static const _maxVisibleStaff = 6;

  final _scene = Scene();
  final _camera = _OrbitCamera();
  DepotLayout? _layout;
  DepotMotion? _motion;
  String? _error;
  double _pinchStart = 1;

  /// Modul fasilitas yang sedang tampil, per jenis: (nama model, node).
  final Map<FacilityType, (String, Node)> _modules = {};
  final List<(BoomSpec, Node)> _booms = [];
  int? _boomLevel;
  final Map<int, _VehicleView> _vehicles = {};

  /// Staf gudang: (tangan kosong, memanggul kardus); satu tampil, satu disembunyikan.
  final List<(Node, Node)> _staff = [];

  /// Lampu lantai per slot parkir: (kosong, terisi).
  final List<(Node, Node)> _slotMarkers = [];

  /// Mekanik yang bekerja di samping kendaraan yang sedang diservis.
  final List<Node> _mechanics = [];

  /// Barang yang disiapkan di platform dock (berkurang saat dimuat).
  final List<Node> _staging = [];
  static const _stagingPerDock = 4;

  /// Sopir yang memuat sendiri bila belum ada staf gudang.
  (Node, Node)? _driverLoader;
  Node? _guard;
  Node? _construction;
  final Map<String, Node> _templates = {};
  bool _syncing = false;
  bool _syncAgain = false;

  GameSession get session => widget.session;
  Depot get depot => session.world.depots.values.first;

  @override
  void initState() {
    super.initState();
    _load();
    session.addListener(_sync);
  }

  @override
  void dispose() {
    session.removeListener(_sync);
    _scene.dispose();
    super.dispose();
  }

  Future<Node> _instance(String model) async {
    final template = _templates[model] ??= await Node.fromGlbAsset('assets/models/$model.glb');
    return template.clone();
  }

  Future<void> _load() async {
    try {
      await Scene.initializeStaticResources();
      _scene
        ..directionalLight = DirectionalLight(
          direction: vm.Vector3(-0.55, -1.0, -0.4),
          color: vm.Vector3(1.0, 0.95, 0.86),
          intensity: 3.2,
          castsShadow: true,
          shadowCascadeCount: 2,
          shadowMaxDistance: 100,
          shadowMapResolution: 1024,
          shadowSoftness: 0.12,
        )
        ..exposure = 1.0;
      final layout = DepotLayout.parse(await rootBundle.loadString('assets/models/depot_layout.json'));
      _scene
        ..add(await _instance('base'))
        ..add(await _instance('props'));
      _guard = await _instance('worker');
      _scene.add(_guard!);
      _layout = layout;
      await _syncNow();
      if (mounted) setState(() => _motion = DepotMotion(layout));
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// Samakan isi scene dengan state (modul per level, palang, kendaraan,
  /// staf, penanda konstruksi). Dipanggil tiap session berubah; murah bila
  /// tidak ada yang berubah.
  void _sync() {
    if (_layout == null) return;
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncNow();
  }

  Future<void> _syncNow() async {
    _syncing = true;
    try {
      do {
        _syncAgain = false;
        await _syncOnce();
      } while (_syncAgain && mounted);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncOnce() async {
    final layout = _layout!;
    final world = session.world;
    for (final type in FacilityType.values) {
      final model = world.facility(depot, type).model;
      final current = _modules[type];
      if (current?.$1 == model) continue;
      final node = await _instance(model);
      if (current != null) _scene.remove(current.$2);
      _scene.add(node);
      _modules[type] = (model, node);
    }
    while (_slotMarkers.length < layout.slots.length) {
      final pair = (await _instance('slot_free'), await _instance('slot_taken'));
      _scene
        ..add(pair.$1)
        ..add(pair.$2);
      _slotMarkers.add(pair);
    }
    final gateLevel = depot.level(FacilityType.gate);
    if (_boomLevel != gateLevel) {
      for (final (_, n) in _booms) {
        _scene.remove(n);
      }
      _booms.clear();
      for (final spec in layout.booms(gateLevel)) {
        final node = await _instance(spec.model);
        node.position = toEngine(spec.hinge.x, 0, spec.hinge.z);
        _scene.add(node);
        _booms.add((spec, node));
      }
      _boomLevel = gateLevel;
    }
    for (final v in world.vehicles.values) {
      final visual = v.model.visual;
      final current = _vehicles[v.id];
      if (current?.visual == visual) continue;
      final view = _VehicleView(
        visual: visual,
        closed: await _instance(visual),
        open: layout.hasDoors(visual) ? await _instance('${visual}_open') : null,
        slots: layout.vehicleCargo(visual),
        crates: [for (final _ in layout.vehicleCargo(visual)) await _instance('cargo_crate')],
      );
      current?.nodes.forEach(_scene.remove);
      view.nodes.forEach(_scene.add);
      _vehicles[v.id] = view;
    }
    Future<(Node, Node)> pair() async {
      final nodes = (await _instance('worker'), await _instance('worker_carry'));
      _scene
        ..add(nodes.$1)
        ..add(nodes.$2);
      return nodes;
    }

    _driverLoader ??= await pair();
    while (_mechanics.length < world.vehicles.length) {
      final node = await _instance('worker');
      _mechanics.add(node);
      _scene.add(node);
    }
    while (_staging.length < 3 * _stagingPerDock) {
      final crate = await _instance('cargo_crate');
      _staging.add(crate);
      _scene.add(crate);
    }
    final wantStaff = math.min(depot.warehouseStaff, _maxVisibleStaff);
    while (_staff.length < wantStaff) {
      _staff.add(await pair());
    }
    while (_staff.length > wantStaff) {
      final (a, b) = _staff.removeLast();
      _scene
        ..remove(a)
        ..remove(b);
    }
    final construction = depot.construction;
    if (construction == null) {
      if (_construction?.parent != null) _scene.remove(_construction!);
    } else {
      final marker = _construction ??= await _instance('construction');
      final a = layout.anchor(construction.type);
      marker.position = toEngine(a.x, 0, a.z);
      if (marker.parent == null) _scene.add(marker);
    }
  }

  void _place(Node node, FloorPose? pose, {double y = 0}) {
    if (pose == null) {
      // Di luar depot: sembunyikan di bawah lantai.
      node.position = vm.Vector3(0, -50, 0);
      return;
    }
    node.position = toEngine(pose.x, y, pose.z);
    node.rotation = headingRotation(pose.heading);
  }

  Camera _frame(Duration elapsed) {
    final motion = _motion;
    if (motion != null) {
      final world = session.world;
      final t = session.displayTime;
      final dockLevel = depot.level(FacilityType.loadingDock);
      final gateLevel = depot.level(FacilityType.gate);
      final snaps = [for (final v in world.vehicles.values) world.vehicleSnapshot(v.id, at: t)];
      final outQueue = snaps.where((s) => s.phase == TripPhase.waitGateOut).length;
      final boomOpen = <int, double>{};
      final loadingDocks = <int>[];
      for (final snap in snaps) {
        final view = _vehicles[snap.vehicleId];
        if (view != null) {
          final pose = motion.pose(
            snap,
            dockLevel: dockLevel,
            gateLevel: gateLevel,
            outQueueAhead: outQueue,
            front: motion.layout.vehicleBounds(view.visual).$2,
          );
          _placeVehicle(view, snap, pose);
        }
        if (snap.phase == TripPhase.gateOut || snap.phase == TripPhase.gateIn) {
          final lane = snap.gateLane ?? 0;
          boomOpen[lane] = math.max(boomOpen[lane] ?? 0, boomOpenAt(snap.phaseProgress));
        }
        if (snap.phase == TripPhase.loading) loadingDocks.add(snap.dock ?? 0);
      }
      _animateBooms(boomOpen);
      _placeStaging(snaps, motion.layout.docks(dockLevel));
      _placeMechanics(motion, snaps, elapsed.inMicroseconds / 1e6);
      _placeSlotMarkers(motion);
      _animatePeople(motion, elapsed.inMicroseconds / 1e6, dockLevel, gateLevel, loadingDocks);
    }
    return PerspectiveCamera(
      position: _camera.position,
      target: toEngine(_OrbitCamera.target.x, _OrbitCamera.target.y, _OrbitCamera.target.z),
      fovRadiansY: math.pi / 4.2,
    );
  }

  /// Kendaraan + muatannya. Kosong saat berangkat ke dock & saat pulang;
  /// terisi bertahap selama dimuat (pintu box terbuka); penuh sampai keluar.
  void _placeVehicle(_VehicleView view, VehicleSnapshot snap, FloorPose? pose) {
    final loading = snap.phase == TripPhase.loading;
    final showOpen = loading && view.open != null;
    _place(view.closed, showOpen ? null : pose);
    if (view.open != null) _place(view.open!, showOpen ? pose : null);

    final count = pose == null ? 0 : _cargo(view, snap).loaded;
    for (final (i, crate) in view.crates.indexed) {
      if (i >= count || pose == null) {
        _place(crate, null);
        continue;
      }
      final (lx, ly, lz) = view.slots[i];
      final fx = math.cos(pose.heading), fz = -math.sin(pose.heading);
      _place(crate, (x: pose.x + fx * lx - fz * lz, z: pose.z + fz * lx + fx * lz, heading: pose.heading), y: ly);
    }
  }

  /// Jumlah palet muatan untuk trip ini (`full`) dan yang sudah di kendaraan
  /// (`loaded`): kosong sebelum dimuat, bertambah selama dimuat, penuh sampai
  /// keluar depot, kosong lagi saat pulang (barang sudah dibongkar).
  ({int full, int loaded}) _cargo(_VehicleView view, VehicleSnapshot snap) {
    final world = session.world;
    final trip = world.trips[snap.tripId];
    if (trip == null || view.crates.isEmpty) return (full: 0, loaded: 0);
    final vehicle = world.vehicles[snap.vehicleId]!;
    final weight = world.contracts[trip.contractId]!.weightKg;
    final share = (weight / vehicle.model.payloadKg).clamp(0.2, 1.0);
    final full = math.max(1, (view.crates.length * share).ceil());
    final fill = switch (snap.phase) {
      TripPhase.loading => snap.phaseProgress,
      TripPhase.toGate || TripPhase.waitGateOut || TripPhase.gateOut => 1.0,
      _ => 0.0,
    };
    return (full: full, loaded: (full * fill).ceil().clamp(0, full));
  }

  /// Barang disiapkan di platform dock begitu kendaraan ditugaskan ke dock,
  /// lalu berkurang seiring dipindahkan ke kendaraan.
  void _placeStaging(List<VehicleSnapshot> snaps, List<FloorPoint> docks) {
    var used = 0;
    final perDock = <int, int>{};
    for (final snap in snaps) {
      if (snap.dock == null || !const {TripPhase.toDock, TripPhase.loading}.contains(snap.phase)) continue;
      final view = _vehicles[snap.vehicleId];
      if (view == null) continue;
      final c = _cargo(view, snap);
      perDock[snap.dock!.clamp(0, docks.length - 1)] = math.min(c.full - c.loaded, _stagingPerDock);
    }
    for (final MapEntry(key: d, value: n) in perDock.entries) {
      final x = docks[d].x;
      const spots = [(-1.25, -4.85), (1.25, -4.85), (-1.25, -3.95), (1.25, -3.95)];
      for (var i = 0; i < n && used < _staging.length; i++) {
        _place(_staging[used++], (x: x + spots[i].$1, z: spots[i].$2, heading: 0), y: 1.1);
      }
    }
    for (var i = used; i < _staging.length; i++) {
      _place(_staging[i], null);
    }
  }

  /// Slot milik kendaraan (termasuk yang sedang bertugas) menyala oranye,
  /// slot kosong hijau; slot di luar kapasitas parkir saat ini tidak tampil.
  void _placeSlotMarkers(DepotMotion motion) {
    final z = motion.layout.slotMarkerZ;
    for (var i = 0; i < _slotMarkers.length; i++) {
      final (free, taken) = _slotMarkers[i];
      final active = i < depot.parkingSlots;
      final occupied = active && depot.slots[i] != null;
      final s = motion.layout.slots[i];
      final pose = (x: s.x, z: z, heading: 0.0);
      _place(free, active && !occupied ? pose : null);
      _place(taken, occupied ? pose : null);
    }
  }

  /// Kendaraan di bengkel tetap di slotnya; mekanik bekerja di sisi kabin.
  void _placeMechanics(DepotMotion motion, List<VehicleSnapshot> snaps, double seconds) {
    var used = 0;
    for (final snap in snaps.where((s) => s.inWorkshop)) {
      if (used >= _mechanics.length) break;
      final slot = motion.layout.slots[snap.slotIndex];
      final sway = 0.25 * math.sin(seconds * 1.7 + used);
      _place(_mechanics[used++], (x: slot.x + 1.55, z: slot.z - 1.6 + sway, heading: math.pi));
    }
    for (var i = used; i < _mechanics.length; i++) {
      _place(_mechanics[i], null);
    }
  }

  /// Gerbang 1 jalur: satu palang. Multi-gate: palang ke-i melayani jalur ke-i.
  void _animateBooms(Map<int, double> openByLane) {
    for (final (i, (spec, node)) in _booms.indexed) {
      final open = openByLane[i] ?? 0.0;
      node.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), spec.side * open * 1.35);
    }
  }

  /// Bongkar muat: staf gudang (atau sopir bila belum ada staf) bolak-balik
  /// dari pintu gudang ke bak kendaraan memanggul kardus, lalu kembali dengan
  /// tangan kosong. Staf yang tidak bekerja siaga di tepi dock. Petugas jaga
  /// berdiri di pos gerbang.
  void _animatePeople(DepotMotion motion, double seconds, int dockLevel, int gateLevel, List<int> loadingDocks) {
    final docks = motion.layout.docks(dockLevel);
    const platformY = 1.1, doorZ = -5.05, edgeZ = -3.2;
    final loaders = _staff.isNotEmpty ? _staff : [?_driverLoader];
    if (_staff.isNotEmpty && _driverLoader != null) {
      _place(_driverLoader!.$1, null);
      _place(_driverLoader!.$2, null);
    }
    for (final (i, (empty, carry)) in loaders.indexed) {
      if (loadingDocks.isEmpty) {
        _place(carry, null);
        if (identical(loaders, _staff)) {
          final dock = docks[i % docks.length];
          _place(empty, (
            x: dock.x - 1.4 + (i ~/ docks.length) * 0.7,
            z: -4.6,
            heading: headingSouth + 0.3 * math.sin(seconds * 0.4 + i),
          ), y: platformY);
        } else {
          _place(empty, null);
        }
        continue;
      }
      final dock = docks[loadingDocks[i % loadingDocks.length].clamp(0, docks.length - 1)];
      final lane = (i ~/ loadingDocks.length) % 3;
      final x = dock.x + const [-0.55, 0.55, 0.0][lane];
      final f = (seconds / 2.4 + i * 0.41) % 1;
      if (f < 0.5) {
        // memanggul kardus menuju bak
        _place(carry, (x: x, z: doorZ + (edgeZ - doorZ) * (f / 0.5), heading: headingSouth), y: platformY);
        _place(empty, null);
      } else {
        _place(empty, (x: x, z: edgeZ - (edgeZ - doorZ) * ((f - 0.5) / 0.5), heading: headingNorth), y: platformY);
        _place(carry, null);
      }
    }
    final guard = _guard;
    if (guard != null) {
      final booth = gateLevel == 1 ? (x: 5.0, z: 13.6) : (x: 5.2, z: 13.4);
      _place(guard, (x: booth.x, z: booth.z, heading: math.pi + 0.4 * math.sin(seconds * 0.3)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF9CC4E4), Color(0xFFD9E7EF)],
              ),
            ),
          ),
        ),
        if (_motion != null)
          Positioned.fill(
            child: GestureDetector(
              onScaleStart: (_) => _pinchStart = 1,
              onScaleUpdate: (d) {
                if (d.pointerCount > 1) {
                  _camera.zoom(d.scale / _pinchStart);
                  _pinchStart = d.scale;
                } else {
                  _camera.drag(d.focalPointDelta.dx, d.focalPointDelta.dy);
                }
              },
              child: TickerMode(
                enabled: widget.active,
                child: SceneView(_scene, cameraBuilder: _frame),
              ),
            ),
          )
        else
          Center(
            child: _error == null
                ? const CircularProgressIndicator()
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Depot 3D gagal dimuat: $_error', style: const TextStyle(color: AppColors.negative)),
                  ),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: _DepotPanel(session: session, onOpenContracts: widget.onOpenContracts),
        ),
      ],
    );
  }
}

/// Ringkasan depot & armada di atas tampilan 3D.
class _DepotPanel extends StatelessWidget {
  const _DepotPanel({required this.session, required this.onOpenContracts});

  final GameSession session;
  final VoidCallback onOpenContracts;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final world = session.world;
      final depot = world.depots.values.first;
      final occupied = depot.slots.whereType<int>().length;
      final construction = depot.construction;
      final busy = world.vehicles.values.where((v) => !v.isAvailable).length;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(depot.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                  Text(
                    'Parkir $occupied/${depot.parkingSlots} · Dock ${world.dockCount(depot)}',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${world.vehicles.length} kendaraan ($busy bertugas) · ${depot.warehouseStaff} staf gudang',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              if (construction != null) ...[
                const SizedBox(height: 10),
                _ConstructionRow(session: session, construction: construction),
              ],
              if (world.vehicles.length == 1) ...[
                const SizedBox(height: 8),
                _VehicleRow(session: session, vehicle: world.vehicles.values.single),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => showFacilitiesSheet(context, session),
                      icon: const GlyphIcon(GameGlyph.construction, size: 18, color: AppColors.accent),
                      label: const Text('Fasilitas'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onOpenContracts,
                      icon: const GlyphIcon(GameGlyph.contracts, size: 18, color: AppColors.onAccent),
                      label: Text(session.offers.isEmpty ? 'Kontrak' : '${session.offers.length} kontrak'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ConstructionRow extends StatelessWidget {
  const _ConstructionRow({required this.session, required this.construction});

  final GameSession session;
  final FacilityConstruction construction;

  @override
  Widget build(BuildContext context) {
    final spec = session.data.content.facilities[construction.type];
    final total = construction.finishAt - construction.startedAt;
    final done = ((session.world.now - construction.startedAt) / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const GlyphIcon(GameGlyph.construction, size: 18, color: AppColors.accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Membangun ${spec.name}: ${spec.level(construction.toLevel).label}',
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              'selesai ${formatGameTime(construction.finishAt, fromSimSeconds: session.world.now)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: done, minHeight: 5, backgroundColor: AppColors.outline),
        ),
      ],
    );
  }
}

class _VehicleRow extends StatelessWidget {
  const _VehicleRow({required this.session, required this.vehicle});

  final GameSession session;
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final snap = session.world.vehicleSnapshot(vehicle.id);
    final trip = vehicle.tripId == null ? null : session.world.trips[vehicle.tripId];
    final driver = trip == null ? null : session.world.drivers[trip.driverId];
    final status = snap.inWorkshop
        ? 'Di bengkel'
        : snap.phase == null
        ? 'Siap di slot ${vehicle.slotIndex + 1}'
        : phaseLabel[snap.phase]!;
    return Row(
      children: [
        VehicleIcon(vehicle.model.visual, width: 48),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(vehicle.model.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                driver == null ? status : '$status · ${driver.name}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        Text(
          '${(vehicle.odometerM / 1000).toStringAsFixed(0)} km',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }
}

/// Node 3D satu kendaraan: model tertutup, varian pintu terbuka (box), dan
/// palet muatan di titik-titik lantai bak.
class _VehicleView {
  _VehicleView({
    required this.visual,
    required this.closed,
    required this.open,
    required this.slots,
    required this.crates,
  });

  final String visual;
  final Node closed;
  final Node? open;
  final List<(double, double, double)> slots;
  final List<Node> crates;

  List<Node> get nodes => [closed, ?open, ...crates];
}
