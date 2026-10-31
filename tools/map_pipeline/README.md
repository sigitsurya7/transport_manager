# Map pipeline

Mengubah data OpenStreetMap menjadi paket peta offline untuk game. Dijalankan di komputer dev, hasilnya dibundel ke aplikasi. Tidak ada unduhan saat gameplay.

| File | Fungsi |
|---|---|
| `build_roads.py` | OSM (.osm / .osm.pbf) → `roads.sqlite` (+ `graph.json`) untuk routing |
| `fetch_java.sh` | Unduh ekstrak OSM Pulau Jawa dari Geofabrik |
| `build_spike_packs.sh` | Graph untuk benchmark Tahap 2a (kota Jakarta, koridor Jakarta–Bandung, Jawa jalan utama) |
| `build_tiles.sh` | Vector tiles `tiles.mbtiles` via Planetiler |
| `data/id-jawa.cities.json` | 6 ibu kota provinsi Jawa + kandidat lokasi depot (perlu verifikasi) |

## Pakai

```bash
pip install osmium
./fetch_java.sh
./build_spike_packs.sh
# benchmark routing (Dart)
cd ../../packages/sim_core && dart run bin/route_bench.dart ../../tools/map_pipeline/out/jakarta-bandung/graph.json
```

## Isi graph

- Node hanya di persimpangan dan ujung ruas; node OSM di tengah ruas disimpan sebagai geometri polyline (precision 6).
- Edge berarah; jalan dua arah → dua edge. `oneway`, roundabout, dan motorway dihormati.
- Atribut: panjang (m), kelas jalan, `maxspeed` (default per kelas), `toll` (motorway dianggap tol kecuali `toll=no`), `maxweight` (ton).
- Tanpa `--detail`, hanya jalan `motorway`…`tertiary` yang dimasukkan.

## Test

```bash
python3 -m unittest discover -s tests
```

Data © OpenStreetMap contributors, lisensi ODbL. Atribusi wajib tampil di layar peta game.
