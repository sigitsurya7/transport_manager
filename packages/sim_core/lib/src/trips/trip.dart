import '../routing/route_planner.dart';

/// Fase siklus pengiriman. Kendaraan tidak pernah muncul atau hilang: setiap
/// perpindahan punya fase dan durasi sendiri. Fase `wait*` adalah antrean:
/// durasinya tidak diketahui sampai sumber daya (dock / jalur gerbang) kosong.
///
/// Tidak setiap trip melewati semua fase: urutannya ada di [Trip.plan]
/// (lihat [TripPlans]). Urutan enum = urutan logis bila semua dilewati.
enum TripPhase {
  /// Menunggu loading dock kosong (di slot parkir).
  waitDock(inDepot: true, waiting: true),

  /// Keluar dari slot menuju loading dock.
  toDock(inDepot: true),

  /// Memuat barang dari gudang di loading dock.
  loading(inDepot: true),

  /// Dari loading dock ke depan gerbang.
  toGate(inDepot: true),

  /// Dari slot langsung ke antrean gerbang (tanpa muat di depot); berputar di
  /// apron dock tanpa memesan dock.
  toGateDirect(inDepot: true),

  /// Antre di depan gerbang untuk keluar.
  waitGateOut(inDepot: true, waiting: true),

  /// Pemeriksaan & lewat gerbang keluar.
  gateOut(inDepot: true),

  /// Di jalan menuju supplier (titik jemput).
  toPickup(onRoad: true),

  /// Memuat barang di supplier.
  pickupLoading(),

  /// Di jalan menuju tujuan.
  outbound(onRoad: true),
  unloading(),

  /// Di jalan kembali ke depot.
  inbound(onRoad: true),

  /// Antre di jalan depan depot untuk masuk.
  waitGateIn(waiting: true),

  /// Pemeriksaan & lewat gerbang masuk.
  gateIn(inDepot: true),

  /// Dari gerbang ke slot parkir.
  toSlot(inDepot: true),

  /// Isi stok: menunggu dock kosong untuk bongkar ke gudang (di slot parkir).
  waitDockIn(inDepot: true, waiting: true),

  /// Isi stok: dari slot ke dock.
  toDockIn(inDepot: true),

  /// Isi stok: bongkar barang ke gudang.
  unloadDock(inDepot: true),

  /// Isi stok: dari dock kembali ke slot.
  dockToSlot(inDepot: true),

  /// Pemeriksaan kendaraan setelah parkir.
  inspection(inDepot: true),
  completed(inDepot: true);

  const TripPhase({this.inDepot = false, this.onRoad = false, this.waiting = false});

  final bool inDepot;
  final bool onRoad;
  final bool waiting;

  /// Fase yang memakai loading dock (dipesan sejak berangkat dari slot).
  bool get usesDock => this == toDock || this == loading || this == toDockIn || this == unloadDock;
}

/// Urutan fase baku per bentuk pekerjaan.
abstract final class TripPlans {
  static const _depart = [TripPhase.waitGateOut, TripPhase.gateOut];
  static const _return = [TripPhase.waitGateIn, TripPhase.gateIn, TripPhase.toSlot];
  static const _end = [TripPhase.inspection, TripPhase.completed];
  static const _dockLoad = [TripPhase.waitDock, TripPhase.toDock, TripPhase.loading, TripPhase.toGate];
  static const _deliver = [TripPhase.outbound, TripPhase.unloading, TripPhase.inbound];
  static const _pickup = [TripPhase.toPickup, TripPhase.pickupLoading];

  /// Save lama / pesanan dari stok penuh: muat di depot → antar.
  static const depotLoad = [..._dockLoad, ..._depart, ..._deliver, ..._return, ..._end];

  /// Jasa angkut / pesanan tanpa stok: jemput di supplier → antar.
  static const pickup = [TripPhase.toGateDirect, ..._depart, ..._pickup, ..._deliver, ..._return, ..._end];

  /// Pesanan toko dengan stok sebagian: muat di depot → beli sisanya → antar.
  static const depotLoadThenPickup = [..._dockLoad, ..._depart, ..._pickup, ..._deliver, ..._return, ..._end];

