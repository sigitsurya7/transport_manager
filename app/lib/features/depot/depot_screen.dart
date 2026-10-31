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
vm.Quaternion headingRotation(double heading) =>
    vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), math.pi - heading);

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
  final Map<int, (String, Node)> _vehicles = {};
  final List<Node> _staff = [];
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
      _scene.add(await _instance('base'));
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
      final current = _vehicles[v.id];
      if (current?.$1 == v.model.visual) continue;
      final node = await _instance(v.model.visual);
      if (current != null) _scene.remove(current.$2);
      _scene.add(node);
      _vehicles[v.id] = (v.model.visual, node);
    }
    final wantStaff = math.min(depot.warehouseStaff, _maxVisibleStaff);
    while (_staff.length < wantStaff) {
      final node = await _instance('worker');
      _staff.add(node);
      _scene.add(node);
    }
    while (_staff.length > wantStaff) {
      _scene.remove(_staff.removeLast());
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
        final node = _vehicles[snap.vehicleId]?.$2;
        if (node != null) {
          _place(node, motion.pose(snap, dockLevel: dockLevel, gateLevel: gateLevel, outQueueAhead: outQueue));
        }
        if (snap.phase == TripPhase.gateOut || snap.phase == TripPhase.gateIn) {
          final lane = snap.gateLane ?? 0;
          boomOpen[lane] = math.max(boomOpen[lane] ?? 0, boomOpenAt(snap.phaseProgress));
        }
        if (snap.phase == TripPhase.loading) loadingDocks.add(snap.dock ?? 0);
      }
      _animateBooms(boomOpen);
      _animatePeople(motion, elapsed.inMicroseconds / 1e6, dockLevel, gateLevel, loadingDocks);
    }
    return PerspectiveCamera(
      position: _camera.position,
      target: toEngine(_OrbitCamera.target.x, _OrbitCamera.target.y, _OrbitCamera.target.z),
      fovRadiansY: math.pi / 4.2,
    );
  }

  /// Gerbang 1 jalur: satu palang. Multi-gate: palang ke-i melayani jalur ke-i.
  void _animateBooms(Map<int, double> openByLane) {
    for (final (i, (spec, node)) in _booms.indexed) {
      final open = openByLane[i] ?? 0.0;
      node.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), spec.side * open * 1.35);
    }
  }

  /// Staf gudang: bolak-balik pintu ↔ bak kendaraan di dock yang sedang
  /// memuat; sisanya siaga di tepi dock. Petugas jaga berdiri di pos gerbang.
  void _animatePeople(DepotMotion motion, double seconds, int dockLevel, int gateLevel, List<int> loadingDocks) {
    final docks = motion.layout.docks(dockLevel);
    const platformY = 1.1;
    for (final (i, node) in _staff.indexed) {
      if (loadingDocks.isNotEmpty) {
        final dock = docks[loadingDocks[i % loadingDocks.length].clamp(0, docks.length - 1)];
        final side = (i ~/ loadingDocks.length).isEven ? -0.8 : 0.8;
        final f = (seconds / 2.6 + i * 0.37) % 2;
        final walk = f <= 1 ? f : 2 - f;
        _place(node, (x: dock.x + side, z: -5.0 + walk * 1.8, heading: f <= 1 ? headingSouth : headingNorth), y: platformY);
      } else {
        final dock = docks[i % docks.length];
        _place(
          node,
          (x: dock.x - 1.6 + (i ~/ docks.length) * 0.7, z: -4.6, heading: headingSouth + 0.3 * math.sin(seconds * 0.4 + i)),
          y: platformY,
        );
      }
    }
    final guard = _guard;
    if (guard != null) {
      final booth = gateLevel == 1 ? (x: 4.4, z: 13.4) : (x: 4.6, z: 13.2);
      _place(guard, (x: booth.x, z: booth.z, heading: math.pi + 0.4 * math.sin(seconds * 0.3)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
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
            child: TickerMode(enabled: widget.active, child: SceneView(_scene, cameraBuilder: _frame)),
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
      Positioned(left: 12, right: 12, bottom: 12, child: _DepotPanel(session: session, onOpenContracts: widget.onOpenContracts)),
    ]);
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(child: Text(depot.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  Text('Parkir $occupied/${depot.parkingSlots} · Dock ${world.dockCount(depot)}',
                      style: const TextStyle(color: AppColors.textMuted)),
                ]),
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
                Row(children: [
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
                ]),
              ]),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const GlyphIcon(GameGlyph.construction, size: 18, color: AppColors.accent),
        const SizedBox(width: 6),
        Expanded(
          child: Text('Membangun ${spec.name}: ${spec.level(construction.toLevel).label}',
              style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
        ),
        Text('selesai ${formatGameTime(construction.finishAt, fromSimSeconds: session.world.now)}',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: done, minHeight: 5, backgroundColor: AppColors.outline),
      ),
    ]);
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
    final status = snap.phase == null ? 'Siap di slot ${vehicle.slotIndex + 1}' : phaseLabel[snap.phase]!;
    return Row(children: [
      VehicleIcon(vehicle.model.visual, width: 48),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(vehicle.model.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(driver == null ? status : '$status · ${driver.name}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ]),
      ),
      Text('${(vehicle.odometerM / 1000).toStringAsFixed(0)} km', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
    ]);
  }
}
