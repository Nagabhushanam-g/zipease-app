import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zipease/services/archive_file_types.dart';
import 'package:zipease/services/archive_library.dart';
import 'package:zipease/services/archive_service.dart';

void main() {
  test('Created ZIPs persist across library instances', () async {
    final temp = await Directory.systemTemp.createTemp('zipease_lib_test_');
    try {
      final src = File('${temp.path}/input.zip');
      await src.writeAsBytes([80, 75, 3, 4, 0, 255]);
      final root = Directory('${temp.path}/saved');
      final library = ArchiveLibrary(root: root);
      final kept = await library.keep(ArchiveOutput(
        path: src.path, fileCount: 1, isDirectory: false,
      ));
      expect(await File(kept.path).readAsBytes(), await src.readAsBytes());
      final reopened = ArchiveLibrary(root: root);
      final entries = await reopened.files();
      expect(entries.length, 1);
      expect(entries.first.created, isTrue);
      expect(entries.first.category, ArchiveFileCategory.archive);
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  });

  test('Extracted mixed files persist in categories and can be removed', () async {
    final temp = await Directory.systemTemp.createTemp('zipease_lib_test_');
    try {
      final extracted = Directory('${temp.path}/extracted');
      await extracted.create();
      final originals = <String, List<int>>{
        'photos/photo.jpg': [255, 216, 255],
        'excel/data.xlsx': [80, 75, 3, 4],
        'word/report.docx': [80, 75, 3, 4, 0],
        'ppt/deck.pptx': [80, 75, 3, 4, 1],
        'apps/sample.apk': [80, 75, 3, 4, 2],
        'videos/movie.mp4': [0, 0, 0, 24],
        'audio/song.mp3': [73, 68, 51],
        'executables/program.exe': [77, 90, 0],
      };
      for (final pair in originals.entries) {
        final file = File('${extracted.path}/${pair.key}');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(pair.value);
      }
      final root = Directory('${temp.path}/saved');
      final library = ArchiveLibrary(root: root);
      await library.keep(ArchiveOutput(
        path: extracted.path, fileCount: originals.length, isDirectory: true,
      ));
      final reopened = ArchiveLibrary(root: root);
      final entries = await reopened.files();
      expect(entries.length, originals.length);
      expect(entries.map((e) => e.category).toSet(), containsAll([
        ArchiveFileCategory.image, ArchiveFileCategory.spreadsheet,
        ArchiveFileCategory.word, ArchiveFileCategory.presentation,
        ArchiveFileCategory.androidApp, ArchiveFileCategory.video,
        ArchiveFileCategory.audio, ArchiveFileCategory.executable,
      ]));
      for (final pair in originals.entries) {
        final entry = entries.singleWhere((e) => e.relativePath.endsWith(pair.key));
        expect(await File(entry.path).readAsBytes(), pair.value);
      }
      await reopened.delete(entries.first);
      expect((await reopened.files()).length, originals.length - 1);
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  });
}
