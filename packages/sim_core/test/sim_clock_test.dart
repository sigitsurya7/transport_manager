import 'package:sim_core/sim_core.dart';
import 'package:test/test.dart';

class _PaidSpeed implements SpeedEntitlementProvider {
  @override
  Set<int> get allowedMultipliers => const {1, 2, 5, 10};
}

void main() {
  group('SimClock', () {
    test('1 menit nyata = 10 menit game', () {
      final clock = SimClock();
      expect(clock.advanceActive(const Duration(minutes: 1)), 600);
      expect(clock.now, 600);
    });

    test('Jakarta–Bandung ±2 jam game = ±12 menit nyata', () {
      final clock = SimClock();
      clock.advanceActive(const Duration(minutes: 12));
      expect(clock.now, const Duration(hours: 2).inSeconds);
    });

    test('tick pendek tidak kehilangan pecahan detik', () {
      final clock = SimClock();
      for (var i = 0; i < 1000; i++) {
        clock.advanceActive(const Duration(milliseconds: 16));
      }
      // 16 s nyata × 10 = 160 s game
      expect(clock.now, 160);
    });

    test('pengali kecepatan ditolak tanpa entitlement', () {
      final clock = SimClock();
      expect(() => clock.setSpeedMultiplier(2), throwsStateError);
      expect(clock.speedMultiplier, 1);
    });

    test('pengali berlaku saat aktif, tidak saat catch-up offline', () {
      final clock = SimClock(entitlement: _PaidSpeed())..setSpeedMultiplier(10);
      expect(clock.advanceActive(const Duration(minutes: 1)), 6000);
      final r = clock.catchUpOffline(const Duration(minutes: 1));
      expect(r.simSecondsAdvanced, 600);
    });

    test('catch-up dibatasi 48 jam', () {
      final clock = SimClock();
      final r = clock.catchUpOffline(const Duration(days: 5));
      expect(r.truncated, isTrue);
      expect(r.applied, const Duration(hours: 48));
      expect(r.simSecondsAdvanced, 48 * 3600 * 10);
    });

    test('waktu negatif tidak memundurkan jam', () {
      final clock = SimClock(startSimSeconds: 100);
      clock.catchUpOffline(const Duration(hours: -3));
      clock.advanceActive(const Duration(seconds: -5));
      expect(clock.now, 100);
    });
  });

  group('OfflineTimeValidator', () {
    const v = OfflineTimeValidator();
    final t0 = DateTime.utc(2026, 10, 31, 4);

    ClockSample s(DateTime wall, Duration mono, [String boot = 'b1']) =>
        ClockSample(wallClock: wall, monotonic: mono, bootId: boot);

    test('boot sama dan konsisten → pakai monotonic', () {
      final e = v.estimate(s(t0, const Duration(hours: 1)),
          s(t0.add(const Duration(hours: 3)), const Duration(hours: 4)));
      expect(e.elapsed, const Duration(hours: 3));
      expect(e.anomaly, TimeAnomaly.none);
    });

    test('jam dinding dimajukan → tetap pakai monotonic, tandai anomali', () {
      final e = v.estimate(s(t0, const Duration(hours: 1)),
          s(t0.add(const Duration(days: 30)), const Duration(hours: 2)));
      expect(e.elapsed, const Duration(hours: 1));
      expect(e.anomaly, TimeAnomaly.wallClockMismatch);
    });

    test('setelah reboot → pakai jam dinding', () {
      final e = v.estimate(s(t0, const Duration(hours: 5)),
          s(t0.add(const Duration(hours: 6)), const Duration(minutes: 3), 'b2'));
      expect(e.elapsed, const Duration(hours: 6));
      expect(e.anomaly, TimeAnomaly.rebootUnverified);
    });

    test('setelah reboot jam mundur → 0', () {
      final e = v.estimate(s(t0, const Duration(hours: 5)),
          s(t0.subtract(const Duration(hours: 2)), const Duration(minutes: 3), 'b2'));
      expect(e.elapsed, Duration.zero);
      expect(e.anomaly, TimeAnomaly.wallClockBackwards);
    });
  });
}
