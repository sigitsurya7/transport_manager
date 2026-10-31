# Progress

Catatan kemajuan pengembangan Transport Manager. Spesifikasi lengkap: [`MANUAL_INSTRUCTION.md`](MANUAL_INSTRUCTION.md).

## Status saat ini

**Tahap 1 — selesai dan disetujui.** Berikutnya: Tahap 2a (spike teknis).

## Log

### 2026-10-31 — Keputusan Tahap 1 disetujui

- [x] Engine 3D: **flutter_scene** (terbaru, Flutter GPU/Impeller, instancing + LOD bawaan) dengan Flutter master dipin via FVM; **Thermion** (Filament, Flutter stable) sebagai fallback.
- [x] Kota awal dipilih pemain dari 6 ibu kota provinsi Jawa: Jakarta, Serang, Bandung, Semarang, Yogyakarta, Surabaya (satu map pack `id-jawa`).
- [x] Skala waktu: 10 menit nyata = 1 menit game (`timeScale = 0.1`, configurable).
- [x] Catch-up offline maksimal 48 jam nyata.
- [x] Monorepo (`app/`, `packages/`, `tools/`) dan Riverpod.
- [x] `docs/TAHAP_1_ARSITEKTUR.md` diperbarui sesuai keputusan, termasuk tabel dampak skala waktu.

Masih terbuka:
- [ ] Apakah pemain boleh mempercepat waktu saat bermain aktif (usulan: 2×–10×).

### 2026-10-31 — Tahap 1 (draft)

- [x] Master prompt dikonversi menjadi `MANUAL_INSTRUCTION.md`.
- [x] Dokumen analisis & arsitektur `docs/TAHAP_1_ARSITEKTUR.md` (17 poin bagian 23).
- [x] `README.md` dan `.gitignore`.

## Berikutnya — Tahap 2a (spike)

- [ ] Setup monorepo + FVM pin Flutter master.
- [ ] Spike 3D: scene depot yang sama di flutter_scene dan Thermion; ukur fps, memori, waktu load, ukuran APK di HP Android menengah.
- [ ] Spike map pipeline: OSM `id-jawa` → `roads.sqlite` + `tiles.mbtiles`, cakupan 6 ibu kota.
- [ ] Spike routing A* di Isolate: benchmark rute dalam kota dan antar-ibukota (mis. Jakarta → Bandung).
