#!/usr/bin/env bash
# Salin data yang dibutuhkan app ke app/assets (hasilnya tidak di-commit):
#  - content/*.json            → assets/content/
#  - data kota                 → assets/data/cities.json
#  - model 3D (dibuat ulang)   → assets/models/
#  - graph kota yang tersedia  → assets/packs/<kota>.graph.json + assets/data/packs.json
# Graph kota dibangun oleh tools/map_pipeline (out/<kota>/graph.json).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
A="$ROOT/app/assets"
PY=$(command -v python3 || command -v python)
rm -rf "$A/packs"
mkdir -p "$A/content" "$A/data" "$A/models" "$A/packs"
cp "$ROOT"/content/*.json "$A/content/"
cp "$ROOT/tools/map_pipeline/data/id-jawa.cities.json" "$A/data/cities.json"
"$PY" "$ROOT/tools/depot_glb/make_depot_glb.py" "$A/models" > /dev/null

packs=()
for city in jakarta serang bandung semarang yogyakarta surabaya; do
  src="$ROOT/tools/map_pipeline/out/$city/graph.json"
  if [ -f "$src" ]; then
    cp "$src" "$A/packs/$city.graph.json"
    packs+=("\"$city\"")
  fi
done
(IFS=,; echo "{\"cities\": [${packs[*]:-}]}") > "$A/data/packs.json"
echo "Aset app disinkronkan. Paket kota: ${packs[*]:-(tidak ada)}"
