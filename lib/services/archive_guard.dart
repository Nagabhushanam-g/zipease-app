import 'package:archive/archive.dart';

/// Limits are deliberately conservative until larger archives can be tested.
class ArchiveGuard {
  static const int maxEntries = 10000;
  static const int maxExpandedBytes = 1024 * 1024 * 1024; // 1 GiB

  static void validate(Iterable<ArchiveFile> entries) {
    var count = 0;
    var total = 0;
    final names = <String>{};

    for (final entry in entries) {
      count++;
      if (count > maxEntries) {
        throw const FormatException('This archive contains too many entries.');
      }
      final name = entry.name;
      if (name.isEmpty ||
          name.contains('\\') ||
          name.contains('\u0000') ||
          name.startsWith('/') ||
          RegExp(r'^[A-Za-z]:').hasMatch(name)) {
        throw FormatException('Unsafe file name in ZIP: $name');
      }
      final segments = name.split('/');
      for (var i = 0; i < segments.length; i++) {
        if (segments[i] == '.' || segments[i] == '..' ||
            (segments[i].isEmpty && i != segments.length - 1)) {
          throw FormatException('Unsafe file path in ZIP: $name');
        }
      }
      if (entry.isSymbolicLink || entry.isHardLink) {
        throw const FormatException('ZIP archives with links are not supported.');
      }
      final path = name.endsWith('/') ? name.substring(0, name.length - 1) : name;
      if (path.isEmpty || !names.add(path)) {
        throw FormatException('Duplicate or empty file name: $name');
      }
      if (entry.size < 0 || entry.size > maxExpandedBytes) {
        throw const FormatException('An archive entry is too large.');
      }
      total += entry.size;
      if (total > maxExpandedBytes) {
        throw const FormatException('The extracted contents exceed the 1 GiB safety limit.');
      }
    }
  }
}
