/// Peran karyawan (`content/employees.json`).
enum EmployeeRole {
  driver('driver'),
  warehouseStaff('warehouse_staff'),
  mechanic('mechanic');

  const EmployeeRole(this.id);

  final String id;
}

/// Aturan sopir: skill, gaji, efek ke BBM & keausan, kelelahan.
class DriverRules {
  const DriverRules({
    required this.defaultSkill,
    required this.hireSkillMin,
    required this.hireSkillMax,
    required this.candidates,
    required this.skillGainPerHour,
    required this.wagePerSkill,
    required this.fuelPenaltyUnskilled,
    required this.wearPenaltyUnskilled,
    required this.maxDrivingHours,
    required this.fullRestHours,
    required this.tiredAt,
  });

  factory DriverRules.fromJson(Map<String, dynamic> j) {
    double d(String k) => (j[k] as num).toDouble();
    final rules = DriverRules(
      defaultSkill: d('default_skill'),
      hireSkillMin: d('hire_skill_min'),
      hireSkillMax: d('hire_skill_max'),
      candidates: (j['candidates'] as num).toInt(),
      skillGainPerHour: d('skill_gain_per_hour'),
      wagePerSkill: d('wage_per_skill'),
      fuelPenaltyUnskilled: d('fuel_penalty_unskilled'),
      wearPenaltyUnskilled: d('wear_penalty_unskilled'),
      maxDrivingHours: d('max_driving_hours'),
      fullRestHours: d('full_rest_hours'),
      tiredAt: d('tired_at'),
    );
    if (rules.hireSkillMin > rules.hireSkillMax || rules.candidates < 1 || rules.maxDrivingHours <= 0) {
      throw const FormatException('Aturan sopir tidak valid');
    }
    return rules;
  }

  final double defaultSkill;
  final double hireSkillMin;
  final double hireSkillMax;

  /// Jumlah calon sopir yang ditawarkan per hari.
  final int candidates;
  final double skillGainPerHour;
  final double wagePerSkill;
  final double fuelPenaltyUnskilled;
  final double wearPenaltyUnskilled;

  /// Jam mengemudi sampai kelelahan penuh (1,0) → wajib istirahat.
  final double maxDrivingHours;

  /// Lama istirahat di depot untuk pulih dari kelelahan penuh.
  final double fullRestHours;

  /// Ambang "lelah" (peringatan; faktor risiko kecelakaan).
  final double tiredAt;

  int wageIdr(int baseDailyWageIdr, double skill) => (baseDailyWageIdr * (1 + wagePerSkill * skill)).round();
  double fuelFactor(double skill) => 1 + fuelPenaltyUnskilled * (1 - skill);
  double wearFactor(double skill) => 1 + wearPenaltyUnskilled * (1 - skill);

  /// Tambahan kelelahan untuk [drivingS] detik mengemudi.
  double fatigueFor(int drivingS) => drivingS / (maxDrivingHours * 3600);

  /// Pemulihan kelelahan selama [restS] detik istirahat.
  double recoveryFor(int restS) => restS / (fullRestHours * 3600);
}

class EmployeeConfig {
  const EmployeeConfig({
    required this.dailyWageIdr,
    required this.roleNames,
    required this.loadingStaffBonus,
    required this.loadingStaffMaxEffective,
    required this.loadingWithoutStaff,
    required this.driver,
    required this.withoutMechanic,
    required this.mechanicBonus,
    required this.mechanicsPerBay,
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
    final mechanic = j['mechanic'] as Map<String, dynamic>;
    return EmployeeConfig(
      dailyWageIdr: {for (final r in EmployeeRole.values) r: (role(r)['daily_wage_idr'] as num).toInt()},
      roleNames: {for (final r in EmployeeRole.values) r: role(r)['name'] as String},
      loadingStaffBonus: (j['loading_staff_bonus'] as num).toDouble(),
      loadingStaffMaxEffective: (j['loading_staff_max_effective'] as num).toInt(),
      loadingWithoutStaff: (j['loading_without_staff'] as num).toDouble(),
      driver: DriverRules.fromJson(j['driver'] as Map<String, dynamic>),
      withoutMechanic: (mechanic['without_mechanic'] as num).toDouble(),
      mechanicBonus: (mechanic['bonus_per_mechanic'] as num).toDouble(),
      mechanicsPerBay: (mechanic['max_effective_per_bay'] as num).toInt(),
      names: names,
    );
  }

  /// Upah dasar harian per peran (sopir: pada skill 0).
  final Map<EmployeeRole, int> dailyWageIdr;
  final Map<EmployeeRole, String> roleNames;
  final double loadingStaffBonus;
  final int loadingStaffMaxEffective;
  final double loadingWithoutStaff;
  final DriverRules driver;
  final double withoutMechanic;
  final double mechanicBonus;
  final int mechanicsPerBay;
  final List<String> names;

  /// Pengali kecepatan bongkar muat di depot dari jumlah staf gudang:
  /// tanpa staf (sopir memuat sendiri) lebih lambat; tiap staf menambah
  /// kecepatan sampai batas efektif.
  double loadingFactor(int staff) {
    if (staff <= 0) return loadingWithoutStaff;
    final effective = staff > loadingStaffMaxEffective ? loadingStaffMaxEffective : staff;
    return 1 + loadingStaffBonus * (effective - 1);
  }

  /// Pengali kecepatan servis di bengkel sendiri dari jumlah mekanik
  /// (efektif sampai [mechanicsPerBay] per bay).
  double mechanicFactor(int mechanics, int bays) {
    if (mechanics <= 0) return withoutMechanic;
    final cap = bays * mechanicsPerBay;
    final effective = mechanics > cap ? cap : mechanics;
    return 1 + mechanicBonus * (effective - 1);
  }
}
