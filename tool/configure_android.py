#!/usr/bin/env python3
"""Patch the fresh Flutter Android template, without broad file permissions."""
from pathlib import Path
import re

manifest = Path('android/app/src/main/AndroidManifest.xml')
if not manifest.exists():
    raise SystemExit('Run flutter create before configuring Android.')
xml = manifest.read_text(encoding='utf-8')
if 'android.permission.INTERNET' not in xml:
    xml = xml.replace('<application',
        '    <uses-permission android:name="android.permission.INTERNET" />\n    <application', 1)
if 'com.google.android.gms.ads.APPLICATION_ID' not in xml:
    xml = xml.replace('</application>',
        '    <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID"\n'
        '        android:value="ca-app-pub-3940256099942544~3347511713" />\n'
        '    </application>', 1)
xml, count = re.subn(r'android:label="[^"]*"', 'android:label="ZipEase"', xml, count=1)
if not count:
    raise SystemExit('Could not find the Flutter Android label in AndroidManifest.xml.')
manifest.write_text(xml, encoding='utf-8')

# AGP 9 R8 strict-full-mode can strip Room's generated database constructor
# needed by transitive WorkManager before Flutter's Dart main() runs.
# Bind these keep rules to the generated release build type explicitly.
gradle = Path('android/app/build.gradle.kts')
if not gradle.exists():
    raise SystemExit('Expected Flutter Android Kotlin-DSL build.gradle.kts.')
gradle_source = gradle.read_text(encoding='utf-8')
rule_line = 'proguardFiles("proguard-rules.pro")'
if rule_line not in gradle_source:
    release_pattern = r'(?m)^([ \\t]*)release[ \\t]*\\{[ \\t]*

# The Flutter-generated min SDK is compatible with the current dependencies.
# Never introduce READ_EXTERNAL_STORAGE or MANAGE_EXTERNAL_STORAGE.
assert 'MANAGE_EXTERNAL_STORAGE' not in xml
assert 'READ_EXTERNAL_STORAGE' not in xml

    release_match = re.search(release_pattern, gradle_source)
    if not release_match:
        raise SystemExit('Could not locate Android release build type to attach R8 rules.')
    indentation = release_match.group(1)
    insert_pos = release_match.end()
    gradle_source = (
        gradle_source[:insert_pos]
        + '\\n' + indentation + '    ' + rule_line
        + gradle_source[insert_pos:]
    )
    gradle.write_text(gradle_source, encoding='utf-8')
proguard_source = Path('platform/android/proguard-rules.pro')
proguard_target = Path('android/app/proguard-rules.pro')
if not proguard_source.exists():
    raise SystemExit('Missing release ProGuard compatibility rules.')
proguard_target.write_text(proguard_source.read_text(encoding='utf-8'), encoding='utf-8')


# The Flutter-generated min SDK is compatible with the current dependencies.
# Never introduce READ_EXTERNAL_STORAGE or MANAGE_EXTERNAL_STORAGE.
assert 'MANAGE_EXTERNAL_STORAGE' not in xml
assert 'READ_EXTERNAL_STORAGE' not in xml
