import 'package:sim_core/sim_core.dart';

import '../../util/format.dart';

/// Kalimat untuk satu baris log simulasi (simulasi hanya menyimpan data).
String logText(SimWorld world, WorldLogEntry e) {
  String vehicle(Object? id) => world.vehicles[id]?.model.name ?? 'Kendaraan';
  String customer(Object? id) => world.contracts[id]?.customer ?? 'pelanggan';
  String facility(Object? id) => world.content.facilities[FacilityType.parse(id! as String)].name;
  String supplier(Object? id) => world.suppliers[id]?.name ?? 'supplier';
  String agreement(Object? id) => world.agreements[id]?.customer ?? 'pelanggan';
  String model(Object? id) => world.content.vehicleModels[id]?.name ?? 'Kendaraan';
  final d = e.data;
  return switch (e.kind) {
    WorldLogKind.contractOffered => 'Tawaran kontrak baru dari ${customer(d['contract'])}.',
    WorldLogKind.dispatched =>
      '${vehicle(d['vehicle'])} ditugaskan ke ${customer(d['contract'])} (${d['mode'] == 'toll' ? 'via tol' : 'non-tol'}).',
    WorldLogKind.departedDepot => '${vehicle(d['vehicle'])} keluar dari gerbang depot.',
    WorldLogKind.delivered =>
      d['late'] == true
          ? 'Barang tiba terlambat di ${customer(d['contract'])}. Dibayar ${formatRupiah(d['settled_idr']! as int)}.'
          : 'Barang tiba tepat waktu di ${customer(d['contract'])}. Dibayar ${formatRupiah(d['settled_idr']! as int)}.',
    WorldLogKind.returnedToDepot => '${vehicle(d['vehicle'])} tiba kembali di depot.',
    WorldLogKind.tripCompleted => '${vehicle(d['vehicle'])} selesai diperiksa dan siap ditugaskan.',
    WorldLogKind.upgradeStarted => 'Konstruksi ${facility(d['facility'])} level ${d['level']} dimulai.',
    WorldLogKind.upgradeFinished => '${facility(d['facility'])} level ${d['level']} selesai dibangun.',
    WorldLogKind.vehiclePurchased =>
      d['used'] == true ? '${vehicle(d['vehicle'])} bekas dibeli.' : '${vehicle(d['vehicle'])} baru dibeli.',
    WorldLogKind.employeeHired => switch (d['role']) {
      'driver' => 'Sopir baru ${world.drivers[d['driver']]?.name ?? ''} bergabung.',
      'mechanic' => 'Mekanik bertambah menjadi ${d['count']} orang.',
      _ => 'Staf gudang bertambah menjadi ${d['count']} orang.',
    },
    WorldLogKind.employeeReleased => switch (d['role']) {
      'driver' => 'Sopir ${d['name']} diberhentikan.',
      'mechanic' => 'Mekanik berkurang menjadi ${d['count']} orang.',
      _ => 'Staf gudang berkurang menjadi ${d['count']} orang.',
    },
    WorldLogKind.maintenanceStarted =>
      '${vehicle(d['vehicle'])} masuk bengkel: ${world.content.maintenance.action(d['action']! as String).name.toLowerCase()}.',
    WorldLogKind.maintenanceFinished =>
      '${vehicle(d['vehicle'])} selesai ${world.content.maintenance.action(d['action']! as String).name.toLowerCase()}.',
    WorldLogKind.payrollPaid => 'Gaji harian dibayar ${formatRupiah(d['amount_idr']! as int)}.',
    WorldLogKind.pickedUp => (d['cost_idr'] as int? ?? 0) > 0
        ? 'Barang untuk ${customer(d['contract'])} dibeli di ${supplier(d['supplier'])} '
            '(${formatRupiah(d['cost_idr']! as int)}).'
        : 'Barang ${customer(d['contract'])} dimuat di ${supplier(d['supplier'])}.',
    WorldLogKind.restocked => 'Barang isi stok masuk gudang.',
    WorldLogKind.vehicleSold =>
      '${model(d['model'])} dijual ${formatRupiah(d['price_idr']! as int)}.',
    WorldLogKind.agreementOffered => 'Tawaran kontrak berulang dari ${agreement(d['agreement'])}.',
    WorldLogKind.agreementAccepted => 'Kontrak berulang dengan ${agreement(d['agreement'])} dimulai.',
    WorldLogKind.agreementRunMissed =>
      'Pengiriman berkala untuk ${agreement(d['agreement'])} terlewat (${d['missed']}×).',
    WorldLogKind.agreementCancelled => d['by_player'] == true
        ? 'Kontrak berulang dengan ${agreement(d['agreement'])} diputus. Denda ${formatRupiah(d['penalty_idr']! as int)}.'
        : 'Kontrak berulang dengan ${agreement(d['agreement'])} putus karena terlalu sering terlewat.',
    WorldLogKind.agreementFinished => 'Semua pengiriman kontrak berulang ${agreement(d['agreement'])} sudah berangkat.',
  };
}
