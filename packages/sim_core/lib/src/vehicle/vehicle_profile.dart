import 'vehicle_class.dart';

/// Karakteristik kendaraan yang memengaruhi routing.
class VehicleProfile {
  const VehicleProfile({
    required this.vehicleClass,
    required this.maxSpeedKmh,
    required this.grossWeightT,
    required this.tollGolongan,
    this.speedFactor = 1.0,
  }) : assert(speedFactor > 0 && speedFactor <= 1);

  final VehicleClass vehicleClass;

  /// Kecepatan operasional maksimum kendaraan.
  final int maxSpeedKmh;

  /// Berat total (kendaraan + muatan) dalam ton, untuk batas `maxweight`.
  final double grossWeightT;

  /// Golongan tarif tol (1–5).
  final int tollGolongan;

  /// Pengali kecepatan aktual terhadap batas jalan (≤ 1), misalnya untuk
  /// truk bermuatan penuh atau kendaraan dengan kondisi mesin buruk.
  final double speedFactor;

  VehicleProfile copyWith({double? grossWeightT, double? speedFactor}) => VehicleProfile(
        vehicleClass: vehicleClass,
        maxSpeedKmh: maxSpeedKmh,
        grossWeightT: grossWeightT ?? this.grossWeightT,
        tollGolongan: tollGolongan,
        speedFactor: speedFactor ?? this.speedFactor,
      );
}
