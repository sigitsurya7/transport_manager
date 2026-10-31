import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:sim_core/sim_core.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../../app/theme.dart';
import '../../game/game_session.dart';
import '../contracts/trip_card.dart';
import 'depot_paths.dart';

/// Kamera orbit di sekitar depot.
class _OrbitCamera {
  double yaw = 1.2;
  double pitch = 0.66;
  double distance = 52;

  /// Pusat pandang: cukup ke timur agar loading dock ikut terlihat.
  static const target = (x: 3.0, y: 0.0, z: 1.0);

  void drag(double dx, double dy) {
    yaw -= dx * 0.008;
    pitch = (pitch + dy * 0.005).clamp(0.32, 1.25);
  }

  void zoom(double factor) => distance = (distance / factor).clamp(18.0, 80.0);

  vm.Vector3 get position => toEngine(
        target.x + distance * math.cos(pitch) * math.cos(yaw),
        target.y + distance * math.sin(pitch),
        target.z + distance * math.cos(pitch) * math.sin(yaw),
      );
}

/// Koordinat depot (sama dengan GLB & `depot_layout.json`) → ruang engine.
/// Importer GLB flutter_scene membalik sumbu Z, jadi posisi node & kamera
/// ikut dibalik agar sejajar dengan geometri.
vm.Vector3 toEngine(double x, double y, double z) => vm.Vector3(x, y, -z);

/// Depot 3D: lingkungan aktif yang menampilkan kendaraan sesuai fase trip di
/// simulasi. Renderer hanya membaca snapshot; tidak mengubah state.
class DepotScreen extends StatefulWidget {
  const DepotScreen({super.key, required this.session, required this.active, required this.onOpenContracts});

  final GameSession session;
  final bool active;
  final VoidCallback onOpenContracts;

  @override
  State<DepotScreen> createState() => _DepotScreenState();
}

class _DepotScreenState extends State<DepotScreen> {
  final _scene = Scene();
  final _camera = _OrbitCamera();
  final Map<int, Node> _vehicles = {};
  final List<Node> _workers = [];
  DepotMotion? _motion;
  String? _error;
  double _pinchStart = 1;

  GameSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scene.dispose();
    super.dispose();
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
          shadowMaxDistance: 90,
          shadowMapResolution: 1024,
          shadowSoftness: 0.12,
        )
        ..exposure = 1.0;
      final layout = DepotLayout.parse(await rootBundle.loadString('assets/models/depot_layout.json'));
      _scene.add(await Node.fromGlbAsset('assets/models/depot.glb'));
      for (final v in session.world.vehicles.values) {
        final node = await Node.fromGlbAsset('assets/models/pickup.glb');
        _vehicles[v.id] = node;
        _scene.add(node);
      }
      for (var i = 0; i < 2; i++) {
        final w = await Node.fromGlbAsset('assets/models/worker.glb');
        _workers.add(w);
        _scene.add(w);
      }
      if (mounted) setState(() => _motion = DepotMotion(layout));
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _place(Node node, FloorPose? pose) {
    if (pose == null) {
      // Kendaraan di luar depot: sembunyikan di bawah lantai.
      node.position = vm.Vector3(0, -50, 0);
      return;
    }
    node.position = toEngine(pose.x, 0, pose.z);
    // Model yang diimpor menghadap -X di ruang engine; diverifikasi di HP:
    // parkir (hidung ke jalur) dan melaju di jalur (hidung ke arah gerak).
    node.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), pose.heading + math.pi);
  }

  Camera _frame(Duration elapsed) {
    final motion = _motion;
    if (motion != null) {
      final t = session.displayTime;
      var loading = false;
      for (final v in session.world.vehicles.values) {
        final snap = session.world.vehicleSnapshot(v.id, at: t);
        loading |= snap.phase == TripPhase.loading;
        _place(_vehicles[v.id]!, motion.pose(v.slotIndex, snap.phase, snap.phaseProgress));
      }
      _animateWorkers(motion, elapsed.inMicroseconds / 1e6, loading);
    }
    return PerspectiveCamera(
      position: _camera.position,
      target: toEngine(_OrbitCamera.target.x, _OrbitCamera.target.y, _OrbitCamera.target.z),
      fovRadiansY: math.pi / 4.2,
    );
  }

  /// Pekerja: satu bolak-balik gudang ↔ kendaraan saat bongkar muat, satu
  /// berjaga di dekat kantor. Murni tampilan.
  void _animateWorkers(DepotMotion motion, double seconds, bool loading) {
    final dock = motion.layout.dockStop;
    if (loading) {
      final carry = DepotPath((x: dock.x - 1.6, z: dock.z - 3.2), [
        (p: (x: dock.x - 1.6, z: dock.z + 0.8), reverse: false),
      ]);
      final f = (seconds / 3.0) % 2;
      final pose = carry.poseAt(f <= 1 ? f : 2 - f);
      _place(_workers[0], (x: pose.x, z: pose.z, heading: f <= 1 ? -math.pi / 2 : math.pi / 2));
    } else {
      _place(_workers[0], (x: dock.x - 3.5, z: dock.z - 3.0, heading: -math.pi / 2 + 0.3 * math.sin(seconds * 0.4)));
    }
    final patrol = DepotPath((x: -17.0, z: 4.0), [(p: (x: -11.0, z: 4.0), reverse: false)]);
    final g = (seconds / 9.0) % 2;
    final pose = patrol.poseAt(g <= 1 ? g : 2 - g);
    _place(_workers[1], (x: pose.x, z: pose.z, heading: g <= 1 ? 0 : math.pi));
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
      Positioned(left: 12, right: 12, bottom: 12, child: _FleetPanel(session: session, onOpenContracts: widget.onOpenContracts)),
    ]);
  }
}

/// Ringkasan armada di atas tampilan 3D.
class _FleetPanel extends StatelessWidget {
  const _FleetPanel({required this.session, required this.onOpenContracts});

  final GameSession session;
  final VoidCallback onOpenContracts;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final world = session.world;
          final depot = world.depots.values.first;
          final occupied = depot.slots.whereType<int>().length;
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
                  Expanded(
                    child: Text(depot.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                  Text('Parkir $occupied/${depot.parkingSlots}', style: const TextStyle(color: AppColors.textMuted)),
                ]),
                const SizedBox(height: 10),
                for (final v in world.vehicles.values) _VehicleRow(session: session, vehicle: v),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onOpenContracts,
                    icon: const Icon(Icons.assignment_rounded),
                    label: Text(session.offers.isEmpty ? 'Cari kontrak' : 'Lihat ${session.offers.length} tawaran kontrak'),
                  ),
                ),
              ]),
            ),
          );
        },
      );
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
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(10)),
        child: Icon(Icons.local_shipping_rounded, color: snap.phase == null ? AppColors.positive : AppColors.accent, size: 20),
      ),
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
