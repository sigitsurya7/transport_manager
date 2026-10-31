# Progress

Catatan kemajuan pengembangan Transport Manager. Spesifikasi lengkap: [`MANUAL_INSTRUCTION.md`](MANUAL_INSTRUCTION.md).

## Status saat ini

**Tahap 2b — core prototype dapat dimainkan dan sudah diuji di HP.** Tahap 2a selesai: flutter_scene dipilih. Tahap 1 selesai dan disetujui.

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

### 2026-10-31 — Tahap 2a (verifikasi compile di komputer dev)

- [x] `sim_core`: `dart analyze` bersih, **36 test lulus** (Dart 3.12).
- [x] Flutter **3.47.9** dipasang via FVM (pin `.fvmrc` dinaikkan dari 3.47.1; Flutter global 3.44.8 tidak diubah). CI ikut 3.47.9.
- [x] `spike_common`: analyze bersih (1 import berlebih dihapus), 3 test lulus.
- [x] `depot_flutter_scene`: analyze tanpa error.
- [x] `depot_thermion`: adapter ditulis ulang ke API Thermion 0.5.0 (`loadGltf`, `ThermionAsset.setTransform`, `getActiveCamera().lookAt`); analyze tanpa error.

Kendala di komputer dev: Python 3 belum terpasang (pipeline peta & pembuat GLB), lisensi Android SDK belum diterima, tidak ada HP terhubung.

### 2026-10-31 — Tahap 2a (spike di HP)

- [x] Test Python lulus semua (pipeline 13, GLB 3); perbaikan test SQLite yang gagal di Windows.
- [x] **flutter_scene di REDMI Note 15 (Helio G99, 8 GB, layar 120 Hz)**: load 228 ms; 1 / 10 / 30 kendaraan = 71–89 / 71–88 / 60–76 fps, jank ≈ 0 %; APK arm64 19,0 MB. **Lolos kriteria dengan margin besar.** Rincian di `spikes/README.md`.
- [x] Benchmark otomatis tanpa sentuh layar (`--dart-define=AUTO_BENCH=true`, hasil di `adb logcat`).
- [x] `setup.sh` spike: tidak lagi menimpa `lib/main.dart` bila proyek Android sudah ada; file bawaan `flutter create` dibersihkan.
- [ ] **Thermion**: build gagal karena binary Filament diunduh dari `*.r2.dev`, dan domain itu diblokir DNS ISP. Butuh VPN/DNS lain, atau putuskan flutter_scene tanpa pembanding.
- [x] `fetch_overpass.sh` + `merge_osm.py` (unduh jalan per ubin + retry, lalu gabung) sebagai alternatif ekstrak Jawa ±900 MB.
- [~] **Benchmark routing data nyata ditunda atas permintaan user** (koneksi ±40 KB/s). Unduhan Geofabrik dijeda di 264/899 MB (lanjutkan dengan `curl -C -`); 4 dari 9 ubin koridor Jakarta–Bandung tersimpan di `raw/tiles`. Logika estimasi waktu tempuh akan ditinjau bersama user.

### 2026-10-31 — Tahap 2b (bagian 1): siklus pengiriman di sim_core

Bagian yang tidak bergantung engine 3D, dikerjakan lebih dulu:

- [x] Konten data-driven baru: `vehicle_models.json`, `cargo_types.json`, `customers.json`, `economy.json`, `depot_ops.json` (dimuat lewat `GameContent`).
- [x] Model domain: `Depot` (slot parkir), `Vehicle` + `VehicleModel` (odometer tidak pernah reset), `Driver`, `Contract` + `CargoType`, `Ledger` (kas = jumlah entri), `Trip` + `TripLeg`.
- [x] `SimWorld`: game baru (1 depot 3 slot, 1 pikap box di slot 0, 1 sopir, modal awal), tawaran kontrak toko ke toko deterministik dari seed, **cek dispatch** (kendaraan/sopir sibuk, tier kelas kendaraan, kapasitas, rute), **estimasi tol vs non-tol sebelum menerima** (ETA, tenggat, pendapatan setelah penalti, BBM, tol, untung).
- [x] Siklus trip lewat event queue: slot → dock → muat → gerbang → jalan berangkat → bongkar → jalan pulang → gerbang masuk → slot → inspeksi. Pembayaran, BBM, tol dicatat di ledger; log kejadian untuk ringkasan.
- [x] **Waktu tempuh pluggable** (`TravelTimeModel`); default sementara = estimasi A*. Siap diganti logika dari user tanpa mengubah alur trip.
- [x] Posisi kendaraan untuk renderer = `f(rute, waktu)` mengikuti geometri jalan nyata (`RouteTrack`), tanpa update per frame.
- [x] Save/load seluruh state + antrean event ke JSON.
- [x] 15 test baru (total **51 lulus**): hasil akhir persis sama dengan estimasi, semua fase dilewati berurutan, posisi depot → tujuan, aturan dispatch, tol lebih cepat tetapi berbayar, penalti telat, satu lompatan panjang == banyak langkah pendek, save di tengah jalan → load → hasil akhir identik.

