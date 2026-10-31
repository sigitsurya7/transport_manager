import 'employee_config.dart';

/// Sopir: skill (naik dengan pengalaman), gaji tetap sejak direkrut, dan
/// kelelahan yang bertambah saat mengemudi & pulih saat istirahat di depot.
class Driver {
  Driver({
    required this.id,
    required this.name,
    required this.depotId,
    required this.skill,
    required this.dailyWageIdr,
    this.drivingSeconds = 0,
    this.fatigue = 0,
    this.restingSince = 0,
    this.tripId,
  });

  final int id;
  final String name;
  final int depotId;

  /// 0..1. Mengurangi pemborosan BBM & keausan; kelak faktor risiko.
  double skill;

  final int dailyWageIdr;

  /// Total detik game mengemudi sepanjang karier.
  int drivingSeconds;

  /// Kelelahan (1,0 = batas jam mengemudi). Saat tidak bertugas, ini nilai
  /// pada [restingSince] dan berkurang linear selama istirahat.
  double fatigue;

  /// Detik game sejak sopir beristirahat di depot.
  int restingSince;

  int? tripId;

  bool get isAvailable => tripId == null;

  /// Kelelahan pada detik [now].
  double fatigueAt(int now, DriverRules rules) {
    if (tripId != null) return fatigue;
    final f = fatigue - rules.recoveryFor(now - restingSince);
    return f < 0 ? 0 : f;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'depot': depotId,
        'skill': skill,
        'wage_idr': dailyWageIdr,
        'driving_s': drivingSeconds,
        'fatigue': fatigue,
        'resting_since': restingSince,
        'trip': tripId,
      };

  /// Save sebelum Tahap 4.2 belum punya skill, gaji, dan kelelahan.
  factory Driver.fromJson(Map<String, dynamic> j, EmployeeConfig cfg) {
    final skill = (j['skill'] as num?)?.toDouble() ?? cfg.driver.defaultSkill;
    return Driver(
      id: j['id'] as int,
      name: j['name'] as String,
      depotId: j['depot'] as int,
      skill: skill,
      dailyWageIdr: j['wage_idr'] as int? ?? cfg.driver.wageIdr(cfg.dailyWageIdr[EmployeeRole.driver]!, skill),
      drivingSeconds: j['driving_s'] as int,
      fatigue: (j['fatigue'] as num?)?.toDouble() ?? 0,
      restingSince: j['resting_since'] as int? ?? 0,
      tripId: j['trip'] as int?,
    );
  }
}

/// Calon sopir yang bisa direkrut hari ini.
class DriverCandidate {
  const DriverCandidate({required this.name, required this.skill, required this.dailyWageIdr});

  final String name;
  final double skill;
  final int dailyWageIdr;
}
