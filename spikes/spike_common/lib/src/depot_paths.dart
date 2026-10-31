import 'dart:math' as math;

/// Titik 2D di lantai depot (meter). x = timur, z = selatan; y selalu 0.
class FloorPoint {
  const FloorPoint(this.x, this.z);
  final double x;
  final double z;
}

/// Pose di lantai: posisi + arah hadap (radian, 0 = menghadap +X).
class FloorPose {
  const FloorPose(this.x, this.z, this.heading);
  final double x;
  final double z;
  final double heading;
}

/// Jalur tertutup, diinterpolasi berdasarkan jarak tempuh.
class LoopPath {
  LoopPath(this.points) : assert(points.length >= 2) {
    var acc = 0.0;
    _cumulative.add(0);
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      acc += math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.z - a.z, 2));
      _cumulative.add(acc);
    }
    length = acc;
  }

  final List<FloorPoint> points;
  final List<double> _cumulative = [];
  late final double length;

  FloorPose poseAt(double distance) {
    var d = distance % length;
    if (d < 0) d += length;
    var i = 0;
    while (_cumulative[i + 1] < d) {
      i++;
    }
    final a = points[i];
    final b = points[(i + 1) % points.length];
    final segLen = _cumulative[i + 1] - _cumulative[i];
    final t = segLen == 0 ? 0.0 : (d - _cumulative[i]) / segLen;
    return FloorPose(
      a.x + (b.x - a.x) * t,
      a.z + (b.z - a.z) * t,
      math.atan2(-(b.z - a.z), b.x - a.x),
    );
  }
}

/// Skenario depot (selaras dengan `tools/depot_glb/depot_layout.json`):
/// gerbang (0, 15) → jalur utama → loading dock (11, -2) → slot parkir → gerbang.
class DepotScenario {
  static final vehicleLoop = LoopPath(const [
    FloorPoint(0, 18),
    FloorPoint(0, 6),
    FloorPoint(11, 6),
    FloorPoint(11, -1.5),
    FloorPoint(11, 6),
    FloorPoint(-6, 6),
    FloorPoint(-6, -2),
    FloorPoint(-6, 6),
    FloorPoint(0, 6),
  ]);

  static final workerLoop = LoopPath(const [
    FloorPoint(6, -3),
    FloorPoint(16, -3),
    FloorPoint(16, 2),
    FloorPoint(-10, 2),
    FloorPoint(-10, 5),
    FloorPoint(6, 5),
  ]);

  /// Kecepatan dalam depot (m/s, waktu tampilan).
  static const vehicleSpeed = 4.0;
  static const workerSpeed = 1.3;

  static const workerCount = 6;

  /// Pose kendaraan ke-[i] dari [count], disebar merata di sepanjang jalur.
  static FloorPose vehicle(int i, int count, double seconds) => vehicleLoop.poseAt(
      seconds * vehicleSpeed + vehicleLoop.length * i / math.max(count, 1));

  static FloorPose worker(int i, double seconds) => workerLoop.poseAt(
      seconds * workerSpeed + workerLoop.length * i / workerCount);
}

/// Kamera orbit sederhana di sekitar pusat depot.
class OrbitCamera {
  double yaw = 0.6; // radian
  double pitch = 0.75; // radian dari horizontal
  double distance = 48;

  static const minPitch = 0.35;
  static const maxPitch = 1.35;

  void drag(double dx, double dy) {
    yaw -= dx * 0.008;
    pitch = (pitch + dy * 0.006).clamp(minPitch, maxPitch);
  }

  void zoom(double scale) => distance = (distance / scale).clamp(15.0, 90.0);

  /// Posisi kamera (x, y, z) memandang titik (0, 0, 0).
  (double, double, double) get position => (
        distance * math.cos(pitch) * math.cos(yaw),
        distance * math.sin(pitch),
        distance * math.cos(pitch) * math.sin(yaw),
      );
}
