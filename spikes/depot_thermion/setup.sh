#!/usr/bin/env bash
# Siapkan proyek Android spike Thermion. Jalankan dari folder ini.
set -euo pipefail
flutter --version | head -1
[ -d android ] || flutter create --platforms=android --project-name depot_thermion .
git checkout -- lib/main.dart 2>/dev/null || true
rm -f test/widget_test.dart
python3 ../../tools/depot_glb/make_depot_glb.py assets
flutter pub get
echo "Siap. Jalankan: flutter run --release"
