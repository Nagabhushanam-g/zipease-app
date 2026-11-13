import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zipease/services/archive_guard.dart';

void main() {
  test('ZipEase-created ZIP extracts its original files intact', () async {
    final temp = await Directory.systemTemp.createTemp('zipease_roundtrip_');
    InputFileStream? input;
    Archive? decoded;
    try {
      final files = <String, List<int>>{
        'note.txt': 'ZipEase extraction test'.codeUnits,
        'picture.png': <int>[137, 80, 78, 71, 13, 10, 26, 10, 0, 255, 42],
        // An APK is simply a binary archive member to ZIP extraction.
        'release.apk': <int>[80, 75, 3, 4, 1, 0, 255, 144, 35, 17],
        'media/picture.jpeg': <int>[255, 216, 255, 224, 0],
        'media/movie.mp4': <int>[0, 0, 0, 24, 102, 116, 121, 112],
        'media/music.mp3': <int>[73, 68, 51, 3, 0],
        'office/document.docx': <int>[80, 75, 3, 4, 20, 0],
        'office/sheet.xlsx': <int>[80, 75, 3, 4, 20, 0, 1],
        'office/slides.pptx': <int>[80, 75, 3, 4, 20, 0, 2],
        'office/report.pdf': <int>[37, 80, 68, 70, 45],
        'bin/program.exe': <int>[77, 90, 144, 0, 3],
        'bin/extensionless': <int>[0, 255, 128, 56, 17],
      };

      final encoder = ZipFileEncoder();
      final zip = File('${temp.path}/created.zip');
      encoder.create(zip.path);
      for (final entry in files.entries) {
        final source = File('${temp.path}/${entry.key}');
        await source.parent.create(recursive: true);
        await source.writeAsBytes(entry.value);
        await encoder.addFile(source, entry.key);
      }
      await encoder.close();

      input = InputFileStream(zip.path);
      decoded = ZipDecoder().decodeStream(
        input,
        verify: true,
        throwOnError: true,
      );
      ArchiveGuard.validate(decoded.files);

      final dest = Directory('${temp.path}/extracted');
      await extractArchiveToDisk(
        decoded,
        dest.path,
        throwOnError: true,
        allowAbsoluteSymlinks: false,
        maxSize: ArchiveGuard.maxExpandedBytes,
      );

      for (final entry in files.entries) {
        expect(await File('${dest.path}/${entry.key}').readAsBytes(), entry.value);
      }
    } finally {
      if (decoded != null) await decoded.clear();
      input?.close();
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  });
}
