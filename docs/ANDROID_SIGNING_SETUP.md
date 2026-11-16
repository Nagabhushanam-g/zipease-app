# ZipEase permanent Android release signing

ZipEase uses Android application ID `com.zipease.zipease`. Android can update an installed app only when the application ID and signing certificate are compatible and the new APK has an acceptable version code. Previous CI releases were generated using Flutter's debug signing configuration and a constant versionCode of 1; those builds might be signed with different ephemeral debug keys.

## Set up the permanent signing key (repository owner)

The release key is **private**. Never commit the `.p12` file, its base64 contents, or the password to GitHub source, an issue, or a public artifact. Keep two offline backups of the keystore and password.

1. Obtain the private signing kit supplied to the repository owner outside GitHub source. It contains `zipease-release.p12`, `ZIPEASE_RELEASE_KEYSTORE_BASE64.txt`, and `ZIPEASE_RELEASE_PASSWORD.txt`.
2. Open `https://github.com/Nagabhushanam-g/zipease-app/settings/secrets/actions`.
3. Create an **Actions repository secret** named `ZIPEASE_RELEASE_KEYSTORE_BASE64`. Paste the *complete one-line contents* of `ZIPEASE_RELEASE_KEYSTORE_BASE64.txt` as its value.
4. Create another Actions repository secret named `ZIPEASE_RELEASE_PASSWORD`. Paste the password from `ZIPEASE_RELEASE_PASSWORD.txt` as its value.
5. Re-run the latest "Build ZipEase APK" workflow from **Actions**. The workflow refuses to publish an APK when secrets are missing or the keystore fingerprint is not the intended one.

Signing alias: `zipease`, keystore type: PKCS12, certificate SHA-256:
`36:79:85:1B:F5:5D:7A:48:9C:71:64:0F:A3:2B:8C:88:E0:28:CD:AF:8C:27:FB:16:F6:94:5B:D7:F6:1D:F0:E3`.

The Gradle configuration reads the private keystore file and password from the CI environment. The workflow uses `--build-number="$GITHUB_RUN_NUMBER"` so Android versionCode increases automatically with every run; it does not depend on the fixed pubspec development version.

## Migrating from previous APKs

A previous ZipEase APK installed on the phone may have been signed by a different, runner-specific debug signing key. If so, Android **cannot** install the first permanently signed release over that APK. Changing only the version code cannot fix a signing mismatch.

Before the **one-time** uninstall, open the existing ZipEase app, export created ZIPs and extracted folders to a device folder such as Downloads, and independently verify those files in the phone's file manager. Uninstalling deletes private My Files data. Then install the first APK successfully signed by the new permanent key.

Do not uninstall for later updates: install future APKs signed with **this same release key** and an incremented versionCode over the existing app. Keep the application ID `com.zipease.zipease` unchanged.

This signing key must be preserved for the lifetime of the app. If it is lost, Android APK upgrade continuity will be broken again. For Google Play, review Play App Signing and the appropriate upload-key model separately.

## Verifying on Android

From a machine with adb and two APKs signed with this release key:

```bash
adb install first-permanently-signed.apk
adb install -r next-permanently-signed.apk
```

The second install should print `Success` and preserve application data.

Do not add the keystore or password to the repository, pull requests, logs, or GitHub Actions artifacts.
