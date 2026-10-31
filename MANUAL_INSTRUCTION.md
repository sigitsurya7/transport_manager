# Master Prompt — Offline Transport Tycoon

> Flutter | Full 3D Depot | Real-World Road Network | Offline Business Simulation

Bertindaklah sebagai Senior Game Designer, Game Systems Architect, Flutter Engineer, Simulation Engineer, dan 3D Technical Artist yang berpengalaman membangun game simulasi manajemen transportasi.

Saya ingin membangun game transport tycoon yang terinspirasi dari genre transport management seperti Truck Manager, tetapi memiliki identitas, sistem gameplay, visual, dan kedalaman simulasi sendiri.

Game ini dikembangkan menggunakan Flutter dan harus dapat dimainkan sepenuhnya secara offline.

Jangan sekadar membuat prototype UI atau game idle sederhana. Rancang sebuah game simulasi perusahaan transportasi dan logistik dengan sistem ekonomi, armada, karyawan, depot 3D, warehouse, jaringan jalan nyata, pengiriman barang, perawatan kendaraan, serta ekspansi bisnis.

---

## 1. VISI DAN IDENTITAS GAME

Game berfokus pada perjalanan pemain membangun perusahaan transportasi dari bisnis distribusi kecil menjadi perusahaan logistik berskala besar.

Pemain memulai dari nol dengan modal terbatas, sebuah depot kecil, kendaraan niaga ringan, seorang sopir, dan kontrak pengiriman sederhana.

Perkembangan bisnis harus berlangsung bertahap.

### Contoh perjalanan bisnis

1. Mengirim barang dari toko ke toko menggunakan pikap.
2. Mengembangkan layanan distribusi antarkawasan.
3. Membeli kendaraan niaga yang lebih besar.
4. Memiliki warehouse dan mengelola persediaan barang.
5. Mengembangkan armada truk.
6. Mengoperasikan kendaraan berat dan trailer.
7. Membuka depot di kota lain.
8. Mengembangkan jaringan distribusi antarkota dan antarwilayah.
9. Mengembangkan layanan transportasi tambahan seperti bus dan kereta pada tahap pengembangan berikutnya.

Game harus memberikan kebebasan kepada pemain untuk menentukan strategi bisnisnya sendiri.

Jangan membuat seluruh perkembangan hanya bergantung pada peningkatan level. Keputusan bisnis, efisiensi operasional, kondisi kendaraan, tenaga kerja, dan kemampuan mengelola risiko harus menentukan keberhasilan perusahaan.

## 2. PLATFORM DAN BATASAN TEKNOLOGI

### Platform utama

- Flutter.
- Bahasa pemrograman Dart.
- Android sebagai target awal, dengan arsitektur yang memungkinkan pengembangan iOS.
- Offline-first dan local-first.
- Tidak membutuhkan akun.
- Tidak membutuhkan backend.
- Tidak membutuhkan server.
- Tidak membutuhkan koneksi internet untuk gameplay.
- Tidak menggunakan API berbayar sebagai ketergantungan gameplay.

Seluruh data permainan harus disimpan secara lokal.

Evaluasi dan tentukan teknologi yang tepat untuk:

- Rendering 3D.
- Visualisasi depot.
- Animasi kendaraan.
- Peta geografis.
- Rendering jaringan jalan.
- Routing.
- Penyimpanan database.
- Simulasi waktu offline.
- Sistem save/load.

Pertimbangkan Flutter 3D rendering, Flame jika relevan, serta alternatif rendering yang kompatibel dengan Flutter.

Jangan memaksakan satu library jika secara teknis tidak cocok.

Gunakan SQLite dengan Drift atau solusi lokal setara untuk menyimpan data permainan.

Pastikan pemisahan antara:

- Game simulation.
- Business logic.
- Data persistence.
- Rendering.
- UI.
- Game progression.

Rendering tidak boleh menjadi sumber kebenaran simulasi.

## 3. WORLD MAP DAN PEMILIHAN NEGARA

Game menggunakan dunia geografis nyata.

Jangan menggunakan peta fiktif sebagai pengganti jaringan jalan sebenarnya.

