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
  static const _openWith = MethodChannel('com.zipease.zipease/open_with');

  static PickedZip? _fromMessage(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<Object?, Object?>.from(raw);
    final error = map['error'];
    if (error is String && error.isNotEmpty) {
      throw FormatException(error);
    }
    final path = map['path'];
    if (path is! String || path.isEmpty) {
      throw const FormatException('The opened ZIP has no readable content.');
    }
    final name = map['name'];
    return PickedZip(path: path, name: name is String ? name : 'selected.zip');
  }

  /// Deliver cold-start and warm-start Android Open with requests.
  static Future<void> registerOpenWithHandler(
    Future<void> Function(PickedZip) onZip,
    void Function(Object) onError,
  ) async {
    _openWith.setMethodCallHandler((call) async {
      if (call.method == 'openedZipError') {
        onError(FormatException(
          call.arguments is String ? call.arguments as String : 'Unable to read ZIP.',
        ));
      } else if (call.method == 'openedZip') {
        try {
          final zip = _fromMessage(call.arguments);
          if (zip != null) await onZip(zip);
        } catch (error) {
          onError(error);
        }
      }
    });
    final pending = await _openWith.invokeMethod<dynamic>('takePendingZip');
    try {
      final zip = _fromMessage(pending);
      if (zip != null) await onZip(zip);
    } catch (error) {
      onError(error);
    }
  }

  static void detachOpenWithHandler() {
    _openWith.setMethodCallHandler(null);
  }

  /// If the default ZIP-only import picker cannot show a provider's ZIP,
  /// allow choosing from all documents as a fallback.
  static Future<PickedZip?> pickZip({bool browseAllFiles = false}) async {
    final selected = await _channel.invokeMapMethod<String, String>(
      browseAllFiles ? 'pickZipAllFiles' : 'pickZip',
    );
    if (selected == null) return null;

    final path = selected['path'];
    if (path == null || path.isEmpty) {
      throw const FormatException('The ZIP file could not be copied from the selected location.');
    }
    return PickedZip(path: path, name: selected['name'] ?? 'selected.zip');
  }
}
