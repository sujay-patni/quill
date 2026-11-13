// Backup & restore: save a backup where the reader chooses, restore one (with a preview, merged
// or replacing everything), the automatic backups, a spreadsheet of the library, and the resets
// that apply to every book.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../library/backup.dart';
import '../library/backup_files.dart';
import '../library/goodreads.dart';
import '../library/library.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.library, this.files = const BackupFiles(), this.temporary});

  final Library library;
  final BackupFiles files;

  /// Where files are prepared before saving (tests pass a directory).
  final Future<Directory> Function()? temporary;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;
  late Future<List<File>> _automatic = widget.library.backups();

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // One job at a time; a failure is said plainly and changes nothing.
  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } on BackupException catch (e) {
      _say(e.message);
    } on PlatformException catch (e) {
      _say(e.message ?? 'That did not work. Nothing was changed.');
    } catch (_) {
      _say('That did not work. Nothing was changed.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _automatic = widget.library.backups();
        });
      }
    }
  }

  Future<File> _prepared(String name) async {
    final dir = Directory('${(await (widget.temporary ?? getTemporaryDirectory)()).path}/export');
    await dir.create(recursive: true);
    return File('${dir.path}/$name');
  }

  Future<void> _saveBackup() => _run(() async {
    final name = 'Quill-backup-${_day(DateTime.now())}.$backupExtension';
    final file = await _prepared(name);
    await file.writeAsBytes(await widget.library.backupBytes(), flush: true);
    final saved = await widget.files.save(file, name, 'application/octet-stream');
    await file.delete();
    if (saved) _say('Backup saved');
  });

  Future<void> _saveCsv() => _run(() async {
    final name = 'Quill-books-${_day(DateTime.now())}.csv';
    final file = await _prepared(name);
    await file.writeAsString(booksCsv(widget.library.books, widget.library.stats), flush: true);
    final saved = await widget.files.save(file, name, 'text/csv');
    await file.delete();
    if (saved) _say('Spreadsheet saved');
  });

  Future<void> _saveGoodreads() async {
    final lib = widget.library;
    final last = await lib.goodreadsExportedAt();
    var since = 0;
    if (last != 0 && mounted) {
      final onlyNew = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Which books?'),
          content: Text('You last saved a Goodreads file on ${_day(DateTime.fromMillisecondsSinceEpoch(last))}.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('All finished and rated')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Finished since then')),
          ],
        ),
      );
      if (onlyNew == null) return;
      if (onlyNew) since = last;
    }
    await _run(() async {
      final csv = goodreadsCsv(lib.books, since: since);
      if (csv.trim().split('\r\n').length < 2) {
        _say('No finished or rated books to save.');
        return;
      }
      final name = 'Quill-for-Goodreads-${_day(DateTime.now())}.csv';
      final file = await _prepared(name);
      await file.writeAsString(csv, flush: true);
      final saved = await widget.files.save(file, name, 'text/csv');
      await file.delete();
      if (!saved) return;
      await lib.markGoodreadsExported();
      _say('Saved. Upload it at goodreads.com, My Books, Import and export.');
    });
  }

  Future<void> _readGoodreads() => _run(() async {
    final file = await widget.files.open();
    if (file == null) return;
    final List<GoodreadsChange> changes;
    try {
      changes = previewGoodreads(widget.library.books, parseGoodreadsExport(await file.readAsString()));
    } on FormatException catch (e) {
      _say(e.message);
      return;
    } on FileSystemException {
      _say('That file is not a Goodreads export.');
      return;
    } finally {
      if (await file.exists()) await file.delete();
    }
    if (changes.isEmpty) {
      _say('Nothing new for your books in that file.');
      return;
    }
    if (!mounted) return;
    final ratings = changes.where((c) => c.after.rating != c.before.rating).length;
    final finished = changes.where((c) => c.after.finished != c.before.finished).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add from Goodreads?'),
        content: Text(
          '${changes.length} of your books are in this file: $ratings ratings and $finished finished marks would be added, '
          'and Goodreads shelves become tags. Nothing you set in Quill is changed.\n\nA backup is taken first.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('applyGoodreads'), onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.library.applyGoodreads(changes);
    _say('Added from Goodreads');
  });

  Future<void> _restoreFromPicker() => _run(() async {
    final file = await widget.files.open();
    if (file == null) return;
    try {
      await _restore(file);
    } finally {
      if (await file.exists()) await file.delete();
    }
  });

  Future<void> _restore(File file) async {
    final backup = parseBackup(await file.readAsBytes());
    final (_, summary) = await widget.library.previewRestore(backup, merge: true);
    if (!mounted) return;
    final merge = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: SingleChildScrollView(
          child: Text(
            [
              if (summary.created != null) 'Made on ${_day(summary.created!)}.',
              '${summary.books} books in the backup: ${summary.exact} are on this phone'
                  '${summary.approximate > 0 ? ', ${summary.approximate} have a changed file (their place in the text is approximate)' : ''}'
                  '${summary.notHere > 0 ? ', ${summary.notHere} are not here (their records are kept for when the files are added)' : ''}.',
              '${summary.statsDays} days of reading time, ${summary.annotations} bookmarks and highlights, ${summary.covers} chosen covers.',
              '',
              'Merge keeps what you have here and adds what is in the backup (the more recent place in each book wins; ${summary.positions} books would move).',
              '',
              'Replace all puts everything back exactly as it was in the backup, including reader settings.',
              '',
              'A backup of how things are now is taken first.',
            ].join('\n'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            key: const Key('restoreReplace'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Replace all'),
          ),
          FilledButton(
            key: const Key('restoreMerge'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    if (merge == null) return;
    final (result, _) = await widget.library.previewRestore(backup, merge: merge);
    await widget.library.applyRestore(result);
    _say(merge ? 'Backup merged' : 'Backup restored');
  }

  Future<void> _confirm(String title, String body, Future<void> Function() action, String done) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text('$body\n\nA backup is taken first.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('confirmResetAll'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await action();
      _say(done);
    });
  }

  static String _label(File f) {
    final name = f.uri.pathSegments.last;
    final auto = RegExp(r'^Quill-auto-(\d{4}-\d{2}-\d{2})\.').firstMatch(name);
    if (auto != null) return 'Daily backup, ${auto.group(1)}';
    final before = RegExp(r'^Quill-before-(\d+)-(.+)\.[a-z]+$').firstMatch(name);
    if (before == null) return name;
    final at = DateTime.fromMillisecondsSinceEpoch(int.parse(before.group(1)!));
    final why = switch (before.group(2)!) {
      'restore' => 'a restore',
      'moon-import' => 'the Moon Reader import',
      'reset-progress' || 'reset-all-progress' => 'a progress reset',
      'reset-stats' || 'reset-all-stats' => 'a statistics reset',
      final other => other,
    };
    return 'Before $why, ${_day(at)} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final lib = widget.library;
    final small = Theme.of(context).textTheme.bodySmall;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup & restore'),
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
      ),
      body: ListView(
        children: [
          heading('Backup'),
          ListTile(
            key: const Key('backupNow'),
            leading: const Icon(Icons.save_alt),
            title: const Text('Back up now'),
            subtitle: const Text('One file with your places, statistics, notes, ratings, shelves, settings and chosen covers. Book files are not included.'),
            onTap: _saveBackup,
          ),
          ListTile(
            key: const Key('restoreFile'),
            leading: const Icon(Icons.restore),
            title: const Text('Restore from a file'),
            subtitle: const Text('Shows what is in the backup before anything changes.'),
            onTap: _restoreFromPicker,
          ),
          ListTile(
            key: const Key('exportCsv'),
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Save the book list as a spreadsheet'),
            subtitle: const Text('CSV: title, author, series, status, rating, dates and time read.'),
            onTap: _saveCsv,
          ),
          heading('Automatic backups'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Kept inside Quill: one a day, and one before every import, restore and reset. The newest seven of each are kept. Tap one to restore it.', style: small),
          ),
          FutureBuilder<List<File>>(
            future: _automatic,
            builder: (context, snap) {
              final all = snap.data ?? const <File>[];
              if (all.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(snap.connectionState == ConnectionState.done ? 'None yet.' : '…', style: small),
                );
              }
              return Column(
                children: [
                  for (final f in all)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.history),
                      title: Text(_label(f)),
                      subtitle: Text('${(f.lengthSync() / 1024).ceil()} KB'),
                      onTap: () => _run(() => _restore(f)),
                    ),
                ],
              );
            },
          ),
          heading('Goodreads'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Goodreads does not let apps mark books for you. Quill can open a book\'s Goodreads page, and exchange files with it.', style: small),
          ),
          ListTile(
            key: const Key('goodreadsExport'),
            leading: const Icon(Icons.upload_file),
            title: const Text('Save finished books for Goodreads'),
            subtitle: const Text('A file to upload at goodreads.com, My Books, Import and export.'),
            onTap: _saveGoodreads,
          ),
          ListTile(
            key: const Key('goodreadsImport'),
            leading: const Icon(Icons.download_outlined),
            title: const Text('Read a Goodreads export'),
            subtitle: const Text('Adds ratings, read dates and shelves for books you have here.'),
            onTap: _readGoodreads,
          ),
          heading('Reset'),
          ListTile(
            key: const Key('resetAllProgress'),
            leading: const Icon(Icons.restart_alt),
            title: const Text('Reset all reading progress'),
            subtitle: const Text('Every book goes back to unread. Ratings, tags, series, notes and statistics stay.'),
            onTap: () => _confirm(
              'Reset all reading progress?',
              'The place, progress and finished mark of all ${lib.books.length} books are cleared.',
              lib.resetAllProgress,
              'Reading progress reset',
            ),
          ),
          ListTile(
            key: const Key('resetAllStats'),
            leading: const Icon(Icons.timer_off_outlined),
            title: const Text('Reset all statistics'),
            subtitle: const Text('Clears all reading time, including time imported from Moon Reader.'),
            onTap: () => _confirm(
              'Reset all statistics?',
              'All recorded reading time is cleared.',
              lib.resetAllStats,
              'Statistics reset',
            ),
          ),
        ],
      ),
    );
  }
}
