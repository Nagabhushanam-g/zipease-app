import 'package:flutter_test/flutter_test.dart';
import 'package:zipease/services/archive_library.dart';

LibraryEntry entry(String name, String relative) => LibraryEntry(
  path: '/tmp/zipease/$relative',
  name: name,
  relativePath: relative,
  created: false,
  size: 128,
  modified: DateTime.utc(2026, 11, 14),
);

void main() {
  test('A file can be found by its source ZIP filename', () {
    final item = entry('app-release.apk', 'session-12/Apps/app-release.apk');
    expect(ArchiveLibrary.matchesSearch(item, 'PROJECT_BACKUP.ZIP',
      sourceArchive: 'Project_Backup.zip'), isTrue);
    expect(ArchiveLibrary.matchesSearch(item, 'apps/'), isTrue);
    expect(ArchiveLibrary.matchesSearch(item, 'release.apk'), isTrue);
    expect(ArchiveLibrary.matchesSearch(item, 'unrelated',
      sourceArchive: 'Project_Backup.zip'), isFalse);
  });

  test('Search is case-insensitive and whitespace trimmed', () {
    final item = entry('Budget.XLSX', 'session-13/Finance/Budget.XLSX');
    expect(ArchiveLibrary.matchesSearch(item, '  budget '), isTrue);
    expect(ArchiveLibrary.matchesSearch(item, 'FINANCE'), isTrue);
    expect(ArchiveLibrary.matchesSearch(item, '  '), isTrue);
  });
}
