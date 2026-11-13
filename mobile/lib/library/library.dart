import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'annotations.dart';
import 'backup.dart';
import 'book.dart';
import 'cover_store.dart';
import 'goodreads.dart';
import 'shelf.dart';
import 'stats.dart';
import '../import/moon_import.dart';

// Native folder access: Android's folder picker (content:// URIs) or the iOS Files picker
// (security-scoped file:// URLs). Books are read in place and never written.
class FolderAccess {
  static const _channel = MethodChannel('app.quill/folders');

  Future<String?> pick() => _channel.invokeMethod<String>('pick');
  Future<bool> hasAccess(String uri) async => await _channel.invokeMethod<bool>('hasAccess', {'uri': uri}) ?? false;
  Future<List<FoundFile>> scan(String uri) async {
    final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('scan', {'uri': uri}) ?? const [];
    return raw.map(FoundFile.fromMap).toList();
  }
}

// Quill's own records (books, positions, shelf choices), stored apart from the originals.
class Library extends ChangeNotifier {
  Library({FolderAccess? folders, Future<Directory> Function()? directory, CoverStore? covers})
    : _folders = folders ?? FolderAccess(),
      _directory = directory ?? getApplicationSupportDirectory,
      covers = covers ?? CoverStore(directory: directory ?? getApplicationSupportDirectory);

  final FolderAccess _folders;
  final Future<Directory> Function() _directory;
  // Cover thumbnails, built in the background after loading and after each scan.
  final CoverStore covers;

  List<Book> books = const [];
  String folderUri = '';
  String message = '';
  bool busy = false;
  ShelfView view = const ShelfView();
  ShelfFilters filters = const ShelfFilters();
  bool compact = false;
  // Named reading orders (book ids in reading order) and saved shelves.
  Map<String, List<String>> orders = {};
  List<SavedShelf> saved = [];
  Future<void> _writes = Future.value();

  Future<File> _file(String name) async => File('${(await _directory()).path}/$name');

  Future<AnnotationStore>? _annotations;

  /// Bookmarks, highlights and notes; loaded on first use.
  Future<AnnotationStore> annotations() => _annotations ??= () async {
    final store = AnnotationStore(await _file('annotations.json'));
    await store.load();
    return store;
  }();

