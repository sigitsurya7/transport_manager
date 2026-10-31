/// Simulation core Transport Manager.
///
/// Satu-satunya sumber kebenaran simulasi. Tidak bergantung pada Flutter,
/// rendering, maupun database.
library;

export 'src/contracts/contract.dart';
export 'src/contracts/contract_tiers.dart';
export 'src/depot/depot.dart';
export 'src/depot/facilities.dart';
export 'src/employees/driver.dart';
export 'src/employees/employee_config.dart';
export 'src/engine/deterministic_rng.dart';
export 'src/engine/event_queue.dart';
export 'src/engine/offline_time_validator.dart';
export 'src/engine/sim_clock.dart';
export 'src/engine/speed_entitlement.dart';
export 'src/engine/time_config.dart';
export 'src/finance/economy_config.dart';
export 'src/finance/ledger.dart';
export 'src/routing/geo.dart';
export 'src/routing/polyline.dart';
export 'src/routing/road_graph.dart';
export 'src/routing/route_planner.dart';
export 'src/routing/toll_tariff.dart';
export 'src/trips/depot_ops_config.dart';
export 'src/trips/dispatch.dart';
export 'src/trips/route_track.dart';
export 'src/trips/travel_time_model.dart';
export 'src/trips/trip.dart';
export 'src/vehicle/maintenance.dart';
export 'src/vehicle/vehicle.dart';
export 'src/vehicle/vehicle_class.dart';
export 'src/vehicle/vehicle_profile.dart';
export 'src/world/game_content.dart';
export 'src/world/sim_world.dart';
export 'src/world/world_log.dart';
