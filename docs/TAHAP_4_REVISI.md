# Tahap 4 — Revisi alur kontrak, gudang, jual-beli armada, level 15

Berasal dari masukan user 2026-10-31 22:57 (lihat `INSTRUKSI_USER.md`). Revisi ini menggantikan urutan 4.4 & 4.5 di `TAHAP_4_RENCANA.md` dan menambah jual-beli armada serta level fasilitas 1–15.

## 1. Masalah alur sebelumnya

Semua kontrak memuat barang di loading dock depot. Padahal gudang perusahaan masih kosong, jadi barangnya datang dari mana?

## 2. Jenis pekerjaan (baru)

| Jenis | Alur kendaraan | Uang | Gudang |
|---|---|---|---|
| **Jasa angkut** (`haul`) | depot → **supplier A** (muat) → **toko B** (bongkar) → depot | Bayaran jasa saja. Barang milik supplier. | Tidak dipakai |
| **Jasa angkut berulang** (`Agreement`) | sama seperti jasa angkut, tiap 1 / 2 / 3 / 7 hari, **kendaraan yang sama** | Bayaran per pengiriman. Pengiriman yang terlewat tidak dibayar, dan 3 kali terlewat berarti kontrak putus. | Tidak dipakai |
| **Pesanan toko** (`storeOrder`) | Ada stok: depot (muat di dock) → toko. Stok kurang: depot (muat yang ada) → **supplier** (beli sisanya) → toko. Tanpa stok: depot → supplier → toko. | Toko membayar **harga barang + ongkos kirim**. Barang yang dibeli di supplier = modal keluar. | Stok berkurang |
| **Isi stok gudang** (`restock`) | depot → supplier (beli, harga grosir) → depot (bongkar di dock ke gudang) | Modal keluar, harga grosir lebih murah | Stok bertambah (dibatasi m³ gudang) |

Kontrak lama (save sebelum revisi) tetap berjalan dengan alur lama (`legacy`: muat di depot).

### Rencana fase per trip

Trip kini menyimpan **daftar fase** (`plan`) yang dihitung saat dispatch, sehingga setiap jenis pekerjaan cukup menyusun urutannya:

- jasa angkut: `toGateDirect → waitGateOut → gateOut → toPickup → pickupLoading → outbound → unloading → inbound → waitGateIn → gateIn → toSlot → inspection`
- pesanan toko, stok sebagian: `waitDock → toDock → loading → toGate → … → toPickup → pickupLoading → outbound → …`
- isi stok: `toGateDirect → … → toPickup → pickupLoading → inbound → … → toSlot → waitDockIn → toDockIn → unloadDock → dockToSlot → inspection`

`toGateDirect` = keluar slot langsung ke antrean gerbang, berputar di apron dock tanpa memesan dock.

### Supplier

Supplier adalah entitas dunia yang tersimpan di save. Ada 6 supplier per kota, dengan nama dan jenis barang dari `content/suppliers.json` serta lokasi di jalan nyata 2–12 km dari depot (deterministik dari seed). Save lama dibuatkan supplier saat dimuat.

## 3. Gudang

- Stok per depot: `barang → jumlah unit`. Kapasitas = `capacity_m3` level gudang, dan volume per unit diambil dari `cargo_types.json`.
- Harga: `price_idr` per unit di katalog barang. Restock = harga × 0,92 (grosir). Beli langsung saat pesanan = harga × 1,0. Toko membayar harga × 1,15.
- Stok dialokasikan saat dispatch. Volume barang yang sedang diangkut ke gudang dihitung sebagai terpakai, supaya gudang tidak bisa kelebihan isi.
- Menyusul: kedaluwarsa, barang rusak, dan forklift/rak sebagai pengali kecepatan.

## 4. Jual-beli armada

- Kendaraan menyimpan **tahun produksi** dan **harga beli**. Kalender game dimulai 1 Januari 2026, dan 1 tahun = 365 hari game.
- **Nilai pasar** = harga baru × faktor umur × faktor odometer × faktor kondisi (minimal 10% harga baru), dengan parameter di `economy.json` → `vehicle_market`.
- **Jual** = nilai pasar × 85% (dealer). Syarat: kendaraan menganggur, tidak terikat kontrak berulang aktif, dan bukan satu-satunya kendaraan.
- **Pasar bekas**: 4 penawaran per hari per depot (deterministik). Isinya model acak, umur 1–12 tahun, odometer 20–60 ribu km/tahun, kondisi komponen acak, harga = nilai pasar × 110%. Syarat beli sama dengan kendaraan baru (slot dan level fasilitas).
- Lelang: fitur berikutnya.

## 5. Fasilitas level 1–15

Setiap fasilitas punya 15 level, terbagi dua jenis:

- **Upgrade statistik**: model 3D tetap, angka naik. Misalnya kecepatan jalur internal parkir, kecepatan dock, waktu lewat gerbang, kapasitas gudang, kapasitas kantor, serta kecepatan dan biaya bengkel.
- **Upgrade ganti wajah** (`tier` visual berubah): model 3D baru, dan biasanya kapasitas fisik ikut naik (slot, dock, jalur gerbang, bay).

| Tier visual | Level | Status |
|---|---|---|
| 1 | 1–3 | ada (model level 1 lama) |
| 2 | 4–7 | ada (model level 2 lama) |
| 3 | 8–11 | ada (model level 3 lama) |
| 4 | 12–14 | **aset & layout lahan diperluas belum dibuat** — sementara memakai tier 3, statistik fisik tetap |
| 5 | 15 (terminal) | **belum dibuat** — sementara memakai tier 3 |

Save lama dimigrasi: level 1 / 2 / 3 → 1 / 4 / 8 (format save 3). Syarat kendaraan di katalog ikut disesuaikan (parkir L2 → L4, L3 → L8). Renderer membaca `tier`, bukan nomor level.

Stat baru parkir: `yard_speed`, yaitu pengali kecepatan perpindahan di dalam depot (slot ↔ dock ↔ gerbang). Ini merujuk ke spesifikasi "memperbaiki jalur internal".

## 6. Depot hidup

Depot kini ramai juga saat tidak ada kendaraan yang ditugaskan:
- Jadwal shift berdasarkan jam game: staf datang pagi (06.00–07.00) dan pulang sore.
- Staf gudang merapikan stok (bolak-balik rak ↔ pintu) bila ada stok.
- Satpam berpatroli di sepanjang pagar.
- Mekanik ada di bengkel. Sopir yang beristirahat duduk di area istirahat.

Semuanya fungsi deterministik dari waktu game di renderer, tanpa state simulasi tambahan.
