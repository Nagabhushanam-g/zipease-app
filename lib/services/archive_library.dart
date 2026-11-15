import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'archive_file_types.dart';
import 'archive_service.dart';

class LibraryEntry {
  const LibraryEntry({required this.path, required this.name,
    required this.relativePath, required this.created, required this.size,
    required this.modified});

  final String path, name, relativePath;
  final bool created;
  final int size;
  final DateTime modified;
  ArchiveFileCategory get category => ArchiveFileTypes.category(name);
}

/// Created ZIPs and extracted files live in app documents, never cache.
/// They survive restarts and app updates, but not app uninstallation.
class ArchiveLibrary {
  ArchiveLibrary({Directory? root}) : _override = root;
  final Directory? _override;
  static int _sequence = 0;

  Future<Directory> _root() async => _override ??
      Directory(p.join((await getApplicationDocumentsDirectory()).path,
          'zipease_library'));

  Future<ArchiveOutput> keep(ArchiveOutput output, {String? sourceName}) async {
    final kind = output.isDirectory ? 'extracted' : 'created';
    final root = await _root();
    final parent = Directory(p.join(root.path, kind));
    await parent.create(recursive: true);
    final id = '${DateTime.now().microsecondsSinceEpoch}_${_sequence++}';
    final staging = Directory(p.join(parent.path, '.pending_$id'));
    final finalDir = Directory(p.join(parent.path, id));
    await staging.create(recursive: true);
    try {
      if (output.isDirectory) {
        final source = Directory(output.path);
        if (!await source.exists()) {
          throw const FormatException('The extracted folder is unavailable.');
        }
        await _copyTree(source, staging);
      } else {
        final source = File(output.path);
        if (!await source.exists()) {
          throw const FormatException('The created ZIP is unavailable.');
        }
        await source.copy(p.join(staging.path, p.basename(source.path)));
      }
      await staging.rename(finalDir.path);
      if (output.isDirectory) {
        // Internal metadata must not be exported with original ZIP contents.
        final metadata = Directory(p.join(root.path, '.zipease_meta'));
        await metadata.create(recursive: true);
        final source = p.basename((sourceName ?? 'Unknown archive.zip').replaceAll('\\', '/'));
        await File(p.join(metadata.path, '$id.json')).writeAsString(
          jsonEncode({'name': source.isEmpty ? 'Unknown archive.zip' : source}),
        );
      }
      return ArchiveOutput(
        path: output.isDirectory ? finalDir.path :
            p.join(finalDir.path, p.basename(output.path)),
        fileCount: output.fileCount,
        isDirectory: output.isDirectory,
      );
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> _copyTree(Directory from, Directory into) async {
    await for (final entity in from.list(followLinks: false)) {
      final target = p.join(into.path, p.basename(entity.path));
      if (entity is Link) {
        throw const FormatException('Linked files are not supported.');
      }
      if (entity is File) {
        await entity.copy(target);
      } else if (entity is Directory) {
        final next = Directory(target);
        await next.create();
        await _copyTree(entity, next);
      }
    }
  }

  Future<List<LibraryEntry>> files() async {
    final root = await _root();
    final found = <LibraryEntry>[];
    for (final kind in ['created', 'extracted']) {
      final dir = Directory(p.join(root.path, kind));
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final relative = p.relative(entity.path, from: dir.path);
        if (p.basename(relative) == '.zipease_source.json' ||
            p.split(relative).any((part) => part.startsWith('.pending_'))) {
          continue;
        }
        final stat = await entity.stat();
        found.add(LibraryEntry(
          path: entity.path, name: p.basename(entity.path),
          relativePath: relative, created: kind == 'created',
          size: stat.size, modified: stat.modified,
        ));
      }
    }
    found.sort((a, b) => b.modified.compareTo(a.modified));
    return found;
  }

  /// Search by filename, internal folder path OR the user-visible source ZIP.
  /// This keeps archives discoverable without exposing opaque session IDs.
  static bool matchesSearch(LibraryEntry entry, String query,
      {String? sourceArchive}) {
    final term = query.trim().toLowerCase();
    if (term.isEmpty) return true;
    return entry.name.toLowerCase().contains(term) ||
        entry.relativePath.toLowerCase().contains(term) ||
        (sourceArchive?.toLowerCase().contains(term) ?? false);
  }

  Future<String> extractionName(String sessionId) async {
    final root = await _root();
    final candidates = [
      File(p.join(root.path, '.zipease_meta', '$sessionId.json')),
      // Backward compatible with older ZipEase versions.
      File(p.join(root.path, 'extracted', sessionId, '.zipease_source.json')),
    ];
    for (final marker in candidates) {
      if (!await marker.exists()) continue;
      try {
        final value = jsonDecode(await marker.readAsString());
        if (value is Map && value['name'] is String) {
          return value['name'] as String;
        }
      } catch (_) {}
    }
    return 'Earlier extraction';
  }

  /// Include original empty folders when browsing extracted ZIPs.
  Future<List<String>> folderPaths(String sessionId) async {
    if (sessionId.isEmpty || p.basename(sessionId) != sessionId ||
        sessionId == '.' || sessionId == '..') {
      throw const FormatException('Invalid extracted ZIP identifier.');
    }
    final root = await _root();
    final dir = Directory(p.join(root.path, 'extracted', sessionId));
    if (!await dir.exists()) return [];
    final result = <String>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is Directory) {
        result.add(p.relative(entity.path, from: dir.path));
      }
    }
    result.sort();
    return result;
  }

  /// Name a folder after its source archive instead of an internal session ID.
  static String exportFolderName(String zipName) {
    final base = p.basename(zipName.replaceAll('\\', '/')).trim();
    final stem = base.toLowerCase().endsWith('.zip')
        ? base.substring(0, base.length - 4)
        : base;
    final cleaned = stem.replaceAll(RegExp(r'[/\\<>:"|?*\x00-\x1F]'), '_').trim();
    return cleaned.isEmpty || cleaned == '.' || cleaned == '..'
        ? 'Extracted_Files'
        : cleaned;
  }

  Future<Directory> sessionDirectory(String sessionId) async {
    if (sessionId.isEmpty || p.basename(sessionId) != sessionId ||
        sessionId == '.' || sessionId == '..') {
      throw const FormatException('Invalid extraction session');
    }
    final root = await _root();
    final dir = Directory(p.join(root.path, 'extracted', sessionId));
    if (!await dir.exists()) throw const FormatException('Extracted folder missing');
    return dir;
  }

  /// Remove one complete extracted ZIP and its private metadata.
  /// Created ZIPs, other extractions and exported copies are not affected.
  Future<void> deleteExtractionSession(String sessionId) async {
    if (sessionId.isEmpty || p.basename(sessionId) != sessionId ||
        sessionId == '.' || sessionId == '..' ||
        sessionId.contains('/') || sessionId.contains('\\')) {
      throw const FormatException('Invalid extraction session.');
    }
    final root = await _root();
    final extractionRoot = Directory(p.join(root.path, 'extracted'));
    final target = Directory(p.join(extractionRoot.path, sessionId));
    final rootPath = p.normalize(p.absolute(extractionRoot.path));
    final targetPath = p.normalize(p.absolute(target.path));
    if (!p.isWithin(rootPath, targetPath) ||
        await FileSystemEntity.type(targetPath, followLinks: false) ==
            FileSystemEntityType.link) {
      throw const FormatException('Unsafe extraction session path.');
    }
    if (!await target.exists()) {
      throw const FormatException('Extracted folder no longer exists.');
    }
    await target.delete(recursive: true);
    final marker = File(p.join(root.path, '.zipease_meta', '$sessionId.json'));
    if (await marker.exists()) await marker.delete();
  }
  Future<void> delete(LibraryEntry entry) async {
    final root = p.normalize(p.absolute((await _root()).path));
    final target = p.normalize(p.absolute(entry.path));
    if (!p.isWithin(root, target)) {
      throw const FormatException('Invalid ZipEase library path.');
    }
    final file = File(target);
    if (await file.exists()) await file.delete();
  }
}
