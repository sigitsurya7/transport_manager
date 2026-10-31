/// Simulation core Transport Manager.
///
/// Satu-satunya sumber kebenaran simulasi. Tidak bergantung pada Flutter,
/// rendering, maupun database.
library;

export 'src/contracts/contract_tiers.dart';
export 'src/engine/deterministic_rng.dart';
export 'src/engine/event_queue.dart';
export 'src/engine/offline_time_validator.dart';
export 'src/engine/sim_clock.dart';
export 'src/engine/speed_entitlement.dart';
export 'src/engine/time_config.dart';
export 'src/routing/geo.dart';
export 'src/routing/polyline.dart';
export 'src/routing/road_graph.dart';
export 'src/routing/route_planner.dart';
export 'src/routing/toll_tariff.dart';
export 'src/vehicle/vehicle_class.dart';
export 'src/vehicle/vehicle_profile.dart';
