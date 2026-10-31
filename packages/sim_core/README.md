# sim_core

Simulation core Transport Manager. Dart murni, tanpa Flutter, dan menjadi satu-satunya sumber kebenaran simulasi.

| Modul | Isi |
|---|---|
| `engine/` | `SimClock` (1 menit nyata = 10 menit game, catch-up offline maks 48 jam), `OfflineTimeValidator` (monotonic clock + boot id), `EventQueue` (discrete-event, deterministik), `DeterministicRng` (SplitMix64), `SpeedEntitlementProvider` (pengali 2×–10× disiapkan, default 1×) |
| `routing/` | `RoadGraph` (dari `graph.json` pipeline), `RoutePlanner` A* berbasis waktu dengan mode **tol / non-tol**, batas berat jalan, `TollTariff` per golongan |
| `vehicle/` | `VehicleClass`, `VehicleProfile` |
| `contracts/` | `ContractTierRules`: toko ke toko (pikap), kawasan (pikap box), antarkota (min. mini truck) dari `content/contract_tiers.json` |

```bash
dart pub get
dart test
dart run bin/route_bench.dart ../../tools/map_pipeline/out/jakarta-bandung/graph.json \
  --cities ../../tools/map_pipeline/data/id-jawa.cities.json
```
