# Tahap 1 — Technical Feasibility & Architecture

Dokumen ini adalah jawaban atas bagian 23 di [`MANUAL_INSTRUCTION.md`](../MANUAL_INSTRUCTION.md). Statusnya **draft untuk disetujui** — implementasi (Tahap 2) baru dimulai setelah keputusan di bagian [Keputusan yang Perlu Disetujui](#keputusan-yang-perlu-disetujui) dikonfirmasi.

Nama kerja proyek: **Transport Manager** (repo `transport_manager`).

---

## 1. Ringkasan Visi Game

Game simulasi manajemen perusahaan logistik, offline penuh, di atas jaringan jalan nyata (OSM). Pemain mulai dari satu pikap dan satu sopir di depot kecil 3 slot, lalu tumbuh menjadi perusahaan multi-depot dengan truk berat, trailer, dan warehouse.

Tiga pilar identitas:

1. **Depot yang hidup** — depot 3D adalah "rumah" pemain: setiap kendaraan, antrean, forklift, dan upgrade terlihat secara fisik.
2. **Peta nyata** — rute, jarak, waktu tempuh, dan batasan jalan berasal dari data OSM, bukan peta fiktif.
3. **Keputusan bisnis yang berbobot** — keuntungan ditentukan oleh pilihan kontrak, kondisi armada, tenaga kerja, dan manajemen risiko, bukan oleh level.

## 2. Analisis Gameplay Loop

**Loop mikro (menit):** lihat papan kontrak → bandingkan estimasi laba & risiko → dispatch (kendaraan + sopir + muatan) → amati kendaraan keluar depot dan bergerak di peta → terima hasil (pendapatan, keausan, kelelahan, kejadian).

**Loop meso (jam/hari game):** kelola cash flow → servis kendaraan → istirahatkan/rekrut sopir → isi stok warehouse → terima kontrak berulang → upgrade satu fasilitas.

**Loop makro (minggu game):** beli kendaraan kelas berikutnya → buka kategori barang baru (mis. cold chain) → ekspansi lahan → buka depot di kota lain → jaringan antarkota.

**Gerbang progresi** bukan level, tetapi kombinasi:

| Gerbang | Contoh |
|---|---|
| Modal | Harga light truck vs saldo kas |
| Fasilitas | Heavy rigid butuh workshop level 2 & slot parkir besar |
| Reputasi per segmen pelanggan | Kontrak manufaktur butuh reputasi tepat waktu ≥ X |
| SDM | Tractor head butuh sopir dengan lisensi/skill kendaraan berat |
| Geografi | Kontrak antarkota butuh paket peta wilayah terkait |

**Tujuan pemain:** jangka pendek (selesaikan kontrak, bayar gaji), menengah (unlock kendaraan/fasilitas berikutnya), panjang (depot kedua, jaringan antarkota, kategori barang khusus).

**Risiko desain yang diantisipasi:** kontrak menjadi "klik → uang". Mitigasi: setiap kontrak memakan kapasitas nyata (slot dock, waktu sopir, keausan, BBM, tol) dan papan kontrak menampilkan rincian biaya, bukan hanya nilai bayaran.

## 3. Analisis Kelayakan Teknis

| Aspek | Kelayakan di Flutter | Catatan |
|---|---|---|
| UI manajemen | Sangat layak | Kekuatan utama Flutter |
| Simulasi & ekonomi (Dart murni) | Sangat layak | Dapat diuji penuh dengan `dart test`, tanpa UI |
| Database lokal (Drift/SQLite) | Sangat layak | Migrasi skema matang |
| Peta 2D offline + overlay kendaraan | Layak | `flutter_map` + vector/raster tiles lokal |
| Routing lokal | Layak dengan pra-pemrosesan | Graph harus dipangkas dan diproses di luar game |
| **Depot 3D** | **Layak tetapi berisiko tertinggi** | Ekosistem 3D Flutter belum sematang Unity; wajib spike teknis |
| Simulasi offline | Sangat layak | Event-driven, tanpa background service |

Kesimpulan: game ini layak dibangun di Flutter **asalkan** renderer 3D diisolasi di balik interface, sehingga engine 3D bisa diganti tanpa menyentuh simulasi. Satu-satunya komponen yang perlu dibuktikan lewat prototipe sebelum komitmen penuh adalah depot 3D.

## 4. Rekomendasi Flutter & 3D Engine

Kandidat (semua perlu diverifikasi ulang versinya saat spike Tahap 2, karena ekosistem ini bergerak cepat):

| Opsi | Kelebihan | Kekurangan |
|---|---|---|
| **Thermion / Filament** (binding Flutter untuk Google Filament) | Renderer PBR native yang matang, glTF, instancing, berjalan di Android & iOS | Ukuran APK bertambah, API binding masih berkembang |
| **flutter_scene** (di atas Flutter GPU / Impeller) | Paling "native Flutter" | Masih eksperimental; ketersediaan Flutter GPU di channel stable perlu dicek |
| **three_js port Dart** | API familiar | Performa & pemeliharaan kurang terjamin |
| **Flame (2.5D isometrik, sprite pra-render)** | Stabil, ringan, sangat cepat di HP murah | Bukan 3D sejati, rotasi kamera terbatas (4 sudut) |
| Unity/Godot di-embed sebagai view | Engine 3D penuh | Integrasi rumit, ukuran besar, dua codebase |

**Rekomendasi:**

1. **Primer: Thermion (Filament)** untuk depot 3D dengan kamera orbit/zoom.
2. **Fallback yang sudah direncanakan: Flame isometrik 2.5D** dengan sprite yang dirender dari model 3D yang sama (4 sudut kamera).
3. Keduanya mengimplementasikan interface yang sama `DepotSceneRenderer`, yang hanya membaca `DepotSnapshot` (state hasil simulasi). Renderer **tidak pernah** menulis state.

Aset 3D: glTF/GLB low-poly, satu atlas tekstur per set fasilitas, LOD 2 tingkat, kendaraan dan pekerja di-instance.

## 5. Rekomendasi Sistem Offline Map

Pisahkan dua hal yang sering dicampur:

- **Peta visual** (apa yang dilihat): tiles.
- **Road graph** (apa yang disimulasikan): graph jalan di SQLite.

**Peta visual:** `flutter_map` dengan tile dari file lokal.

| Format | Penilaian |
|---|---|
| **MBTiles (SQLite)** | Direkomendasikan. Mudah dibaca dari Dart/SQLite, satu file per wilayah |
| PMTiles | Sangat efisien untuk HTTP range request; untuk file lokal keuntungannya kecil dan dukungan Dart lebih sedikit |
| Vector tiles (MVT) | Direkomendasikan di dalam MBTiles: ukuran kecil, styling bebas, zoom tajam |
| Raster tiles | Fallback jika renderer vector tile bermasalah di HP murah |

Rencana: MBTiles berisi vector tiles (dibuat dengan Planetiler/tilemaker dari OSM PBF), dirender via `vector_map_tiles`, dengan fallback raster.

**Struktur paket wilayah (`map pack`):**

```
packs/id-jawa/
  manifest.json      # versi, bbox, lisensi ODbL, daftar kota & depot
  tiles.mbtiles      # peta visual
  roads.sqlite       # road graph untuk routing
  places.json        # kota, lokasi depot, toko/supplier sintetis yang dipetakan ke node jalan
```

Paket dibundel di APK (untuk wilayah awal) atau diimpor dari file lokal; tidak ada unduhan saat gameplay. Atribusi OSM (ODbL) wajib ditampilkan di layar peta dan credits.

## 6. Rekomendasi Routing Engine

Routing dikerjakan **di Dart sendiri**, bukan engine eksternal (OSRM/Valhalla/GraphHopper tidak praktis dijalankan on-device dari Flutter).

**Pipeline pra-pemrosesan (di luar game, `tools/map_pipeline`, Python + pyosmium):**

1. Ekstrak jalan dari OSM PBF per wilayah.
2. Filter kelas jalan: `motorway`…`tertiary` untuk graph antarkota; `residential`/`unclassified` hanya di radius kota yang dimainkan.
3. Bangun graph: node hanya di persimpangan; geometri di antara persimpangan disimpan sebagai polyline terenkode pada edge.
4. Atribut edge: panjang, kelas jalan, `maxspeed` (atau default per kelas), tol, `oneway`, batas berat/tinggi jika ada, kemiringan jika data elevasi tersedia.
5. Simpan ke `roads.sqlite` + indeks spasial (R*Tree) untuk snapping titik ke jalan.

**Runtime:**

- **A\*** dengan heuristik jarak haversine dibagi kecepatan maksimum (admissible).
- Biaya edge = waktu tempuh untuk *profil kendaraan* (truk lebih lambat, dilarang di jalan dengan batas berat, opsi hindari tol).
- Dijalankan di **Isolate** agar UI tidak tersendat.
- Hasil rute di-cache per (asal, tujuan, profil) di DB save.
- Jika graph Jawa penuh terlalu besar untuk A* polos: tambah **Contraction Hierarchies** di pipeline (keputusan ditunda sampai benchmark Tahap 2).

Kendaraan bergerak dengan menginterpolasi posisi sepanjang polyline rute berdasarkan waktu simulasi — tidak pernah garis lurus.

## 7. Arsitektur Keseluruhan

```
┌──────────────────────────── UI (Flutter widgets) ────────────────────────────┐
│ Contract │ Fleet │ Depot view │ World map │ Warehouse │ Staff │ Finance       │
└───────▲──────────────────────────────▲───────────────────────────▲──────────┘
        │ commands                      │ read-only snapshots       │
┌───────┴──────── Application layer (use cases, Riverpod) ────────────────────┐
└───────▲──────────────────────────────▲──────────────────────────────────────┘
        │                              │
┌───────┴──────── Simulation core (Dart murni, tanpa Flutter) ────────────────┐
│ SimClock · EventQueue · Domain services · DomainEventBus · Seeded RNG        │
└───────▲──────────────────────────────▲──────────────────────────────────────┘
        │ repositories                 │ static data
┌───────┴────────── Persistence ───────┴──────────── Content ─────────────────┐
│ Drift: save slot DB                  │ JSON katalog (kendaraan, barang, ...) │
│                                      │ Map packs (MBTiles + roads.sqlite)    │
└──────────────────────────────────────┴──────────────────────────────────────┘
        Renderers (Depot 3D, Map overlay) hanya membaca snapshot.
```

Aturan inti:

- **Simulation core adalah satu-satunya sumber kebenaran.** UI mengirim *command*; renderer membaca *snapshot*.
- Simulation core adalah package Dart murni (`packages/sim_core`) agar dapat diuji cepat dan dipakai ulang (misal untuk tool balancing).
- State management: **Riverpod**.
- Semua konten (kendaraan, body, barang, fasilitas, kota) dari **JSON data-driven** yang divalidasi saat load.

## 8. Struktur Folder Proyek

```
transport_manager/
├── MANUAL_INSTRUCTION.md
├── progress.md
├── docs/
├── app/                              # Flutter app
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app/                      # routing, theme, DI
│   │   ├── features/                 # satu folder per layar
│   │   │   ├── new_game/  depot/  world_map/  contracts/
│   │   │   ├── fleet/  warehouse/  staff/  finance/  save_load/
│   │   ├── render/
│   │   │   ├── depot3d/              # DepotSceneRenderer + implementasi
│   │   │   └── map/                  # layer tiles + overlay kendaraan
│   │   └── platform/                 # monotonic clock, file import
│   ├── assets/
│   │   ├── data/                     # katalog JSON
│   │   ├── models/                   # glTF/GLB
│   │   └── packs/                    # map pack bawaan
│   └── test/  integration_test/
├── packages/
│   ├── sim_core/                     # Dart murni
│   │   ├── lib/src/
│   │   │   ├── engine/               # clock, event queue, rng, bus
│   │   │   ├── world/  map/  routing/
│   │   │   ├── vehicle/  cargo/  contracts/  employees/
│   │   │   ├── depot/  warehouse/  workshop/
│   │   │   ├── finance/  insurance/  accidents/
│   │   │   └── progression/
│   │   └── test/
│   ├── persistence/                  # Drift schema, migrasi, repository impl
│   └── content/                      # loader & validator katalog JSON
└── tools/
    ├── map_pipeline/                 # OSM PBF → MBTiles + roads.sqlite
    └── balancing/                    # simulasi headless untuk tuning ekonomi
```

Setiap domain di `sim_core` berisi `model/`, `service/`, `repository.dart` (interface) dan `rules/`.

## 9. Desain Database

Tiga jenis basis data, dipisah agar save tidak membengkak dan konten bisa di-update:

1. **Content** (read-only, JSON di assets): katalog kendaraan, body, barang, fasilitas & level, pelanggan template.
2. **Map pack** (read-only, SQLite/MBTiles per wilayah).
3. **Save slot** (Drift, **satu file SQLite per slot**: `saves/slot_<id>.db`). Memudahkan backup, hapus, dan salin.

Tabel inti save slot (Tahap 2 hanya mengisi yang ditandai ★):

| Tabel | Isi utama |
|---|---|
| ★ `save_meta` | schema_version, content_version, map_pack_id, seed, nama perusahaan, sim_time, last_wall_clock, last_monotonic, boot_id |
| ★ `company` | kas, reputasi per segmen |
| ★ `depots` | id, kota, node jalan terdekat, posisi, spesialisasi |
| ★ `facilities` | depot_id, tipe, level, status konstruksi |
| ★ `parking_slots` | depot_id, index, ukuran, vehicle_id |
| ★ `vehicles` | model_id, body_id, odometer_m, tahun, harga beli, status, depot_id |
| `vehicle_components` | vehicle_id, komponen, kondisi (0–1), km sejak servis |
| ★ `employees` | role, skill, pengalaman, gaji, fatigue, assigned_vehicle |
| ★ `contracts` | pelanggan, tipe, muatan, asal/tujuan node, deadline, bayaran, penalti, status |
| ★ `trips` | vehicle, driver, contract, route_id, depart_time, leg saat ini, status |
| ★ `routes` | cache polyline & profil biaya |
| ★ `scheduled_events` | sim_time, seq, tipe, payload JSON (antrean event yang tertunda) |
| `inventory_lots` | warehouse, cargo_id, qty, berat, volume, kondisi, kedaluwarsa |
| `ledger_entries` | sim_time, akun, jumlah, referensi (sumber laporan laba rugi) |
| `insurance_policies`, `claims` | premi, deductible, limit, masa berlaku |
| `incidents` | trip/vehicle, tipe, biaya, klaim |
| ★ `event_log` | ringkasan untuk "selama Anda pergi…" |

Semua uang disimpan sebagai **integer rupiah**, jarak dalam **meter**, waktu simulasi dalam **detik (int64)** — tidak ada floating point untuk akuntansi.

**Migrasi:** Drift `schemaVersion` + `MigrationStrategy` bertahap, dengan test migrasi per versi (Drift `SchemaVerifier`). Sebelum migrasi, file save disalin sebagai backup.

## 10. Desain Domain & Hubungan Antarsistem

Domain berkomunikasi lewat **DomainEventBus** sinkron di dalam simulation core, bukan saling memanggil secara langsung.

```
Accidents ──VehicleBrokeDown──▶ Vehicle(status=broken) ──▶ Dispatch menolak kendaraan
Trip ──TripCompleted──▶ Contracts(selesai/telat) ──ContractSettled──▶ Finance(ledger)
Finance ──CashChanged──▶ Progression(cek unlock) ──▶ Depot upgrade tersedia
Trip ──DistanceDriven──▶ Vehicle(odometer, keausan) ──▶ Workshop(rekomendasi servis)
Trip ──DrivingTime──▶ Employees(fatigue) ──▶ Accidents(faktor risiko)
```

Contoh dependensi utama:

- **Dispatch** = orkestrator: kontrak + kendaraan + body + sopir + rute + slot dock.
- **Vehicle** tidak tahu Finance; ia memancarkan `MaintenanceCompleted(cost)`, Finance yang mencatat.
- **Progression** hanya mendengarkan event dan membaca state; tidak memodifikasi domain lain.

## 11. Desain Event Simulation

Model: **discrete-event simulation** dengan antrean prioritas.

- `SimTime`: detik game (int64).
- `EventQueue`: diurutkan berdasarkan `(time, priority, seq)` — `seq` monoton menjamin urutan deterministik untuk event bersamaan.
- Setiap event = data murni (serializable) + handler di domain terkait; handler boleh menjadwalkan event baru.
- **RNG deterministik:** `Random` turunan dari `hash(saveSeed, entityId, eventSeq)`, jadi hasil tidak bergantung pada kapan pemain membuka game.
- **Tidak ada per-frame update** di core. Posisi kendaraan untuk render dihitung `f(route, departTime, now)`.
- Biaya berkala (gaji, sewa, premi) dijadwalkan sebagai event berulang harian/bulanan.

Contoh rantai event satu pengiriman:

```
ContractAccepted → DispatchRequested → LoadingQueued → LoadingStarted
→ LoadingFinished → GateExitQueued → DepartedDepot → (IncidentCheckpoint?)
→ ArrivedAtDestination → UnloadingFinished → ReturnLegStarted
→ ArrivedAtDepotGate → ParkedInSlot → InspectionDone → DriverRestStarted
```

**Kecelakaan tanpa menghitung per frame:** saat leg dimulai, hitung laju bahaya per segmen (kondisi kendaraan, fatigue, kelas jalan, muatan), sampling *satu* waktu kejadian dengan distribusi eksponensial; jika jatuh sebelum leg selesai, jadwalkan `IncidentOccurred`. Indikator risiko sebelum dispatch memakai rumus yang sama (probabilitas = 1 − e^(−Σλ·d)).

## 12. Desain Offline Progression

Saat **ditutup/ke background:** simpan semua state (sudah otomatis karena event queue persisten) + `last_wall_clock`, `last_monotonic` (SystemClock.elapsedRealtime via platform channel), `boot_id`.

Saat **dibuka:**

1. Hitung `Δ` wall clock dan, jika boot sama, `Δ` monotonic.
2. **Validasi waktu:**
   - Jika boot sama dan |Δwall − Δmono| besar → jam perangkat diubah; pakai Δmono.
   - Jika Δwall negatif → Δ = 0 (waktu tidak mundur), catat anomali.
   - **Batas catch-up** (usulan 72 jam nyata); sisa waktu di atas batas diabaikan, bukan "dihukum".
3. Konversi ke waktu game (`time scale`, lihat keputusan di bawah).
4. Jalankan event queue sampai `now` (batch, di Isolate, dengan progress bar jika lama).
5. **Kebijakan anti-hukuman:** selama offline, kendaraan yang menganggur tidak mengambil kontrak baru; kontrak berulang yang terlewat dibatalkan tanpa penalti berat; kas tidak boleh membuat perusahaan bangkrut hanya karena offline (gaji ditangguhkan, bukan pailit instan).
6. Tampilkan ringkasan dari `event_log`.

## 13. Desain Sistem Depot 3D

- **Data → visual:** setiap level fasilitas di katalog JSON menunjuk ke `visual_variant` (model GLB, jumlah dock, jumlah rak). Statistik dan visual berasal dari sumber yang sama.
- **Layout berbasis grid** (mis. 1 sel = 4 m) dengan zona: gate, jalan internal, slot parkir, dock, gudang, kantor, bengkel, trailer yard. Ekspansi lahan = menambah blok grid.
- **Jalur internal** sebagai graph kecil (waypoint) agar kendaraan bergerak gate → dock → slot, termasuk titik antrean.
- **Aktor visual** (kendaraan, forklift, pekerja) adalah *proyeksi* dari state simulasi: renderer membaca `DepotSnapshot { vehicles: [id, posisi-pada-jalur, aksi], workers: [...], queues: [...] }` lalu menganimasikan transisi.
- **Kamera:** orbit + zoom + pan, dengan sudut dibatasi agar tetap terbaca di layar HP.
- Saat layar depot tidak dibuka, renderer dimatikan sepenuhnya; simulasi tetap berjalan.

## 14. Desain Progression Kendaraan & Fasilitas

| Fase | Kendaraan | Fasilitas kunci | Kategori barang |
|---|---|---|---|
| Early | Pikap losbak, pikap box, mini truck (setara kelas Carry/L300/Gran Max) | Parking 3→6, gudang kecil, 1 dock | Retail, minuman |
| Mid | Light truck (CDE/CDD), medium truck (engkel/fuso ringan) | Workshop, dock 2–3, office (dispatcher), cold storage | Bahan bangunan, pertanian, pendingin |
| Late | Heavy rigid (tronton), tractor head + trailer, container, lowbed | Trailer yard, heavy workshop, depot kedua | Kontainer, barang khusus, berat |

Kendaraan referensi memakai **nama generik** (bukan merek dagang), dengan spesifikasi realistis untuk kelasnya. Kompatibilitas body dan barang didefinisikan di katalog (`vehicle_class → allowed_bodies`, `cargo → required_body/temperature/hazard`).

## 15. Strategi Optimasi Android

- Simulation core di Isolate untuk catch-up; tidak memblokir UI thread.
- Renderer 3D: instancing, LOD, atlas tekstur, batas aktor visual (mis. maks 12 pekerja terlihat; sisanya hanya statistik), target 30 fps di HP menengah, 60 fps opsional.
- Peta: tile cache, overlay kendaraan digambar sebagai satu layer, dan hanya kendaraan di viewport yang dianimasikan.
- Database: transaksi batch saat catch-up, WAL mode, indeks pada `scheduled_events(time)`.
- Ukuran: map pack per wilayah, tidak semua dibundel; target APK awal < 150 MB.
- Profil di perangkat target murah (RAM 3–4 GB) sejak Tahap 2.

## 16. Roadmap Implementasi

| Tahap | Hasil yang bisa dijalankan | Kriteria selesai |
|---|---|---|
| 1 | Dokumen ini | Keputusan teknis disetujui |
| 2a | Spike 3D (Thermion vs Flame) + spike routing di graph kota nyata | Benchmark fps & waktu routing di HP target |
| 2b | Core prototype: New Game → depot 3 slot → 1 pikap 1 sopir 1 kontrak → keluar depot → rute nyata → kembali → autosave/load | Satu siklus pengiriman penuh, test sim_core hijau |
| 3 | Depot simulation: gate, dock, antrean, pekerja, upgrade + visual | Antrean memengaruhi waktu, upgrade mengubah visual |
| 4 | Business simulation: kontrak lengkap, barang, warehouse, staff, finance, maintenance, asuransi, kecelakaan | Laporan laba rugi konsisten dengan ledger |
| 5 | Offline simulation lengkap + validasi waktu + ringkasan | Test determinisme: catch-up 1×72 jam == 72×1 jam |
| 6 | Ekspansi: kendaraan besar, trailer, multi-depot, wilayah lain | Depot kedua di kota lain beroperasi |

## 17. Risiko Teknis & Solusi

| Risiko | Dampak | Solusi |
|---|---|---|
| Library 3D Flutter belum matang / bermasalah di GPU tertentu | Tinggi | Interface `DepotSceneRenderer` + fallback Flame 2.5D; spike sebelum komitmen |
| Graph jalan satu pulau terlalu besar | Tinggi | Pangkas kelas jalan, detail hanya di sekitar kota, CH jika perlu, routing di Isolate |
| Ukuran APK membengkak oleh map pack | Sedang | Paket per wilayah, vector tiles, impor dari file lokal |
| Hasil simulasi offline berbeda dengan online | Tinggi | Satu jalur kode (event queue) untuk keduanya; test determinisme |
| Manipulasi jam perangkat | Sedang | Monotonic clock + boot id + batas catch-up |
| Ekonomi tidak seimbang | Sedang | Tool balancing headless di `tools/balancing` |
| Migrasi save rusak | Tinggi | Backup otomatis sebelum migrasi + test migrasi tiap versi |
| Lisensi data OSM (ODbL) | Sedang | Atribusi di peta & credits, dokumentasi sumber di manifest pack |
| Merek kendaraan nyata | Rendah–sedang | Nama generik, desain sendiri |

---

## Keputusan yang Perlu Disetujui

1. **Engine 3D:** Thermion/Filament sebagai primer, Flame 2.5D sebagai fallback — diputuskan final setelah spike 2a. *(Rekomendasi: setuju)*
2. **Wilayah awal prototype:** satu kota dulu (usul: **Surabaya** atau **Bandung**, graph lebih kecil daripada Jakarta), lalu diperluas ke seluruh Jawa.
3. **Skala waktu game:** usul **1 menit nyata = 10 menit game** saat aktif, dengan opsi percepat 2×/4×; offline mengikuti skala yang sama, catch-up maks 72 jam nyata.
4. **Monorepo** dengan `app/` + `packages/sim_core` + `tools/`. *(Rekomendasi: setuju)*
5. **State management:** Riverpod. *(Rekomendasi: setuju)*
