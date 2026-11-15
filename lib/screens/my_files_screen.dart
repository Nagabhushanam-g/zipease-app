import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/archive_file_types.dart';
import '../services/archive_library.dart';
import '../services/export_service.dart';
import '../services/file_actions.dart';
import 'archive_folder_browser.dart';

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
  final Set<String> _expandedSessions = {};
  final Map<String, String> _sessionNames = {};

  Future<void> _loadNames(List<LibraryEntry> entries) async {
    final ids = entries.where((e) => !e.created)
        .map((e) => p.split(e.relativePath).first).toSet();
    for (final id in ids) {
      if (!_sessionNames.containsKey(id)) {
        _sessionNames[id] = await _library.extractionName(id);
      }
    }
    if (mounted) setState(() {});
  }


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

  void _refresh() => setState(() {
    _loading = _library.files();
    _sessionNames.clear();
  });

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

  Future<void> _fileAction(LibraryEntry entry, FileAction action) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final status = await FileActions.perform(
        path: entry.path,
        name: entry.name,
        action: action,
      );
      if (!mounted) return;
      if (status == 'permission_required') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
            'Enable "Allow from this source" in Android settings, '
            'then return and tap Install APK again.',
          ),
          duration: Duration(seconds: 7),
        ));
      }
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.message ?? 'No compatible app is available.'),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Unable to open file: ${error.toString()}'),
        ));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _confirmInstall(LibraryEntry entry) async {
    if (!entry.name.toLowerCase().endsWith('.apk')) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Install APK?'),
        content: Text('Install ${entry.name} using Android’s system installer? '
          'Only install APKs from sources you trust. '
          'Android will ask you to confirm the installation.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (approved == true) {
      await _fileAction(entry, FileAction.install);
    }
  }

  Future<void> _details(LibraryEntry entry) async {
    final sourceZip = entry.created
        ? null
        : await _library.extractionName(p.split(entry.relativePath).first);
    if (!mounted) return;
    final originalPath = entry.created ? entry.name
        : p.joinAll(p.split(entry.relativePath).skip(1));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (entry.category == ArchiveFileCategory.image) ...[
                SizedBox(height: 180,
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
              const SizedBox(height: 8),
              Text('${ArchiveFileTypes.label(entry.name)} · ${_size(entry.size)}'),
              Text(entry.created ? 'Created ZIP' : 'Extracted file'),
              if (sourceZip != null)
                Text('From ZIP: $sourceZip',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('Original path: $originalPath', maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(c).textTheme.bodySmall),
              const SizedBox(height: 14),
              FilledButton.icon(
                icon: const Icon(Icons.open_in_new),
                onPressed: () {
                  Navigator.pop(c);
                  _fileAction(entry, FileAction.open);
                },
                label: const Text('Open with'),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.share_outlined),
                onPressed: () {
                  Navigator.pop(c);
                  _fileAction(entry, FileAction.share);
                },
                label: const Text('Share'),
              ),
              if (entry.name.toLowerCase().endsWith('.apk'))
                FilledButton.icon(
                  icon: const Icon(Icons.install_mobile_outlined),
                  onPressed: () {
                    Navigator.pop(c);
                    _confirmInstall(entry);
                  },
                  label: const Text('Install APK'),
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.save_alt),
                onPressed: () {
                  Navigator.pop(c);
                  _save(entry);
                },
                label: const Text('Save file to device'),
              ),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  Navigator.pop(c);
                  _delete(entry);
                },
                label: const Text('Delete from My Files'),
              ),
              const SizedBox(height: 4),
              Text(
                entry.name.toLowerCase().endsWith('.apk')
                  ? 'APK installation requires your approval and Android’s '
                    'system installer. Never install unknown APKs.'
                  : 'Open with uses compatible apps installed on your phone. '
                    'ZipEase does not run Windows executables.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
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
            'Created ZIPs and extracted files stay grouped under their '
            'source archive. Open a ZIP folder to browse its original folders.',
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
            final unknown = snap.data!.where((e) => !e.created)
                .map((e) => p.split(e.relativePath).first).toSet()
                .difference(_sessionNames.keys.toSet());
            if (unknown.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _loadNames(snap.data!);
              });
            }
            final matches = snap.data!.where((e) =>
              (_source == _Source.all ||
                (_source == _Source.created && e.created) ||
                (_source == _Source.extracted && !e.created)) &&
              (_category == null || e.category == _category) &&
              ArchiveLibrary.matchesSearch(e, _query,
                sourceArchive: e.created ? null :
                    _sessionNames[p.split(e.relativePath).first])
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
            final grouped = <String, List<LibraryEntry>>{};
            for (final entry in matches) {
              final id = entry.created ? 'created' : p.split(entry.relativePath).first;
              grouped.putIfAbsent(id, () => []).add(entry);
            }
            final groups = grouped.entries.toList()
              ..sort((a, b) => b.value.first.modified.compareTo(a.value.first.modified));
            return Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Align(alignment: Alignment.centerLeft,
                  child: Text('${matches.length} file(s) in ${groups.length} group(s)',
                    style: Theme.of(context).textTheme.bodySmall)),
              ),
              Expanded(child: ListView.builder(
                itemCount: groups.length,
                itemBuilder: (context, index) {
                  final group = groups[index];
                  final created = group.key == 'created';
                  final expanded = _expandedSessions.contains(group.key);
                  return Card(
                    margin: const EdgeInsets.fromLTRB(12, 5, 12, 5),
                    child: Column(children: [
                      ListTile(
                        leading: Icon(created ? Icons.archive_outlined : Icons.folder_zip_outlined),
                        title: Text(created ? 'Created ZIPs' :
                            (_sessionNames[group.key] ?? 'Extracted ZIP'),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${group.value.length} file(s)'),
                        trailing: Icon(created ? (expanded
                            ? Icons.expand_less : Icons.expand_more) : Icons.chevron_right),
                        onTap: () async {
                          if (!created) {
                            // Browse the complete archive, even if My Files
                            // currently has a category/search filter applied.
                            try {
                              final folders = await _library.folderPaths(group.key);
                              if (!mounted) return;
                              final entries = snap.data!.where((item) =>
                                !item.created &&
                                p.split(item.relativePath).first == group.key,
                              ).toList();
                              final deleted = await Navigator.push<bool>(context,
                                MaterialPageRoute<bool>(builder: (_) =>
                                  ArchiveFolderBrowser(
                                    archiveName: _sessionNames[group.key]
                                        ?? 'Earlier extraction',
                                    sessionId: group.key,
                                    entries: entries,
                                    folderPaths: folders,
                                    onFileTap: _details,
                                  ),
                                ),
                              );
                              if (deleted == true && mounted) {
                                _expandedSessions.remove(group.key);
                                _refresh();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content:
                                    Text('Extracted ZIP folder removed from My Files.')),
                                );
                              }
                            } catch (_) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content:
                                    Text('Could not open this ZIP folder.')),
                                );
                              }
                            }
                            return;
                          }
                          setState(() {
                            if (expanded) {
                              _expandedSessions.remove(group.key);
                            } else {
                              _expandedSessions.add(group.key);
                            }
                          });
                        },
                      ),
                      if (created && expanded) ...[
                        const Divider(height: 1),
                        for (final entry in group.value)
                          ListTile(
                            contentPadding: const EdgeInsets.only(left: 26, right: 12),
                            leading: Icon(ArchiveFileTypes.icon(entry.name)),
                            title: Text(created ? entry.name :
                                p.joinAll(p.split(entry.relativePath).skip(1)),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${ArchiveFileTypes.label(entry.name)}'
                                ' · ${_size(entry.size)}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _details(entry),
                          ),
                      ],
                    ]),
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
