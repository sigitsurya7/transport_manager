# Katalog kendaraan & aset 3D

## Arah visual

**Low-poly bergaya** (opsi A), melanjutkan gaya depot yang sudah ada. Alasannya: renderer flutter_scene sudah berjalan baik di HP dengan mesh berwarna datar tanpa tekstur dan bayangan dari directional light. Model dibuat orisinal oleh generator, sehingga skala, orientasi, dan proporsinya konsisten dengan depot.

**Aset pihak ketiga: tidak ada.** Semua kendaraan dan properti dibuat oleh `tools/depot_glb`. Tidak ada aset yang diunduh, sehingga tidak ada lisensi atau atribusi yang perlu dicatat. Game tetap 100% offline.

## Struktur data (`content/vehicle_models.json`)

| Bagian | Isi |
|---|---|
| `cargo_kinds` | Jenis muatan: umum, berpendingin, curah, material bangunan, cairan, kendaraan, kayu |
| `categories` | 8 kategori dealer |
| `chassis` | 19 sasis/kabin. `mount` = jenis dudukan, `body_max_m` = panjang bodi maksimum |
| `bodies` | 39 bodi, semitrailer, dan kontainer. `mounts` = dudukan yang cocok, `cargo_kinds`, `doors` |
| `models` | 40 kendaraan jadi = sasis + bodi + angka operasional + dimensi + syarat buka |

Validasi di `sim_core` (`VehicleCatalog.fromJson`) menolak:
- bodi yang dudukannya tidak cocok dengan sasis (mis. kontainer 20 ft di pikap),
- bodi yang lebih panjang dari `body_max_m` sasis,
- id ganda, jenis muatan atau kategori yang tidak dikenal,
- syarat fasilitas di atas level maksimum.

Gameplay:
- Dispatch menolak kendaraan yang bodinya tidak sanggup mengangkut jenis barang kontrak (`cargoIncompatible`).
- Tawaran kontrak hanya memakai jenis barang yang bisa diangkut armada depot.
- `unlock: {facility, level}` mensyaratkan level fasilitas depot (truk sedang butuh parkir level 2).
- `unlock: {terminal: true}` menandai truk berat dan tractor yang terlalu panjang untuk depot kota. Fasilitas **terminal truk belum ada**, jadi model-model ini tampil di dealer dengan status "Butuh terminal truk" dan belum bisa dibeli.

## Ringkasan katalog

| Kategori | Model | Bisa masuk depot kota |
|---|---|---|
| Pikap | 6 (kompak, bak 1 ton, kanopi, kabin ganda, heavy-duty, mobil box) | ya |
| Van | 4 (blind van kota, panel, atap tinggi, van niaga besar) | ya |
| Truk mini | 4 (kompak, box, bak besi, berpendingin) | ya |
| Truk ringan | 7 (bak kayu, kontainer 10 ft, box, flatbed, curtain-side, berpendingin, dump) | ya |
| Truk sedang | 5 (box, flatbed, curtain-side, berpendingin, dump) | ya (parkir L2) |
| Khusus | 4 (tangki 5.000 L, towing pengangkut mobil, crane material, kayu gelondong) | ya |
| Truk berat | 5 (box, flatbed, kontainer 20 ft, tipper, tangki) | butuh terminal truk |
| Tractor head | 5 (kabin harian + 40 ft, kabin tidur + box, moncong panjang + flatbed, cab-over + tangki, heavy-duty + car carrier) | butuh terminal truk |

Total 40 model. Ada 30 GLB kendaraan untuk depot, ditambah varian `_open` untuk kendaraan berpintu. Semua 40 model punya thumbnail PNG.

## Pipeline aset

```
content/vehicle_models.json ──► tools/depot_glb/vehicles.py ──► app/assets/models/<id>.glb (+ <id>_open.glb)
                                       │                         app/assets/models/thumbs/<id>.png
                                       └──► depot_layout.json: vehicle_bounds, vehicle_cargo, vehicle_dims
```

- `geom.py`: palet material, `MeshBuilder` (solid cembung, normal otomatis keluar), penulis GLB.
- `vehicles.py`: kabin (bermoncong, cab-over, van, moncong panjang), bodi (bak, kanopi, box, berpendingin, curtain, kontainer, flatbed, dump, tangki, dek mobil, crane, rak kayu, semitrailer), dan perakitan.
- `thumbs.py`: rasterizer z-buffer tanpa dependensi untuk thumbnail 320×160 dari mesh yang sama. Thumbnail di-cache per hash mesh di `tools/depot_glb/.thumb_cache/`.