Sumber data yang dapat dipertimbangkan:

- OpenStreetMap.
- Data jalan hasil ekstraksi OSM.
- Data geografis terbuka lainnya yang memiliki lisensi sesuai.

Game harus dapat menggunakan paket peta dan jaringan jalan yang telah disiapkan secara lokal.

Tidak boleh bergantung pada pengunduhan peta saat gameplay berlangsung.

### Alur permainan baru

Ketika pemain memilih New Game:

1. Pemain memilih negara.
2. Pemain memilih wilayah atau pulau.
3. Pemain memilih kota awal.
4. Pemain memilih lokasi depot awal yang tersedia.
5. Pemain memulai perusahaan transportasi.

### Contoh struktur Indonesia

**Country**

- Indonesia

**Region**

- Jawa
- Sumatra
- Kalimantan
- Sulawesi
- Bali dan Nusa Tenggara
- Papua

**City**

- Jakarta
- Bandung
- Semarang
- Surabaya
- Yogyakarta
- Medan
- Palembang
- Makassar
- Dan kota lainnya sesuai ketersediaan data.

Struktur harus data-driven sehingga negara, wilayah, kota, dan lokasi depot dapat ditambahkan tanpa mengubah keseluruhan game engine.

Pemain hanya boleh memilih wilayah yang benar-benar memiliki paket data lokal yang tersedia.

Jangan membuat rute jalan darat fiktif yang menghubungkan pulau-pulau terpisah.

Sistem transportasi laut atau ferry dapat dikembangkan kemudian sebagai sistem konektivitas antarpulau.

### Sistem peta

Peta harus memiliki:

- Jalan nyata.
- Klasifikasi jalan.
- Persimpangan.
- Koneksi antarkota.
- Geometri rute.
- Jarak perjalanan.
- Estimasi waktu.
- Pembatasan kendaraan berdasarkan karakteristik jalan.
- Informasi medan dan karakteristik rute jika tersedia.

Gunakan local road graph dan algoritma routing seperti A* atau Dijkstra.

Kendaraan harus mengikuti geometri jalan yang sebenarnya.

Jangan membuat kendaraan bergerak dalam garis lurus dari titik awal menuju titik tujuan.

Siapkan sistem offline map package yang dapat diperluas.

Evaluasi format MBTiles, PMTiles, vector tiles, atau format lokal lainnya berdasarkan kompatibilitas implementasi Flutter.

## 4. SISTEM PERMULAAN PERUSAHAAN

Pemain tidak langsung menjadi perusahaan besar.

Permainan dimulai dengan bisnis distribusi skala kecil.

### Kondisi awal

- 1 depot kecil.
- 3 slot parkir kendaraan.
- 1 kendaraan niaga ringan.
- 1 sopir.
- 1 gudang sederhana.
- 1 loading area.
- 1 gerbang masuk dan keluar.
- Kantor operasional sederhana.
- Modal awal terbatas.
- Kontrak pengiriman sederhana.

Dua slot parkir lainnya masih kosong dan dapat digunakan untuk perkembangan armada awal.

Kendaraan awal harus berupa kendaraan untuk distribusi barang antartoko, bukan truk besar atau tractor head.

### Contoh kendaraan awal

- Pikap losbak.
- Pikap box.
- Kendaraan niaga ringan.
- Mini truck.

### Contoh pekerjaan

- Mengirim air mineral dari distributor ke toko.
- Mengirim beras ke toko kelontong.
- Mengirim minyak goreng ke minimarket.
- Mengirim LPG menggunakan kendaraan yang sesuai.
- Mengirim makanan dan kebutuhan harian.
- Mengirim barang dari supplier menuju beberapa toko.

Pemain harus membangun reputasi dan keuntungan sebelum mampu membeli kendaraan yang lebih besar.

## 5. SISTEM KENDARAAN

Kendaraan harus memiliki klasifikasi berdasarkan ukuran, kapasitas, fungsi, dan kebutuhan operasional.

### Tahapan kendaraan

Tahap awal:

- Pikap losbak.
- Pikap box.
- Mini truck.
- Light commercial vehicle.

