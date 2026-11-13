// Backup and restore of everything Quill keeps about a library: one ZIP file (.quill) with a
// manifest, the library records, reading statistics, annotations, reader settings, pending Moon
// Reader highlights and the covers the user chose. Book files are never part of it.
//
// A backup file is untrusted input: only known entry names are read, sizes are capped, and
// nothing is ever written by an entry's own path.
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'annotations.dart';
import 'book.dart';
import 'shelf.dart';
import 'stats.dart';

const backupFormat = 1;
const backupExtension = 'quill';

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Everything Quill keeps, as plain values: the current state, or the inside of a backup.
class BackupContent {
  BackupContent({
    this.books = const [],
    this.folder = '',
    this.shelf = const {},
    this.orders = const {},
    this.saved = const [],
    ReadingStats? stats,
    this.annotations = const [],
    this.reader,
    this.bookSettings = const {},
    this.themes = const {},
    this.moonHighlights = const [],
    this.moonImport,
    this.covers = const {},
    this.created,
  }) : stats = stats ?? ReadingStats();

  final List<Book> books;
  final String folder;

  /// The open shelf and its filters, as written in library.json.
  final Map<String, dynamic> shelf;
  final Map<String, List<String>> orders;
  final List<SavedShelf> saved;
  final ReadingStats stats;
  final List<Annotation> annotations;

  /// The usual reader settings (reader.json); null when never saved.
  final Map<String, dynamic>? reader;

  /// Reader settings kept for one book (by book id), and named saved settings.
  final Map<String, dynamic> bookSettings;
  final Map<String, dynamic> themes;

  /// Moon Reader highlights waiting to be placed, and the record of the last Moon import.
  final List<Map<String, dynamic>> moonHighlights;
  final Map<String, dynamic>? moonImport;

  /// Covers the user chose, as JPEG bytes by book id.
  final Map<String, Uint8List> covers;

  /// When a backup was made (null for the current state).
  final DateTime? created;

  int get statsDays => stats.byBook.values.fold(0, (n, days) => n + days.length);
}

final _safeId = RegExp(r'^[A-Za-z0-9_.-]{1,128}$');
const _maxJson = 64 << 20;
const _maxCover = 8 << 20;
const _maxCovers = 5000;

/// The backup file for [content]. The ZIP is built off the UI thread.
Future<Uint8List> buildBackup(BackupContent content, {DateTime? now}) {
  final files = <String, Uint8List>{};
  void put(String name, Object json) => files[name] = utf8.encode(jsonEncode(json));
  final covers = {
    for (final e in content.covers.entries)
      if (_safeId.hasMatch(e.key)) e.key: e.value,
  };
  put('manifest.json', {
    'app': 'Quill',
    'format': backupFormat,
    'created': (now ?? DateTime.now()).toIso8601String(),
    'books': content.books.length,
    'statsDays': content.statsDays,
    'annotations': content.annotations.length,
    'covers': covers.length,
  });
  put('library.json', {
    'version': 1,
    'folder': content.folder,
    'shelf': content.shelf,
    'orders': content.orders,
    'saved': [for (final s in content.saved) s.toJson()],
    'books': [for (final b in content.books) b.toJson()],
  });
  put('stats.json', content.stats.toJson());
  put('annotations.json', {
    'v': AnnotationStore.version,
    'annotations': [for (final a in content.annotations) a.toJson()],
  });
  put('settings.json', {'reader': content.reader, 'books': content.bookSettings, 'themes': content.themes});
  put('moon.json', {'highlights': content.moonHighlights, 'import': content.moonImport});
  for (final e in covers.entries) {
    files['covers/${e.key}.jpg'] = e.value;
  }
  return Isolate.run(() => _zip(files));
}

