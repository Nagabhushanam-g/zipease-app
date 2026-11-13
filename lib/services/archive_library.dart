import 'dart:io';
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

  Future<ArchiveOutput> keep(ArchiveOutput output) async {
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
        if (p.split(relative).any((part) => part.startsWith('.pending_'))) {
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