### 2026-10-31 — Tahap 2b (bagian 2): save slot & aplikasi

- [x] **Keputusan**: flutter_scene final; visual low-poly bergaya yang ringan (lihat keputusan #9–13 di dokumen arsitektur).
- [x] `packages/persistence`: `SaveStore` (satu file SQLite per slot, tulis atomik, daftar/hapus slot, backup maks 3, migrasi berversi, tolak save dari versi lebih baru). 7 test lulus.
- [x] `app/` (Flutter 3.47.9, Riverpod):
  - Menu utama: permainan baru, lanjutkan (daftar save), hapus save.
  - Permainan baru: negara → wilayah → kota → lokasi depot → nama perusahaan. Wilayah/kota tanpa paket peta tampil terkunci.
  - **Depot 3D** (flutter_scene): matahari + bayangan; kendaraan bergerak sesuai fase trip (slot → dock → mundur keluar → gerbang; masuk → mundur ke slot); pekerja bongkar muat saat loading; kamera orbit/zoom.
  - **Peta**: jalan nyata dari map pack (vektor, LOD per kelas jalan), rute pergi/pulang, depot, tujuan, kendaraan bergerak mengikuti geometri jalan; mode ikuti kendaraan.
  - **Kontrak**: 3 tawaran, lembar dispatch dengan perbandingan tol vs non-tol (ETA, tenggat, BBM, tol, untung), status trip berjalan.
  - **Keuangan**: kas, pendapatan/biaya, buku besar.
  - Jam game berjalan (1 menit nyata = 10 menit game), **autosave** (setiap kejadian, tiap 60 detik nyata, saat app ke background, saat keluar), **catch-up offline** dengan jam monotonic Android (anti-manipulasi jam) + ringkasan "Selama kamu pergi".
  - 12 test app (format, jalur depot, integrasi: game baru Bandung → pengiriman penuh → save → load). Bug ditemukan & diperbaiki: save yang tumpang tindih bisa membuang state terbaru.
- [x] Model 3D baru: depot 2.952 segitiga (gudang beratap pelana, pos jaga, palang gerbang, jalan umum bermarka, pohon, lampu, rumah tetangga), pikap 468, pekerja 184; total aset ±250 KB. Test winding per segitiga & anggaran segitiga.
- [x] APK release arm64: **23,6 MB**.
- [x] **Diuji di HP (REDMI Note 15)**: game baru Bandung, depot 3D, kontrak, dispatch, pikap keluar slot → jalur → dock → gerbang, catch-up offline ("keluar dari gerbang" tercatat saat app ditutup), peta dengan kendaraan mengikuti jalan nyata & mode ikuti, lanjutkan dari save.
- [x] Perbaikan dari uji di HP: sumbu Z GLB terbalik di flutter_scene (posisi node & kamera dikonversi), arah hadap kendaraan, kamera awal kini memperlihatkan loading dock, ringkasan offline tidak muncul untuk jeda singkat tanpa kejadian.
- [ ] Map pack baru Bandung (dari ubin Overpass, jalan utama). Kota lain menunggu ekstrak Jawa (unduhan dilanjutkan di latar belakang).

## Berikutnya

- [ ] Uji satu siklus penuh sampai kembali & parkir; ukur fps di layar depot & peta pada game sungguhan.
- [ ] Bangun map pack 6 kota dari ekstrak Jawa (termasuk jalan residential) & verifikasi koordinat depot.
- [ ] Setelah itu: **Tahap 3 — depot simulation** (antrean gerbang/dock, pekerja, upgrade fasilitas + visual).
