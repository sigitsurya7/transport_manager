// SEMUA pemanggilan API Thermion dikumpulkan di file ini.
//
// Catatan: pemanggilan di bawah mengikuti README Thermion (createViewer,
// ThermionWidget, loadGlb, setCameraPosition, setRendering). API transform
// per-entity & cahaya di thermion_flutter 0.5.0 perlu dicek ulang saat
// `flutter analyze`; bila ada yang berubah, cukup sesuaikan file ini.
import 'package:thermion_flutter/thermion_flutter.dart';

class ThermionDepot {
  ThermionDepot._(this.viewer);

  final ThermionViewer viewer;
  final List<dynamic> vehicles = [];
  final List<dynamic> workers = [];

  static Future<ThermionDepot> create() async {
    final viewer = await ThermionFlutterPlugin.createViewer();
    return ThermionDepot._(viewer);
  }

  Future<void> loadScene({required int workerCount}) async {
    await viewer.loadGlb('assets/depot.glb');
    for (var i = 0; i < workerCount; i++) {
      workers.add(await viewer.loadGlb('assets/worker.glb'));
    }
    await viewer.setRendering(true);
  }

  Future<void> setVehicleCount(int count) async {
    while (vehicles.length < count) {
      vehicles.add(await viewer.loadGlb('assets/pickup.glb'));
    }
    while (vehicles.length > count) {
      await viewer.destroyAsset(vehicles.removeLast());
    }
  }

  Future<void> place(dynamic entity, double x, double z, double heading) async {
    await viewer.setPosition(entity, x, 0, z);
    await viewer.setRotation(entity, heading, 0, 1, 0);
  }

  Future<void> setCamera(double x, double y, double z) async {
    await viewer.setCameraPosition(x, y, z);
    await viewer.lookAt(0, 0, 0);
  }

  Future<void> dispose() => viewer.dispose();
}
