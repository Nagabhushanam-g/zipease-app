import 'package:flutter/material.dart';
import '../services/export_service.dart';

import '../services/archive_file_types.dart';
import '../services/archive_folder_tree.dart';
import '../services/archive_library.dart';

/// Opens a source ZIP as a folder. Directory navigation is inside the screen,
/// so users can verify the original hierarchy before opening individual files.
class ArchiveFolderBrowser extends StatefulWidget {
  const ArchiveFolderBrowser({
    super.key,
    required this.archiveName,
    required this.sessionId,
    required this.entries,
    required this.folderPaths,
    required this.onFileTap,
  });

  final String archiveName;
  final String sessionId;
  final List<LibraryEntry> entries;
  final List<String> folderPaths;
  final ValueChanged<LibraryEntry> onFileTap;

  @override
  State<ArchiveFolderBrowser> createState() => _ArchiveFolderBrowserState();
}

class _ArchiveFolderBrowserState extends State<ArchiveFolderBrowser> {
  late final ArchiveFolderNode _root = ArchiveFolderNode.build(
    widget.entries,
    folderPaths: widget.folderPaths,
  );
  List<String> _location = [];
  bool _exporting = false;

  Future<void> _exportFolder({bool currentOnly = false}) async {
    if (_exporting) return;
    // Freeze selection before opening Android's external folder picker.
    final parts = List<String>.from(_location);
    if (currentOnly && parts.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final library = ArchiveLibrary();
      final directory = currentOnly
          ? await library.subfolderDirectory(widget.sessionId, parts)
          : await library.sessionDirectory(widget.sessionId);
      final name = currentOnly
          ? parts.last
          : ArchiveLibrary.exportFolderName(widget.archiveName);
      final saved = await ExportService.saveToDevice(
        directory.path,
        fileName: name,
      );
      if (!mounted) return;
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(currentOnly
              ? 'Saved the $name folder, including nested files.'
              : 'Saved the complete extracted ZIP folder.'),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Unable to export the selected ZIP folder.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _deleteExtraction() async {
    if (_exporting) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete extracted ZIP?'),
        content: Text(
          'Remove all files and folders extracted from '
          '${widget.archiveName} from ZipEase? '
          'Your original ZIP and any files saved to Downloads will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete extraction'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _exporting = true);
    try {
      await ArchiveLibrary().deleteExtractionSession(widget.sessionId);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not remove the extracted ZIP folder.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _root.folderAt(_location);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.archiveName,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(child: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            TextButton.icon(
              icon: const Icon(Icons.folder_zip_outlined, size: 18),
              label: Text(widget.archiveName),
              onPressed: () => setState(() => _location = []),
            ),
            for (var i = 0; i < _location.length; i++) ...[
              const Icon(Icons.chevron_right, size: 17),
              TextButton(
                onPressed: () => setState(() {
                  _location = _location.take(i + 1).toList();
                }),
                child: Text(_location[i]),
              ),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${current.fileCount} file(s), '
              '${current.orderedFolders.length} folder(s)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(child: ListView(children: [
          for (final folder in current.orderedFolders)
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(folder.name),
              subtitle: Text('${folder.fileCount} file(s)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() {
                _location = [..._location, folder.name];
              }),
            ),
          for (final file in current.orderedFiles)
            ListTile(
              leading: Icon(ArchiveFileTypes.icon(file.name)),
              title: Text(file.name),
              subtitle: Text(ArchiveFileTypes.label(file.name)),
              trailing: const Icon(Icons.more_horiz),
              onTap: () => widget.onFileTap(file),
            ),
          if (current.orderedFiles.isEmpty && current.orderedFolders.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('This folder is empty.',
                textAlign: TextAlign.center),
            ),
        ])),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_location.isNotEmpty)
                OutlinedButton.icon(
                  icon: const Icon(Icons.drive_folder_upload_outlined),
                  onPressed: _exporting
                      ? null
                      : () => _exportFolder(currentOnly: true),
                  label: Text(_exporting
                      ? 'Working…' : 'Export current folder: ${_location.last}'),
                ),
              FilledButton.icon(
                icon: const Icon(Icons.save_alt),
                onPressed: _exporting ? null : _exportFolder,
                label: Text(_exporting
                    ? 'Working…' : 'Export complete ZIP folder'),
              ),
              TextButton.icon(
                onPressed: _exporting ? null : _deleteExtraction,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete this extraction'),
              ),
            ],
          ),
        ),
      ])),
    );
  }
}
