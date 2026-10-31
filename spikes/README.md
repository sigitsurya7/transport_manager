# Spike 3D — Tahap 2a

Dua aplikasi Android menjalankan **skenario depot yang sama persis** agar perbandingannya adil:

| Folder | Engine | Status |
|---|---|---|
| `depot_flutter_scene/` | flutter_scene 0.24.x (Flutter GPU / Impeller) | **Primer** |
| `depot_thermion/` | thermion_flutter 0.5.x (Filament) | Cadangan |
| `spike_common/` | jalur kendaraan & pekerja, kamera orbit, statistik frame, HUD | Bersama |

Aset (`depot.glb`, `pickup.glb`, `worker.glb`) dibuat oleh `tools/depot_glb/make_depot_glb.py`: depot awal 40×30 m dengan 3 slot parkir, gerbang, loading area, gudang, kantor; 6 pekerja; 1–30 pikap yang berputar gerbang → dock → slot → gerbang.

## Menjalankan

Butuh Flutter **3.47.x stable** (dipin di `.fvmrc`) dan HP Android arm64.

```bash
cd spikes/depot_flutter_scene && ./setup.sh && flutter run --release
cd spikes/depot_thermion      && ./setup.sh && flutter run --release
```

## Prosedur benchmark

Di setiap engine, pada HP yang sama (sebaiknya kelas menengah, RAM 4 GB):

1. Catat **Load** (ms) di HUD saat pertama terbuka.
2. Set kendaraan ke **1**, tekan **Benchmark 30 detik**. Ulangi untuk **10** dan **30** kendaraan.
3. Hasil juga tercetak di log (`flutter logs`, baris `BENCH`) dalam format CSV.
4. Catat ukuran APK: `flutter build apk --release --target-platform android-arm64` lalu lihat `build/app/outputs/flutter-apk/app-release.apk`.
5. Isi tabel di bawah dan commit.

Kriteria lolos: **≥ 30 fps rata-rata dan jank < 5 % pada 10 kendaraan** di HP kelas menengah.

| Engine | HP | Load (ms) | 1 kend. fps | 10 kend. fps | 30 kend. fps | p90 @10 (ms) | APK (MB) |
|---|---|---|---|---|---|---|---|
| flutter_scene | | | | | | | |
| Thermion | | | | | | | |

## Status verifikasi

Diverifikasi 2026-10-31 dengan Flutter **3.47.9** (FVM) di komputer dev Windows:

- `spike_common`: `flutter analyze` bersih, 3 test lulus.
- `depot_flutter_scene` (flutter_scene 0.24.x): `flutter analyze` tanpa error; API sesuai dokumentasi.
- `depot_thermion` (thermion 0.5.0): adapter ditulis ulang ke API 0.5.0 — `loadGltf('asset://…')`, `ThermionAsset.setTransform(Matrix4)`, `getActiveCamera().lookAt(...)`. `flutter analyze` tanpa error.
- Satu-satunya warning: folder `assets/` belum ada — dibuat oleh `setup.sh` (butuh Python 3).

Belum: build APK dan pengukuran fps di HP (tabel di atas).
