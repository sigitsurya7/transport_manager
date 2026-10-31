# Progress

Catatan kemajuan pengembangan Transport Manager. Spesifikasi lengkap: [`MANUAL_INSTRUCTION.md`](MANUAL_INSTRUCTION.md).

## Status saat ini

**Tahap 1 — Technical Feasibility & Architecture: draft selesai, menunggu persetujuan.**

## Log

### 2026-10-31 — Tahap 1

Selesai:
- [x] Master prompt dikonversi menjadi `MANUAL_INSTRUCTION.md` (format Markdown, isi tidak diubah).
- [x] Dokumen analisis & arsitektur `docs/TAHAP_1_ARSITEKTUR.md`, mencakup 17 poin di bagian 23 spesifikasi:
  visi, gameplay loop, kelayakan teknis, engine 3D, offline map, routing, arsitektur, struktur folder,
  database, domain, event simulation, offline progression, depot 3D, progression, optimasi Android, roadmap, risiko.
- [x] `README.md` dan `.gitignore`.

Rekomendasi utama:
- Simulation core sebagai package Dart murni (`packages/sim_core`), event-driven & deterministik.
- Depot 3D: Thermion/Filament (primer), Flame 2.5D (fallback), di balik interface `DepotSceneRenderer`.
- Peta: `flutter_map` + MBTiles (vector tiles); road graph terpisah di SQLite dari OSM, routing A* di Isolate.
- Save: Drift, satu file SQLite per slot; uang integer rupiah, waktu int64 detik.
- Offline: catch-up event queue + validasi monotonic clock, batas 72 jam.

Menunggu keputusan (lihat akhir `docs/TAHAP_1_ARSITEKTUR.md`):
- [ ] Engine 3D (setujui spike Thermion vs Flame).
- [ ] Kota awal prototype (usul: Surabaya atau Bandung).
- [ ] Skala waktu game (usul: 1 menit nyata = 10 menit game).
- [ ] Monorepo & Riverpod.

## Berikutnya

Tahap 2a — spike teknis: renderer 3D di HP Android target dan routing A* pada graph kota nyata, lalu Tahap 2b core prototype.
