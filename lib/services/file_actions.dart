import 'package:flutter/services.dart';

enum FileAction { open, share, install }

class FileActions {
  static const MethodChannel _channel =
      MethodChannel('com.zipease.zipease/exports');

  static Future<String> perform({
    required String path,
    required String name,
    required FileAction action,
  }) async {
    if (action == FileAction.install && !name.toLowerCase().endsWith('.apk')) {
      throw const FormatException('Only APK files can be installed.');
    }
    final status = await _channel.invokeMethod<String>('fileAction', {
      'path': path,
      'fileName': name,
      'action': action.name,
    });
    return status ?? 'unknown';
  }
}
