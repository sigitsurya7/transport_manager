import '../routing/route_planner.dart';
import 'contract.dart';
import 'contract_tiers.dart';

enum AgreementStatus {
  /// Ditawarkan, belum diterima.
  offered,

  /// Berjalan: pengiriman dijadwalkan berkala.
  active,

  /// Semua pengiriman sudah diberangkatkan.
  finished,

  /// Diputus (oleh pemain, atau karena terlalu sering terlewat).
  cancelled,
}

/// Kontrak jasa angkut berulang: setiap [intervalS] mengirim barang yang
/// sama dari supplier ke tujuan yang sama memakai kendaraan yang sama.
///
/// Setiap pengiriman dibuat sebagai [Contract] anak (`agreementId`), sehingga
/// dispatch, pembayaran, dan penalti memakai logika kontrak biasa.
class Agreement {
  Agreement({
    required this.id,
    required this.customer,
    required this.supplierId,
    required this.pickupNode,
    required this.pickupName,
    required this.destinationNode,
    required this.destinationName,
    required this.scope,
    required this.lines,
    required this.weightKg,
    required this.payPerRunIdr,
    required this.allowedS,
    required this.latePenaltyPerHourIdr,
    required this.intervalS,
    required this.runsTotal,
    required this.offeredAt,
    this.status = AgreementStatus.offered,
    this.vehicleId,
    this.driverId,
    this.mode = RouteMode.toll,
    this.runsDispatched = 0,
    this.runsMissed = 0,
    this.nextRunAt,
  });

  final int id;
  final String customer;
  final int supplierId;
  final int pickupNode;
  final String pickupName;
  final int destinationNode;
  final String destinationName;
  final DeliveryScope scope;
  final List<OrderLine> lines;
  final int weightKg;
  final int payPerRunIdr;
  final int allowedS;
  final int latePenaltyPerHourIdr;

  /// Jarak antar-pengiriman (detik game): 1, 2, 3, atau 7 hari.
  final int intervalS;
  final int runsTotal;
  final int offeredAt;

  AgreementStatus status;

  /// Kendaraan tetap untuk semua pengiriman.
  int? vehicleId;

  /// Sopir utama; bila sedang bertugas / lelah dipakai sopir lain yang siap.
  int? driverId;

  RouteMode mode;
  int runsDispatched;
  int runsMissed;

  /// Waktu pengiriman berikutnya dijadwalkan.
  int? nextRunAt;

  int get intervalDays => intervalS ~/ 86400;
  int get runsLeft => runsTotal - runsDispatched;
  bool get isActive => status == AgreementStatus.active;

  Map<String, dynamic> toJson() => {
        'id': id,
        'customer': customer,
        'supplier': supplierId,
        'pickup_node': pickupNode,
        'pickup_name': pickupName,
        'dest_node': destinationNode,
        'dest_name': destinationName,
        'scope': scope.id,
        'lines': [for (final l in lines) l.toJson()],
        'weight_kg': weightKg,
        'pay_per_run_idr': payPerRunIdr,
        'allowed_s': allowedS,
        'late_penalty_idr_h': latePenaltyPerHourIdr,
        'interval_s': intervalS,
        'runs_total': runsTotal,
        'offered_at': offeredAt,
        'status': status.name,
        'vehicle': vehicleId,
        'driver': driverId,
        'mode': mode.name,
        'runs_dispatched': runsDispatched,
        'runs_missed': runsMissed,
        'next_run_at': nextRunAt,
      };

  factory Agreement.fromJson(Map<String, dynamic> j) => Agreement(
        id: j['id'] as int,
        customer: j['customer'] as String,
        supplierId: j['supplier'] as int,
        pickupNode: j['pickup_node'] as int,
        pickupName: j['pickup_name'] as String,
        destinationNode: j['dest_node'] as int,
        destinationName: j['dest_name'] as String,
        scope: DeliveryScope.parse(j['scope'] as String),
        lines: [for (final l in j['lines'] as List) OrderLine.fromJson(l as Map<String, dynamic>)],
        weightKg: j['weight_kg'] as int,
        payPerRunIdr: j['pay_per_run_idr'] as int,
        allowedS: j['allowed_s'] as int,
        latePenaltyPerHourIdr: j['late_penalty_idr_h'] as int,
        intervalS: j['interval_s'] as int,
        runsTotal: j['runs_total'] as int,
        offeredAt: j['offered_at'] as int,
        status: AgreementStatus.values.byName(j['status'] as String),
        vehicleId: j['vehicle'] as int?,
        driverId: j['driver'] as int?,
        mode: RouteMode.values.byName(j['mode'] as String),
        runsDispatched: j['runs_dispatched'] as int,
        runsMissed: j['runs_missed'] as int,
        nextRunAt: j['next_run_at'] as int?,
      );
}

/// Supplier (pemasok) di kota depot: titik jemput jasa angkut & tempat beli barang.
class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    required this.cityId,
    required this.node,
    required this.sells,
  });

  final int id;
  final String name;
  final String cityId;
  final int node;

  /// Id barang yang dijual.
  final List<String> sells;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'city': cityId, 'node': node, 'sells': sells};

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
        id: j['id'] as int,
        name: j['name'] as String,
        cityId: j['city'] as String,
        node: j['node'] as int,
        sells: (j['sells'] as List).cast<String>(),
      );
}

/// Template supplier dari `content/suppliers.json`.
class SupplierTemplate {
  const SupplierTemplate({required this.name, required this.sells});

  factory SupplierTemplate.fromJson(Map<String, dynamic> j) =>
      SupplierTemplate(name: j['name'] as String, sells: (j['sells'] as List).cast<String>());

  final String name;
  final List<String> sells;
}
