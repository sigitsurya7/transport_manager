import 'dart:math' as math;

import '../finance/economy_config.dart';
import 'maintenance.dart';
import 'vehicle.dart';

/// Nilai pasar kendaraan dari umur, odometer, dan kondisi.
///
/// nilai = harga baru × faktor umur × faktor odometer × faktor kondisi,
/// tidak pernah di bawah `floor_pct` harga baru.
int estimateMarketValueIdr({
  required VehicleModel model,
  required int ageYears,
  required int odometerM,
  required double averageCondition,
  required VehicleMarketConfig cfg,
}) {
  final age = math.max(0, ageYears);
  final ageFactor = age == 0
      ? 1.0
      : (1 - cfg.firstYearDropPct / 100) * math.pow(1 - cfg.depreciationPerYearPct / 100, age - 1);
  final odoFactor = math.max(0.3, 1 - odometerM / 1000 / cfg.odometerLifeKm);
  final w = cfg.conditionWeightPct / 100;
  final conditionFactor = (1 - w) + w * averageCondition.clamp(0.0, 1.0);
  final value = model.priceIdr * ageFactor * odoFactor * conditionFactor;
  final floor = model.priceIdr * cfg.floorPct / 100;
  return math.max(value, floor).round();
}

/// Penawaran kendaraan bekas di dealer (deterministik per hari).
class UsedListing {
  const UsedListing({
    required this.key,
    required this.model,
    required this.builtYear,
    required this.odometerM,
    required this.condition,
    required this.priceIdr,
  });

  /// `hari:indeks`; penawaran yang sudah dibeli tidak muncul lagi.
  final String key;
  final VehicleModel model;
  final int builtYear;
  final int odometerM;
  final Map<VehicleComponent, double> condition;
  final int priceIdr;

  double get averageCondition => condition.values.reduce((a, b) => a + b) / condition.length;
}
