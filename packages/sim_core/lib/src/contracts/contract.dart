import 'dart:math' as math;

import 'contract_tiers.dart';

/// Jenis barang dari katalog (`content/cargo_types.json`).
class CargoType {
  const CargoType({
    required this.id,
    required this.name,
    required this.unit,
    required this.unitWeightKg,
    this.kind = 'general',
  });

  factory CargoType.fromJson(Map<String, dynamic> j) => CargoType(
        id: j['id'] as String,
        name: j['name'] as String,
        unit: j['unit'] as String,
        unitWeightKg: (j['unit_weight_kg'] as num).toInt(),
        kind: j['kind'] as String? ?? 'general',
      );

  static Map<String, CargoType> catalogFromJson(Map<String, dynamic> json) => {
        for (final c in json['cargo'] as List)
          (c as Map<String, dynamic>)['id'] as String: CargoType.fromJson(c),
      };

  final String id;
  final String name;
  final String unit;
  final int unitWeightKg;

  /// Jenis muatan (`cargo_kinds` di katalog kendaraan): menentukan bodi yang sanggup mengangkut.
  final String kind;
}

enum ContractStatus {
  /// Ditawarkan, belum diterima.
  offered,

  /// Sedang dikerjakan (sudah di-dispatch).
  inProgress,

  /// Barang sudah dibongkar di tujuan dan dibayar.
  delivered,
}

/// Kontrak pengiriman satu kali dari depot ke satu tujuan.
class Contract {
  Contract({
    required this.id,
    required this.customer,
    required this.cargoId,
    required this.units,
    required this.weightKg,
    required this.destinationNode,
    required this.destinationName,
    required this.scope,
    required this.payIdr,
    required this.offeredAt,
    required this.allowedS,
    required this.latePenaltyPerHourIdr,
    this.status = ContractStatus.offered,
    this.deadline,
    this.deliveredAt,
    this.settledIdr,
  });

  final int id;
  final String customer;
  final String cargoId;
  final int units;
  final int weightKg;
  final int destinationNode;
  final String destinationName;
  final DeliveryScope scope;

  /// Bayaran penuh bila tepat waktu.
  final int payIdr;

  final int offeredAt;

  /// Waktu yang diberikan sejak dispatch sampai barang tiba (detik game).
  final int allowedS;

  final int latePenaltyPerHourIdr;

  ContractStatus status;

  /// Tenggat absolut, ditetapkan saat dispatch.
  int? deadline;

  int? deliveredAt;
  int? settledIdr;

  /// Pembayaran bila barang tiba pada [arrival]: bayaran dikurangi penalti per
  /// jam keterlambatan (dibulatkan ke atas), tidak pernah negatif.
  int settlementAt(int arrival, {required int deadline}) {
    final lateS = math.max(0, arrival - deadline);
    final lateHours = (lateS + 3599) ~/ 3600;
    return math.max(0, payIdr - lateHours * latePenaltyPerHourIdr);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'customer': customer,
        'cargo': cargoId,
        'units': units,
        'weight_kg': weightKg,
        'dest_node': destinationNode,
        'dest_name': destinationName,
        'scope': scope.id,
        'pay_idr': payIdr,
        'offered_at': offeredAt,
        'allowed_s': allowedS,
        'late_penalty_idr_h': latePenaltyPerHourIdr,
        'status': status.name,
        'deadline': deadline,
        'delivered_at': deliveredAt,
        'settled_idr': settledIdr,
      };

  factory Contract.fromJson(Map<String, dynamic> j) => Contract(
        id: j['id'] as int,
        customer: j['customer'] as String,
        cargoId: j['cargo'] as String,
        units: j['units'] as int,
        weightKg: j['weight_kg'] as int,
        destinationNode: j['dest_node'] as int,
        destinationName: j['dest_name'] as String,
        scope: DeliveryScope.parse(j['scope'] as String),
        payIdr: j['pay_idr'] as int,
        offeredAt: j['offered_at'] as int,
        allowedS: j['allowed_s'] as int,
        latePenaltyPerHourIdr: j['late_penalty_idr_h'] as int,
        status: ContractStatus.values.byName(j['status'] as String),
        deadline: j['deadline'] as int?,
        deliveredAt: j['delivered_at'] as int?,
        settledIdr: j['settled_idr'] as int?,
      );
}
