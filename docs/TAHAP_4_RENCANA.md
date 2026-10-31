# Tahap 4 — Business Simulation: rencana

Dipecah menjadi bagian kecil yang masing-masing dapat dijalankan, diuji, dan dievaluasi. Urutan dipilih agar setiap bagian langsung memengaruhi bagian berikutnya (rantai sebab-akibat di §10 dokumen arsitektur).

| # | Bagian | Isi | Bergantung pada |
|---|---|---|---|
| 4.1 | **Perawatan kendaraan** | Keausan 7 komponen (mesin, transmisi, rem, ban, suspensi, pendingin, kelistrikan) per km & beban; kondisi memengaruhi BBM & kecepatan; servis/ganti ban/perbaikan/overhaul dengan biaya & durasi; fasilitas **bengkel** (tanpa bengkel = servis luar, lebih mahal & lama); kendaraan di bengkel tidak bisa ditugaskan | — |
| 4.2 | **Karyawan** | Sopir: skill, pengalaman, kelelahan, istirahat wajib; mekanik mempercepat servis; gaji per skill | 4.1 |
| 4.3 | **Kecelakaan & asuransi** | Laju bahaya per leg (kondisi kendaraan, kelelahan, kelas jalan, muatan) → satu sampel kejadian (eksponensial, deterministik); mogok/ban pecah/tabrakan/kerusakan barang; indikator risiko sebelum dispatch; polis (premi, masa berlaku, deductible, batas, pengecualian) & klaim | 4.1, 4.2 |
| 4.4 | **Barang & kontrak** | Kategori barang & kebutuhan bodi (bak terbuka / box / berpendingin), mudah rusak, kedaluwarsa; kontrak berulang, multi-toko, antarkota (mini truck ke atas); reputasi pelanggan | 4.3 |
| 4.5 | **Supplier & gudang** | Beli barang dari supplier, stok di gudang (kapasitas m³ dari level gudang), pesanan toko dipenuhi dari stok; barang rusak/kedaluwarsa | 4.4 |
| 4.6 | **Keuangan** | Laporan laba rugi per periode, arus kas, aset (nilai kendaraan menyusut, inventaris, depot), liabilitas; penyeimbangan ekonomi | 4.1–4.5 |

Prinsip yang tetap berlaku: simulasi hanya di `sim_core` (Dart murni, deterministik, teruji), konten data-driven di `content/`, save kompatibel ke belakang (migrasi), renderer & UI hanya membaca state.
