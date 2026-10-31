// SEMUA pemanggilan API Thermion dikumpulkan di file ini.
//
// Disesuaikan dengan thermion_flutter / thermion_dart 0.5.0: aset dimuat via
// `loadGltf('asset://...')`, transform per-aset lewat `ThermionAsset.setTransform`,
// kamera lewat `getActiveCamera().lookAt`.
import 'package:thermion_flutter/thermion_flutter.dart';

class ThermionDepot {
  ThermionDepot._(this.viewer);

  final ThermionViewer viewer;
  final List<ThermionAsset> vehicles = [];
  final List<ThermionAsset> workers = [];

  static Future<ThermionDepot> create() async {
    final viewer = await ThermionFlutterPlugin.createViewer();
    return ThermionDepot._(viewer);
  }

  Future<void> loadScene({required int workerCount}) async {
    await viewer.loadGltf('asset://assets/depot.glb');
    for (var i = 0; i < workerCount; i++) {
      workers.add(await viewer.loadGltf('asset://assets/worker.glb'));
    }
    await viewer.setRendering(true);
  }

  Future<void> setVehicleCount(int count) async {
    while (vehicles.length < count) {
      vehicles.add(await viewer.loadGltf('asset://assets/pickup.glb'));
    }
    while (vehicles.length > count) {
      await viewer.destroyAsset(vehicles.removeLast());
    }
  }

  Future<void> place(ThermionAsset asset, double x, double z, double heading) =>
      asset.setTransform(
        Matrix4.compose(
          Vector3(x, 0, z),
          Quaternion.axisAngle(Vector3(0, 1, 0), heading),
          Vector3.all(1),
        ),
      );

  Future<void> setCamera(double x, double y, double z) async {
    final camera = await viewer.getActiveCamera();
    await camera.lookAt(Vector3(x, y, z));
  }

  Future<void> dispose() => viewer.dispose();
}
