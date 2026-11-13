import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zipease/services/archive_guard.dart';

void main() {
  test('accepts safe ZIP entries', () {
    ArchiveGuard.validate([
      ArchiveFile.directory('folder/'),
      ArchiveFile.bytes('folder/readme.txt', [72, 105]),
    ]);
  });

  test('blocks parent traversal', () {
    expect(() => ArchiveGuard.validate([
      ArchiveFile.bytes('../private.txt', [1]),
    ]), throwsFormatException);
  });

  test('blocks absolute and Windows paths', () {
    expect(() => ArchiveGuard.validate([ArchiveFile.bytes('/tmp/a', [1])]), throwsFormatException);
    expect(() => ArchiveGuard.validate([ArchiveFile.bytes(r'C:\foo.txt', [1])]), throwsFormatException);
  });

  test('blocks symbolic links', () {
    expect(() => ArchiveGuard.validate([ArchiveFile.symlink('shortcut', '../../outside')]), throwsFormatException);
  });

  test('blocks duplicate file names', () {
    expect(() => ArchiveGuard.validate([
      ArchiveFile.bytes('data.txt', [1]), ArchiveFile.bytes('data.txt', [2]),
    ]), throwsFormatException);
  });
}
