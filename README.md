# Transport Manager

Game simulasi perusahaan transportasi & logistik offline berbasis Flutter: depot 3D, jaringan jalan nyata (OpenStreetMap), dan simulasi bisnis.

- Spesifikasi: [MANUAL_INSTRUCTION.md](MANUAL_INSTRUCTION.md)
- Arsitektur (Tahap 1): [docs/TAHAP_1_ARSITEKTUR.md](docs/TAHAP_1_ARSITEKTUR.md)
- Progres: [progress.md](progress.md)
- Log instruksi user: [docs/INSTRUKSI_USER.md](docs/INSTRUKSI_USER.md)

## Struktur

| Folder | Isi |
|---|---|
| `app/` | Aplikasi Flutter (UI, depot 3D flutter_scene, peta) |
| `packages/sim_core/` | Simulation core, Dart murni (satu-satunya sumber kebenaran) |
| `packages/persistence/` | Save slot SQLite |
| `content/` | Katalog data-driven (kendaraan, barang, ekonomi, …) |
| `tools/map_pipeline/` | OSM → graph jalan (map pack) |
| `tools/depot_glb/` | Generator model 3D low-poly |

## Menjalankan app

Butuh Flutter 3.47.x (dipin di `.fvmrc`) dan Python 3.

```bash
bash tools/sync_app_assets.sh        # salin konten, model 3D, map pack ke app/assets
cd app && flutter run --release
```

Kota hanya bisa dipilih bila map pack-nya ada (`tools/map_pipeline/out/<kota>/graph.json`, lihat `tools/map_pipeline/README.md`).
