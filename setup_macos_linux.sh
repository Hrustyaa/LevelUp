#!/usr/bin/env bash
# Run from the Flutter project root after copying files from this kit.
set -euo pipefail
GRADLE=android/app/build.gradle.kts
if [ ! -f "$GRADLE" ]; then echo "Create the Flutter project first" >&2; exit 1; fi
python3 - <<'PY'
from pathlib import Path
p=Path('android/app/build.gradle.kts'); s=p.read_text()
s=s.replace('compileSdk = flutter.compileSdkVersion','compileSdk = 36')
s=s.replace('targetSdk = flutter.targetSdkVersion','targetSdk = 36')
s=s.replace('minSdk = flutter.minSdkVersion','minSdk = 24')
p.write_text(s)
PY
flutter pub get