Konvensi model:
- menghadap +X, Y ke atas, satuan meter;
- ujung belakang tepat di x = -2,7, sehingga bak berhenti pas di depan platform dock;
- lebar termasuk spion;
- muat di slot 3,5 m; ujung depan ≤ 5,0 m dari origin agar tidak menembus bengkel saat parkir.

Jalur di depot menyesuaikan panjang kendaraan (`DepotMotion.pose(front: …)`): kendaraan panjang berbelok lebih awal di gerbang, melebar ke lajur jauh saat masuk, dan berhenti lebih jauh dari palang.

Anggaran: kendaraan ≤ 1.600 segitiga, modul fasilitas ≤ 3.500, base ≤ 9.000. GLB hanya dimuat untuk kendaraan yang dimiliki pemain; katalog tidak dimuat ke scene.

## Menambah kendaraan baru

1. **Hanya kombinasi baru dari sasis + bodi yang sudah ada:** tambahkan entri di `models` (`content/vehicle_models.json`): id unik, nama, `category`, `subcategory`, `chassis`, `body`, `class`, `livery` (nama material di `geom.py`), angka operasional, dan `unlock` bila perlu. Isi dimensi dengan sembarang angka dulu.
2. **Butuh bentuk baru:** tambahkan sasis atau bodi di JSON, lalu tambahkan geometrinya di `vehicles.py`: spesifikasi sasis di `TRUCKS` atau cabang `build_vehicle`, bodi di cabang `kind`. Bila bodi membawa barang umum dengan palet, tambahkan `kind` ke `CARGO_BODIES`.
3. Jalankan `python tools/depot_glb/update_catalog_dims.py` untuk menulis `length_m`, `width_m`, dan `height_m` dari model 3D.
4. Jalankan `bash tools/sync_app_assets.sh` untuk membuat ulang GLB, layout, dan thumbnail.
5. Uji:
   - `python -m unittest test_make_depot_glb` (di `tools/depot_glb`): dimensi cocok, thumbnail ada, model tidak identik, anggaran segitiga;
   - `dart test` (di `packages/sim_core`): validasi katalog dan pembelian;
   - `flutter test` (di `app`): uji tabrakan semua kendaraan di semua level fasilitas.

   Bila uji tabrakan gagal, kendaraan terlalu panjang atau lebar untuk depot kota: perkecil, atau beri `unlock: {terminal: true}`.

## Perombakan visual depot

- **Lantai:** sambungan panel beton tiap 5 m, marka putus-putus di tengah jalur, panah arah di gerbang, penyeberangan pejalan kaki kantor–gudang, polisi tidur kuning-hitam.
- **Pagar:** model BRC dengan plinth beton, tiang, jeruji, rel, dan kawat atas.
- **Parkir:** kepala slot bergaris kuning-hitam; level 2 menambah garis tepi kuning. **Lampu lantai per slot**: hijau = kosong, oranye = milik kendaraan. Slot di atas kapasitas parkir saat ini tidak tampil.
- **Dock:** seal hitam di sekeliling pintu, lampu dock, bollard kuning; level 2+ menambah lampu lalu lintas dan tumpukan palet; level 3 menambah kanopi dan leveler.
- **Gudang:** rusuk dinding, talang dan pipa turun, ventilasi bubungan, papan nama, pintu orang dengan kanopi; level 2+ menambah skylight; level 3 menambah panel surya dan rak.
- **Kantor:** 1/2/3 lantai sesuai level, dengan list lantai, unit AC, kanopi pintu, papan nama di atap (L2+), pagar atap, panel surya, dan tiang bendera (L3). Sayap kantor L3 lama diganti lantai ke-3 karena tepat berada di sapuan truk panjang yang keluar gerbang.
- **Bengkel:** papan nama, rusuk dinding, drum oli.
- **Gerbang:** papan di pilar, rambu batas kecepatan.
- **Props:** pembatas keselamatan di depan kantor, palet dan kardus, pot tanaman, pagar tanaman. Gazebo, parkir motor, dan forklift dipindah keluar dari sapuan truk panjang.
- **Progres awal tetap 3 slot parkir.**
