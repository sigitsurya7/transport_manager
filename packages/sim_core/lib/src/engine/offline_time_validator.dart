/// Satu sampel jam perangkat.
class ClockSample {
  const ClockSample({
    required this.wallClock,
    required this.monotonic,
    required this.bootId,
  });

  /// Jam dinding (bisa diubah pengguna).
  final DateTime wallClock;

  /// Waktu sejak boot (Android `SystemClock.elapsedRealtime`), tidak bisa
  /// diubah pengguna tetapi reset saat reboot.
  final Duration monotonic;

  /// Penanda boot (mis. `Settings.Global.BOOT_COUNT`).
  final String bootId;
}

enum TimeAnomaly {
  none,

  /// Jam dinding berbeda jauh dari jam monotonic pada boot yang sama:
  /// kemungkinan jam perangkat diubah.
  wallClockMismatch,

  /// Jam dinding mundur setelah reboot.
  wallClockBackwards,

  /// Perangkat sudah reboot; hanya jam dinding yang tersedia.
  rebootUnverified,
}

class ElapsedEstimate {
  const ElapsedEstimate(this.elapsed, this.anomaly);

  final Duration elapsed;
  final TimeAnomaly anomaly;
}

/// Menentukan berapa lama pemain benar-benar offline.
///
/// Aturan:
/// - Boot sama → percaya jam monotonic. Bila jam dinding menyimpang lebih dari
///   [tolerance], tandai [TimeAnomaly.wallClockMismatch].
/// - Boot berbeda → pakai jam dinding; bila mundur, anggap 0.
/// - Hasil tidak pernah negatif. Batas atas diterapkan oleh `SimClock`.
class OfflineTimeValidator {
  const OfflineTimeValidator({this.tolerance = const Duration(minutes: 2)});

  final Duration tolerance;

  ElapsedEstimate estimate(ClockSample last, ClockSample now) {
    final wall = now.wallClock.difference(last.wallClock);

    if (now.bootId == last.bootId) {
      final mono = now.monotonic - last.monotonic;
      if (mono.isNegative) {
        return const ElapsedEstimate(Duration.zero, TimeAnomaly.wallClockMismatch);
      }
      final drift = (wall - mono).abs();
      return ElapsedEstimate(
        mono,
        drift > tolerance ? TimeAnomaly.wallClockMismatch : TimeAnomaly.none,
      );
    }

    if (wall.isNegative) {
      return const ElapsedEstimate(Duration.zero, TimeAnomaly.wallClockBackwards);
    }
    return ElapsedEstimate(wall, TimeAnomaly.rebootUnverified);
  }
}
