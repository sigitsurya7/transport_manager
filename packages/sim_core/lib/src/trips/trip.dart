import '../routing/route_planner.dart';

/// Fase satu siklus pengiriman, berurutan. Kendaraan tidak pernah muncul
/// atau hilang: setiap perpindahan punya fase dan durasi sendiri.
enum TripPhase {
  /// Dari slot parkir ke loading area.
  toDock(inDepot: true),
  loading(inDepot: true),

  /// Dari loading area ke gerbang, lalu keluar.
  toGate(inDepot: true),

  /// Di jalan menuju tujuan.
  outbound(onRoad: true),
  unloading(),

  /// Di jalan kembali ke depot.
  inbound(onRoad: true),

  /// Melewati gerbang masuk.
  gateIn(inDepot: true),
  toSlot(inDepot: true),

  /// Pemeriksaan kendaraan setelah parkir.
  inspection(inDepot: true),
  completed(inDepot: true);

  const TripPhase({this.inDepot = false, this.onRoad = false});

  final bool inDepot;
  final bool onRoad;

  TripPhase get next => TripPhase.values[index + 1];
}

/// Satu leg perjalanan di jalan, disimpan sebagai daftar edge graph.
class TripLeg {
  const TripLeg({
    required this.edges,
    required this.startNode,
    required this.distanceM,
    required this.durationS,
    required this.tollIdr,
  });

  factory TripLeg.fromRoute(Route route, int durationS) => TripLeg(
        edges: List.unmodifiable(route.edges),
        startNode: route.nodes.first,
        distanceM: route.distanceM.round(),
        durationS: durationS,
        tollIdr: route.tollCostIdr,
      );

  final List<int> edges;

  /// Node awal (dibutuhkan bila [edges] kosong: asal = tujuan).
  final int startNode;

  final int distanceM;
  final int durationS;
  final int tollIdr;

  Map<String, dynamic> toJson() => {
        'edges': edges,
        'start': startNode,
        'distance_m': distanceM,
        'duration_s': durationS,
        'toll_idr': tollIdr,
      };

  factory TripLeg.fromJson(Map<String, dynamic> j) => TripLeg(
        edges: List.unmodifiable((j['edges'] as List).cast<int>()),
        startNode: j['start'] as int,
        distanceM: j['distance_m'] as int,
        durationS: j['duration_s'] as int,
        tollIdr: j['toll_idr'] as int,
      );
}

class Trip {
  Trip({
    required this.id,
    required this.contractId,
    required this.vehicleId,
    required this.driverId,
    required this.mode,
    required this.outbound,
    required this.inbound,
    required this.startedAt,
    required this.phase,
    required this.phaseStart,
    required this.phaseEnd,
  });

  final int id;
  final int contractId;
  final int vehicleId;
  final int driverId;
  final RouteMode mode;
  final TripLeg outbound;
  final TripLeg inbound;
  final int startedAt;

  TripPhase phase;
  int phaseStart;
  int phaseEnd;

  bool get isActive => phase != TripPhase.completed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'contract': contractId,
        'vehicle': vehicleId,
        'driver': driverId,
        'mode': mode.name,
        'outbound': outbound.toJson(),
        'inbound': inbound.toJson(),
        'started_at': startedAt,
        'phase': phase.name,
        'phase_start': phaseStart,
        'phase_end': phaseEnd,
      };

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        id: j['id'] as int,
        contractId: j['contract'] as int,
        vehicleId: j['vehicle'] as int,
        driverId: j['driver'] as int,
        mode: RouteMode.values.byName(j['mode'] as String),
        outbound: TripLeg.fromJson(j['outbound'] as Map<String, dynamic>),
        inbound: TripLeg.fromJson(j['inbound'] as Map<String, dynamic>),
        startedAt: j['started_at'] as int,
        phase: TripPhase.values.byName(j['phase'] as String),
        phaseStart: j['phase_start'] as int,
        phaseEnd: j['phase_end'] as int,
      );
}
