import 'package:sim_core/sim_core.dart';

import '../../util/format.dart';

/// Kalimat untuk satu baris log simulasi (simulasi hanya menyimpan data).
String logText(SimWorld world, WorldLogEntry e) {
  String vehicle(Object? id) => world.vehicles[id]?.model.name ?? 'Kendaraan';
  String customer(Object? id) => world.contracts[id]?.customer ?? 'pelanggan';
  String facility(Object? id) => world.content.facilities[FacilityType.parse(id! as String)].name;
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
    WorldLogKind.vehiclePurchased => '${vehicle(d['vehicle'])} baru dibeli.',
    WorldLogKind.employeeHired =>
      d['role'] == 'driver'
          ? 'Sopir baru ${world.drivers[d['driver']]?.name ?? ''} bergabung.'
          : 'Staf gudang bertambah menjadi ${d['count']} orang.',
    WorldLogKind.employeeReleased => 'Staf gudang berkurang menjadi ${d['count']} orang.',
    WorldLogKind.maintenanceStarted =>
      '${vehicle(d['vehicle'])} masuk bengkel: ${world.content.maintenance.action(d['action']! as String).name.toLowerCase()}.',
    WorldLogKind.maintenanceFinished =>
      '${vehicle(d['vehicle'])} selesai ${world.content.maintenance.action(d['action']! as String).name.toLowerCase()}.',
    WorldLogKind.payrollPaid => 'Gaji harian dibayar ${formatRupiah(d['amount_idr']! as int)}.',
  };
}
