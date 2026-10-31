# Instruksi dari User

Log perintah dan keputusan yang diberikan langsung oleh user di luar `MANUAL_INSTRUCTION.md`. Urutan kronologis, waktu WIB.

## 2026-10-31 10:45 — Cara kerja

> Fokus per tahap dahulu, jika sekiranya sudah.
> Kau bisa commit kerjaan mu ke github. Buat master prompt di atas menjadi manual instruction md dan di push ke git lalu apa yang sudah kau kerjakan letakan di progress.md.
>
> https://github.com/sigitsurya7/transport_manager

## 2026-10-31 10:50 — Keputusan Tahap 1

> Spike perbandingan engine 3D gunakan yang terbaik dan terbarukan.
>
> Kota awal user bisa memilih dan saran saya ada di seluruh ibukota di pulau jawa terlebih dahulu
>
> Skala waktu terbalik: 10 menit di dunia nyata = 1 menit in game. Catch-up offline maksimal di 48Jam.
>
> Ya, boleh *(monorepo & Riverpod)*

## 2026-10-31 10:57 — Koreksi skala waktu, rute, jangkauan pengiriman, percepatan waktu

> Nyatanya jakarta bandung hanya berjarak 2 jam saja -,-! Jadi in game hanya 12 Menit saja. Coba rute yang di ambil bisa rute tol atau rute non tol.
>
> Pengiriman dari toko ke toko hanya pengiriman jarak dekat bukan antar kota, pengiriman antar kota harusnya menggunakan mobil yang lebih besar truk mini ke atas. Pengiriman bisa di dalam kota sampai keluar kota.
>
> Siapkan saja, namun nantinya ada micro transaksi di sana atau menggunakan ads untuk menggunakan 2x > 10x kecepatan. Jangan di terapkan terlebih dahulu.

Interpretasi yang dipakai: perjalanan nyata 2 jam = 12 menit waktu main, artinya **1 menit nyata = 10 menit game** (`timeScale = 10`).

## 2026-10-31 11:04 — Lanjut tahap berikutnya

> Sudah ku jalankan. Dan jalankan ke tahap selanjutnya

## 2026-10-31 11:15 — Push

> Push saja ke git, dan push juga command yang tadi ku berikan

## 2026-10-31 11:19 — Tahap 2a

> Lanjutkan tahap 2a, lalu push ke github

## 2026-10-31 — Lanjutkan pengerjaan

> Baca MANUAL_INSTRUCTION.md dan progress.md sebelum melanjutkan.
> Jika sudah lanjutkan pengerjaan.

## 2026-10-31 — HP terhubung

> Aku sudah menghubungkan HP Android, jadi kau bisa menjalankan spike.
> Aku sudah menjalankan 1 sampai point ke dua

## 2026-10-31 — Data peta kecil untuk benchmark routing

> Pakai data yang lebih kecil untuk benchmark routing.

## 2026-10-31 — Lewati benchmark routing

> Jika masih lama skip saja pengantarannya atau mengukur waktu tempuhnya. Nanti ku carikan logic yang bagus. Sekarang kerjakan yang lain saja

Interpretasi: benchmark routing dengan data nyata ditunda (unduhan Overpass dihentikan; ubin yang sudah lengkap disimpan). Logika estimasi waktu tempuh akan ditinjau ulang bersama user.

## 2026-10-31 — Engine final & arah visual

> Ya lanjutkan, gunakan saja model 3D yang mudah dan tidak terlalu rumit. Yang terpenting adalah hasil 3D dan rendernya terlihat bagus, siap di publish serta tidak berat sama sekali.

Keputusan: **flutter_scene** jadi engine final (Thermion tidak dilanjutkan). Arah visual: low-poly bergaya, warna flat yang rapi + pencahayaan, jumlah segitiga kecil, tanpa tekstur besar.

## 2026-10-31 — Install via USB

> Sudah ku aktifkan Install via USB, coba pasang lagi

## 2026-10-31 — Tahap 3 + temuan uji HP

> Lanjutkan ke Tahap 3,
> Mobil sudah kembali namun saat masuk ke depot mobil malah mundur dan palang / gate tidak terbuka.

## 2026-10-31 — Perbaikan aset 3D & ikon

> Ada bangunan yang menutupi jalan.
> Bedakan mobil pickup, mobil box, mobil container kecil dan lain sebagainya.
>
> Mobil menabrak bangunan, pastikan tidak ada bangunan atau properti lain yang menabrak.
>
> Buat aset itu terlebih dahulu. Dan untuk icon jangan generic.

## 2026-10-31 — Sebelum Tahap 4: model, animasi muat, peta, dekorasi, mode dev

> Model 3D kendaraan juga berbeda, mobil pikap, mobil box, truk mini, truk engkel.
>
> Buat animasi saat load barang, seperti menaikan barang ke mobil, mobil kosong dan mobil terisi. Lalu ada manusia yang loading barang.
>
> Pada peta ada garing orange, hapus saja garis orange. jika tidak ada kontrak di jalankan maka kosong pada map.
>
> Tambahkan beberapa model 3D agar di tab depot tidak terlalu kosong.
>
> Tambahkan mode dev yang bisa menambahkan uang.