Tahap berkembang:

- Light truck.
- Medium truck.
- Heavy rigid truck.

Tahap lanjut:

- Tractor head.
- Trailer.
- Container truck.
- Heavy haul truck.
- Kendaraan khusus.

Kendaraan harus berdasarkan karakteristik kendaraan niaga yang realistis, terutama kendaraan yang relevan dengan Indonesia.

### Sistem body kendaraan

Pisahkan kendaraan dasar dari jenis body atau trailer yang kompatibel.

Contoh:

- Open bed.
- Box.
- Refrigerated box.
- Tanker.
- Flatbed.
- Container.
- Lowbed.

Tidak semua body kompatibel dengan semua kendaraan.

Tractor head dan trailer harus dapat memiliki kondisi serta kebutuhan perawatan masing-masing.

### Atribut kendaraan

Setiap kendaraan memiliki:

- Harga beli.
- Harga jual kembali.
- Tahun produksi.
- Odometer.
- Kapasitas muatan.
- Volume muatan.
- Konsumsi bahan bakar.
- Kecepatan operasional.
- Kondisi mesin.
- Kondisi transmisi.
- Kondisi rem.
- Kondisi ban.
- Kondisi suspensi.
- Kondisi sistem pendingin.
- Biaya perawatan.
- Status asuransi.
- Riwayat kecelakaan.
- Status operasional.

Odometer harus terus bertambah dan tidak kembali ke nol ketika mesin diganti.

Sediakan pasar kendaraan baru dan bekas.

Kendaraan bekas memiliki kondisi, kilometer, dan riwayat berbeda.

Upgrade kendaraan harus memiliki konsekuensi ekonomi dan tetap memperhatikan batas legal kendaraan.

## 6. SISTEM BARANG DAN LOGISTIK

Barang harus memiliki karakteristik dan kebutuhan transportasi masing-masing.

### Kategori barang

**Retail**

- Beras.
- Mi instan.
- Air mineral.
- Minyak goreng.
- Gula.
- Kebutuhan toko kelontong.

**Minuman**

- Air galon.
- Minuman kemasan.
- Produk minuman lainnya.

**Bahan bangunan**

- Semen.
- Besi.
- Pasir.
- Material konstruksi.

**Pertanian**

- Hasil panen.
- Sayuran.
- Buah-buahan.

**Pendingin**

- Daging.
- Ikan.
- Produk beku.
- Es krim.

**Industri**

- Mesin.
- Spare part.
- Peralatan industri.

**Barang khusus**

- LPG.
- Bahan bakar.
- Cairan industri.
- Bahan kimia sesuai kendaraan dan standar keselamatan.

**Barang kontainer**

- Barang ekspor.
- Barang impor.
- Barang manufaktur.

**Barang berat**

- Alat berat.
- Mesin besar.
- Material konstruksi khusus.

Setiap barang memiliki:

- Berat.
- Volume.
- Harga.
- Kebutuhan penyimpanan.
- Kategori penanganan.
- Risiko kerusakan.
- Masa kedaluwarsa jika relevan.
- Kebutuhan suhu.
- Jenis kendaraan yang kompatibel.

Muatan tidak boleh melebihi kapasitas kendaraan.

Barang berbahaya harus menggunakan kendaraan khusus yang sesuai.

## 7. SISTEM KONTRAK DAN PELANGGAN

Sediakan sistem kontrak dari:

- Toko kelontong.
- Minimarket.
- Distributor.
- Supplier.
- Perusahaan manufaktur.
- Perusahaan konstruksi.
- Perusahaan industri.
- Perusahaan perdagangan.
- Pelanggan khusus.

### Jenis kontrak

- Pengiriman satu kali.
- Pengiriman berulang.
- Distribusi beberapa toko.
- Pengiriman berdasarkan jadwal.
- Kontrak jangka panjang.
- Kontrak dengan tenggat waktu.

Setiap kontrak mempunyai:

- Nilai pembayaran.
- Jarak.
- Estimasi waktu.
- Biaya operasional.
- Tenggat waktu.
- Penalti keterlambatan.
- Persyaratan kendaraan.
- Persyaratan kapasitas.
- Risiko kerusakan barang.

