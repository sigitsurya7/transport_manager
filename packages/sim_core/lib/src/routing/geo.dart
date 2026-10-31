import 'dart:math' as math;

class LatLng {
  const LatLng(this.lat, this.lon);

  final double lat;
  final double lon;

  @override
  bool operator ==(Object other) =>
      other is LatLng && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => 'LatLng($lat, $lon)';
}

const double _earthRadiusM = 6371008.8;

double _rad(double deg) => deg * math.pi / 180;

/// Jarak lingkaran besar dalam meter. Rumus sama dengan pipeline Python.
double haversineMeters(LatLng a, LatLng b) {
  final p1 = _rad(a.lat);
  final p2 = _rad(b.lat);
  final dp = p2 - p1;
  final dl = _rad(b.lon - a.lon);
  final h = math.pow(math.sin(dp / 2), 2) +
      math.cos(p1) * math.cos(p2) * math.pow(math.sin(dl / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.sqrt(h));
}
