/// Jenis kejadian yang dicatat untuk riwayat & ringkasan "selama Anda pergi".
enum WorldLogKind {
  contractOffered,
  dispatched,
  departedDepot,
  delivered,
  returnedToDepot,
  tripCompleted,
  upgradeStarted,
  upgradeFinished,
  vehiclePurchased,
  employeeHired,
  employeeReleased,
  payrollPaid,
}

/// Satu baris log. Teks untuk pemain disusun UI dari [kind] + [data]
/// (simulasi tidak menyimpan kalimat jadi).
class WorldLogEntry {
  const WorldLogEntry(this.time, this.kind, this.data);

  final int time;
  final WorldLogKind kind;
  final Map<String, Object?> data;

  Map<String, dynamic> toJson() => {'t': time, 'kind': kind.name, 'data': data};

  factory WorldLogEntry.fromJson(Map<String, dynamic> j) => WorldLogEntry(
        j['t'] as int,
        WorldLogKind.values.byName(j['kind'] as String),
        Map<String, Object?>.from(j['data'] as Map),
      );
}