Tampilkan estimasi keuntungan sebelum kontrak diterima.

Pemain harus dapat membandingkan beberapa kontrak.

Jangan menjadikan kontrak sebagai sistem klik dan uang otomatis. Setiap kontrak harus terhubung dengan operasi kendaraan dan distribusi barang.

## 8. SISTEM WAREHOUSE

Warehouse merupakan fasilitas penting dalam bisnis logistik.

Pemain dapat:

- Membeli barang dari supplier.
- Menyimpan barang.
- Mengelola inventaris.
- Mengirim barang berdasarkan pesanan toko.
- Mengatur distribusi.
- Mengelola kapasitas penyimpanan.
- Mengembangkan fasilitas gudang.

Barang yang disimpan harus memiliki jumlah, berat, volume, dan kondisi.

Sistem gudang harus mendukung:

- Rak penyimpanan.
- Pallet.
- Forklift.
- Loading dock.
- Bongkar muat.
- Cold storage.
- Manajemen stok.
- Kedaluwarsa.
- Barang rusak.
- Kebutuhan tenaga kerja.

Warehouse dapat berkembang melalui level dan upgrade visual.

## 9. SISTEM DEPOT 3D

Depot adalah salah satu fitur utama game.

Depot bukan sekadar menu statistik, tetapi lingkungan 3D yang aktif dan dapat diamati pemain.

Gunakan perspektif isometrik atau 3D dengan kamera yang dapat dirotasi dan diperbesar.

Pemain harus dapat melihat:

- Kendaraan terparkir.
- Kendaraan keluar melalui gerbang.
- Kendaraan masuk kembali.
- Antrean kendaraan.
- Loading dock.
- Pekerja.
- Forklift.
- Gudang.
- Bengkel.
- Kantor.
- Area istirahat.
- Trailer yard.
- Aktivitas operasional.

### Kondisi depot awal

- 3 slot parkir.
- 1 gerbang.
- 1 loading area.
- Gudang sederhana.
- Kantor kecil.
- Belum ada workshop khusus.

### Upgrade fasilitas

Semua fasilitas harus dapat ditingkatkan berdasarkan level dan perubahan visual.

Fasilitas:

- Parking yard.
- Gate.
- Warehouse.
- Loading dock.
- Workshop.
- Office.
- Rest area.
- Cold storage.
- Trailer yard.
- Security system.

### Contoh upgrade

**Parking**

- Menambah slot parkir.
- Memperluas lahan.
- Memperbaiki jalur internal.

**Gate**

- Gerbang manual.
- Gerbang otomatis.
- Multi-gate.

**Warehouse**

- Memperbesar bangunan.
- Menambah kapasitas.
- Menambah rak.
- Menambah forklift.
- Menambah loading dock.
- Mengembangkan sistem penyimpanan.

**Workshop**

- Menambah peralatan.
- Menambah mekanik.
- Meningkatkan kapasitas perbaikan.
- Membuka servis kendaraan berat.

**Office**

- Menambah ruang staf.
- Membuka posisi dispatcher.
- Membuka supervisor.
- Meningkatkan kemampuan administrasi.

**Rest area**

- Menambah kapasitas istirahat.
- Meningkatkan fasilitas pekerja.

**Cold storage**

- Menambah kapasitas.
- Meningkatkan kontrol suhu.
- Mengurangi risiko kerusakan barang.

**Trailer yard**

- Menambah kapasitas trailer.
- Menambah area parkir kendaraan berat.

### Sistem visual upgrade

Upgrade harus mengubah tampilan fisik depot.

Contoh:

- Bangunan semakin besar.
- Material bangunan berubah.
- Jumlah pintu bertambah.
- Rak gudang bertambah.
- Forklift muncul.
- Peralatan bengkel bertambah.
- Area parkir meluas.
- Marka jalan berubah.
- Pekerja bertambah.
- Area operasional semakin ramai.

Jangan hanya mengganti angka level.

Data fasilitas, statistik, kapasitas, dan aset visual harus saling terhubung.

### Sistem ekspansi

