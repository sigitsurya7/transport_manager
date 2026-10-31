import '../routing/route_planner.dart';

/// Alasan dispatch ditolak.
enum DispatchProblem {
  contractNotOffered,
  vehicleBusy,

  /// Kendaraan sedang di bengkel (atau antre servis).
  vehicleInWorkshop,
  driverBusy,

  /// Sopir mencapai batas jam mengemudi; harus istirahat di depot.
  driverNeedsRest,

  /// Kelas kendaraan di bawah minimum jangkauan kontrak (mis. pikap untuk antarkota).
  vehicleClassTooSmall,

  /// Muatan melebihi kapasitas kendaraan.
  overCapacity,

  /// Tidak ada rute pergi atau pulang untuk kendaraan ini.
  noRoute,
}

/// Estimasi lengkap satu pilihan rute, ditampilkan sebelum pemain menerima.
class DispatchQuote {
  const DispatchQuote({
    required this.mode,
    required this.outboundRoute,
    required this.inboundRoute,
    required this.outboundS,
    required this.inboundS,
    required this.beforeDepartureS,
    required this.unloadingS,
    required this.afterReturnS,
    required this.dispatchAt,
    required this.deadline,
    required this.revenueIdr,
    required this.fuelIdr,
    required this.tollIdr,
    required this.fatigueAfter,
  });

  final RouteMode mode;
  final Route outboundRoute;
  final Route inboundRoute;
  final int outboundS;
  final int inboundS;

  /// Slot → dock → muat → gerbang.
  final int beforeDepartureS;
  final int unloadingS;

  /// Gerbang masuk → slot → inspeksi.
  final int afterReturnS;

  final int dispatchAt;
  final int deadline;

  /// Bayaran yang diterima bila tiba sesuai estimasi (sudah dikurangi penalti).
  final int revenueIdr;
  final int fuelIdr;
  final int tollIdr;

  /// Kelelahan sopir saat kembali ke depot (≥ 1,0 = melewati batas jam mengemudi).
  final double fatigueAfter;

  /// Barang selesai dibongkar di tujuan.
  int get deliveryEta => dispatchAt + beforeDepartureS + outboundS + unloadingS;

  /// Kendaraan siap dipakai lagi.
  int get completionEta => deliveryEta + inboundS + afterReturnS;

  bool get onTime => deliveryEta <= deadline;
  int get distanceM => (outboundRoute.distanceM + inboundRoute.distanceM).round();
  int get costIdr => fuelIdr + tollIdr;
  int get profitIdr => revenueIdr - costIdr;
}

/// Hasil pemeriksaan dispatch: masalah (bila ada) dan estimasi tol vs non-tol.
class DispatchCheck {
  const DispatchCheck({required this.problems, this.viaToll, this.nonToll});

  final List<DispatchProblem> problems;
  final DispatchQuote? viaToll;
  final DispatchQuote? nonToll;

  bool get canDispatch => problems.isEmpty;

  DispatchQuote? quote(RouteMode mode) => mode == RouteMode.toll ? viaToll : nonToll;
}

class DispatchException implements Exception {
  const DispatchException(this.problems);

  final List<DispatchProblem> problems;

  @override
  String toString() => 'DispatchException(${problems.map((p) => p.name).join(', ')})';
}
