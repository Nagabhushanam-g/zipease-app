import 'package:flutter_test/flutter_test.dart';
import 'package:zipease/services/archive_folder_tree.dart';
import 'package:zipease/services/archive_library.dart';

LibraryEntry item(String relative) => LibraryEntry(
  path: '/tmp/${relative}',
  name: relative.split('/').last,
  relativePath: relative,
  created: false,
  size: 42,
  modified: DateTime.utc(2026),
);

void main() {
  test('Original nested folders and empty directories are preserved', () {
    final root = ArchiveFolderNode.build([
      item('session1/Documents/Excel/Budget.xlsx'),
      item('session1/Documents/Word/Report.docx'),
      item('session1/Applications/app-release.apk'),
      item('session1/Documents/Excel/Summary.xlsx'),
    ], folderPaths: [
      'Documents/Excel', 'Documents/Word',
      'Applications', 'Empty/Subfolder',
    ]);
    expect(root.fileCount, 4);
    expect(root.orderedFolders.map((f) => f.name),
        ['Applications', 'Documents', 'Empty']);
    expect(root.folderAt(['Documents', 'Excel']).orderedFiles.map((f) => f.name),
        ['Budget.xlsx', 'Summary.xlsx']);
    expect(root.folderAt(['Applications']).files.single.name, 'app-release.apk');
    expect(root.folderAt(['Empty', 'Subfolder']).fileCount, 0);
  });

  test('Equal filenames remain in separate original directories', () {
    final root = ArchiveFolderNode.build([
      item('session1/Photos/screenshot.png'),
      item('session1/Backup/screenshot.png'),
    ]);
    expect(root.folderAt(['Photos']).files.single.relativePath,
        'session1/Photos/screenshot.png');
    expect(root.folderAt(['Backup']).files.single.relativePath,
        'session1/Backup/screenshot.png');
  });
}
