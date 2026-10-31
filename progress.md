# Progress

Catatan kemajuan pengembangan Transport Manager. Spesifikasi lengkap: [`MANUAL_INSTRUCTION.md`](MANUAL_INSTRUCTION.md).

## Status saat ini

**Tahap 2a — kode spike selesai, menunggu pengukuran di HP Android.** Tahap 1 selesai dan disetujui.

## Log

### 2026-10-31 — Keputusan Tahap 1 disetujui

- [x] Engine 3D: **flutter_scene** (terbaru, Flutter GPU/Impeller, instancing + LOD bawaan) dengan Flutter 3.47.x stable dipin via FVM; **Thermion** (Filament, Flutter stable) sebagai fallback.
- [x] Kota awal dipilih pemain dari 6 ibu kota provinsi Jawa: Jakarta, Serang, Bandung, Semarang, Yogyakarta, Surabaya (satu map pack `id-jawa`).
- [x] Skala waktu: **1 menit nyata = 10 menit game** (`timeScale = 10`, configurable). Jakarta → Bandung via tol ±2 jam = ±12 menit nyata. *(dikoreksi 10:57)*
- [x] Catch-up offline maksimal 48 jam nyata.
- [x] Monorepo (`app/`, `packages/`, `tools/`) dan Riverpod.
- [x] `docs/TAHAP_1_ARSITEKTUR.md` diperbarui sesuai keputusan, termasuk tabel dampak skala waktu.

- [x] Rute: pemain memilih **tol atau non-tol** per dispatch (dua kandidat rute: jarak, waktu, biaya tol, BBM, risiko).
- [x] Jangkauan pengiriman: toko ke toko hanya dalam kota (pikap); antarkota minimal **mini truck**; kontrak bisa dari dalam kota sampai keluar kota.
- [x] Percepatan waktu 2×–10×: arsitektur disiapkan (`SpeedEntitlementProvider`, default 1×), **belum diterapkan**; kelak via micro-transaction / rewarded ads.

### 2026-10-31 — Tahap 1 (draft)

- [x] Master prompt dikonversi menjadi `MANUAL_INSTRUCTION.md`.
- [x] Dokumen analisis & arsitektur `docs/TAHAP_1_ARSITEKTUR.md` (17 poin bagian 23).
- [x] `README.md` dan `.gitignore`.

### 2026-10-31 — Tahap 2a (spike teknis)

Selesai:
- [x] **Map pipeline** `tools/map_pipeline/build_roads.py`: OSM (.osm/.pbf) → `roads.sqlite` (+ R-tree) dan `graph.json`. Node hanya di persimpangan, geometri nyata sebagai polyline, oneway, tol (motorway = tol kecuali `toll=no`), maxspeed, maxweight, filter bbox. **11 test lulus.**
- [x] Skrip unduh OSM Jawa (Geofabrik), build graph spike (kota Jakarta, koridor Jakarta–Bandung, Jawa jalan utama), dan vector tiles MBTiles (Planetiler).
- [x] `data/id-jawa.cities.json`: 6 ibu kota provinsi Jawa + 2 kandidat lokasi depot per kota (koordinat perkiraan, **perlu verifikasi**).
- [x] **`packages/sim_core`** (Dart murni):
  - `SimClock`: 1 menit nyata = 10 menit game, carry pecahan detik, catch-up offline maks 48 jam, pengali kecepatan lewat `SpeedEntitlementProvider` (default hanya 1×, tidak berlaku untuk catch-up).
  - `OfflineTimeValidator`: monotonic clock + boot id; deteksi jam dimajukan/mundur.
  - `EventQueue` discrete-event deterministik `(time, priority, seq)` + snapshot/restore.
  - `DeterministicRng` SplitMix64 + `derive(saveSeed, entityId, eventSeq)`.
  - `RoutePlanner` A* berbasis waktu tempuh: mode **tol / non-tol**, batas berat jalan, biaya tol per golongan (tarif pendekatan).
  - `ContractTierRules` dari `content/contract_tiers.json`: toko ke toko (pikap), kawasan (pikap box), antarkota (min. mini truck).
  - Test: jam & validator, event queue (termasuk "1× catch-up panjang == banyak catch-up pendek"), RNG vs vektor referensi, routing di graph hasil pipeline, A* vs Dijkstra pada grid acak, tier kontrak.
  - `bin/route_bench.dart`: benchmark A* acak + rute antar ibu kota (tol vs non-tol, waktu game & nyata).
- [x] **Aset 3D** `tools/depot_glb/make_depot_glb.py`: `depot.glb` (lahan 40×30 m, 3 slot parkir, gerbang, loading area, gudang, kantor), `pickup.glb`, `worker.glb`. Validasi struktur GLB: **3 test lulus.**
- [x] **Spike 3D**: `spikes/depot_flutter_scene` dan `spikes/depot_thermion` dengan skenario identik (`spikes/spike_common`): 1–30 pikap bergerak, 6 pekerja, kamera orbit/zoom, HUD fps, tombol benchmark 30 detik (CSV di log).
- [x] **CI GitHub Actions**: `dart analyze` + `dart test` + benchmark fixture untuk sim_core, test Python, `flutter analyze` spike (non-blocking).
- [x] Dokumen arsitektur: flutter_scene kini cukup Flutter **3.47 stable** (bukan master); tabel jangkauan pengiriman disederhanakan jadi 3 tingkat.

Belum terverifikasi (keterbatasan workspace Claude: tidak ada akses pub.dev / Dart SDK / Geofabrik):
- [ ] Kode Dart `sim_core` dan spike belum pernah di-compile di sini → diverifikasi oleh CI setelah push.
- [ ] API Thermion 0.5.0 di `thermion_adapter.dart` kemungkinan perlu penyesuaian.

## Berikutnya — sisa Tahap 2a (butuh HP / komputer dev)

- [ ] Cek hasil CI; perbaiki error compile bila ada.
- [ ] Jalankan kedua spike di HP Android, isi tabel di `spikes/README.md`, putuskan engine final.
- [ ] Jalankan `fetch_java.sh` + `build_spike_packs.sh`, lalu `route_bench.dart` untuk angka routing nyata (Jakarta–Bandung tol vs non-tol).
- [ ] Verifikasi koordinat kandidat depot.
- [ ] Setelah itu: **Tahap 2b — core prototype**.
