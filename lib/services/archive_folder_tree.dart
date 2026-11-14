import 'package:path/path.dart' as p;
import 'archive_library.dart';

/// Preserves a ZIP's nested directory structure, including empty directories.
class ArchiveFolderNode {
  ArchiveFolderNode(this.name, this.relativePath);

  final String name;
  final String relativePath;
  final Map<String, ArchiveFolderNode> folders = {};
  final List<LibraryEntry> files = [];

  int get fileCount =>
      files.length + folders.values.fold<int>(0, (n, folder) => n + folder.fileCount);

  List<ArchiveFolderNode> get orderedFolders =>
      folders.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  List<LibraryEntry> get orderedFiles =>
      files.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  ArchiveFolderNode folderAt(List<String> pathParts) {
    var node = this;
    for (final part in pathParts) {
      final next = node.folders[part];
      if (next == null) return this;
      node = next;
    }
    return node;
  }

  static ArchiveFolderNode build(List<LibraryEntry> entries,
      {Iterable<String> folderPaths = const []}) {
    final root = ArchiveFolderNode('', '');

    ArchiveFolderNode ensureFolder(List<String> parts) {
      var node = root;
      var relative = '';
      for (final part in parts) {
        if (part.isEmpty || part == '.' || part == '..') break;
        relative = relative.isEmpty ? part : p.join(relative, part);
        node = node.folders.putIfAbsent(
          part, () => ArchiveFolderNode(part, relative),
        );
      }
      return node;
    }

    for (final folder in folderPaths) {
      ensureFolder(p.split(folder));
    }
    for (final entry in entries) {
      if (entry.created) continue;
      final parts = p.split(entry.relativePath);
      if (parts.length < 2 || parts.contains('..')) continue;
      final inner = parts.skip(1).toList();
      ensureFolder(inner.take(inner.length - 1).toList()).files.add(entry);
    }
    return root;
  }
}
