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

# The Flutter-generated min SDK is compatible with the current dependencies.
# Never introduce READ_EXTERNAL_STORAGE or MANAGE_EXTERNAL_STORAGE.
assert 'MANAGE_EXTERNAL_STORAGE' not in xml
assert 'READ_EXTERNAL_STORAGE' not in xml
