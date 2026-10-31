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
