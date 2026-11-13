import 'dart:io';
import 'package:flutter/material.dart';

import '../services/archive_file_types.dart';
import '../services/archive_library.dart';
import '../services/export_service.dart';

enum _Source { all, created, extracted }

class MyFilesScreen extends StatefulWidget {
  const MyFilesScreen({super.key});

  @override
  State<MyFilesScreen> createState() => _MyFilesScreenState();
}

class _MyFilesScreenState extends State<MyFilesScreen> {
  final ArchiveLibrary _library = ArchiveLibrary();
  late Future<List<LibraryEntry>> _loading = _library.files();
  _Source _source = _Source.all;
  ArchiveFileCategory? _category;
  String _query = '';
  bool _exporting = false;

  static const types = <ArchiveFileCategory, String>{
    ArchiveFileCategory.image: 'Photos',
    ArchiveFileCategory.video: 'Videos',
    ArchiveFileCategory.audio: 'Audio',
    ArchiveFileCategory.word: 'Word & Text',
    ArchiveFileCategory.spreadsheet: 'Excel',
    ArchiveFileCategory.presentation: 'PowerPoint',
    ArchiveFileCategory.androidApp: 'APKs',
    ArchiveFileCategory.pdf: 'PDFs',
    ArchiveFileCategory.archive: 'ZIP & Archives',
    ArchiveFileCategory.executable: 'Executables',
    ArchiveFileCategory.other: 'Other',
  };

  void _refresh() => setState(() => _loading = _library.files());

  String _size(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    if (n < 1024 * 1024 * 1024) {
      return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _save(LibraryEntry entry) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final saved = await ExportService.saveToDevice(
        entry.path, fileName: entry.name,
      );
      if (saved && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Saved ${entry.name} to your selected location.'),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Unable to export this file.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _delete(LibraryEntry entry) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove from ZipEase?'),
        content: Text('Delete ${entry.name} from My Files? '
          'A separate copy in Downloads, if any, is not affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete')),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await _library.delete(entry);
      if (mounted) _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to remove the file.')),
        );
      }
    }
  }

  Future<void> _details(LibraryEntry entry) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (entry.category == ArchiveFileCategory.image) ...[
              SizedBox(height: 220,
                child: Image.file(File(entry.path), fit: BoxFit.contain,
                  errorBuilder: (_, error, stack) => const Center(
                    child: Text('No image preview available.'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(children: [
              Icon(ArchiveFileTypes.icon(entry.name), size: 32),
              const SizedBox(width: 12),
              Expanded(child: Text(entry.name,
                style: Theme.of(c).textTheme.titleMedium)),
            ]),
            const SizedBox(height: 12),
            Text('${ArchiveFileTypes.label(entry.name)} · ${_size(entry.size)}'),
            const SizedBox(height: 6),
            Text(entry.created ? 'Created ZIP' : 'Extracted file'),
            Text(entry.relativePath,
              maxLines: 3, overflow: TextOverflow.ellipsis,
              style: Theme.of(c).textTheme.bodySmall),
            const SizedBox(height: 14),
            FilledButton.icon(
              icon: const Icon(Icons.save_alt),
              onPressed: () {
                Navigator.pop(c);
                _save(entry);
              },
              label: const Text('Save file to device'),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                Navigator.pop(c);
                _delete(entry);
              },
              label: const Text('Delete from My Files'),
            ),
            if (entry.category != ArchiveFileCategory.image)
              const Text(
                'For document or media viewing in another app, save the '
                'file to your device. ZipEase never executes APKs or programs.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
          ],
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Files'), actions: [
        IconButton(onPressed: _refresh, tooltip: 'Refresh',
          icon: const Icon(Icons.refresh)),
      ]),
      body: SafeArea(child: Column(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Text(
            'Created ZIPs and extracted files are saved here in ZipEase. '
            'Choose a category or search by name.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search My Files',
              border: OutlineInputBorder(), isDense: true,
            ),
            onChanged: (s) => setState(() => _query = s.toLowerCase().trim()),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            for (final option in _Source.values) ...[
              ChoiceChip(
                label: Text(switch(option) {
                  _Source.all => 'All files',
                  _Source.created => 'Created ZIPs',
                  _Source.extracted => 'Extracted files',
                }),
                selected: _source == option,
                onSelected: (_) => setState(() => _source = option),
              ),
              const SizedBox(width: 8),
            ],
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            ChoiceChip(
              label: const Text('All types'),
              selected: _category == null,
              onSelected: (_) => setState(() => _category = null),
            ),
            const SizedBox(width: 8),
            for (final type in types.entries) ...[
              ChoiceChip(
                label: Text(type.value),
                selected: _category == type.key,
                onSelected: (_) => setState(() => _category = type.key),
              ),
              const SizedBox(width: 8),
            ],
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(child: FutureBuilder<List<LibraryEntry>>(
          future: _loading,
          builder: (context, snap) {
            if (snap.hasError) {
              return const Center(child: Text('Could not load saved files.'));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final matches = snap.data!.where((e) =>
              (_source == _Source.all ||
                (_source == _Source.created && e.created) ||
                (_source == _Source.extracted && !e.created)) &&
              (_category == null || e.category == _category) &&
              (_query.isEmpty || e.name.toLowerCase().contains(_query) ||
                e.relativePath.toLowerCase().contains(_query))
            ).toList();
            if (matches.isEmpty) {
              return const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No saved files in this category. Create or extract a ZIP '
                  'to add files to My Files.',
                  textAlign: TextAlign.center,
                ),
              ));
            }
            return Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Align(alignment: Alignment.centerLeft,
                  child: Text('${matches.length} file(s)',
                    style: Theme.of(context).textTheme.bodySmall)),
              ),
              Expanded(child: ListView.separated(
                itemCount: matches.length,
                separatorBuilder: (_, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = matches[index];
                  final img = entry.category == ArchiveFileCategory.image ?
                    Image.file(File(entry.path), width: 42, height: 42,
                      fit: BoxFit.cover,
                      errorBuilder: (_, e, stack) =>
                        Icon(ArchiveFileTypes.icon(entry.name))) :
                    Icon(ArchiveFileTypes.icon(entry.name), size: 28);
                  return ListTile(
                    leading: SizedBox(width: 48, child: Center(child: img)),
                    title: Text(entry.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${entry.created ? "Created ZIP" : ArchiveFileTypes.label(entry.name)}'
                      ' · ${_size(entry.size)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _details(entry),
                  );
                },
              )),
            ]);
          },
        )),
      ])),
    );
  }
}
