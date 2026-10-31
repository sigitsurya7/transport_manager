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
    this.unitVolumeM3 = 0.05,
    this.priceIdr = 0,
    this.storable = true,
  });

  factory CargoType.fromJson(Map<String, dynamic> j) => CargoType(
        id: j['id'] as String,
        name: j['name'] as String,
        unit: j['unit'] as String,
        unitWeightKg: (j['unit_weight_kg'] as num).toInt(),
        kind: j['kind'] as String? ?? 'general',
        unitVolumeM3: (j['unit_volume_m3'] as num?)?.toDouble() ?? 0.05,
        priceIdr: (j['price_idr'] as num?)?.toInt() ?? 0,
        storable: j['storable'] as bool? ?? true,
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

  /// Volume satu unit di gudang (m³).
  final double unitVolumeM3;

  /// Harga dasar satu unit di supplier (rupiah).
  final int priceIdr;

  /// Bisa disimpan di gudang umum (barang curah / kendaraan / kayu tidak).
  final bool storable;
}

/// Satu baris barang dalam kontrak atau stok.
class OrderLine {
  const OrderLine(this.cargoId, this.units);

  final String cargoId;
  final int units;

  Map<String, dynamic> toJson() => {'cargo': cargoId, 'units': units};

  factory OrderLine.fromJson(Map<String, dynamic> j) => OrderLine(j['cargo'] as String, j['units'] as int);

  @override
  bool operator ==(Object other) => other is OrderLine && other.cargoId == cargoId && other.units == units;

  @override
  int get hashCode => Object.hash(cargoId, units);

  @override
  String toString() => '$cargoId×$units';
}

enum ContractKind {
  /// Save lama: barang dimuat di depot lalu diantar ke tujuan.
  legacy,

  /// Jasa angkut: jemput di supplier ([Contract.pickupNode]) lalu antar ke tujuan.
  haul,

  /// Pesanan toko: barang dari stok gudang dan/atau dibeli di supplier.
  storeOrder,

  /// Isi stok gudang sendiri: beli di supplier, bongkar di dock depot.
  restock,
}

enum ContractStatus {
  /// Ditawarkan, belum diterima.
  offered,

  /// Sedang dikerjakan (sudah di-dispatch).
  inProgress,

  /// Barang sudah dibongkar di tujuan dan dibayar.
  delivered,
}

/// Rincian sumber barang pesanan toko, ditetapkan saat dispatch.
class Fulfillment {
  const Fulfillment({required this.fromStock, required this.toBuy});

  /// Diambil dari gudang (dimuat di dock depot).
  final List<OrderLine> fromStock;

  /// Dibeli di supplier saat penjemputan.
  final List<OrderLine> toBuy;

  bool get usesStock => fromStock.isNotEmpty;
  bool get needsPickup => toBuy.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'from_stock': [for (final l in fromStock) l.toJson()],
        'to_buy': [for (final l in toBuy) l.toJson()],
      };

  factory Fulfillment.fromJson(Map<String, dynamic> j) => Fulfillment(
        fromStock: [for (final l in j['from_stock'] as List) OrderLine.fromJson(l as Map<String, dynamic>)],
        toBuy: [for (final l in j['to_buy'] as List) OrderLine.fromJson(l as Map<String, dynamic>)],
      );
}

