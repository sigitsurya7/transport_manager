import 'package:sim_core/sim_core.dart';
import 'package:test/test.dart';

void main() {
  test('cocok dengan vektor referensi SplitMix64', () {
    final r = DeterministicRng(0);
    expect(r.nextInt64(), -2152535657050944081); // 0xE220A8397B1DCDAF
    expect(r.nextInt64(), 7960286522194355700);
    expect(r.nextInt64(), 487617019471545679);
  });

  test('derive deterministik (vektor dari implementasi Python)', () {
    expect(DeterministicRng.derive(42, 7, 3).nextInt64(), -4405259165259170938);
  });

  test('benih berbeda per entitas', () {
    final a = DeterministicRng.derive(1, 10, 0).nextInt64();
    final b = DeterministicRng.derive(1, 11, 0).nextInt64();
    expect(a, isNot(b));
  });

  test('nextDouble pada [0,1) dan rata-rata wajar', () {
    final r = DeterministicRng(123);
    var sum = 0.0;
    for (var i = 0; i < 10000; i++) {
      final d = r.nextDouble();
      expect(d, inInclusiveRange(0.0, 0.9999999999));
      sum += d;
    }
    expect(sum / 10000, closeTo(0.5, 0.02));
  });

  test('nextExponential rata-rata ≈ 1/rate', () {
    final r = DeterministicRng(9);
    var sum = 0.0;
    for (var i = 0; i < 20000; i++) {
      sum += r.nextExponential(0.25);
    }
    expect(sum / 20000, closeTo(4.0, 0.15));
  });
}
