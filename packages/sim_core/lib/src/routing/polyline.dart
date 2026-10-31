import 'geo.dart';

/// Decode Google encoded polyline (default precision 6, sama dengan
/// `tools/map_pipeline/build_roads.py`).
List<LatLng> decodePolyline(String encoded, {int precision = 6}) {
  var factor = 1;
  for (var i = 0; i < precision; i++) {
    factor *= 10;
  }
  final points = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lon = 0;
  while (index < encoded.length) {
    final values = <int>[0, 0];
    for (var k = 0; k < 2; k++) {
      var shift = 0;
      var result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      values[k] = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    }
    lat += values[0];
    lon += values[1];
    points.add(LatLng(lat / factor, lon / factor));
  }
  return points;
}
