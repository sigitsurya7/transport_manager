# Progress

Catatan kemajuan pengembangan Transport Manager. Spesifikasi lengkap: [`MANUAL_INSTRUCTION.md`](MANUAL_INSTRUCTION.md).

## Status saat ini

**Tahap 1 — selesai dan disetujui.** Berikutnya: Tahap 2a (spike teknis).

## Log

### 2026-10-31 — Keputusan Tahap 1 disetujui

- [x] Engine 3D: **flutter_scene** (terbaru, Flutter GPU/Impeller, instancing + LOD bawaan) dengan Flutter master dipin via FVM; **Thermion** (Filament, Flutter stable) sebagai fallback.
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

## Berikutnya — Tahap 2a (spike)

- [ ] Setup monorepo + FVM pin Flutter master.
- [ ] Spike 3D: scene depot yang sama di flutter_scene dan Thermion; ukur fps, memori, waktu load, ukuran APK di HP Android menengah.
- [ ] Spike map pipeline: OSM `id-jawa` → `roads.sqlite` + `tiles.mbtiles`, cakupan 6 ibu kota.
- [ ] Spike routing A* di Isolate: benchmark rute dalam kota dan antar-ibukota (mis. Jakarta → Bandung), mode tol dan non-tol.
