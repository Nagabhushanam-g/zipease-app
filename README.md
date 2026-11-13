# ZipEase · Free ZIP & UnZIP for Android

A separate Flutter Android project for secure on-device ZIP compression and extraction, with **Google AdMob test ads** and a GitHub Actions APK build.

## What works in this MVP source

- Create ZIP from multiple files chosen with Android's standard file picker.
- Extract ZIP files, including password-protected ZIP files (when a valid password is provided).
- Prevent obvious ZIP path traversal, symlink extraction, duplicate paths, oversized archives (1 GiB cap), and excessive entries.
- Preview extracted files and export the **entire folder** into a user-selected Android folder (preserving the hierarchy).
- Save newly created ZIP files to a user-selected Android location.
- Offline ZIP processing. **Only ads need internet**.
- AdMob TEST banner and TEST interstitial, with interstitial no more often than every fourth successful export.
- CI builds an installable, debug-key-signed release APK suitable for internal testing.
- Automatic cleanup of older `zipease-apk-*` artifacts, keeping 10 newest from successful workflow runs after a successful upload.

## Publish this project on GitHub

Create a **new empty repository** called `zipease-app` in your GitHub account, with no README, and upload these files **preserving `.github/workflows/build-apk.yml`**. You can instead use the Git CLI:

```bash
git init -b main
git add .
git commit -m "Initial ZipEase Flutter MVP and APK CI"
git remote add origin https://github.com/Nagabhushanam-g/zipease-app.git
git push -u origin main
```

See **Actions → Build ZipEase APK**, open a successful run, then download artifact `zipease-apk-<run number>`. Unzip the downloaded artifact and install `app-release.apk` on Android.

**No APK is bundled in this source download.** GitHub Actions produces one after a successful run.

## Build locally

Install current Flutter stable (Dart 3.10+), Android SDK, and Java 17. Then:

```bash
bash tool/bootstrap_android.sh
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter build apk --release
```

Android scaffolding is intentionally generated from the installed Flutter SDK to avoid outdated Gradle/AGP templates. The bootstrap script installs the Kotlin SAF exporter and the AdMob Android test app ID into the generated project. Run the bootstrap after changing Flutter SDK templates or when `android/` is missing. Existing `android/` files are not destroyed by `flutter create` unless deliberately overwritten.

## AdMob

All three IDs are **Google's public test IDs**, not accounts owned by this project:

- Android test App ID: `ca-app-pub-3940256099942544~3347511713` (in `tool/configure_android.py`)
- Android test banner unit: `ca-app-pub-3940256099942544/6300978111`
- Android test interstitial unit: `ca-app-pub-3940256099942544/1033173712`

To go live: register your own AdMob app, replace the test App ID and ad units, implement Google UMP consent where required, prepare app-ads.txt, complete Play Store Data Safety / privacy declarations, and test using registered test devices before allowing real ads. Never click your own live ads.

## Android file access

ZipEase uses Android's **Storage Access Framework (SAF)** through a Flutter file picker for inputs and Android native document/folder pickers for exported outputs. It deliberately requests **neither `MANAGE_EXTERNAL_STORAGE` nor `READ_EXTERNAL_STORAGE`**. Source files stay local; the native exporter uses streaming rather than loading an entire output ZIP into RAM.

## Important MVP limitations

- **ZIP only**; RAR and 7z are not implemented.
- No ZIP password creation yet; password-protected ZIP *extraction* is supported.
- ZIP extraction currently has a 1 GiB uncompressed safety limit; large ZIPs require additional stress tests and configurable limits.
- The app has not been device-tested as part of this source packaging. GitHub CI must be run and any errors fixed before distribution.
- A production Play Store build requires a private, consistent release signing key. CI's default debug-key-signed release artifact is for testing, not publication.
- Production ads need appropriate privacy/consent controls and live ad configuration.
- For reliable Android export, choose a local device folder with sufficient free space. Some remote document providers may behave differently.

## Independent repository

This project contains no Firebase credentials and does not alter RideGo, ApkForge, or other projects.