  Future<void> load() async {
    try {
      final file = await _file('library.json');
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        books = (data['books'] as List).map((j) => Book.fromJson(j as Map<String, dynamic>)).toList();
        folderUri = (data['folder'] ?? '') as String;
        _readShelf((data['shelf'] ?? const {}) as Map<String, dynamic>);
        orders = {
          for (final e in ((data['orders'] as Map?) ?? const {}).entries)
            e.key as String: [for (final id in e.value as List) id as String],
        };
        saved = [
          for (final j in (data['saved'] as List? ?? const [])) ?SavedShelf.fromJson((j as Map).cast<String, dynamic>()),
        ];
      }
    } catch (e) {
      message = 'Saved library could not be read. Choose your Books folder again.';
    }
    notifyListeners();
    stats = await ReadingStats.load(await _file('stats.json'));
    notifyListeners();
    await covers.load();
    unawaited(covers.build(books));
  }

  Map<String, Object> _shelfJson() => {
    'kind': view.kind.name,
    'value': view.value,
    'status': filters.status.name,
    'type': filters.type.name,
    'sort': filters.sort.name,
    'compact': compact,
  };

  void _readShelf(Map<String, dynamic> shelf) {
    T pick<T extends Enum>(List<T> values, Object? name, T otherwise) =>
        values.where((v) => v.name == name).firstOrNull ?? otherwise;
    view = ShelfView(pick(ShelfKind.values, shelf['kind'], ShelfKind.all), (shelf['value'] ?? '') as String);
    filters = ShelfFilters(
      status: pick(ReadStatus.values, shelf['status'], ReadStatus.all),
      type: pick(FileType.values, shelf['type'], FileType.all),
      sort: pick(SortBy.values, shelf['sort'], SortBy.title),
    );
    compact = shelf['compact'] == true;
  }

  // Writes go through one queue and replace the file atomically, so a crash never leaves
  // half a library on disk.
  Future<void> _save() {
    final snapshot = jsonEncode({
      'version': 1,
      'folder': folderUri,
      'shelf': _shelfJson(),
      'orders': orders,
      'saved': [for (final s in saved) s.toJson()],
      'books': books.map((b) => b.toJson()).toList(),
    });
    _writes = _writes.then((_) async {
      final file = await _file('library.json');
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(snapshot, flush: true);
      await temp.rename(file.path);
    });
    return _writes;
  }

  Future<void> update(String id, Book Function(Book) change) {
    books = [for (final b in books) b.id == id ? change(b) : b];
    notifyListeners();
    return _save();
  }

  // Reading statistics, saved in stats.json beside the library.
  ReadingStats stats = ReadingStats();
  Future<void> _statsWrites = Future.value();

  Future<void> _saveStats() {
    final snapshot = ReadingStats.fromJson(jsonDecode(jsonEncode(stats.toJson())) as Map<String, dynamic>);
    _statsWrites = _statsWrites.then((_) async => snapshot.save(await _file('stats.json')));
    return _statsWrites;
  }

  // Adds finished reading spans for a book and notes when reading started.
  Future<void> recordReading(String id, List<ReadingSpan> spans, {double? progress}) async {
    if (spans.isEmpty) return;
    for (final span in spans) {
      stats.record(id, span, progressAtEnd: progress);
    }
    final first = spans.first.start.millisecondsSinceEpoch;
    books = [
      for (final b in books) b.id == id && (b.startedAt == 0 || b.startedAt > first) ? b.copyWith(startedAt: first) : b,
    ];
    notifyListeners();
    await Future.wait([_save(), _saveStats()]);
  }

  // Edits from the book information page. These fields are marked as the user's, so imports and
  // book metadata never overwrite them.
  /// Creates or replaces a reading order; an empty list removes it.
  Future<void> setOrder(String name, List<String> ids) {
    orders = {...orders}..remove(name);
    if (ids.isNotEmpty) orders[name] = ids;
    if (ids.isEmpty && view.kind == ShelfKind.orders && view.value == name) view = const ShelfView();
    notifyListeners();
    return _save();
  }

  /// Saves the current shelf, filters and sort under [name] (replacing one of that name).
  Future<void> saveShelf(String name) {
    saved = [...saved.where((s) => s.name != name), SavedShelf(name, view, filters)];
    notifyListeners();
    return _save();
  }

  Future<void> removeSaved(String name) {
    saved = saved.where((s) => s.name != name).toList();
    notifyListeners();
    return _save();
  }

  Future<void> edit(String id, Set<String> fields, Book Function(Book) change) => update(id, (b) {
    final next = change(b);
    return next.copyWith(provenance: {...b.provenance, for (final f in fields) f: 'user'});
  });

  Future<void> setFinished(String id, bool finished, {int? rating}) => update(
    id,
    (b) => b.copyWith(
      finished: finished,
      finishedAt: finished ? (b.finishedAt == 0 ? DateTime.now().millisecondsSinceEpoch : b.finishedAt) : 0,
      rating: rating,
    ),
  );

  // Every reset takes a full backup first (backups/, newest 7 kept).
  Future<void> resetProgress(String id) async {
    await autoBackup('reset-progress');
    await update(
      id,
      (b) => b.copyWith(locator: '', progress: 0, finished: false, finishedAt: 0, startedAt: 0, approximate: false),
    );
  }

  Future<void> resetBookStats(String id) async {
    await autoBackup('reset-stats');
    stats.resetBook(id);
    notifyListeners();
    await _saveStats();
  }

  Future<void> resetAllStats() async {
    await autoBackup('reset-all-stats');
    stats.resetAll();
    notifyListeners();
    await _saveStats();
  }

  Future<void> resetAllProgress() async {
    await autoBackup('reset-all-progress');
    books = [
      for (final b in books)
        b.copyWith(locator: '', progress: 0, finished: false, finishedAt: 0, startedAt: 0, approximate: false),
    ];
    notifyListeners();
    await _save();
  }

  // The hash of the last Moon Reader backup applied, if any (moon-import.json).
  Future<String?> moonImportHash() async {
    try {
      final j = jsonDecode(await (await _file('moon-import.json')).readAsString()) as Map<String, dynamic>;
      return j['hash'] as String?;
    } catch (_) {
      return null;
    }
  }

  // Applies a previewed Moon Reader import. A full backup is taken first; Moon Reader's statistics
  // replace only its own earlier rows; highlights are kept for annotations (moon-highlights.json).
  Future<void> applyMoonImport(ImportPreview preview) async {
    await autoBackup('moon-import');
    final byId = {for (final c in preview.changes) c.before.id: c};
    books = [for (final b in books) byId[b.id]?.after ?? b];
    for (final c in preview.changes) {
      stats.replaceSource(c.before.id, moonSource, c.days);
    }
    notifyListeners();
    await Future.wait([_save(), _saveStats()]);
    final highlights = [
      for (final c in preview.changes)
        for (final h in c.highlights) h.toJson(c.before.id),
    ];
    await (await _file('moon-highlights.json')).writeAsString(jsonEncode({'version': 1, 'highlights': highlights}));
    await (await _file('moon-import.json')).writeAsString(
      jsonEncode({
        'hash': preview.hash,
        'at': DateTime.now().toIso8601String(),
        'books': preview.changes.length,
        'unmatched': preview.unmatched.length,
        'positions': preview.positions,
        'finished': preview.newlyFinished,
        'statsDays': preview.statsDays,
        'highlights': highlights.length,
      }),
    );
  }

  // ---- Goodreads (goodreads.dart) ----

  /// Applies a previewed Goodreads export. A full backup is taken first.
  Future<void> applyGoodreads(List<GoodreadsChange> changes) async {
    if (changes.isEmpty) return;
    await autoBackup('goodreads-import');
    final byId = {for (final c in changes) c.before.id: c.after};
    books = [for (final b in books) byId[b.id] ?? b];
    notifyListeners();
    await _save();
  }

  /// When books were last saved for Goodreads (0 = never), so the next file can hold only newer ones.
  Future<int> goodreadsExportedAt() async => ((await _readJson('goodreads.json'))?['exportedAt'] as num?)?.toInt() ?? 0;

  Future<void> markGoodreadsExported() => _writeJson('goodreads.json', {'exportedAt': DateTime.now().millisecondsSinceEpoch});

  // ---- Backup and restore (backup.dart) ----

  Future<Map<String, dynamic>?> _readJson(String name) async {
    try {
      final value = jsonDecode(await (await _file(name)).readAsString());
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeJson(String name, Object? value) async {
    final file = await _file(name);
    if (value == null) {
      if (await file.exists()) await file.delete();
      return;
    }
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(value), flush: true);
    await temp.rename(file.path);
  }

  /// Everything Quill keeps, once every pending write is on disk.
  Future<BackupContent> content() async {
    await _writes;
    await _statsWrites;
    final notes = await annotations();
    await notes.flush();
    final extras = await _readJson('reader-extras.json') ?? const {};
    Map<String, dynamic> map(Object? v) => v is Map ? v.cast<String, dynamic>() : {};
    final chosen = <String, Uint8List>{};
    if (covers.loaded) {
      for (final id in covers.customIds) {
        try {
          chosen[id] = await covers.fileFor(id).readAsBytes();
        } catch (_) {}
      }
    }
    return BackupContent(
      books: books,
      folder: folderUri,
      shelf: _shelfJson(),
      orders: orders,
      saved: saved,
      stats: ReadingStats.fromJson(jsonDecode(jsonEncode(stats.toJson())) as Map<String, dynamic>),
      annotations: notes.all,
      reader: await _readJson('reader.json'),
      bookSettings: map(extras['books']),
      themes: map(extras['themes']),
      moonHighlights: [for (final h in (await _readJson('moon-highlights.json'))?['highlights'] as List? ?? const []) map(h)],
      moonImport: await _readJson('moon-import.json'),
      covers: chosen,
    );
  }

  /// A backup file of the current state.
  Future<Uint8List> backupBytes() async => buildBackup(await content());

  Future<Directory> _backups() async => Directory('${(await _directory()).path}/backups').create(recursive: true);

  static String _dayName(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // Keeps the newest seven of each kind: daily backups and the ones taken before a change.
  static Future<void> _prune(Directory dir, String prefix) async {
    final all = await dir.list().where((e) => e is File && e.uri.pathSegments.last.startsWith(prefix)).toList();
    all.sort((a, b) => b.path.compareTo(a.path));
    for (final old in all.skip(7)) {
      await old.delete();
    }
  }

  /// A full backup in Quill's own storage, taken before an import, a restore or a reset. If it
  /// cannot be written this throws, and the change that asked for it does not happen.
  Future<File> autoBackup(String reason) async {
    final dir = await _backups();
    final file = File('${dir.path}/Quill-before-${DateTime.now().millisecondsSinceEpoch}-$reason.$backupExtension');
    await file.writeAsBytes(await backupBytes(), flush: true);
    await _prune(dir, 'Quill-before-');
    return file;
  }

  /// One automatic backup per day Quill is used (the newest seven are kept). Never throws.
  Future<void> dailyBackup() async {
    try {
      if (books.isEmpty) return;
      final dir = await _backups();
      final file = File('${dir.path}/Quill-auto-${_dayName(DateTime.now())}.$backupExtension');
      if (await file.exists()) return;
      final temp = File('${file.path}.tmp');
      await temp.writeAsBytes(await backupBytes(), flush: true);
      await temp.rename(file.path);
      await _prune(dir, 'Quill-auto-');
    } catch (_) {}
  }

  /// The backups in Quill's own storage, newest first.
  Future<List<File>> backups() async {
    final dir = await _backups();
    final all = [
      await for (final e in dir.list())
        if (e is File && e.path.endsWith('.$backupExtension')) e,
    ];
    final times = {for (final f in all) f.path: (await f.lastModified()).millisecondsSinceEpoch};
    return all..sort((a, b) => times[b.path]!.compareTo(times[a.path]!));
  }

  /// What restoring [backup] would give, without changing anything.
  Future<(BackupContent, RestoreSummary)> previewRestore(BackupContent backup, {required bool merge}) async =>
      restoreBackup(await content(), backup, merge: merge);

  /// Makes [result] (from [previewRestore]) the current state. The state before it is backed up
  /// first. Every record goes through its usual atomic save.
  Future<void> applyRestore(BackupContent result) async {
    await autoBackup('restore');
    final notes = await annotations();
    books = result.books;
    orders = {for (final e in result.orders.entries) e.key: [...e.value]};
    saved = [...result.saved];
    _readShelf(result.shelf);
    stats = result.stats;
    // The folder is kept only while this phone still has access to it.
    if (folderUri.isEmpty && result.folder.isNotEmpty) {
      try {
        if (await _folders.hasAccess(result.folder)) folderUri = result.folder;
      } catch (_) {}
    }
    notifyListeners();
    await Future.wait([_save(), _saveStats(), notes.replaceAll(result.annotations)]);
    await _writeJson('reader.json', result.reader);
    await _writeJson(
      'reader-extras.json',
      result.bookSettings.isEmpty && result.themes.isEmpty ? null : {'books': result.bookSettings, 'themes': result.themes},
    );
    await _writeJson(
      'moon-highlights.json',
      result.moonHighlights.isEmpty ? null : {'version': 1, 'highlights': result.moonHighlights},
    );
    await _writeJson('moon-import.json', result.moonImport);
    if (covers.loaded) {
      final before = await content();
      for (final id in covers.customIds.toList()) {
        if (!result.covers.containsKey(id)) await covers.clearCustom(id);
      }
      final temp = await _file('restore-cover.tmp');
      for (final e in result.covers.entries) {
        if (listEquals(before.covers[e.key], e.value)) continue;
        await temp.writeAsBytes(e.value, flush: true);
        await covers.setCustom(e.key, temp);
      }
      if (await temp.exists()) await temp.delete();
      unawaited(covers.build(books));
    }
    message = 'Backup restored';
    notifyListeners();
  }

  Future<void> setShelf({ShelfView? view, ShelfFilters? filters, bool? compact}) {
    this.view = view ?? this.view;
    this.filters = filters ?? this.filters;
    this.compact = compact ?? this.compact;
    notifyListeners();
    return _save();
  }

  Future<void> chooseFolder() async {
    try {
      final uri = await _folders.pick();
      if (uri != null) await scan(uri);
    } on PlatformException catch (e) {
      message = e.message ?? 'Unable to open the folder picker.';
      notifyListeners();
    }
  }

  Future<void> rescan() => folderUri.isEmpty ? chooseFolder() : scan(folderUri);

  Future<void> scan(String uri) async {
    if (busy) return;
    busy = true;
    message = 'Looking through your Books folder…';
    notifyListeners();
    try {
      final found = await _folders.scan(uri);
      books = mergeScan(books, found);
      folderUri = uri;
      message = '${found.length} books · Originals stay in your folder';
      await _save();
      unawaited(covers.build(books));
    } on PlatformException catch (e) {
      message = e.message ?? 'Unable to read this folder. Your library is preserved.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
