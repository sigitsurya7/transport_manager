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

Benchmark otomatis tanpa sentuh layar: build dengan `--dart-define=AUTO_BENCH=true`. App menjalankan 1 → 10 → 30 kendaraan (pemanasan 5 detik + ukur 30 detik) dan mencetak baris `BENCH` yang bisa dibaca lewat `adb logcat -s flutter:I`.

Kriteria lolos: **≥ 30 fps rata-rata dan jank < 5 % pada 10 kendaraan** di HP kelas menengah.

| Engine | HP | Load (ms) | 1 kend. fps | 10 kend. fps | 30 kend. fps | p90 @10 (ms) | APK (MB) |
|---|---|---|---|---|---|---|---|
| flutter_scene | REDMI Note 15 — 2510DRA23E (Helio G99 / MT6789, RAM 8 GB, layar 120 Hz, Android 16) | 228 | 71–89 | 71–88 | 60–76 | 15–24 | 19,0 |
| Thermion | — | belum: build gagal, unduhan binary Filament dari `*.r2.dev` diblokir DNS ISP | | | | | |

## Status verifikasi

Diverifikasi 2026-10-31 dengan Flutter **3.47.9** (FVM) di komputer dev Windows:

- `spike_common`: `flutter analyze` bersih, 3 test lulus.
- `depot_flutter_scene` (flutter_scene 0.24.x): `flutter analyze` tanpa error; API sesuai dokumentasi.
- `depot_thermion` (thermion 0.5.0): adapter ditulis ulang ke API 0.5.0 — `loadGltf('asset://…')`, `ThermionAsset.setTransform(Matrix4)`, `getActiveCamera().lookAt(...)`. `flutter analyze` tanpa error.
- Satu-satunya warning: folder `assets/` belum ada — dibuat oleh `setup.sh` (butuh Python 3).

### Hasil HP 2026-10-31 (flutter_scene)

Dua run berturut-turut. Run 1 dalam kondisi HP dingin, run 2 setelah HP hangat (thermal status 2, CPU/GPU ±55 °C):

| Run | Kendaraan | avg fps | p90 (ms) | p99 (ms) | jank % |
|---|---|---|---|---|---|
| 1 | 1 | 89,2 | 21,8 | 27,8 | 0,2 |
| 1 | 10 | 88,1 | 15,3 | 20,2 | 0,0 |
| 1 | 30 | 75,5 | 21,4 | 22,7 | 0,0 |
| 2 | 1 | 71,3 | 27,9 | 30,1 | 0,1 |
| 2 | 10 | 70,7 | 24,2 | 28,6 | 0,0 |
| 2 | 30 | 60,3 | 25,4 | 29,4 | 0,1 |

p90/p99 adalah `FrameTiming.totalSpan` (build + raster, termasuk antrean pipeline), bukan jarak antar-frame. **flutter_scene lolos kriteria dengan margin besar**: lebih dari 2× target 30 fps pada 10 kendaraan, dan jank ≈ 0 % bahkan pada 30 kendaraan.

Thermion: build hook `thermion_dart` mengunduh `filament-v1.69.1-android-release.zip` dari `pub-c8b6…r2.dev`, tetapi DNS ISP mengarahkan domain itu ke IP blokir sehingga build gagal.
