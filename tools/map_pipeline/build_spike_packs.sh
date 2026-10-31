#!/usr/bin/env bash
# Spike 2a: bangun road graph untuk benchmark routing.
#  - jakarta-kota : detail (termasuk residential), area kota Jakarta
#  - jakarta-bandung : jalan utama saja, koridor Jakarta–Bandung (tol & non-tol)
#  - jawa-utama : jalan utama seluruh Jawa (uji ukuran & waktu A* antar-ibukota)
# Butuh: pip install osmium ; raw/java-latest.osm.pbf (lihat fetch_java.sh)
set -euo pipefail
PBF=raw/java-latest.osm.pbf
python3 build_roads.py "$PBF" --out out/jakarta-kota --bbox 106.68,-6.38,107.00,-6.08 --detail --json
python3 build_roads.py "$PBF" --out out/jakarta-bandung --bbox 106.60,-7.05,107.80,-6.05 --json
python3 build_roads.py "$PBF" --out out/jawa-utama --bbox 105.10,-8.90,114.70,-5.80 --json
