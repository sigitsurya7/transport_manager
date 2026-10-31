/// Format tampilan (Bahasa Indonesia).
library;

/// Detik game 0 = Hari 1 pukul 06.00.
const _epochOffsetS = 6 * 3600;

String formatRupiah(int idr) {
  final negative = idr < 0;
  final digits = idr.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return '${negative ? '-' : ''}Rp$buf';
}

/// Ringkas untuk ruang sempit: "Rp850.000", "Rp560,6 jt", "Rp1,15 M".
String formatRupiahCompact(int idr) {
  final sign = idr < 0 ? '-' : '';
  final v = idr.abs();
  String dec(double x, int digits) => x.toStringAsFixed(digits).replaceAll('.', ',');
  if (v < 1000000) return formatRupiah(idr);
  if (v < 1000000000) return '${sign}Rp${dec(v / 1e6, v < 10000000 ? 2 : 1)} jt';
  return '${sign}Rp${dec(v / 1e9, 2)} M';
}

/// "Hari 3 · 14.05"
String formatGameClock(int simSeconds) {
  final t = simSeconds + _epochOffsetS;
  final day = t ~/ 86400 + 1;
  final h = (t % 86400) ~/ 3600;
  final m = (t % 3600) ~/ 60;
  return 'Hari $day · ${_pad2(h)}.${_pad2(m)}';
}

/// Jam saja: "14.05", ditambah "(+1 hari)" bila melewati hari [fromSimSeconds].
String formatGameTime(int simSeconds, {int? fromSimSeconds}) {
  final t = simSeconds + _epochOffsetS;
  final text = '${_pad2((t % 86400) ~/ 3600)}.${_pad2((t % 3600) ~/ 60)}';
  if (fromSimSeconds == null) return text;
  final days = t ~/ 86400 - (fromSimSeconds + _epochOffsetS) ~/ 86400;
  return days > 0 ? '$text (+$days hari)' : text;
}

/// Durasi waktu game: "1 j 25 m" / "40 m".
String formatDuration(int seconds) {
  final m = (seconds / 60).round();
  if (m < 60) return '$m m';
  return '${m ~/ 60} j ${m % 60} m';
}

/// Durasi game dikonversi ke waktu nyata pada skala [timeScale].
String formatRealDuration(int gameSeconds, int timeScale) {
  final s = (gameSeconds / timeScale).round();
  if (s < 60) return '$s dtk';
  final m = (s / 60).round();
  if (m < 60) return '$m mnt';
  return '${m ~/ 60} jam ${m % 60} mnt';
}

String formatKm(num meters) {
  final km = meters / 1000;
  return km < 10 ? '${km.toStringAsFixed(1).replaceAll('.', ',')} km' : '${km.round()} km';
}

String formatKg(int kg) =>
    kg >= 1000 ? '${(kg / 1000).toStringAsFixed(kg % 1000 == 0 ? 0 : 1).replaceAll('.', ',')} t' : '$kg kg';

String _pad2(int v) => v.toString().padLeft(2, '0');