  /// Isi stok gudang: beli di supplier → bongkar di dock depot.
  static const restock = [
    TripPhase.toGateDirect,
    ..._depart,
    ..._pickup,
    TripPhase.inbound,
    ..._return,
    TripPhase.waitDockIn,
    TripPhase.toDockIn,
    TripPhase.unloadDock,
    TripPhase.dockToSlot,
    ..._end,
  ];
}

/// Leg perjalanan di jalan.
enum LegKind { pickup, outbound, inbound }

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

  /// Leg kosong (tidak ditempuh), mis. leg antar untuk isi stok.
  const TripLeg.none(this.startNode)
      : edges = const [],
        distanceM = 0,
        durationS = 0,
        tollIdr = 0;

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
    this.pickup,
    List<TripPhase>? plan,
    this.dock,
    this.gateLane,
  }) : plan = List.unmodifiable(plan ?? TripPlans.depotLoad);

  final int id;
  final int contractId;
  final int vehicleId;
  final int driverId;
  final RouteMode mode;

  /// Depot → supplier (bila ada penjemputan).
  final TripLeg? pickup;

  /// Ke tujuan (dari depot atau supplier). Kosong untuk isi stok.
  final TripLeg outbound;

  /// Kembali ke depot (dari tujuan atau, untuk isi stok, dari supplier).
  final TripLeg inbound;

  final int startedAt;

  /// Urutan fase trip ini (diakhiri [TripPhase.completed]).
  final List<TripPhase> plan;

  TripPhase phase;
  int phaseStart;

  /// Akhir fase. Untuk fase antrean (`wait*`) belum diketahui → sama dengan
  /// [phaseStart].
  int phaseEnd;

  /// Loading dock yang dipakai (dipesan sejak berangkat dari slot sampai
  /// selesai muat / bongkar).
  int? dock;

  /// Jalur gerbang yang sedang dilewati.
  int? gateLane;

  bool get isActive => phase != TripPhase.completed;

  bool has(TripPhase p) => plan.contains(p);

  /// Fase sesudah [p] di rencana trip ini.
  TripPhase next(TripPhase p) {
    final i = plan.indexOf(p);
    if (i < 0 || i + 1 >= plan.length) return TripPhase.completed;
    return plan[i + 1];
  }

  /// Leg yang sedang ditempuh (fase di jalan), atau `null`.
  LegKind? get legKind => switch (phase) {
        TripPhase.toPickup => LegKind.pickup,
        TripPhase.outbound => LegKind.outbound,
        TripPhase.inbound => LegKind.inbound,
        _ => null,
      };

  TripLeg? leg(LegKind kind) => switch (kind) {
        LegKind.pickup => pickup,
        LegKind.outbound => has(TripPhase.outbound) ? outbound : null,
        LegKind.inbound => inbound,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'contract': contractId,
        'vehicle': vehicleId,
        'driver': driverId,
        'mode': mode.name,
        'pickup': pickup?.toJson(),
        'outbound': outbound.toJson(),
        'inbound': inbound.toJson(),
        'started_at': startedAt,
        'plan': [for (final p in plan) p.name],
        'phase': phase.name,
        'phase_start': phaseStart,
        'phase_end': phaseEnd,
        'dock': dock,
        'gate_lane': gateLane,
      };

  /// Save lama tanpa `plan`: alur muat di depot.
  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        id: j['id'] as int,
        contractId: j['contract'] as int,
        vehicleId: j['vehicle'] as int,
        driverId: j['driver'] as int,
        mode: RouteMode.values.byName(j['mode'] as String),
        pickup: j['pickup'] == null ? null : TripLeg.fromJson(j['pickup'] as Map<String, dynamic>),
        outbound: TripLeg.fromJson(j['outbound'] as Map<String, dynamic>),
        inbound: TripLeg.fromJson(j['inbound'] as Map<String, dynamic>),
        startedAt: j['started_at'] as int,
        plan: j['plan'] == null ? null : [for (final p in j['plan'] as List) TripPhase.values.byName(p as String)],
        phase: TripPhase.values.byName(j['phase'] as String),
        phaseStart: j['phase_start'] as int,
        phaseEnd: j['phase_end'] as int,
        dock: j['dock'] as int?,
        gateLane: j['gate_lane'] as int?,
      );
}
