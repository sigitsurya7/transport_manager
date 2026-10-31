import 'speed_entitlement.dart';
import 'time_config.dart';

/// Hasil pemrosesan waktu offline.
class CatchUpResult {
  const CatchUpResult({
    required this.requested,
    required this.applied,
    required this.simSecondsAdvanced,
  });

  /// Waktu nyata yang terlewat menurut validator.
  final Duration requested;

  /// Waktu nyata yang benar-benar diproses (setelah dibatasi).
  final Duration applied;

  final int simSecondsAdvanced;

  bool get truncated => applied < requested;
}

/// Jam simulasi. Mengubah waktu nyata menjadi detik game.
///
/// - Saat bermain aktif: `timeScale × speedMultiplier`.
/// - Saat catch-up offline: hanya `timeScale` (pengali tidak berlaku) dan
///   dibatasi [TimeConfig.maxOfflineCatchUp].
class SimClock {
  SimClock({
    this.config = const TimeConfig(),
    this.entitlement = const FreeSpeedEntitlement(),
    int startSimSeconds = 0,
  }) : _now = startSimSeconds;

  final TimeConfig config;
  final SpeedEntitlementProvider entitlement;

  int _now;
  int _speedMultiplier = 1;

  /// Sisa mikrodetik game yang belum genap 1 detik, agar tidak hilang
  /// ketika frame/tick sangat pendek.
  int _carryGameMicros = 0;

  /// Waktu simulasi saat ini (detik game).
  int get now => _now;

  int get speedMultiplier => _speedMultiplier;

  void setSpeedMultiplier(int multiplier) {
    if (!entitlement.allowedMultipliers.contains(multiplier)) {
      throw StateError('Pengali kecepatan ${multiplier}x tidak diizinkan');
    }
    _speedMultiplier = multiplier;
  }

  /// Majukan jam saat bermain aktif. Mengembalikan detik game yang bertambah.
  int advanceActive(Duration real) =>
      _advance(real, config.timeScale * _speedMultiplier);

  /// Proses waktu offline. [elapsed] sebaiknya berasal dari
  /// `OfflineTimeValidator`.
  CatchUpResult catchUpOffline(Duration elapsed) {
    final requested = elapsed.isNegative ? Duration.zero : elapsed;
    final applied = requested > config.maxOfflineCatchUp
        ? config.maxOfflineCatchUp
        : requested;
    final advanced = _advance(applied, config.timeScale);
    return CatchUpResult(
      requested: requested,
      applied: applied,
      simSecondsAdvanced: advanced,
    );
  }

  int _advance(Duration real, int factor) {
    if (real.isNegative || real == Duration.zero) return 0;
    final total = real.inMicroseconds * factor + _carryGameMicros;
    final seconds = total ~/ Duration.microsecondsPerSecond;
    _carryGameMicros = total - seconds * Duration.microsecondsPerSecond;
    _now += seconds;
    return seconds;
  }
}
