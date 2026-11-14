import 'package:flutter/material.dart';

import '../services/archive_file_types.dart';
import '../services/archive_folder_tree.dart';
import '../services/archive_library.dart';

/// Opens a source ZIP as a folder. Directory navigation is inside the screen,
/// so users can verify the original hierarchy before opening individual files.
class ArchiveFolderBrowser extends StatefulWidget {
  const ArchiveFolderBrowser({
    super.key,
    required this.archiveName,
    required this.entries,
    required this.folderPaths,
    required this.onFileTap,
  });

  final String archiveName;
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
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 6, 18, 12),
          child: Text('Tap a folder to browse it or a file to open, share, '
              'save or install it using Android.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12)),
        ),
      ])),
    );
  }
}
