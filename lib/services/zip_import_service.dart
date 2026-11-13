import 'dart:io';

import 'package:flutter/services.dart';

/// Android returns a verified app-private copy of a document selected through
/// the Storage Access Framework. ZIP files are not restricted by provider MIME.
class PickedZip {
  const PickedZip({required this.path, required this.name});

  final String path;
  final String name;

  Future<void> deleteTemporaryCopy() async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class ZipImportService {
  static const _channel = MethodChannel('com.zipease.zipease/exports');

  static Future<PickedZip?> pickZip() async {
    final selected = await _channel.invokeMapMethod<String, String>('pickZip');
    if (selected == null) return null;

    final path = selected['path'];
    if (path == null || path.isEmpty) {
      throw const FormatException('The ZIP file could not be copied from the selected location.');
    }
    return PickedZip(path: path, name: selected['name'] ?? 'selected.zip');
  }
}
