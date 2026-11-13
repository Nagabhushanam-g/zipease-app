import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'archive_guard.dart';

class ArchiveOutput {
  const ArchiveOutput({required this.path, required this.fileCount, required this.isDirectory});

  final String path;
  final int fileCount;
  final bool isDirectory;
}

class ArchiveService {
  static String _uniqueName() => DateTime.now().microsecondsSinceEpoch.toString();

  /// Uses cached copies produced by Android's Storage Access Framework picker.
  Future<ArchiveOutput> compress(List<PlatformFile> pickedFiles) async {
    if (pickedFiles.isEmpty) throw const FormatException('Select at least one file.');
    final cache = await getTemporaryDirectory();
    final output = File(p.join(cache.path, 'zipease_${_uniqueName()}.zip'));
    final encoder = ZipFileEncoder();
    final used = <String>{};
    var created = false;
    try {
      encoder.create(output.path);
      created = true;
      for (final file in pickedFiles) {
        final localPath = file.path;
        if (localPath == null || !await File(localPath).exists()) {
          throw FormatException('Cannot read selected file: ${file.name}');
        }
        final safe = p.basename(file.name.replaceAll('\\', '/'));
        if (safe.isEmpty || safe == '.' || safe == '..') {
          throw const FormatException('Invalid selected file name.');
        }
        var name = safe;
        var suffix = 2;
        while (!used.add(name.toLowerCase())) {
          final ext = p.extension(safe);
          final stem = p.basenameWithoutExtension(safe);
          name = '$stem ($suffix)$ext';
          suffix++;
        }
        await encoder.addFile(File(localPath), name);
      }
      await encoder.close();
      return ArchiveOutput(path: output.path, fileCount: pickedFiles.length, isDirectory: false);
    } catch (_) {
      if (created) {
        try { await encoder.close(); } catch (_) {}
      }
      if (await output.exists()) await output.delete();
      rethrow;
    }
  }

  /// For existing callers that use the cross-platform picker.
  Future<ArchiveOutput> extract(PlatformFile pickedZip, {String? password}) async {
    final localPath = pickedZip.path;
    if (localPath == null) {
      throw const FormatException('The selected ZIP file is unavailable.');
    }
    return extractLocalZip(localPath, password: password);
  }

  /// Supports ZIPs copied from content:// providers via Android SAF, rather
  /// than depending on filesystem paths exposed by the document provider.
  Future<ArchiveOutput> extractLocalZip(String localPath, {String? password}) async {
    if (!await File(localPath).exists()) {
      throw const FormatException('The selected ZIP file is unavailable.');
    }

    final cache = await getTemporaryDirectory();
    final output = Directory(p.join(cache.path, 'zipease_extract_${_uniqueName()}'));
    await output.create(recursive: true);
    final input = InputFileStream(localPath);
    Archive? archive;
    try {
      archive = ZipDecoder().decodeStream(
        input,
        password: password?.isEmpty == true ? null : password,
        verify: true,
        throwOnError: true,
      );
      ArchiveGuard.validate(archive.files);
      await extractArchiveToDisk(
        archive,
        output.path,
        throwOnError: true,
        allowAbsoluteSymlinks: false,
        maxSize: ArchiveGuard.maxExpandedBytes,
      );
      final count = archive.files.where((entry) => entry.isFile).length;
      return ArchiveOutput(path: output.path, fileCount: count, isDirectory: true);
    } catch (_) {
      if (await output.exists()) await output.delete(recursive: true);
      rethrow;
    } finally {
      if (archive != null) await archive.clear();
      input.close();
    }
  }

  Future<List<String>> preview(ArchiveOutput output) async {
    if (!output.isDirectory) return [p.basename(output.path)];
    final root = Directory(output.path);
    if (!await root.exists()) return [];
    final names = <String>[];
    await for (final item in root.list(recursive: true, followLinks: false)) {
      if (item is File) names.add(p.relative(item.path, from: root.path));
      if (names.length >= 30) break;
    }
    names.sort();
    return names;
  }
}
