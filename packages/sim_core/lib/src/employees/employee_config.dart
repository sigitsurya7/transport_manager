/// Peran karyawan Tahap 3 (`content/employees.json`).
enum EmployeeRole {
  driver('driver'),
  warehouseStaff('warehouse_staff');

  const EmployeeRole(this.id);

  final String id;
}

class EmployeeConfig {
  const EmployeeConfig({
    required this.dailyWageIdr,
    required this.roleNames,
    required this.loadingStaffBonus,
    required this.loadingStaffMaxEffective,
    required this.loadingWithoutStaff,
    required this.names,
  });

  factory EmployeeConfig.fromJson(Map<String, dynamic> j) {
    final roles = {
      for (final r in (j['roles'] as List).cast<Map<String, dynamic>>()) r['id'] as String: r,
    };
    Map<String, dynamic> role(EmployeeRole r) =>
        roles[r.id] ?? (throw FormatException('Peran ${r.id} tidak didefinisikan'));
    final names = (j['names'] as List).cast<String>();
    if (names.isEmpty) throw const FormatException('Daftar nama karyawan kosong');
    return EmployeeConfig(
      dailyWageIdr: {for (final r in EmployeeRole.values) r: (role(r)['daily_wage_idr'] as num).toInt()},
      roleNames: {for (final r in EmployeeRole.values) r: role(r)['name'] as String},
      loadingStaffBonus: (j['loading_staff_bonus'] as num).toDouble(),
      loadingStaffMaxEffective: (j['loading_staff_max_effective'] as num).toInt(),
      loadingWithoutStaff: (j['loading_without_staff'] as num).toDouble(),
      names: names,
    );
  }

  final Map<EmployeeRole, int> dailyWageIdr;
  final Map<EmployeeRole, String> roleNames;
  final double loadingStaffBonus;
  final int loadingStaffMaxEffective;
  final double loadingWithoutStaff;
  final List<String> names;

  /// Pengali kecepatan bongkar muat di depot dari jumlah staf gudang:
  /// tanpa staf (sopir memuat sendiri) lebih lambat; tiap staf menambah
  /// kecepatan sampai batas efektif.
  double loadingFactor(int staff) {
    if (staff <= 0) return loadingWithoutStaff;
    final effective = staff > loadingStaffMaxEffective ? loadingStaffMaxEffective : staff;
    return 1 + loadingStaffBonus * (effective - 1);
  }
}
