import 'geo.dart';
import 'polyline.dart';

enum RoadClass {
  motorway('motorway'),
  motorwayLink('motorway_link'),
  trunk('trunk'),
  trunkLink('trunk_link'),
  primary('primary'),
  primaryLink('primary_link'),
  secondary('secondary'),
  secondaryLink('secondary_link'),
  tertiary('tertiary'),
  tertiaryLink('tertiary_link'),
  unclassified('unclassified'),
  residential('residential');

  const RoadClass(this.osmTag);

  final String osmTag;

  static RoadClass parse(String tag) => RoadClass.values.firstWhere(
        (c) => c.osmTag == tag,
        orElse: () => throw FormatException('Kelas jalan tidak dikenal: $tag'),
      );
}

/// Ruas jalan berarah antar dua persimpangan.
class RoadEdge {
  RoadEdge({
    required this.id,
    required this.from,
    required this.to,
    required this.lengthM,
    required this.roadClass,
    required this.maxSpeedKmh,
    required this.isToll,
    this.maxWeightT,
    this.encodedGeometry,
  });

  final int id;
  final int from;
  final int to;
  final double lengthM;
  final RoadClass roadClass;
  final int maxSpeedKmh;
  final bool isToll;

  /// Batas berat kendaraan (ton), `null` bila tidak ada batas.
  final double? maxWeightT;

  final String? encodedGeometry;
  List<LatLng>? _geometry;

  /// Geometri nyata ruas (di-decode saat pertama dibutuhkan).
  List<LatLng> get geometry =>
      _geometry ??= encodedGeometry == null ? const [] : decodePolyline(encodedGeometry!);
}

/// Graph jalan untuk routing. ID node padat `0..nodeCount-1`.
class RoadGraph {
  RoadGraph({required List<LatLng> nodes, required List<RoadEdge> edges})
      : _nodes = nodes,
        _edges = edges,
        _outgoing = List.generate(nodes.length, (_) => <int>[]) {
    var maxSpeed = 0;
    for (final e in edges) {
      if (e.from < 0 || e.from >= nodes.length || e.to < 0 || e.to >= nodes.length) {
        throw FormatException('Edge ${e.id} menunjuk node yang tidak ada');
      }
      _outgoing[e.from].add(e.id);
      if (e.maxSpeedKmh > maxSpeed) maxSpeed = e.maxSpeedKmh;
    }
    _maxSpeedKmh = maxSpeed;
  }

  /// Baca `graph.json` hasil `build_roads.py --json` (format 1).
  ///
  /// `nodes`: `[id, lat, lon]`; `edges`: `[from, to, length_m, class,
  /// maxspeed, toll, maxweight, geometry]`, ID edge = indeks.
  factory RoadGraph.fromJson(Map<String, dynamic> json) {
    if (json['format'] != 1) {
      throw FormatException('Format graph tidak didukung: ${json['format']}');
    }
    final rawNodes = json['nodes'] as List;
    final nodes = List<LatLng>.filled(rawNodes.length, const LatLng(0, 0));
    for (final n in rawNodes) {
      final row = n as List;
      nodes[(row[0] as num).toInt()] =
          LatLng((row[1] as num).toDouble(), (row[2] as num).toDouble());
    }
    final rawEdges = json['edges'] as List;
    final edges = <RoadEdge>[];
    for (var i = 0; i < rawEdges.length; i++) {
      final r = rawEdges[i] as List;
      edges.add(RoadEdge(
        id: i,
        from: (r[0] as num).toInt(),
        to: (r[1] as num).toInt(),
        lengthM: (r[2] as num).toDouble(),
        roadClass: RoadClass.parse(r[3] as String),
        maxSpeedKmh: (r[4] as num).toInt(),
        isToll: (r[5] as num) != 0,
        maxWeightT: (r[6] as num?)?.toDouble(),
        encodedGeometry: r[7] as String?,
      ));
    }
    return RoadGraph(nodes: nodes, edges: edges);
  }

  final List<LatLng> _nodes;
  final List<RoadEdge> _edges;
  final List<List<int>> _outgoing;
  late final int _maxSpeedKmh;

  int get nodeCount => _nodes.length;
  int get edgeCount => _edges.length;

  /// Batas kecepatan tertinggi di seluruh graph (untuk heuristik A*).
  int get maxSpeedKmh => _maxSpeedKmh;

  LatLng node(int id) => _nodes[id];
  RoadEdge edge(int id) => _edges[id];

  Iterable<RoadEdge> outgoing(int node) => _outgoing[node].map((id) => _edges[id]);

  /// Node terdekat (pencarian linear; di aplikasi diganti R-tree SQLite).
  int nearestNode(LatLng p) {
    var best = -1;
    var bestDist = double.infinity;
    for (var i = 0; i < _nodes.length; i++) {
      final d = haversineMeters(p, _nodes[i]);
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }
}
