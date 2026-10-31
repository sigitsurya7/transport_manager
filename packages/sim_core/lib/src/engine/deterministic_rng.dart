import 'dart:math' as math;

/// RNG deterministik (SplitMix64).
///
/// Dipakai alih-alih `dart:math` `Random` agar hasil kejadian acak tidak
/// bergantung pada kapan pemain membuka game: benih diturunkan dari
/// `(saveSeed, entityId, eventSeq)`.
///
/// Mengandalkan aritmetika int 64-bit yang wrap-around (Dart native / AOT),
/// yaitu target Android & iOS.
class DeterministicRng {
  DeterministicRng(int seed) : _state = seed;

  /// Benih khusus untuk satu entitas pada satu event.
  factory DeterministicRng.derive(int saveSeed, int entityId, int eventSeq) =>
      DeterministicRng(mix(mix(mix(saveSeed) ^ entityId) ^ eventSeq));

  int _state;

  static int mix(int value) {
    var z = value;
    z = (z ^ (z >>> 30)) * -4658895280553007687; // 0xBF58476D1CE4E5B9
    z = (z ^ (z >>> 27)) * -7723592293110705685; // 0x94D049BB133111EB
    return z ^ (z >>> 31);
  }

  int nextInt64() {
    _state += -7046029254386353131; // 0x9E3779B97F4A7C15
    return mix(_state);
  }

  /// Bilangan pada `[0, 1)`.
  double nextDouble() => (nextInt64() >>> 11) / 9007199254740992.0; // 2^53

  /// Bilangan bulat pada `[0, max)`.
  int nextInt(int max) {
    if (max <= 0) throw ArgumentError.value(max, 'max', 'harus > 0');
    return (nextDouble() * max).floor();
  }

  bool nextBool(double probability) => nextDouble() < probability;

  /// Sampel distribusi eksponensial dengan laju [rate] (per satuan).
  /// Dipakai untuk menjadwalkan waktu kejadian (mis. insiden) satu kali per
  /// leg perjalanan, bukan memeriksa setiap frame.
  double nextExponential(double rate) {
    if (rate <= 0) return double.infinity;
    return -math.log(1 - nextDouble()) / rate;
  }
}
