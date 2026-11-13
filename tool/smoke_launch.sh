#!/usr/bin/env bash
# Run under android-emulator-runner, where each script line is executed separately.
# All conditions are run by this single Bash process.
set -euo pipefail
PACKAGE="com.zipease.zipease"
APK="smoke-apk/app-release.apk"
LOG="zipease-launch.log"

test -s "$APK" || { echo "::error::APK artifact missing"; exit 1; }
adb install -r "$APK"
adb logcat -c
echo "Starting ZipEase..."
# am start -W can time out on a slow emulator. Verify the actual process.
adb shell am start -W -n "$PACKAGE/.MainActivity" || true
sleep 15
adb logcat -d > "$LOG" || true
adb exec-out screencap -p > zipease-launch.png || true
echo "Foreground activity state:"
adb shell dumpsys activity activities | grep -E "ResumedActivity|topResumedActivity|mResumedActivity|mFocusedApp" | tail -20 || true

if ! adb shell pidof "$PACKAGE" >/dev/null 2>&1; then
  echo "::error::ZipEase process exited during cold start"
  grep -E "FATAL EXCEPTION|AndroidRuntime|flutter|$PACKAGE" "$LOG" | tail -160 || true
  exit 1
fi

# Process alive is insufficient if no ZipEase activity is displayed.
ACTIVITY_INFO="$(adb shell dumpsys activity activities || true)"
if ! echo "$ACTIVITY_INFO" | grep -E "(ResumedActivity|topResumedActivity|mResumedActivity).*$PACKAGE" >/dev/null; then
  WINDOW_INFO="$(adb shell dumpsys window || true)"
  if ! echo "$WINDOW_INFO" | grep -E "mCurrentFocus.*$PACKAGE|mFocusedApp.*$PACKAGE" >/dev/null; then
    echo "::error::ZipEase process exists but no ZipEase activity is resumed"
    grep -E "FATAL EXCEPTION|AndroidRuntime|flutter|$PACKAGE" "$LOG" | tail -160 || true
    exit 1
  fi
fi
# Verify Android exposes ZipEase as an eligible ZIP ACTION_VIEW target.
# This detects missing Open with manifest registrations in future releases.
echo "Checking Android ZIP Open with registration..."
VIEW_HANDLERS="$(adb shell cmd package query-activities --brief -a android.intent.action.VIEW -t application/zip -d content://com.android.externalstorage.documents/document/primary%3ADownload%2Fsample.zip || true)"
echo "$VIEW_HANDLERS"
if ! echo "$VIEW_HANDLERS" | grep -F "$PACKAGE" >/dev/null; then
  echo "::error::ZipEase is not registered as a ZIP Open with activity."
  exit 1
fi
echo "ZipEase cold-start and ZIP Open with registration passed."
