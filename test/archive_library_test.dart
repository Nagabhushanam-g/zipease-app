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

  test('Removing an extraction does not remove other archives', () async {
    final temp = await Directory.systemTemp.createTemp('zipease_remove_test_');
    try {
      final root = Directory('${temp.path}/library');
      final library = ArchiveLibrary(root: root);
      final source = Directory('${temp.path}/input');
      await source.create(recursive: true);
      await File('${source.path}/report.docx').writeAsBytes([1, 3, 9]);
      final first = await library.keep(ArchiveOutput(
        path: source.path, fileCount: 1, isDirectory: true,
      ), sourceName: 'first.zip');
      final second = await library.keep(ArchiveOutput(
        path: source.path, fileCount: 1, isDirectory: true,
      ), sourceName: 'second.zip');
      final zipFile = File('${temp.path}/backup.zip');
      await zipFile.writeAsBytes([80, 75, 3, 4]);
      final created = await library.keep(ArchiveOutput(
        path: zipFile.path, fileCount: 1, isDirectory: false,
      ));
      final id = first.path.split(Platform.pathSeparator).last;
      final marker = File('${root.path}/.zipease_meta/$id.json');
      expect(await marker.exists(), isTrue);
      await library.deleteExtractionSession(id);
      expect(await Directory(first.path).exists(), isFalse);
      expect(await marker.exists(), isFalse);
      expect(await Directory(second.path).exists(), isTrue);
      expect(await File(created.path).exists(), isTrue);
      expect((await library.files()).length, 2);
      await expectLater(library.deleteExtractionSession('../'),
          throwsFormatException);
      await expectLater(library.deleteExtractionSession('missing'),
          throwsFormatException);
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
      final stored = await library.keep(ArchiveOutput(
        path: extracted.path, fileCount: originals.length, isDirectory: true,
      ), sourceName: 'Project_Backup.zip');
      // Internal ZipEase metadata cannot contaminate extracted file exports.
      expect(await File('${stored.path}/.zipease_source.json').exists(), isFalse);
      final sessionId = stored.path.split(Platform.pathSeparator).last;
      expect(await library.extractionName(sessionId), 'Project_Backup.zip');
      expect(ArchiveLibrary.exportFolderName('Project_Backup.zip'), 'Project_Backup');
      expect(ArchiveLibrary.exportFolderName('My Files.ZIP'), 'My Files');
      expect(ArchiveLibrary.exportFolderName('../'), 'Extracted_Files');
      expect((await library.sessionDirectory(sessionId)).path, stored.path);
      // Save only a chosen subfolder without flattening other folders.
      final selected = await library.subfolderDirectory(sessionId, ['excel']);
      expect(await File('${selected.path}/data.xlsx').readAsBytes(),
          originals['excel/data.xlsx']);
      expect(await File('${selected.path}/photo.jpg').exists(), isFalse);
      expect(await library.subfolderDirectory(sessionId, []),
          isA<Directory>());
      await expectLater(
          library.subfolderDirectory(sessionId, ['..']), throwsFormatException);
      await expectLater(
          library.subfolderDirectory(sessionId, ['not-a-folder']),
          throwsFormatException);
      expect(await library.folderPaths(sessionId),
          containsAll(['photos', 'excel', 'word', 'ppt', 'apps', 'videos', 'audio', 'executables']));
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