Selain upgrade, pemain dapat melakukan ekspansi:

- Membeli lahan tambahan.
- Membuka area parkir baru.
- Membangun warehouse kedua.
- Membuka workshop kendaraan berat.
- Membuka trailer yard.
- Mengembangkan depot menjadi pusat distribusi.

Arsitektur harus mendukung beberapa depot dalam satu perusahaan.

Depot dapat memiliki spesialisasi berdasarkan kebutuhan bisnis.

## 10. SIMULASI OPERASIONAL DEPOT

Seluruh aktivitas depot harus mengikuti sistem simulasi.

### Contoh alur dispatch

1. Pemain memilih kontrak.
2. Sistem memeriksa ketersediaan kendaraan.
3. Sistem memeriksa kompatibilitas muatan.
4. Sistem memeriksa ketersediaan sopir.
5. Barang dipersiapkan.
6. Kendaraan menuju loading dock.
7. Kendaraan menunggu jika dock penuh.
8. Barang dimuat.
9. Kendaraan menuju gerbang.
10. Kendaraan keluar depot.
11. Simulasi perjalanan dimulai.

### Ketika kendaraan kembali

1. Kendaraan mencapai lokasi depot.
2. Kendaraan menunggu jika gerbang penuh.
3. Kendaraan memasuki depot.
4. Kendaraan menempati slot parkir.
5. Kondisi kendaraan diperiksa.
6. Barang yang tersisa diproses.
7. Sopir mendapatkan waktu istirahat jika diperlukan.

Kendaraan tidak boleh muncul dan menghilang secara ajaib.

Antrean harus memengaruhi waktu operasional.

Jika kapasitas parkir penuh, pemain harus mengelola armada, memperluas depot, atau menggunakan fasilitas depot lain yang tersedia.

## 11. SISTEM KARYAWAN

### Jenis karyawan

- Driver.
- Warehouse staff.
- Forklift operator.
- Mechanic.
- Dispatcher.
- Administrative staff.
- Supervisor.

Setiap karyawan mempunyai:

- Skill.
- Pengalaman.
- Gaji.
- Kelelahan.
- Kebutuhan istirahat.
- Penugasan.
- Produktivitas.

**Driver**

- Memiliki kemampuan mengemudi.
- Memiliki tingkat pengalaman.
- Memiliki batas kerja.
- Membutuhkan istirahat.
- Memengaruhi risiko kecelakaan.
- Dapat ditugaskan ke kendaraan tertentu.

**Warehouse staff**

- Memengaruhi kecepatan bongkar muat.

**Mechanic**

- Memengaruhi kecepatan dan kualitas perbaikan.

**Dispatcher**

- Membantu mengelola operasional kendaraan dan kontrak.

Karyawan harus dapat divisualisasikan di depot sesuai pekerjaan masing-masing.

Hindari micromanagement yang berlebihan.

## 12. MAINTENANCE DAN PERBAIKAN

Kendaraan memiliki sistem keausan komponen.

### Komponen

- Mesin.
- Transmisi.
- Ban.
- Rem.
- Suspensi.
- Sistem pendingin.
- Sistem kelistrikan.

### Sediakan

- Servis rutin.
- Ganti oli.
- Ganti filter.
- Ganti ban.
- Perbaikan rem.
- Perbaikan mesin.
- Overhaul.
- Penggantian mesin.
- Pemeriksaan kendaraan.

Kondisi kendaraan memengaruhi:

- Konsumsi bahan bakar.
- Kecepatan.
- Risiko kerusakan.
- Risiko kecelakaan.
- Biaya perawatan.
- Ketersediaan kendaraan.

Kendaraan yang sedang diperbaiki tidak dapat digunakan untuk kontrak.

Workshop memiliki kapasitas servis dan antrean.

## 13. EKONOMI PERUSAHAAN

Game harus memiliki sistem ekonomi yang realistis dan saling berhubungan.

### Pendapatan

- Kontrak pengiriman.
- Distribusi barang.
- Penjualan barang warehouse.
- Layanan logistik lainnya.

### Pengeluaran

