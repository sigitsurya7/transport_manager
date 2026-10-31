import '../contracts/contract.dart';
import '../routing/route_planner.dart';
import 'trip.dart';

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

  /// Bodi kendaraan tidak sanggup mengangkut jenis barang ini (mis. barang beku tanpa box berpendingin).
  cargoIncompatible,

  /// Tidak ada rute untuk salah satu leg.
  noRoute,

  /// Kas tidak cukup untuk membeli barang di supplier.
  insufficientCash,

  /// Isi stok: ruang gudang tidak cukup.
  warehouseFull,

  /// Kendaraan lain ditetapkan untuk kontrak berulang ini.
  wrongVehicle,
}

/// Estimasi lengkap satu pilihan rute, ditampilkan sebelum pemain menerima.
class DispatchQuote {
  const DispatchQuote({
    required this.mode,
    required this.plan,
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
    this.outboundRoute,
    this.pickupRoute,
    this.pickupS = 0,
    this.pickupLoadingS = 0,
    this.purchaseIdr = 0,
    this.stockValueIdr = 0,
    this.fulfillment,
  });

  final RouteMode mode;
  final List<TripPhase> plan;

  /// Depot → supplier (bila ada penjemputan).
  final Route? pickupRoute;

  /// Ke tujuan; `null` untuk isi stok.
  final Route? outboundRoute;
  final Route inboundRoute;
  final int pickupS;
  final int pickupLoadingS;
  final int outboundS;
  final int inboundS;

  /// Di depot sebelum lewat gerbang (slot → [dock → muat] → gerbang).
  final int beforeDepartureS;
  final int unloadingS;

  /// Gerbang masuk → slot (→ bongkar ke gudang) → inspeksi.
  final int afterReturnS;

  final int dispatchAt;
  final int deadline;

  /// Bayaran yang diterima bila tiba sesuai estimasi (sudah dikurangi penalti).
  final int revenueIdr;
  final int fuelIdr;
  final int tollIdr;

  /// Modal membeli barang di supplier.
  final int purchaseIdr;

  /// Nilai (harga grosir) stok gudang yang dipakai pesanan ini; informasi saja,
  /// tidak memengaruhi kas.
  final int stockValueIdr;

  /// Sumber barang pesanan toko.
  final Fulfillment? fulfillment;

  /// Kelelahan sopir saat kembali ke depot (≥ 1,0 = melewati batas jam mengemudi).
  final double fatigueAfter;

  /// Barang selesai dibongkar di tujuan (isi stok: selesai dimuat di supplier).
  int get deliveryEta => dispatchAt + beforeDepartureS + pickupS + pickupLoadingS + outboundS + unloadingS;

  /// Kendaraan siap dipakai lagi.
  int get completionEta => deliveryEta + inboundS + afterReturnS;

  bool get onTime => deliveryEta <= deadline;
  int get distanceM =>
      ((pickupRoute?.distanceM ?? 0) + (outboundRoute?.distanceM ?? 0) + inboundRoute.distanceM).round();
  bool get usesToll =>
      (pickupRoute?.usesToll ?? false) || (outboundRoute?.usesToll ?? false) || inboundRoute.usesToll;
  int get costIdr => fuelIdr + tollIdr + purchaseIdr;
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