/// Kontrak pengiriman.
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
    this.kind = ContractKind.legacy,
    List<OrderLine>? lines,
    this.pickupNode,
    this.pickupName,
    this.supplierId,
    this.agreementId,
    this.goodsValueIdr = 0,
    this.status = ContractStatus.offered,
    this.deadline,
    this.deliveredAt,
    this.settledIdr,
    this.fulfillment,
  }) : lines = List.unmodifiable(lines ?? [OrderLine(cargoId, units)]);

  final int id;
  final String customer;

  /// Barang pertama (kompatibilitas tampilan lama). Rincian lengkap di [lines].
  final String cargoId;
  final int units;

  /// Berat total semua baris.
  final int weightKg;

  /// Tujuan bongkar. Untuk [ContractKind.restock] = node depot.
  final int destinationNode;
  final String destinationName;
  final DeliveryScope scope;
  final ContractKind kind;
  final List<OrderLine> lines;

  /// Lokasi jemput (supplier). `null` untuk kontrak lama.
  final int? pickupNode;
  final String? pickupName;
  final int? supplierId;

  /// Bagian dari kontrak berulang.
  final int? agreementId;

  /// Untuk pesanan toko: bagian [payIdr] yang merupakan harga barang.
  final int goodsValueIdr;

  /// Bayaran penuh bila tepat waktu (pesanan toko: barang + ongkos kirim).
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

  /// Sumber barang pesanan toko (ditetapkan saat dispatch).
  Fulfillment? fulfillment;

  bool get hasDeadline => kind != ContractKind.restock;

  /// Pembayaran bila barang tiba pada [arrival]: bayaran dikurangi penalti per
  /// jam keterlambatan (dibulatkan ke atas), tidak pernah negatif. Penalti
  /// hanya memotong ongkos kirim, bukan harga barang.
  int settlementAt(int arrival, {required int deadline}) {
    if (kind == ContractKind.restock) return 0;
    final lateS = math.max(0, arrival - deadline);
    final lateHours = (lateS + 3599) ~/ 3600;
    final fee = payIdr - goodsValueIdr;
    return goodsValueIdr + math.max(0, fee - lateHours * latePenaltyPerHourIdr);
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
        'kind': kind.name,
        'lines': [for (final l in lines) l.toJson()],
        'pickup_node': pickupNode,
        'pickup_name': pickupName,
        'supplier': supplierId,
        'agreement': agreementId,
        'goods_value_idr': goodsValueIdr,
        'pay_idr': payIdr,
        'offered_at': offeredAt,
        'allowed_s': allowedS,
        'late_penalty_idr_h': latePenaltyPerHourIdr,
        'status': status.name,
        'deadline': deadline,
        'delivered_at': deliveredAt,
        'settled_idr': settledIdr,
        'fulfillment': fulfillment?.toJson(),
      };

  /// Save sebelum revisi Tahap 4: tanpa jenis, baris, maupun lokasi jemput.
  factory Contract.fromJson(Map<String, dynamic> j) => Contract(
        id: j['id'] as int,
        customer: j['customer'] as String,
        cargoId: j['cargo'] as String,
        units: j['units'] as int,
        weightKg: j['weight_kg'] as int,
        destinationNode: j['dest_node'] as int,
        destinationName: j['dest_name'] as String,
        scope: DeliveryScope.parse(j['scope'] as String),
        kind: ContractKind.values.byName(j['kind'] as String? ?? ContractKind.legacy.name),
        lines: j['lines'] == null
            ? null
            : [for (final l in j['lines'] as List) OrderLine.fromJson(l as Map<String, dynamic>)],
        pickupNode: j['pickup_node'] as int?,
        pickupName: j['pickup_name'] as String?,
        supplierId: j['supplier'] as int?,
        agreementId: j['agreement'] as int?,
        goodsValueIdr: j['goods_value_idr'] as int? ?? 0,
        payIdr: j['pay_idr'] as int,
        offeredAt: j['offered_at'] as int,
        allowedS: j['allowed_s'] as int,
        latePenaltyPerHourIdr: j['late_penalty_idr_h'] as int,
        status: ContractStatus.values.byName(j['status'] as String),
        deadline: j['deadline'] as int?,
        deliveredAt: j['delivered_at'] as int?,
        settledIdr: j['settled_idr'] as int?,
        fulfillment:
            j['fulfillment'] == null ? null : Fulfillment.fromJson(j['fulfillment'] as Map<String, dynamic>),
      );
}
