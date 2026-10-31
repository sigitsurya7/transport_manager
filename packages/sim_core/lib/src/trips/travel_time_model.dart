import '../routing/route_planner.dart';
import '../vehicle/vehicle_profile.dart';

/// Menentukan lama satu leg perjalanan di jalan (detik game).
///
/// Sengaja dipisah dari routing: A* memilih rute, model ini menentukan
/// berapa lama rute itu ditempuh. Model yang lebih realistis (kemacetan
/// per jam, kondisi kendaraan, muatan, kelelahan sopir) cukup
/// mengimplementasikan interface ini tanpa mengubah alur trip.
abstract interface class TravelTimeModel {
  int legSeconds(Route route, VehicleProfile vehicle);
}

/// Model sementara: memakai estimasi waktu tempuh A* apa adanya
/// (batas kecepatan jalan & kendaraan, tanpa kemacetan).
class RouteEstimateTravelTime implements TravelTimeModel {
  const RouteEstimateTravelTime();

  @override
  int legSeconds(Route route, VehicleProfile vehicle) => route.durationS.ceil();
}
