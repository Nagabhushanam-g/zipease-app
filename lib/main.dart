import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:path/path.dart' as p;

import 'services/ad_service.dart';
import 'services/archive_service.dart';
import 'services/archive_library.dart';
import 'screens/my_files_screen.dart';
import 'services/archive_file_types.dart';
import 'services/export_service.dart';
import 'services/zip_import_service.dart';
import 'widgets/test_banner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The first screen must never wait for Google Play services or an ad network.
  runApp(const ZipEaseApp());
}

class ZipEaseApp extends StatelessWidget {
  const ZipEaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ZipEase',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4658C9)),
        scaffoldBackgroundColor: const Color(0xFFF7F8FC),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF7F8FC)),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _archiveService = ArchiveService();
  final _ads = InterstitialCoordinator();
  bool _busy = false;
  bool _adsReady = false;
  bool _openingZip = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    // Initialize ads only AFTER Flutter has drawn the home screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAds();
      ZipImportService.registerOpenWithHandler(
        _openSelectedZip,
        _error,
      ).catchError((Object error) {
        _error(error);
      });
    });
  }

  Future<void> _initializeAds() async {
    // Build with --dart-define=ZIPEASE_ENABLE_ADS=false to diagnose devices
    // where Android's Google Mobile Ads SDK fails during initialization.
    const adsEnabled = bool.fromEnvironment(
      'ZIPEASE_ENABLE_ADS',
      defaultValue: true,
    );
    if (!adsEnabled || !mounted) return;
    try {
      await MobileAds.instance.initialize().timeout(
        const Duration(seconds: 12),
      );
      if (!mounted) return;
      setState(() => _adsReady = true);
      _ads.preload();
    } catch (error) {
      // Optional advertisements must never prevent ZIP and unzip from working.
      debugPrint('ZipEase: ads unavailable; continuing without ads: $error');
    }
  }

  @override
  void dispose() {
    ZipImportService.detachOpenWithHandler();
    _ads.dispose();
    super.dispose();
  }

  void _error(Object error) {
    if (!mounted) return;
    final message = error is FormatException
        ? error.message
        : error is PlatformException
            ? (error.message ?? 'Could not read the selected ZIP.')
            : 'Could not complete the operation. Check the ZIP file, password, or available storage.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _perform(Future<ArchiveOutput> Function() job, String description,
      {String? sourceName}) async {
    setState(() { _busy = true; _status = description; });
    try {
      final output = await job();
      if (mounted) setState(() => _status = 'Saving to My Files…');
      // Permanently retain every successful create/extract operation.
      final stored = await ArchiveLibrary().keep(output, sourceName: sourceName);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (context) =>
            ResultScreen(output: stored, service: _archiveService, ads: _ads)),
      );
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() { _busy = false; _status = ''; });
    }
  }

  Future<void> _compress() async {
    if (_busy) return;
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (!mounted || files.isEmpty) return;
      await _perform(() => _archiveService.compress(files), 'Creating your ZIP file…');
    } catch (error) { _error(error); }
  }

  Future<void> _extract() => _extractPicked(browseAllFiles: false);

  Future<void> _browseAllZipFiles() => _extractPicked(browseAllFiles: true);

  Future<void> _extractPicked({required bool browseAllFiles}) async {
    if (_busy || _openingZip) return;
    try {
      final selected = await ZipImportService.pickZip(
        browseAllFiles: browseAllFiles,
      );
      if (selected != null) await _openSelectedZip(selected);
    } catch (error) {
      _error(error);
    }
  }

  /// Shared by file pickers and Android's Open with/VIEW integration.
  Future<void> _openSelectedZip(PickedZip selected) async {
    try {
      if (!mounted) return;
      if (_busy || _openingZip) {
        _error(const FormatException(
          'Finish the current ZIP operation before opening another archive.',
        ));
        return;
      }
      _openingZip = true;
      final password = await _passwordPrompt();
      if (password == null || !mounted) return;
      await _perform(
        () => _archiveService.extractLocalZip(
          selected.path,
          password: password,
        ),
        'Extracting your ZIP file…',
        sourceName: selected.name,
      );
    } catch (error) {
      _error(error);
    } finally {
      _openingZip = false;
      // Only the temporary imported copy is removed, not the original ZIP.
      try {
        await selected.deleteTemporaryCopy();
      } catch (error) {
        debugPrint('Failed to remove ZIP temporary copy: $error');
      }
    }
  }

  Future<String?> _passwordPrompt() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Extract ZIP'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('If your archive is password-protected, enter the password. Otherwise leave it blank.'),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password (optional)', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Extract')),
          ],
        ),
      );
    } finally { controller.dispose(); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ZipEase', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(onPressed: () => showAboutDialog(context: context,
          applicationName: 'ZipEase', applicationVersion: '0.1.0',
          children: [const Text('Free ZIP & UnZIP utility. All archive processing stays on your device. Test advertisements only.')]),
          icon: const Icon(Icons.info_outline), tooltip: 'About ZipEase')],
      ),
      bottomNavigationBar: _adsReady ? const TestBanner() : null,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 26), children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF485DD4), Color(0xFF6B7CF1)]),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.folder_zip_outlined, color: Colors.white, size: 40),
              SizedBox(height: 24),
              Text('Files made simple.', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: Colors.white)),
              SizedBox(height: 7),
              Text('Create and open ZIP files securely, without uploading anything.',
                style: TextStyle(color: Color(0xFFE9ECFF), height: 1.4)),
            ]),
          ),
          const SizedBox(height: 22),
          Text('What would you like to do?', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.unarchive_outlined,
            title: 'Extract ZIP',
            description: 'Unzip files and export the extracted folder',
            onTap: _busy ? null : _extract,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _browseAllZipFiles,
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              label: const Text("Can't find the ZIP? Browse all files"),
            ),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.archive_outlined,
            title: 'Create ZIP',
            description: 'Select multiple files and compress them',
            onTap: _busy ? null : _compress,
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.folder_copy_outlined,
            title: 'My Files',
            description: 'Created ZIPs and extracted photos, Word, Excel, PPT, APK and more',
            onTap: _busy ? null : () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (_) => const MyFilesScreen()),
              );
            },
          ),
          if (_busy) ...[
            const SizedBox(height: 22),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(_status, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 20),
          const Row(children: [Icon(Icons.lock_outline, size: 18, color: Color(0xFF65718A)),
            SizedBox(width: 8), Expanded(child: Text('Private by design · Works offline · No file uploads',
              style: TextStyle(color: Color(0xFF65718A), fontSize: 12)))]),
        ]),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.title, required this.description, required this.onTap});
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(
              color: const Color(0xFFEEF0FF), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: const Color(0xFF4658C9), size: 28)),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 4),
              Text(description, style: const TextStyle(fontSize: 12, color: Color(0xFF647085))),
            ])),
            const Icon(Icons.chevron_right, color: Color(0xFF65718A)),
          ]),
        ),
      ),
    );
  }
}

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.output, required this.service, required this.ads});

  final ArchiveOutput output;
  final ArchiveService service;
  final InterstitialCoordinator ads;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late final Future<List<String>> _preview = widget.service.preview(widget.output);
  bool _saving = false;
  bool _saved = false;
  String _filter = '';

  Future<void> _export({
    required String path,
    required String fileName,
    required bool wholeOutput,
  }) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final saved = await ExportService.saveToDevice(path, fileName: fileName);
      if (!mounted) return;
      if (saved) {
        if (wholeOutput) setState(() => _saved = true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Saved ${fileName} to your selected location.'),
        ));
        widget.ads.onSuccessfulExport();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not save. Check file name, space and folder access.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    var name = p.basename(widget.output.path);
    if (widget.output.isDirectory) {
      final zipName = await ArchiveLibrary().extractionName(name);
      name = ArchiveLibrary.exportFolderName(zipName);
    }
    await _export(
      path: widget.output.path,
      fileName: name,
      wholeOutput: true,
    );
  }

  Future<void> _saveFile(String relativeName) async {
    // Names originate from our extracted folder scan. Android also checks
    // the canonical source path is located inside app-private storage.
    if (relativeName.isEmpty || p.isAbsolute(relativeName) ||
        p.split(relativeName).contains('..')) return;
    await _export(
      path: p.join(widget.output.path, relativeName),
      fileName: p.basename(relativeName),
      wholeOutput: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFolder = widget.output.isDirectory;
    return Scaffold(
      appBar: AppBar(title: const Text('Completed')),
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.check_circle_rounded, size: 64, color: Color(0xFF369A73)),
          const SizedBox(height: 12),
          Text(isFolder ? 'ZIP extracted successfully' : 'ZIP created successfully',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 21)),
          const SizedBox(height: 6),
          Text('${widget.output.fileCount} file(s)', textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF647085))),
          const SizedBox(height: 6),
          const Text('Saved automatically in My Files',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF369A73), fontSize: 12)),
          const SizedBox(height: 16),
          if (isFolder) ...[
            const Text('Extracted files · tap one to save it separately',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search files in the ZIP',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(
                () => _filter = value.toLowerCase().trim(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: Card(child: FutureBuilder<List<String>>(
              future: _preview,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Unable to list extracted files.'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final allFiles = snapshot.data!;
                if (allFiles.isEmpty) {
                  return const Center(child: Text('This ZIP contains no files.'));
                }
                final visible = _filter.isEmpty ? allFiles :
                    allFiles.where((name) => name.toLowerCase().contains(_filter)).toList();
                if (visible.isEmpty) {
                  return const Center(child: Text('No matching files.'));
                }
                return ListView.separated(
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final name = visible[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(ArchiveFileTypes.icon(name)),
                      title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(ArchiveFileTypes.label(name)),
                      trailing: const Icon(Icons.save_alt_outlined),
                      enabled: !_saving,
                      onTap: () => _saveFile(name),
                    );
                  },
                  separatorBuilder: (_, index) => const Divider(height: 1),
                );
              },
            ))),
          ] else const Spacer(),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_saved ? Icons.check : Icons.save_alt),
            label: Text(_saving ? 'Saving…' :
              isFolder ? 'Export extracted folder' : 'Save ZIP to device'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _saving ? null : () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (_) => const MyFilesScreen()),
              );
            },
            icon: const Icon(Icons.folder_copy_outlined),
            label: const Text('View My Files'),
          ),
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Back to home'),
          ),
        ]),
      )),
    );
  }
}