- Pembelian kendaraan.
- Bahan bakar.
- Tol.
- Gaji.
- Maintenance.
- Asuransi.
- Pajak.
- Biaya depot.
- Biaya warehouse.
- Pembelian barang.
- Kerusakan kendaraan.
- Penalti kontrak.

### Sediakan

- Cash flow.
- Laporan laba rugi.
- Aset perusahaan.
- Liabilitas.
- Hutang jika sistem pinjaman dikembangkan.
- Nilai kendaraan.
- Nilai inventaris.
- Nilai depot.

Pemain harus dapat memahami apakah sebuah kontrak benar-benar menguntungkan.

Jangan hanya menampilkan uang bertambah setelah pengiriman.

## 14. ASURANSI

Kendaraan dan barang dapat diasuransikan.

### Jenis perlindungan

- Kerusakan kendaraan.
- Kecelakaan.
- Kerusakan barang.
- Kehilangan barang.
- Tanggung jawab pihak ketiga.

Asuransi harus memiliki:

- Premi.
- Masa berlaku.
- Deductible.
- Batas pertanggungan.
- Pengecualian.
- Proses klaim.

Tidak semua kerugian otomatis ditanggung.

## 15. KECELAKAAN DAN RANDOM EVENTS

Gunakan model campuran antara keputusan pemain dan faktor tak terduga.

### Faktor risiko

- Kondisi kendaraan.
- Kondisi ban.
- Pengalaman driver.
- Kelelahan.
- Kecepatan.
- Berat muatan.
- Karakteristik rute.
- Kondisi jalan.
- Cuaca jika disimulasikan.

### Jenis kejadian

- Ban pecah.
- Mesin overheating.
- Kerusakan transmisi.
- Rem bermasalah.
- Kendaraan mogok.
- Tabrakan.
- Kerusakan barang.
- Kegagalan sistem pendingin.
- Keterlambatan.
- Gangguan operasional.

### Konsekuensi

- Biaya perbaikan.
- Downtime.
- Kerusakan barang.
- Penalti.
- Klaim asuransi.
- Penurunan reputasi.
- Kewajiban terhadap pihak ketiga.

Kecelakaan tidak boleh terasa seperti hukuman acak tanpa alasan.

Tampilkan indikator risiko sebelum pemain mengambil keputusan dispatch.

Kejadian tak terduga tetap harus mungkin terjadi meskipun pemain telah melakukan persiapan dengan baik.

Jangan menggunakan visual kecelakaan yang grafis atau eksplisit.

## 16. SIMULASI WAKTU OFFLINE

Waktu permainan tetap berjalan ketika aplikasi ditutup.

Tidak boleh bergantung pada background service yang harus terus aktif.

Gunakan pendekatan timestamp-based simulation.

### Ketika pemain menutup game

- Simpan waktu terakhir.
- Simpan status seluruh operasi.
- Simpan posisi perjalanan.
- Simpan status kendaraan.
- Simpan status kontrak.
- Simpan antrean depot.
- Simpan status pekerja.
- Simpan status ekonomi.

### Ketika pemain membuka game

- Hitung selisih waktu.
- Proses kejadian yang seharusnya berlangsung.
- Perbarui status kendaraan.
- Proses kontrak.
- Proses gaji dan pengeluaran.
- Proses maintenance.
- Proses warehouse.
- Proses kecelakaan sesuai sistem risiko.
- Tampilkan ringkasan kejadian selama offline.

Simulasi harus deterministik sejauh mungkin dan memiliki event ordering yang benar.

Jangan menghitung setiap frame selama pemain offline.

Sediakan sistem simulasi berbasis event dan interval waktu yang efisien.

Perhatikan perubahan jam perangkat dan manipulasi waktu.

Jangan membiarkan perubahan waktu perangkat memberikan keuntungan tidak wajar.

Sediakan batasan dan mekanisme pemulihan yang masuk akal jika waktu perangkat tidak konsisten.

## 17. GAME PROGRESSION DAN RETENTION

Buat perkembangan bisnis dalam beberapa fase.

### Early Game

- Distribusi barang antartoko.
- Kendaraan niaga ringan.
- Kontrak sederhana.
- Depot kecil.
- Modal terbatas.
- Fokus pada cash flow.

