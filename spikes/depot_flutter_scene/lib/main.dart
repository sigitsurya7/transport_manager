import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:spike_common/spike_common.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() => runApp(const MaterialApp(home: DepotSpike(), debugShowCheckedModeBanner: false));

class DepotSpike extends StatefulWidget {
  const DepotSpike({super.key});

  @override
  State<DepotSpike> createState() => _DepotSpikeState();
}

class _DepotSpikeState extends State<DepotSpike> {
  final scene = Scene();
  final stats = FrameStats();
  final camera = OrbitCamera();

  final List<Node> _vehicles = [];
  final List<Node> _workers = [];
  int _vehicleCount = 1;
  int? _loadMs;
  String? _error;
  double _scaleStart = 1;

  @override
  void initState() {
    super.initState();
    stats.attach();
    _load();
  }

  @override
  void dispose() {
    stats.detach();
    super.dispose();
  }

  Future<void> _load() async {
    final sw = Stopwatch()..start();
    try {
      await Scene.initializeStaticResources();
      scene.add(await Node.fromGlbAsset('assets/depot.glb'));
      for (var i = 0; i < DepotScenario.workerCount; i++) {
        final w = await Node.fromGlbAsset('assets/worker.glb');
        _workers.add(w);
        scene.add(w);
      }
      await _setVehicleCount(_vehicleCount);
    } catch (e) {
      _error = '$e';
    }
    sw.stop();
    if (mounted) setState(() => _loadMs = sw.elapsedMilliseconds);
    if (autoBenchEnabled && _error == null) {
      await runAutoBenchmark(
        engine: 'flutter_scene',
        stats: stats,
        loadTimeMs: sw.elapsedMilliseconds,
        setVehicles: _setVehicleCount,
      );
    }
  }

  Future<void> _setVehicleCount(int count) async {
    while (_vehicles.length < count) {
      final v = await Node.fromGlbAsset('assets/pickup.glb');
      _vehicles.add(v);
      scene.add(v);
    }
    while (_vehicles.length > count) {
      scene.remove(_vehicles.removeLast());
    }
    if (mounted) setState(() => _vehicleCount = count);
  }

  void _place(Node node, FloorPose pose) {
    node.position = vm.Vector3(pose.x, 0, pose.z);
    node.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), pose.heading);
  }

  /// Dipanggil setiap frame oleh SceneView. Simulasi sebenarnya ada di
  /// sim_core; di spike ini posisi hanya fungsi dari waktu tampilan.
  Camera _frame(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    for (var i = 0; i < _vehicles.length; i++) {
      _place(_vehicles[i], DepotScenario.vehicle(i, _vehicles.length, t));
    }
    for (var i = 0; i < _workers.length; i++) {
      _place(_workers[i], DepotScenario.worker(i, t));
    }
    final (x, y, z) = camera.position;
    return PerspectiveCamera(
      position: vm.Vector3(x, y, z),
      target: vm.Vector3.zero(),
      fovRadiansY: math.pi / 4,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF9EB7C9),
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onScaleStart: (_) => _scaleStart = 1,
              onScaleUpdate: (d) {
                if (d.pointerCount > 1) {
                  camera.zoom(d.scale / _scaleStart);
                  _scaleStart = d.scale;
                } else {
                  camera.drag(d.focalPointDelta.dx, d.focalPointDelta.dy);
                }
              },
              child: SceneView(scene, cameraBuilder: _frame),
            ),
          ),
          SpikeHud(
            engine: 'flutter_scene',
            stats: stats,
            vehicles: _vehicleCount,
            loadTimeMs: _loadMs,
            onVehiclesChanged: _setVehicleCount,
          ),
          if (_error != null)
            Center(child: Text('Gagal memuat: $_error', style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
  }
}
