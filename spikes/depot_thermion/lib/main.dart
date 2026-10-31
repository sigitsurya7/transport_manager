import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:spike_common/spike_common.dart';
import 'package:thermion_flutter/thermion_flutter.dart';

import 'thermion_adapter.dart';

void main() => runApp(const MaterialApp(home: DepotSpike(), debugShowCheckedModeBanner: false));

class DepotSpike extends StatefulWidget {
  const DepotSpike({super.key});

  @override
  State<DepotSpike> createState() => _DepotSpikeState();
}

class _DepotSpikeState extends State<DepotSpike> with SingleTickerProviderStateMixin {
  final stats = FrameStats();
  final camera = OrbitCamera();
  ThermionDepot? _depot;
  Ticker? _ticker;
  int _vehicleCount = 1;
  int? _loadMs;
  String? _error;
  bool _updating = false;
  double _scaleStart = 1;

  @override
  void initState() {
    super.initState();
    stats.attach();
    _load();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    stats.detach();
    _depot?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final sw = Stopwatch()..start();
    try {
      final depot = await ThermionDepot.create();
      await depot.loadScene(workerCount: DepotScenario.workerCount);
      await depot.setVehicleCount(_vehicleCount);
      _depot = depot;
      _ticker = createTicker(_tick)..start();
    } catch (e) {
      _error = '$e';
    }
    sw.stop();
    if (mounted) setState(() => _loadMs = sw.elapsedMilliseconds);
  }

  /// Update transform setiap frame. Panggilan Thermion asinkron, jadi frame
  /// berikutnya dilewati bila update sebelumnya belum selesai.
  Future<void> _tick(Duration elapsed) async {
    final depot = _depot;
    if (depot == null || _updating) return;
    _updating = true;
    final t = elapsed.inMicroseconds / 1e6;
    try {
      for (var i = 0; i < depot.vehicles.length; i++) {
        final p = DepotScenario.vehicle(i, depot.vehicles.length, t);
        await depot.place(depot.vehicles[i], p.x, p.z, p.heading);
      }
      for (var i = 0; i < depot.workers.length; i++) {
        final p = DepotScenario.worker(i, t);
        await depot.place(depot.workers[i], p.x, p.z, p.heading);
      }
      final (x, y, z) = camera.position;
      await depot.setCamera(x, y, z);
    } finally {
      _updating = false;
    }
  }

  Future<void> _setVehicleCount(int count) async {
    await _depot?.setVehicleCount(count);
    if (mounted) setState(() => _vehicleCount = count);
  }

  @override
  Widget build(BuildContext context) {
    final depot = _depot;
    return Scaffold(
      backgroundColor: const Color(0xFF9EB7C9),
      body: Stack(
        children: [
          if (depot != null)
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
                child: ThermionWidget(viewer: depot.viewer),
              ),
            ),
          SpikeHud(
            engine: 'Thermion',
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
