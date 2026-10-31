import 'package:flutter_test/flutter_test.dart';
import 'package:transport_manager/util/format.dart';

void main() {
  test('rupiah dengan titik ribuan', () {
    expect(formatRupiah(50000000), 'Rp50.000.000');
    expect(formatRupiah(-12500), '-Rp12.500');
    expect(formatRupiah(0), 'Rp0');
  });

  test('jam game: detik 0 = Hari 1 pukul 06.00', () {
    expect(formatGameClock(0), 'Hari 1 · 06.00');
    expect(formatGameClock(18 * 3600 + 5 * 60), 'Hari 2 · 00.05');
  });

  test('jam dengan penanda ganti hari', () {
    expect(formatGameTime(3600, fromSimSeconds: 0), '07.00');
    expect(formatGameTime(20 * 3600, fromSimSeconds: 0), '02.00 (+1 hari)');
  });

  test('durasi game dan nyata (skala 10)', () {
    expect(formatDuration(45 * 60), '45 m');
    expect(formatDuration(2 * 3600 + 5 * 60), '2 j 5 m');
    expect(formatRealDuration(2 * 3600, 10), '12 mnt');
  });

  test('jarak & berat', () {
    expect(formatKm(4250), '4,3 km');
    expect(formatKm(23400), '23 km');
    expect(formatKg(950), '950 kg');
    expect(formatKg(2500), '2,5 t');
  });
}
