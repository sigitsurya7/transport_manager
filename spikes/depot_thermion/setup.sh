#!/usr/bin/env bash
# Siapkan proyek Android spike Thermion. Jalankan dari folder ini.
set -euo pipefail
flutter --version | head -1
if [ ! -d android ]; then
  flutter create --platforms=android --project-name depot_thermion .
  # flutter create menimpa lib/main.dart & menambah file bawaan: kembalikan milik kita
  git checkout -- lib/main.dart
  rm -f test/widget_test.dart analysis_options.yaml README.md .gitignore
fi
python3 ../../tools/depot_glb/make_depot_glb.py assets
flutter pub get
echo "Siap. Jalankan: flutter run --release"
