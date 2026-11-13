import 'package:flutter/services.dart';

class ExportService {
  static const _channel = MethodChannel('com.zipease.zipease/exports');

  /// Android SAF handles the user's chosen destination; no broad storage permission.
  /// Returns false if the user cancels the system picker.
  static Future<bool> saveToDevice(String localPath, {required String fileName}) async {
    final saved = await _channel.invokeMethod<bool>('exportPath', {
      'path': localPath,
      'fileName': fileName,
    });
    return saved ?? false;
  }
}
