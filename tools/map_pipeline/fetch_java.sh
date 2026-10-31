#!/usr/bin/env bash
# Unduh ekstrak OSM Pulau Jawa dari Geofabrik (± 1 GB). Jalankan di komputer dev, BUKAN saat gameplay.
set -euo pipefail
mkdir -p raw
curl -L -o raw/java-latest.osm.pbf https://download.geofabrik.de/asia/indonesia/java-latest.osm.pbf
echo "Selesai: raw/java-latest.osm.pbf"
