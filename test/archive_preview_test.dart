import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zipease/services/archive_service.dart';

void main() {
  test('Preview lists more than 30 mixed files', () async {
    final folder = await Directory.systemTemp.createTemp('zipease_preview_');
    try {
      const count = 45;
      for (var index = 0; index < count; index++) {
        final ext = index.isEven ? 'apk' : 'xlsx';
        final file = File('${folder.path}/file_${index}.${ext}');
        await file.writeAsBytes([index, 42]);
      }
      final output = ArchiveOutput(
        path: folder.path,
        fileCount: count,
        isDirectory: true,
      );
      final all = await ArchiveService().preview(output);
      expect(all.length, count);
      expect(all, contains('file_44.apk'));
      expect(all, contains('file_43.xlsx'));
    } finally {
      if (await folder.exists()) await folder.delete(recursive: true);
    }
  });
}
