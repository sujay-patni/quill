import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../library/library.dart';
import 'moon_import.dart';
import '../oak.dart';

// Reads the backup through the native allowlisted reader (MainActivity "app.quill/moon").
class MoonBackupSource {
  const MoonBackupSource();

  static const _channel = MethodChannel('app.quill/moon');

  Future<String?> pick() => _channel.invokeMethod<String>('pick');

  Future<MoonBackup> read(String uri) async =>
      MoonBackup.fromNative((await _channel.invokeMethod<Map<Object?, Object?>>('read', {'uri': uri}))!);
}

// Import from Moon Reader: pick the .mrstd backup, preview every change, apply only on Import.
class MoonImportPage extends StatefulWidget {
  const MoonImportPage({super.key, required this.library, this.source = const MoonBackupSource(), this.uri});

  final Library library;
  final MoonBackupSource source;
  // Skips the picker (tests).
  final String? uri;

  @override
  State<MoonImportPage> createState() => _MoonImportPageState();
}

class _MoonImportPageState extends State<MoonImportPage> {
  ImportPreview? _preview;
  String? _error;
  String _status = 'Choose your Moon Reader backup (.mrstd)…';
  bool _applying = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final uri = widget.uri ?? await widget.source.pick();
      if (uri == null) {
        if (mounted) Navigator.pop(context);
        return;
      }
      setState(() => _status = 'Reading the backup…');
      final backup = await widget.source.read(uri);
      final preview = previewImport(widget.library.books, backup, previousHash: await widget.library.moonImportHash());
      if (mounted) setState(() => _preview = preview);
    } catch (e) {
      if (mounted) setState(() => _error = 'The backup could not be read. Nothing was changed.\n$e');
    }
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    try {
      await widget.library.applyMoonImport(_preview!);
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'The import stopped: $e\nA snapshot from before the import is kept.');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    return Scaffold(
      appBar: AppBar(flexibleSpace: const OakPanel(), title: const Text('Import from Moon Reader')),
      body: _error != null
          ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!))
          : p == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [const CircularProgressIndicator(), const SizedBox(height: 16), Text(_status)],
              ),
            )
          : _body(context, p),
      bottomNavigationBar: p == null || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _done
                    ? FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))
                    : FilledButton(
                        key: const Key('applyImport'),
                        onPressed: _applying || p.changes.isEmpty ? null : _apply,
                        child: Text(_applying ? 'Importing…' : 'Import'),
                      ),
              ),
            ),
    );
  }

  Widget _body(BuildContext context, ImportPreview p) {
    final text = Theme.of(context).textTheme;
    final hours = p.statsMs / 3600000;
    String plural(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';
    Widget line(String label, String value, {Key? key}) => Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: text.titleSmall),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (_done)
          _Note(icon: Icons.check_circle_outline, text: 'Imported. A snapshot from before the import is kept.')
        else if (p.alreadyImported)
          const _Note(
            icon: Icons.info_outline,
            text: 'This backup was imported before. Importing again changes nothing new.',
          )
        else
          const _Note(
            icon: Icons.visibility_outlined,
            text: 'Nothing has changed yet. Check the preview, then tap Import. Your own edits in Quill are kept.',
          ),
        const SizedBox(height: 8),
        line('Books found in Quill', '${p.changes.length}', key: const Key('importMatched')),
        line('  by folder and file name', '${p.matchedByPath}'),
        if (p.matchedOther > 0) line('  by file name or title', '${p.matchedOther}'),
        line('Not found in Quill', '${p.unmatched.length}', key: const Key('importUnmatched')),
        const Divider(),
        line('Positions to restore (approximate)', '${p.positions}'),
        if (p.keptQuillPosition > 0) line('Newer position in Quill kept', '${p.keptQuillPosition}'),
        line('Marked finished', '${p.newlyFinished}'),
        line('Series set', '${p.series}'),
        line('Reading time', '${hours.toStringAsFixed(hours < 10 ? 1 : 0)} h over ${plural(p.statsDays, 'day')}'),
        if (p.highlights > 0) line('Highlights kept for later', '${p.highlights}'),
        const SizedBox(height: 8),
        if (p.unmatched.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Not found (${p.unmatched.length})'),
            children: [
              for (final path in p.unmatched)
                ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(path.split('/').last)),
            ],
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('Changes by book (${p.withChanges})'),
          children: [
            for (final c in p.changes)
              if (c.changed.isNotEmpty)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(c.after.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(c.changed.join(' · ')),
                ),
          ],
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}
