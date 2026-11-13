import 'package:flutter_test/flutter_test.dart';
import 'package:zipease/services/archive_file_types.dart';

void main() {
  test('Recognizes file categories while allowing opaque files', () {
    expect(ArchiveFileTypes.category('photo.JPG'), ArchiveFileCategory.image);
    expect(ArchiveFileTypes.category('movie.mp4'), ArchiveFileCategory.video);
    expect(ArchiveFileTypes.category('music.mp3'), ArchiveFileCategory.audio);
    expect(ArchiveFileTypes.category('app.APK'), ArchiveFileCategory.androidApp);
    expect(ArchiveFileTypes.category('file.docx'), ArchiveFileCategory.word);
    expect(ArchiveFileTypes.category('book.xlsx'), ArchiveFileCategory.spreadsheet);
    expect(ArchiveFileTypes.category('deck.pptx'), ArchiveFileCategory.presentation);
    expect(ArchiveFileTypes.category('report.pdf'), ArchiveFileCategory.pdf);
    expect(ArchiveFileTypes.category('install.exe'), ArchiveFileCategory.executable);
    expect(ArchiveFileTypes.category('nested.zip'), ArchiveFileCategory.archive);
    expect(ArchiveFileTypes.category('unknownfile'), ArchiveFileCategory.other);
    expect(ArchiveFileTypes.label('script.bat'), contains('extract only'));
  });
}
