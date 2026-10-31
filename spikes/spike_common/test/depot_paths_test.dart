import 'package:flutter_test/flutter_test.dart';
import 'package:spike_common/spike_common.dart';

void main() {
  test('jalur tertutup kembali ke titik awal', () {
    final path = DepotScenario.vehicleLoop;
    final a = path.poseAt(0);
    final b = path.poseAt(path.length);
    expect(b.x, closeTo(a.x, 1e-9));
    expect(b.z, closeTo(a.z, 1e-9));
  });

  test('arah hadap mengikuti segmen', () {
    final p = LoopPath(const [FloorPoint(0, 0), FloorPoint(10, 0)]);
    expect(p.poseAt(5).heading, closeTo(0, 1e-9));
    expect(p.poseAt(5).x, closeTo(5, 1e-9));
  });

  test('kendaraan tersebar merata', () {
    final a = DepotScenario.vehicle(0, 2, 0);
    final b = DepotScenario.vehicle(1, 2, 0);
    expect(a.x == b.x && a.z == b.z, isFalse);
  });
}
