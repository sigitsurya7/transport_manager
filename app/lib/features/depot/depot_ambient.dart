import 'dart:math' as math;

import 'depot_paths.dart';

/// Aktivitas "depot hidup" saat tidak ada (atau di sela) penugasan kendaraan:
/// satpam berpatroli, sopir yang istirahat di gazebo, staf gudang merapikan
/// stok, mekanik siaga di bengkel. Semua fungsi murni dari waktu game, jadi
/// tidak ada state simulasi tambahan dan hasilnya sama setiap kali dirender.
///
/// Titik & jalur dipilih di luar lintasan kendaraan dan diuji terhadap
/// rintangan layout (`test/depot_ambient_test.dart`).
abstract final class DepotAmbient {
  /// Jam kerja staf (jam game).
  static const workStartHour = 6, workEndHour = 19;

  static bool isWorkHour(int simSeconds, {int dayStartOffset = 6 * 3600}) {
    final hour = ((simSeconds + dayStartOffset) % 86400) ~/ 3600;
    return hour >= workStartHour && hour < workEndHour;
  }

  /// Jalur patroli satpam (bolak-balik): dari pos jaga menyusuri sisi
  /// selatan-timur, menjauhi jalur gerbang & antrean keluar.
  static const patrol = <FloorPoint>[
    (x: 4.75, z: 13.6),
    (x: 4.75, z: 10.6),
    (x: 9.2, z: 10.6),
    (x: 9.2, z: 9.75),
    (x: 19.3, z: 9.75),
    (x: 19.3, z: 14.0),
  ];

  /// Tempat sopir beristirahat di sekitar gazebo.
  static const restSpots = <FloorPoint>[
    (x: 9.3, z: 12.0),
    (x: 9.3, z: 13.6),
    (x: 14.7, z: 12.2),
    (x: 14.7, z: 13.8),
  ];

  /// Tempat mekanik siaga di depan bengkel (utara slot parkir).
  static const mechanicSpots = <FloorPoint>[(x: -6.0, z: -9.6), (x: -8.6, z: -9.6), (x: -4.2, z: -9.7)];

  /// Patroli: kecepatan jalan ±1,1 m/s dalam waktu tampilan, berhenti sejenak di ujung.
  static FloorPose guardPatrol(double seconds) {
    final lengths = <double>[];
    for (var i = 1; i < patrol.length; i++) {
      lengths.add(math.sqrt(math.pow(patrol[i].x - patrol[i - 1].x, 2) + math.pow(patrol[i].z - patrol[i - 1].z, 2)));
    }
    final total = lengths.fold(0.0, (a, b) => a + b);
    const speed = 1.1, pause = 6.0;
    final leg = total / speed + pause;
    final t = seconds % (2 * leg);
    final forward = t < leg;
    final walked = (forward ? t : t - leg).clamp(0.0, total / speed) * speed;
    var d = forward ? walked : total - walked;
    for (var i = 0; i < lengths.length; i++) {
      if (d <= lengths[i] || i == lengths.length - 1) {
        final a = patrol[i], b = patrol[i + 1];
        final f = lengths[i] == 0 ? 0.0 : (d / lengths[i]).clamp(0.0, 1.0);
        var heading = math.atan2(-(b.z - a.z), b.x - a.x);
        if (!forward) heading += math.pi;
        return (x: a.x + (b.x - a.x) * f, z: a.z + (b.z - a.z) * f, heading: heading);
      }
      d -= lengths[i];
    }
    return (x: patrol.first.x, z: patrol.first.z, heading: 0);
  }

  /// Staf gudang merapikan stok: bolak-balik di platform dock [dock]
  /// (pintu gudang ↔ ujung platform). `carrying` = sedang memanggul kardus.
  static ({FloorPose pose, bool carrying}) stockKeeper(int index, double seconds, FloorPoint dock) {
    const half = 1.6, speed = 0.8;
    final period = 4 * half / speed;
    final t = (seconds + index * 2.3) % period;
    final out = t < period / 2;
    final f = out ? t / (period / 2) : (t - period / 2) / (period / 2);
    final x = out ? dock.x - half + 2 * half * f : dock.x + half - 2 * half * f;
    final z = -4.75 + 0.6 * (index % 2);
    return (pose: (x: x, z: z, heading: out ? 0.0 : math.pi), carrying: out);
  }
}