### Mid Game

- Armada lebih besar.
- Warehouse berkembang.
- Kontrak antarkota.
- Karyawan bertambah.
- Workshop.
- Ekspansi depot.
- Distribusi multi-kota.

### Late Game

- Heavy truck.
- Tractor head.
- Trailer.
- Kontainer.
- Heavy haul.
- Beberapa depot.
- Jaringan logistik antardaerah.
- Bisnis transportasi skala besar.

Bus dan kereta dapat menjadi pengembangan transportasi pada tahap berikutnya.

Jangan memaksakan semua sistem late game muncul di awal permainan.

Buat progression yang membuat pemain memiliki tujuan:

- Jangka pendek.
- Jangka menengah.
- Jangka panjang.

Game tidak boleh memberikan hukuman berlebihan hanya karena pemain tidak membuka aplikasi selama beberapa hari.

## 18. SAVE SYSTEM

Game harus mendukung:

- Multiple save slots.
- Autosave.
- Manual save.
- Load game.
- New game.
- Delete save.
- Save backup lokal jika memungkinkan.

Simpan seluruh state yang diperlukan untuk melanjutkan simulasi.

Pastikan migrasi database dapat dilakukan tanpa merusak save lama ketika versi game berkembang.

## 19. UI DAN ART DIRECTION

Buat visual game yang modern, bersih, dan profesional.

### Arah visual

- 3D isometric atau perspektif 3D.
- Lingkungan industri yang detail.
- Kendaraan dengan proporsi realistis.
- Warehouse dan depot yang hidup.
- Animasi kendaraan halus.
- UI manajemen yang mudah dipahami.
- Informasi bisnis yang jelas.

Pisahkan:

1. Management UI.
2. World map.
3. Depot 3D.
4. Vehicle detail.
5. Warehouse management.
6. Employee management.
7. Contract management.
8. Finance dashboard.

Jangan membuat semua informasi dalam satu layar.

UI harus nyaman digunakan pada layar smartphone.

## 20. PERFORMANCE DAN OPTIMIZATION

Target game adalah smartphone Android.

### Optimalkan

- Rendering 3D.
- Jumlah objek aktif.
- Jumlah pekerja yang divisualisasikan.
- Animasi kendaraan.
- Penggunaan tekstur.
- Pemakaian memori.
- Penyimpanan lokal.
- Pemrosesan event.
- Pemuatan map package.

Gunakan level of detail jika dibutuhkan.

Tidak semua objek harus menggunakan model 3D kompleks.

Objek yang jauh dapat menggunakan model lebih sederhana.

Ketika pemain tidak sedang melihat depot, simulasi tetap berjalan tanpa merender seluruh aktivitas 3D.

Ketika game ditutup, tidak ada kebutuhan untuk mempertahankan rendering.

## 21. ARSITEKTUR DAN ENGINEERING RULES

Gunakan arsitektur modular dan maintainable.

### Pisahkan domain

- World.
- Map.
- Routing.
- Vehicle.
- Cargo.
- Contracts.
- Employees.
- Depot.
- Warehouse.
- Workshop.
- Finance.
- Insurance.
- Accidents.
- Simulation.
- Save system.

Setiap domain harus memiliki model, service, repository, dan aturan bisnis yang jelas sesuai kebutuhan.

Jangan membuat seluruh game logic di dalam widget Flutter.

Jangan menggabungkan simulasi dengan rendering 3D.

Jangan membuat data kendaraan, barang, kota, atau fasilitas secara hardcoded di banyak tempat.

Gunakan konfigurasi dan data-driven architecture.

Siapkan sistem event internal agar perubahan satu domain dapat memengaruhi domain lainnya secara konsisten.

Contoh:

- Kendaraan rusak memicu perubahan status kendaraan.
- Status kendaraan memengaruhi dispatch.
- Dispatch memengaruhi kontrak.
- Kontrak memengaruhi keuangan.
- Keuangan memengaruhi kemampuan upgrade.

Tambahkan unit test dan integration test untuk sistem simulasi dan ekonomi.

