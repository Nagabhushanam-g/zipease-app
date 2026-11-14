#!/usr/bin/env python3
"""Patch the generated Flutter Android project without broad storage permissions."""
from pathlib import Path
import re

manifest = Path("android/app/src/main/AndroidManifest.xml")
if not manifest.exists():
    raise SystemExit("Run flutter create before configuring Android.")
xml = manifest.read_text(encoding="utf-8")
if "android.permission.INTERNET" not in xml:
    xml = xml.replace(
        "<application",
        '    <uses-permission android:name="android.permission.INTERNET" />\n    <application',
        1,
    )
if "com.google.android.gms.ads.APPLICATION_ID" not in xml:
    xml = xml.replace(
        "</application>",
        '    <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID"\n'
        '        android:value="ca-app-pub-3940256099942544~3347511713" />\n'
        "    </application>",
        1,
    )
xml, count = re.subn(
    r'android:label="[^"]*"',
    'android:label="ZipEase"',
    xml,
    count=1,
)
if count != 1:
    raise SystemExit("Could not locate Flutter Android application label.")
if "MANAGE_EXTERNAL_STORAGE" in xml or "READ_EXTERNAL_STORAGE" in xml:
    raise SystemExit("Broad storage permissions are not permitted.")

# Android ZIP association: VIEW is for "Open with"; SEND is for "Share".
# MIME-only filters match local content:// and file:// URIs. In contrast,
# ACTION_SEND normally has no data URI (it uses EXTRA_STREAM), so its filter
# must not require a URI scheme. Other formats inside ZIPs are handled as bytes.
if 'android.intent.action.VIEW' not in xml or 'android.intent.action.SEND' not in xml:
    filters = """
            <!-- ZIP files opened from Files, Downloads or other apps. -->
            <intent-filter android:label="ZipEase">
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="application/zip" />
                <data android:mimeType="application/x-zip-compressed" />
                <data android:mimeType="application/x-zip" />
                <data android:mimeType="application/octet-stream" />
                <data android:mimeType="application/x-compressed" />
            </intent-filter>

            <!-- ZIP files shared via Android's share sheet. -->
            <intent-filter android:label="ZipEase">
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="application/zip" />
                <data android:mimeType="application/x-zip-compressed" />
                <data android:mimeType="application/x-zip" />
                <data android:mimeType="application/octet-stream" />
                <data android:mimeType="application/x-compressed" />
            </intent-filter>
            <meta-data
                android:name="flutter_deeplinking_enabled"
                android:value="false" />
"""
    activity = re.search(
        r'(?s)(<activity\b[^>]*\bandroid:name="\.MainActivity"[^>]*>)(.*?)(</activity>)',
        xml,
    )
    if activity is None:
        raise SystemExit("Flutter MainActivity not found for ZIP intent registration.")
    if 'android:exported="true"' not in activity.group(1):
        raise SystemExit("MainActivity must be exported to handle external ZIP files.")
    xml = xml[:activity.start(3)] + filters + xml[activity.start(3):]


# A private FileProvider supplies short-lived read-only content:// URIs to
# Android viewers, share targets and the system APK installer.
if 'androidx.core.content.FileProvider' not in xml:
    provider_tag = """
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="__APPLICATION_ID__.zipease_files"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/zipease_share_paths" />
        </provider>
""".replace("__APPLICATION_ID__", "$" + "{applicationId}")
    xml = xml.replace("</application>", provider_tag + "</application>", 1)

# Required only for explicitly user-initiated APK installation via Android's
# system installer. A Play Store release must justify this permission under
# the restricted REQUEST_INSTALL_PACKAGES policy for file-management apps.
if "android.permission.REQUEST_INSTALL_PACKAGES" not in xml:
    xml = xml.replace(
        "<application",
        '    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />\n    <application',
        1,
    )

manifest.write_text(xml, encoding="utf-8")

# Android/WorkManager/Room R8 reflective-constructor compatibility rules.
gradle = Path("android/app/build.gradle.kts")
if not gradle.exists():
    raise SystemExit("Expected Flutter Android Kotlin DSL build.gradle.kts.")
gradle_source = gradle.read_text(encoding="utf-8")
rule_line = 'proguardFiles("proguard-rules.pro")'
if rule_line not in gradle_source:
    match = re.search(r"(?m)^([ \t]*)release[ \t]*\{[ \t]*$", gradle_source)
    if match is None:
        raise SystemExit("Could not find the Android release build type.")
    insert_at = match.end()
    gradle_source = (
        gradle_source[:insert_at]
        + "\n"
        + match.group(1)
        + "    "
        + rule_line
        + gradle_source[insert_at:]
    )
    gradle.write_text(gradle_source, encoding="utf-8")

proguard_source = Path("platform/android/proguard-rules.pro")
proguard_target = Path("android/app/proguard-rules.pro")
if not proguard_source.is_file():
    raise SystemExit("Missing Android ProGuard compatibility rules.")
proguard_target.write_text(
    proguard_source.read_text(encoding="utf-8"), encoding="utf-8"
)

# FileProvider is explicitly declared; pin AndroidX Core instead of depending
# on incidental transitive plugin dependencies.
core_dep = 'implementation("androidx.core:core:1.15.0")'
if core_dep not in gradle_source:
    gradle_source += '\n\ndependencies {\n    ' + core_dep + '\n}\n'
    gradle.write_text(gradle_source, encoding="utf-8")

