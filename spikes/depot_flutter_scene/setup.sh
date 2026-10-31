#!/usr/bin/env bash
# Siapkan proyek Android spike flutter_scene. Jalankan dari folder ini.
set -euo pipefail
flutter --version | head -1
if [ ! -d android ]; then
  flutter create --platforms=android --project-name depot_flutter_scene .
  # flutter create menimpa lib/main.dart & menambah file bawaan: kembalikan milik kita
  git checkout -- lib/main.dart
  rm -f test/widget_test.dart analysis_options.yaml README.md .gitignore
fi
# Aktifkan Flutter GPU
MANIFEST=android/app/src/main/AndroidManifest.xml
python3 - "$MANIFEST" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
tag = '<meta-data android:name="io.flutter.embedding.android.EnableFlutterGPU" android:value="true" />'
if "EnableFlutterGPU" not in s:
    i = s.index("<activity")
    s = s[:i] + tag + "\n        " + s[i:]
    open(p, "w").write(s)
PY
python3 ../../tools/depot_glb/make_depot_glb.py assets
flutter pub get
echo "Siap. Jalankan: flutter run --release"