## 2026-10-31 — Lanjutkan

> lanjutkan

## 2026-10-31 — Bilah atas, waktu upgrade, lanjut Tahap 4

> Untuk topBar kau bisa buat...
> Paling Kiri ada Hari x . Waktu in game
> Paling Kanan Uang dan tombol pengaturan.
>
> Hapus saja button kembali dan button keluar. ganti dengan button Pengaturan. Waktu upgrade sangat lama.
>
> Setelah itu lanjut ke tahap 4.

## 2026-10-31 — Master task: perluasan katalog kendaraan & perombakan visual depot

> (Instruksi panjang berbahasa Inggris, diringkas.) Audit dulu sebelum mengubah. Perluas katalog kendaraan di setiap kategori (pikap, van, truk mini, truk ringan, truk sedang, truk berat rigid, tractor head, kendaraan khusus) dengan model yang benar-benar berbeda bentuknya (bukan ganti warna). Data tiap kendaraan: id, nama, kategori/subkategori, harga, biaya operasi, kapasitas & jenis muatan, dimensi & tapak parkir, kecepatan, BBM, perawatan, syarat buka/tier, referensi model, bodi/trailer/kontainer yang kompatibel. Pisahkan sasis, bodi muatan, trailer, kontainer dengan data kompatibilitas eksplisit dan validasi. Tingkatkan kualitas visual depot (lantai, marka parkir, area muat, gudang, dock, gerbang, pagar, jalan, kantor, bengkel, pencahayaan, umpan balik slot terisi/kosong) dan props industri; upgrade fasilitas harus terlihat berubah sesuai data; pertahankan progres awal 3 slot. Pilih satu arah visual yang konsisten (low-poly bergaya atau voxel). Aset pihak ketiga boleh bila lisensinya diverifikasi & didokumentasikan; bila tidak, buat model orisinal lewat generator. Integrasikan dengan gameplay (beli, sopir, dispatch, parkir, muat, gerbang, rute, perawatan, save/load, offline). Dealer dengan navigasi kategori, thumbnail, perbandingan. Optimasi untuk HP. Tambah test (katalog, referensi aset, kompatibilitas, data upgrade). Laporan akhir lengkap.
>
> Jalankan saja semuanya langsung. sampai selesai.

## 2026-10-31 22:57 — Revisi alur kontrak, gudang, jual-beli armada, level 15, depot hidup

> Tapi di sistem warehouse tuh ada yang salah.
>
> Kontrak itu terjadi seperti ini alurnya...
> Jadi A ( Supplier Mang Engking ) minat sama jasa kita buat nganter barang ke B ( Warung mang ujang ), jadi kita cuma keluar dari depot ke poin A terus nganter ke poin B. Bukan loading di depot, karna apa ? Yak, betul. Warehouse kita belum punya apa-apa.
>
> Nah kontrak ini ada yang sekali jalan dan ada yang berkelanjutan. Mis. Berkelanjutan jadi tiap hari / minggu / beberapa hari sekali mengirim barang dari poin yang uda di tentukan dengan mobil yang sama.
>
> Klo warehouse kita buat apa ? Nah, warehouse kita itu di fungsikan untuk nyimpen barang. Misal Toko indojuni minta barang A, B, C, nah di warehouse belum ada barangnya atau cuma ada barang A, atau B, atau C aja. Yauda berarti loading barang yang ada di warehouse terus sisanya ngambil barang ke supplier yang ada. Berarti modal lagi tuh 😂 beda cerita klo barangnya ada di warehouse. Jadi bisa ambil langsung di warehouse.
>
> Nah ada lagi yang kurang.
> Jual beli armada.
>
> Kadang gini bre.... Misal usaha lagi jatuh banget kan mau gamau armada ada yang di jual ( sesuai odo meter dan kondisi serta tahun produksi ) nah pas uda dijual beli yang lebih murah tapi bekas. Atau ikutan lelang, nah lelang ini ( next feature ) wkwk
>
> Terus untuk lv nya sekarang baru 3. Gue pengen lvnya tuh sampe 15. Jadi bener2 depot itu kaya terminal nantinya 🤣 Warehouse yang gede, kantor yang gede. Jadi tiap upgrade ga melulu soal visual, ada yang upgrade tapi cuma nambah stat aja. Dan ada yang upgrade sekalian ganti wajah. Terus di tambah area depot yang hidup, sebab yang sekarang area depot hidup hanya saat mobil di tugaskan aja.
>
> Kerjakan sampai kuota mingguan maksimum ada di 70% jika sudah menyentuh atau lebih maka stop dan berikan point untuk resumenya

Desain: `docs/TAHAP_4_REVISI.md`. Catatan: Claude tidak bisa melihat sisa kuota user, jadi pekerjaan dipecah per bagian dengan commit di setiap bagian dan titik resume di `progress.md`.
