#!/usr/bin/env bash
# Generates the Android project with the CI-installed Flutter SDK and adds
# ZipEase's Android Storage Access Framework exporter and AdMob TEST config.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --no-pub --platforms=android --org=com.zipease --project-name=zipease .

mkdir -p android/app/src/main/kotlin/com/zipease/zipease
cp platform/android/MainActivity.kt android/app/src/main/kotlin/com/zipease/zipease/MainActivity.kt
mkdir -p android/app/src/main/res/xml
cp platform/android/zipease_share_paths.xml android/app/src/main/res/xml/zipease_share_paths.xml
python3 tool/configure_android.py

echo "Android project configured for ZipEase."