Uint8List _zip(Map<String, Uint8List> files) {
  final archive = Archive();
  for (final e in files.entries) {
    archive.addFile(ArchiveFile.bytes(e.key, e.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Reads a backup file. Throws [BackupException] with a message for the reader when the file is
/// not a Quill backup, is damaged, or was made by a newer Quill.
BackupContent parseBackup(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const BackupException('This file is not a Quill backup.');
  }
  Map<String, dynamic>? json(String name) {
    final f = archive.findFile(name);
    if (f == null) return null;
    if (f.size > _maxJson) throw const BackupException('This backup is too large to read.');
    final value = jsonDecode(utf8.decode(f.content));
    return value is Map<String, dynamic> ? value : null;
  }

  try {
    final manifest = json('manifest.json');
    if (manifest == null || manifest['app'] != 'Quill' || manifest['format'] is! int) {
      throw const BackupException('This file is not a Quill backup.');
    }
    if (manifest['format'] as int > backupFormat) {
      throw const BackupException('This backup was made by a newer Quill. Update Quill, then restore it.');
    }
    final library = json('library.json');
    if (library == null) throw const BackupException('This backup has no library in it.');
    final settings = json('settings.json') ?? const {};
    final moon = json('moon.json') ?? const {};
    final covers = <String, Uint8List>{};
    for (final f in archive.files) {
      if (!f.isFile || !f.name.startsWith('covers/') || !f.name.endsWith('.jpg')) continue;
      final id = f.name.substring(7, f.name.length - 4);
      if (!_safeId.hasMatch(id) || f.size > _maxCover || covers.length >= _maxCovers) continue;
      covers[id] = f.content;
    }
    Map<String, dynamic> map(Object? v) => v is Map ? v.cast<String, dynamic>() : {};
    return BackupContent(
      books: [for (final j in library['books'] as List) Book.fromJson((j as Map).cast<String, dynamic>())],
      folder: library['folder'] as String? ?? '',
      shelf: map(library['shelf']),
      orders: {
        for (final e in map(library['orders']).entries) e.key: [for (final id in e.value as List) id as String],
      },
      saved: [
        for (final j in library['saved'] as List? ?? const []) ?SavedShelf.fromJson((j as Map).cast<String, dynamic>()),
      ],
      stats: ReadingStats.fromJson(json('stats.json') ?? const {}),
      annotations: [
        for (final j in (json('annotations.json') ?? const {})['annotations'] as List? ?? const [])
          ?Annotation.fromJson((j as Map).cast<String, dynamic>()),
      ],
      reader: settings['reader'] is Map ? map(settings['reader']) : null,
      bookSettings: map(settings['books']),
      themes: map(settings['themes']),
      moonHighlights: [for (final h in moon['highlights'] as List? ?? const []) map(h)],
      moonImport: moon['import'] is Map ? map(moon['import']) : null,
      covers: covers,
      created: DateTime.tryParse(manifest['created'] as String? ?? ''),
    );
  } on BackupException {
    rethrow;
  } catch (_) {
    throw const BackupException('This backup is damaged and could not be read.');
  }
}

/// How a book in a backup was found in the library on this phone.
enum MatchKind {
  /// The same file (same place or same name, and the same size).
  exact,

  /// Probably the same book, but the file differs: its place in the text is not carried over.
  approximate,
}

class BookMatch {
  const BookMatch(this.current, this.kind);
  final Book current;
  final MatchKind kind;
}

/// Finds each backup book in [current]: by id, then by file location, then by file name and
/// size, then by a file name that is unique on both sides. Quill keeps no content fingerprint,
/// so name and size stand in for one. Keyed by the backup book's id.
Map<String, BookMatch> matchBooks(List<Book> current, List<Book> backup) {
  final out = <String, BookMatch>{};
  final used = <String>{};
  void take(Book b, Book? c, {bool exact = false}) {
    if (c == null || used.contains(c.id) || out.containsKey(b.id)) return;
    used.add(c.id);
    out[b.id] = BookMatch(c, exact || c.size == b.size ? MatchKind.exact : MatchKind.approximate);
  }

  final byId = {for (final c in current) c.id: c};
  final byUri = {for (final c in current) c.uri: c};
  for (final b in backup) {
    take(b, byId[b.id]);
  }
  for (final b in backup) {
    take(b, byUri[b.uri]);
  }
  // Each later pass pairs only what is unique on both sides among the books still unpaired.
  void pass(String Function(Book) key, {required bool exact}) {
    final here = <String, List<Book>>{};
    for (final c in current.where((c) => !used.contains(c.id))) {
      here.putIfAbsent(key(c), () => []).add(c);
    }
    final there = <String, List<Book>>{};
    for (final b in backup.where((b) => !out.containsKey(b.id))) {
      there.putIfAbsent(key(b), () => []).add(b);
    }
    for (final e in there.entries) {
      final candidates = here[e.key];
      if (e.value.length == 1 && candidates != null && candidates.length == 1) {
        take(e.value.single, candidates.single, exact: exact);
      }
    }
  }

  pass((b) => '${b.name}\n${b.size}', exact: true);
  pass((b) => b.name, exact: false);
  return out;
}

/// What a restore would do, for the preview.
class RestoreSummary {
  const RestoreSummary({
    required this.created,
    required this.books,
    required this.exact,
    required this.approximate,
    required this.notHere,
    required this.positions,
    required this.statsDays,
    required this.annotations,
    required this.covers,
  });

  final DateTime? created;

  /// Books in the backup; how many are the same file here, a changed file here, or not here.
  final int books;
  final int exact;
  final int approximate;
  final int notHere;

  /// Books whose place or progress would change.
  final int positions;
  final int statsDays;
  final int annotations;
  final int covers;
}

Book _with(Book b, Map<String, Object?> changes) => Book.fromJson({...b.toJson(), ...changes});

// The record from the backup on the file that is here.
Book _replaced(Book here, Book from, MatchKind kind) => _with(from, {
  'id': here.id,
  'uri': here.uri,
  'name': here.name,
  'folder': here.folder,
  'size': here.size,
  'modified': here.modified,
  'missing': here.missing,
  if (kind == MatchKind.approximate && from.locator.isNotEmpty) ...{'locator': '', 'approximate': true},
});

int _earliest(int a, int b) => a == 0 ? b : (b == 0 ? a : (a < b ? a : b));

// Both records combined: the place read most recently, and anything the user set on either
// side (what was set here wins when both were). Merging the same backup twice changes nothing.
Book _merged(Book here, Book from, MatchKind kind) {
  final changes = <String, Object?>{};
  final hasPlace = from.locator.isNotEmpty || from.progress > 0;
  // A book with no place here (never read, or reset) takes the backup's place whatever its date.
  final untouched = here.progress == 0 && here.locator.isEmpty;
  if (hasPlace && (from.opened > here.opened || untouched)) {
    final approximate = kind == MatchKind.approximate && from.locator.isNotEmpty;
    changes.addAll({
      'progress': from.progress,
      'opened': from.opened,
      'locator': approximate ? '' : from.locator,
      'approximate': approximate || from.approximate,
    });
  }
  final provenance = {...here.provenance};
  final hereJson = here.toJson(), fromJson = from.toJson();
  for (final field in const ['title', 'author', 'series', 'universe', 'description', 'isbn']) {
    final mine = hereJson[field] as String, theirs = fromJson[field] as String;
    final take = (!here.editedByUser(field) && from.editedByUser(field)) || (mine.isEmpty && theirs.isNotEmpty);
    if (!take || mine == theirs && here.provenance[field] == from.provenance[field]) continue;
    changes[field] = theirs;
    if (field == 'series') changes['seriesIndex'] = from.seriesIndex;
    if (from.provenance[field] != null) provenance[field] = from.provenance[field]!;
  }
  if (here.series == from.series && here.seriesIndex == null && from.seriesIndex != null) {
    changes['seriesIndex'] = from.seriesIndex;
  }
  if (here.rating == 0 && from.rating != 0) {
    changes['rating'] = from.rating;
    if (from.provenance['rating'] != null) provenance['rating'] = from.provenance['rating']!;
  }
  changes.addAll({
    'favorite': here.favorite || from.favorite,
    'touched': here.touched || from.touched,
    'finished': here.finished || from.finished,
    'finishedAt': here.finishedAt > from.finishedAt ? here.finishedAt : from.finishedAt,
    'startedAt': _earliest(here.startedAt, from.startedAt),
    'addedAt': _earliest(here.addedAt, from.addedAt),
    'tags': [...here.tags, ...from.tags.where((t) => !here.tags.contains(t))],
    'provenance': provenance,
  });
  return _with(here, changes);
}

Annotation _moved(Annotation a, String bookId) =>
    a.bookId == bookId ? a : Annotation.fromJson({...a.toJson(), 'book': bookId})!;

// Days of two records of the same book: per day and source, the longer one. Never added up, so
// restoring the same backup twice does not double the reading time.
List<ReadingDay> _mergedDays(List<ReadingDay> a, List<ReadingDay> b) {
  final days = {for (final d in a) '${d.day}:${d.source}': d};
  for (final d in b) {
    final key = '${d.day}:${d.source}';
    final mine = days[key];
    if (mine == null || d.ms > mine.ms) days[key] = d;
  }
  return days.values.toList()..sort((x, y) => x.day != y.day ? x.day.compareTo(y.day) : x.source.compareTo(y.source));
}

/// The state after restoring [from] into [now], and a summary for the preview. Nothing is
/// written here. With [merge], both sides are combined; without it the backup's records replace
/// the current ones (files on this phone stay in the library, with the backup's records where
/// they match and none where they do not).
(BackupContent, RestoreSummary) restoreBackup(BackupContent now, BackupContent from, {required bool merge}) {
  final matches = matchBooks(now.books, from.books);
  final fromFor = {for (final b in from.books) if (matches[b.id] != null) matches[b.id]!.current.id: b};
  String idOf(String backupId) => matches[backupId]?.current.id ?? backupId;

  final books = <Book>[
    for (final here in now.books)
      if (fromFor[here.id] case final theirs?)
        (merge ? _merged : _replaced)(here, theirs, matches[theirs.id]!.kind)
      else if (merge)
        here
      else
        Book(id: here.id, uri: here.uri, name: here.name, folder: here.folder, size: here.size, modified: here.modified, missing: here.missing),
    // Records for books that are not on this phone wait for their files: a later scan of the
    // Books folder picks them up by file name and size.
    for (final b in from.books)
      if (matches[b.id] == null) _with(b, {'missing': true}),
  ];
  final ids = {for (final b in books) b.id};

  final stats = <String, List<ReadingDay>>{
    if (merge)
      for (final e in now.stats.byBook.entries) e.key: e.value,
  };
  for (final e in from.stats.byBook.entries) {
    final id = idOf(e.key);
    stats[id] = _mergedDays(stats[id] ?? const [], e.value);
  }

  final notes = <String, Annotation>{
    for (final a in from.annotations) a.id: _moved(a, idOf(a.bookId)),
  };
  if (merge) {
    for (final a in now.annotations) {
      final theirs = notes[a.id];
      if (theirs == null || theirs.updated <= a.updated) notes[a.id] = a;
    }
  }

  Map<String, T> keyed<T>(Map<String, T> mine, Map<String, T> theirs, {bool byBook = false}) => {
    for (final e in theirs.entries) byBook ? idOf(e.key) : e.key: e.value,
    if (merge) ...mine,
  };
  final orders = keyed(now.orders, {
    for (final e in from.orders.entries) e.key: [for (final id in e.value) idOf(id)],
  });
  final savedByName = keyed({for (final s in now.saved) s.name: s}, {for (final s in from.saved) s.name: s});
  final theirHighlights = [
    for (final h in from.moonHighlights) {...h, if (h['book'] is String) 'book': idOf(h['book'] as String)},
  ];
  final covers = keyed(now.covers, from.covers, byBook: true)..removeWhere((id, _) => !ids.contains(id));

  final result = BackupContent(
    books: books,
    folder: now.folder,
    shelf: merge || from.shelf.isEmpty ? now.shelf : from.shelf,
    orders: orders,
    saved: savedByName.values.toList(),
    stats: ReadingStats(stats),
    annotations: notes.values.toList(),
    reader: merge ? now.reader ?? from.reader : from.reader ?? now.reader,
    bookSettings: keyed(now.bookSettings, from.bookSettings, byBook: true),
    themes: keyed(now.themes, from.themes),
    moonHighlights: merge && now.moonHighlights.isNotEmpty ? now.moonHighlights : theirHighlights,
    moonImport: merge ? now.moonImport ?? from.moonImport : from.moonImport,
    covers: covers,
  );

  final before = {for (final b in now.books) b.id: b};
  final summary = RestoreSummary(
    created: from.created,
    books: from.books.length,
    exact: matches.values.where((m) => m.kind == MatchKind.exact).length,
    approximate: matches.values.where((m) => m.kind == MatchKind.approximate).length,
    notHere: from.books.length - matches.length,
    positions: books.where((b) {
      final was = before[b.id];
      return was != null && (was.locator != b.locator || was.progress != b.progress || was.finished != b.finished);
    }).length,
    statsDays: from.statsDays,
    annotations: from.annotations.length,
    covers: from.covers.length,
  );
  return (result, summary);
}

String _csvCell(Object? v) {
  final s = '${v ?? ''}';
  return s.contains(RegExp('[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

String _date(int ms) => ms == 0 ? '' : DateTime.fromMillisecondsSinceEpoch(ms).toIso8601String().substring(0, 10);

String _number(double n) => n == n.roundToDouble() ? '${n.round()}' : '$n';

/// The library as a spreadsheet (CSV, one row per book).
String booksCsv(List<Book> books, ReadingStats stats) {
  final rows = <List<Object?>>[
    const [
      'Title', 'Author', 'Series', 'Number in series', 'Universe', 'Status', 'Progress %', 'Rating', 'Favourite',
      'Tags', 'Added', 'Started', 'Finished', 'Minutes read', 'Format', 'ISBN', 'File', //
    ],
    for (final b in books)
      [
        b.title,
        b.author,
        b.series,
        b.seriesIndex == null ? '' : _number(b.seriesIndex!),
        b.universe,
        statusOf(b).name,
        (b.progress * 100).round(),
        b.rating == 0 ? '' : b.rating,
        b.favorite ? 'yes' : '',
        b.tags.join('; '),
        _date(b.addedAt),
        _date(b.startedAt),
        _date(b.finishedAt),
        stats.daysFor(b.id).fold<int>(0, (n, d) => n + d.ms) ~/ 60000,
        b.format,
        b.isbn,
        b.folder.isEmpty ? b.name : '${b.folder}/${b.name}',
      ],
  ];
  return '${rows.map((r) => r.map(_csvCell).join(',')).join('\r\n')}\r\n';
}
