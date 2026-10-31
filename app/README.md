# Transport Manager — app

Aplikasi Flutter. Logika game ada di `packages/sim_core`; app hanya UI, render, dan penyimpanan.

```bash
bash ../tools/sync_app_assets.sh   # wajib sebelum build: konten, model 3D, map pack
flutter run --release
```

| Folder | Isi |
|---|---|
| `lib/game/` | `GameSession`: jam game, autosave, catch-up offline |
| `lib/features/` | Layar: menu, permainan baru, depot 3D, peta, kontrak, keuangan |
| `lib/data/` | Pemuat konten, kota, map pack |
| `lib/platform/` | Jam monotonic Android (MethodChannel) |