## 22. METODE IMPLEMENTASI

Jangan langsung membangun seluruh game dalam satu tahap.

Saya ingin pengembangan dilakukan secara bertahap dengan fondasi arsitektur yang benar.

### Tahap 1 — Technical Feasibility dan Architecture

Analisis:

- Kelayakan Flutter untuk game ini.
- Pilihan engine 3D.
- Sistem peta offline.
- Format road network.
- Routing lokal.
- Simulasi waktu offline.
- Database.
- Save system.
- Performance Android.

Berikan rekomendasi teknologi dengan alasan teknis.

Identifikasi risiko teknis dan batasan implementasi.

### Tahap 2 — Core Prototype

Implementasikan:

- New Game.
- Pemilihan negara dan wilayah.
- Pemilihan kota.
- Pemilihan depot.
- Depot 3D awal.
- Tiga slot parkir.
- Satu kendaraan niaga ringan.
- Satu sopir.
- Satu kontrak pengiriman.
- Kendaraan keluar dari depot.
- Kendaraan mengikuti jaringan jalan nyata.
- Kendaraan sampai tujuan.
- Kendaraan kembali ke depot.
- Autosave dan load.

### Tahap 3 — Depot Simulation

Implementasikan:

- Parking.
- Gate.
- Loading dock.
- Warehouse.
- Antrean.
- Pekerja.
- Aktivitas kendaraan.
- Upgrade fasilitas.
- Visual upgrade.

### Tahap 4 — Business Simulation

Implementasikan:

- Kontrak.
- Barang.
- Supplier.
- Warehouse inventory.
- Employee.
- Finance.
- Vehicle maintenance.
- Insurance.
- Accident system.

### Tahap 5 — Offline Simulation

Implementasikan:

- Timestamp simulation.
- Event processing.
- Offline progression.
- Recovery.
- Time validation.
- Offline summary.

### Tahap 6 — Expansion

Implementasikan:

- Kendaraan lebih besar.
- Trailer.
- Beberapa depot.
- Ekspansi kota.
- Wilayah lain.
- Sistem transportasi tambahan.

---

## 23. OUTPUT YANG SAYA INGINKAN DARI CLAUDE

Sebelum menulis implementasi, lakukan analisis menyeluruh terhadap spesifikasi ini.

Berikan:

1. Ringkasan visi game.
2. Analisis gameplay loop.
3. Analisis kelayakan teknis.
4. Rekomendasi Flutter dan 3D engine.
5. Rekomendasi sistem offline map.
6. Rekomendasi routing engine.
7. Arsitektur keseluruhan.
8. Struktur folder proyek.
9. Desain database.
10. Desain domain dan hubungan antarsistem.
11. Desain event simulation.
12. Desain offline progression.
13. Desain sistem depot 3D.
14. Desain progression kendaraan dan fasilitas.
15. Strategi optimasi Android.
16. Roadmap implementasi.
17. Risiko teknis dan solusi.

Setelah analisis disetujui, lanjutkan implementasi secara bertahap.

Jangan membuat seluruh sistem sekaligus hanya demi menghasilkan banyak kode.

Setiap tahap harus memiliki hasil yang dapat dijalankan, diuji, dan dievaluasi.

Jika terdapat keputusan teknis yang belum jelas, jelaskan alternatifnya dan berikan rekomendasi sebelum melanjutkan.

Jangan menghilangkan fitur inti hanya karena implementasinya kompleks. Jika suatu fitur perlu disederhanakan untuk tahap awal, desain arsitekturnya tetap harus memungkinkan pengembangan fitur tersebut di masa depan.

> **PRINSIP UTAMA:** Bangun simulasi transportasi yang benar-benar hidup. Pemain bukan hanya membeli kendaraan dan mengumpulkan uang, tetapi mengelola perusahaan logistik yang memiliki armada, pekerja, fasilitas, pelanggan, risiko, dan jaringan distribusi nyata.

Game harus tetap sepenuhnya offline, dapat berkembang dari distribusi kecil antartoko hingga perusahaan transportasi besar, dan memiliki identitas visual serta gameplay yang kuat.
