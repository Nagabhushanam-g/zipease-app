import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

/// ZIP entries are exported byte-for-byte without an extension allowlist.
/// Labels only help people distinguish entries in the extracted file list.
/// Executable file types are NEVER executed by ZipEase.
enum ArchiveFileCategory {
  image, video, audio, androidApp, word, spreadsheet, presentation,
  pdf, executable, archive, other,
}

class ArchiveFileTypes {
  static ArchiveFileCategory category(String filename) {
    final extension = path.extension(filename).toLowerCase();
    if (const {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.heic', '.svg', '.tif', '.tiff'}.contains(extension)) {
      return ArchiveFileCategory.image;
    }
    if (const {'.mp4', '.mkv', '.avi', '.mov', '.webm', '.3gp', '.m4v', '.wmv'}.contains(extension)) {
      return ArchiveFileCategory.video;
    }
    if (const {'.mp3', '.wav', '.m4a', '.aac', '.ogg', '.opus', '.flac', '.wma'}.contains(extension)) {
      return ArchiveFileCategory.audio;
    }
    if (const {'.apk', '.aab', '.apks', '.xapk'}.contains(extension)) {
      return ArchiveFileCategory.androidApp;
    }
    if (const {'.doc', '.docx', '.odt', '.rtf', '.txt'}.contains(extension)) {
      return ArchiveFileCategory.word;
    }
    if (const {'.xls', '.xlsx', '.xlsm', '.csv', '.ods'}.contains(extension)) {
      return ArchiveFileCategory.spreadsheet;
    }
    if (const {'.ppt', '.pptx', '.odp'}.contains(extension)) {
      return ArchiveFileCategory.presentation;
    }
    if (extension == '.pdf') return ArchiveFileCategory.pdf;
    if (const {'.exe', '.msi', '.bat', '.cmd', '.sh', '.bin', '.dll', '.so', '.run', '.appimage'}.contains(extension)) {
      return ArchiveFileCategory.executable;
    }
    if (const {'.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz', '.tgz'}.contains(extension)) {
      return ArchiveFileCategory.archive;
    }
    return ArchiveFileCategory.other;
  }

  static String label(String filename) {
    switch (category(filename)) {
      case ArchiveFileCategory.image: return 'Image';
      case ArchiveFileCategory.video: return 'Video';
      case ArchiveFileCategory.audio: return 'Audio';
      case ArchiveFileCategory.androidApp: return 'Android app package';
      case ArchiveFileCategory.word: return 'Document';
      case ArchiveFileCategory.spreadsheet: return 'Spreadsheet';
      case ArchiveFileCategory.presentation: return 'Presentation';
      case ArchiveFileCategory.pdf: return 'PDF document';
      case ArchiveFileCategory.executable: return 'Executable file — extract only';
      case ArchiveFileCategory.archive: return 'Archive file';
      case ArchiveFileCategory.other: return 'File';
    }
  }

  static IconData icon(String filename) {
    switch (category(filename)) {
      case ArchiveFileCategory.image: return Icons.image_outlined;
      case ArchiveFileCategory.video: return Icons.movie_outlined;
      case ArchiveFileCategory.audio: return Icons.audiotrack_outlined;
      case ArchiveFileCategory.androidApp: return Icons.android_outlined;
      case ArchiveFileCategory.word: return Icons.description_outlined;
      case ArchiveFileCategory.spreadsheet: return Icons.table_chart_outlined;
      case ArchiveFileCategory.presentation: return Icons.slideshow_outlined;
      case ArchiveFileCategory.pdf: return Icons.picture_as_pdf_outlined;
      case ArchiveFileCategory.executable: return Icons.code_outlined;
      case ArchiveFileCategory.archive: return Icons.folder_zip_outlined;
      case ArchiveFileCategory.other: return Icons.insert_drive_file_outlined;
    }
  }
}
