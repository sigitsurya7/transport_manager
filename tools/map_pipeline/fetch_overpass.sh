#!/usr/bin/env bash
# Alternatif kecil untuk fetch_java.sh: ambil jalan per bbox dari Overpass API.
# Cukup untuk benchmark routing spike 2a; map pack id-jawa final tetap dibangun
# dari ekstrak Geofabrik.
#  - jakarta-pusat   : ±11×11 km, semua kelas termasuk residential/unclassified
#  - jakarta-bandung : jalan utama saja (tol & non-tol)
# Tiap area dipecah jadi ubin kecil (koneksi lambat sering memutus respons
# besar), diunduh dengan retry, lalu digabung oleh merge_osm.py.
# Lalu: python3 build_roads.py raw/<nama>.osm.pbf --out out/<nama> --json [--detail]
set -euo pipefail
OVERPASS=${OVERPASS:-https://overpass-api.de/api/interpreter}
UA="transport_manager-map-pipeline/0.1 (+https://github.com/sigitsurya7/transport_manager)"
mkdir -p raw/tiles

# fetch <nama> <regex highway> <min_lon,min_lat,max_lon,max_lat> <kolom> <baris>
fetch() {
  local name=$1 classes=$2 cols=$4 rows=$5
  IFS=, read -r w s e n <<<"$3"
  local files=()
  for ((r = 0; r < rows; r++)); do
    for ((c = 0; c < cols; c++)); do
      read -r tw ts te tn < <(awk -v w="$w" -v s="$s" -v e="$e" -v n="$n" -v c=$c -v r=$r -v C="$cols" -v R="$rows" \
        'BEGIN { dx = (e - w) / C; dy = (n - s) / R; printf "%.5f %.5f %.5f %.5f\n", w + c*dx, s + r*dy, w + (c+1)*dx, s + (r+1)*dy }')
      local f="raw/tiles/$name-$r-$c.osm"
      files+=("$f")
      if [ -s "$f" ] && tail -c 20 "$f" | grep -q "</osm>"; then continue; fi
      local q="[out:xml][timeout:600];way[\"highway\"~\"^(${classes})\$\"](${ts},${tw},${tn},${te});(._;>;);out body;"
      for attempt in 1 2 3 4 5; do
        echo "Unduh $f (percobaan $attempt)"
        if curl -sS --fail -A "$UA" --data-urlencode "data=$q" -o "$f" "$OVERPASS" &&
          tail -c 20 "$f" | grep -q "</osm>"; then
          break
        fi
        rm -f "$f"
        sleep $((attempt * 10))
      done
      [ -s "$f" ] || { echo "Gagal: $f" >&2; exit 1; }
    done
  done
  python3 merge_osm.py "raw/$name.osm.pbf" "${files[@]}"
}

MAIN='motorway|motorway_link|trunk|trunk_link|primary|primary_link|secondary|secondary_link|tertiary|tertiary_link'
fetch jakarta-bandung "$MAIN" 106.60,-7.05,107.80,-6.05 3 3
fetch jakarta-pusat "$MAIN|unclassified|residential" 106.78,-6.25,106.88,-6.15 2 2
