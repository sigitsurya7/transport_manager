#!/usr/bin/env bash
# Peta visual (vector tiles MBTiles) memakai Planetiler (butuh Java 21+).
# Output dipakai flutter_map + vector_map_tiles di aplikasi.
set -euo pipefail
PLANETILER_JAR=${PLANETILER_JAR:-planetiler.jar}
if [ ! -f "$PLANETILER_JAR" ]; then
  curl -L -o "$PLANETILER_JAR" https://github.com/onthegomap/planetiler/releases/latest/download/planetiler.jar
fi
mkdir -p out/id-jawa
java -Xmx4g -jar "$PLANETILER_JAR" --osm-path=raw/java-latest.osm.pbf \
  --output=out/id-jawa/tiles.mbtiles --maxzoom=14 --force
