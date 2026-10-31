import 'package:flutter/services.dart';
import 'package:sim_core/sim_core.dart';

/// Sampel jam perangkat untuk validasi waktu offline. Di Android memakai
/// `SystemClock.elapsedRealtime` + `BOOT_COUNT` (lihat MainActivity.kt);
/// platform lain jatuh ke jam dinding saja.
class DeviceClock {
  const DeviceClock();

  static const _channel = MethodChannel('transport_manager/clock');

  Future<ClockSample> sample() async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('sample');
      if (m != null) {
        return ClockSample(
          wallClock: DateTime.fromMillisecondsSinceEpoch(m['wallClockMs']! as int),
          monotonic: Duration(milliseconds: m['monotonicMs']! as int),
          bootId: m['bootId']! as String,
        );
      }
    } on MissingPluginException {
      // Bukan Android (mis. test): hanya jam dinding.
    } on PlatformException {
      // Sama: jatuh ke jam dinding.
    }
    return ClockSample(wallClock: DateTime.now(), monotonic: Duration.zero, bootId: 'unknown');
  }
}
