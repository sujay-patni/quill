import '../library/book.dart';
import '../library/names.dart';
import '../library/stats.dart';

// One-time Moon Reader migration (docs/releases/0.1/plans/moon-import.md).
//
// The native side reads only an allowlist from the .mrstd backup (books, statistics and notes
// tables of mrbooks.db, and positions10.xml) and hands the rows here. Everything below is pure:
// parse, match to Quill's books, build a preview, then apply. Nothing is written until the user
// applies the preview.

const moonSource = 'moon-reader';

class MoonBook {
  const MoonBook({
    required this.path,
    this.title = '',
    this.author = '',
    this.description = '',
    this.category = '',
    this.addedAt = 0,
  });

  final String path;
  final String title;
  final String author;
  final String description;
  final String category;
  final int addedAt;

  static MoonBook fromRow(Map<String, Object?> r) => MoonBook(
    path: '${r['filename'] ?? ''}',
    title: '${r['book'] ?? ''}'.trim(),
    author: '${r['author'] ?? ''}'.trim(),
    description: '${r['description'] ?? ''}'.trim(),
    category: '${r['category'] ?? ''}',
    addedAt: int.tryParse('${r['addTime'] ?? ''}') ?? 0,
  );
}

class MoonDay {
  const MoonDay(this.day, this.ms, this.words, this.percent);

  final int day; // days since 1970-01-01, as Quill counts
  final int ms;
  final int words;
  final double? percent;
}

class MoonStats {
  const MoonStats({required this.path, required this.days});

  final String path;
  final List<MoonDay> days;

  static MoonStats fromRow(Map<String, Object?> r) =>
      MoonStats(path: '${r['filename'] ?? ''}', days: parseDays('${r['dates'] ?? ''}'));
}

class MoonPosition {
  const MoonPosition({required this.percent, this.chapter, required this.raw});

  final double percent; // 0..100 of the whole book
  final int? chapter;
  final String raw;
}

class MoonHighlight {
  const MoonHighlight({
    required this.path,
    required this.text,
    required this.chapter,
    required this.position,
    required this.time,
    this.color = 0,
    this.underline = false,
    this.strikethrough = false,
  });

  final String path;
  final String text;
  final int chapter;
  final int position;
  final int time;
  final int color;
  final bool underline;
  final bool strikethrough;

  static MoonHighlight fromRow(Map<String, Object?> r) {
    int n(String k) => num.tryParse('${r[k] ?? ''}')?.toInt() ?? 0;
    return MoonHighlight(
      path: '${r['filename'] ?? ''}',
      text: '${r['original'] ?? ''}',
      chapter: n('lastChapter'),
      position: n('lastPosition'),
      time: n('time'),
      color: n('highlightColor'),
      underline: n('underline') != 0,
      strikethrough: n('strikethrough') != 0,
    );
  }

  Map<String, Object> toJson(String bookId) => {
    'book': bookId,
    'text': text,
    'chapter': chapter,
    'position': position,
    'time': time,
    'color': color,
    'underline': underline,
    'strikethrough': strikethrough,
    'source': moonSource,
  };
}

class MoonBackup {
  const MoonBackup({
    required this.hash,
    this.books = const [],
    this.stats = const [],
    this.positions = const {},
    this.highlights = const [],
  });

  final String hash;
  final List<MoonBook> books;
  final List<MoonStats> stats;
  // Normalised path → position.
  final Map<String, MoonPosition> positions;
  final List<MoonHighlight> highlights;

  // What the native reader returns: table rows and the raw positions XML.
  static MoonBackup fromNative(Map<Object?, Object?> m) {
    List<Map<String, Object?>> rows(String k) => [
      for (final r in (m[k] as List?) ?? const []) (r as Map).map((k, v) => MapEntry('$k', v)),
    ];
    return MoonBackup(
      hash: '${m['hash'] ?? ''}',
      books: [for (final r in rows('books')) MoonBook.fromRow(r)],
      stats: [for (final r in rows('statistics')) MoonStats.fromRow(r)],
      positions: parsePositionsXml('${m['positions'] ?? ''}'),
      highlights: [for (final r in rows('notes')) MoonHighlight.fromRow(r)],
    );
  }
}

// ---- Parsers ----

// "<Series name>\n#2.0#\n(tag)\nShelf\n" → series, number and tags. Moon Reader writes the series
// in angle brackets, its number between #, and tags either in parentheses or as plain lines.
({String series, double? index, List<String> tags}) parseCategory(String raw) {
  var series = '';
  double? index;
  final tags = <String>[];
  for (final line in raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty)) {
    if (line.startsWith('<') && line.endsWith('>')) {
      series = line.substring(1, line.length - 1).trim();
    } else if (line.length > 2 && line.startsWith('#') && line.endsWith('#')) {
      index = double.tryParse(line.substring(1, line.length - 1));
    } else {
      final tag = line.startsWith('(') && line.endsWith(')') ? line.substring(1, line.length - 1).trim() : line;
      if (tag.isNotEmpty && !tags.contains(tag)) tags.add(tag);
    }
  }
  return (series: series, index: index != null && index > 0 ? index : null, tags: tags);
}

// Statistics "dates": one line per day, "day|ms@words #percent%"; percent may be decimal.
final _dayLine = RegExp(r'^(\d+)\|(\d+)@(\d+)(?:\s*#([\d.]+)%)?$');

List<MoonDay> parseDays(String raw) => [
  for (final line in raw.split('\n'))
    if (_dayLine.firstMatch(line.trim()) case final m?)
      MoonDay(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), m[4] == null ? null : double.tryParse(m[4]!)),
];

// positions10.xml values: "chapter@split#offset:percent%" (reflowable), "page:percent%" (PDF and
// comics) or "0" (never opened). Other forms (PDF view states) carry no book position.
final _reflowable = RegExp(r'^(\d+)@\d+#\d+:([\d.]+)%$');
final _paged = RegExp(r'^\d+:([\d.]+)%$');

MoonPosition? parsePosition(String raw) {
  final v = raw.trim();
  if (_reflowable.firstMatch(v) case final m?) {
    return MoonPosition(percent: double.parse(m[2]!), chapter: int.parse(m[1]!), raw: v);
  }
  if (_paged.firstMatch(v) case final m?) return MoonPosition(percent: double.parse(m[1]!), raw: v);
  return null;
}

final _xmlString = RegExp(r'<string name="([^"]*)">([^<]*)</string>');

Map<String, MoonPosition> parsePositionsXml(String xml) {
  final out = <String, MoonPosition>{};
  for (final m in _xmlString.allMatches(xml)) {
    final position = parsePosition(_unescape(m[2]!));
    if (position != null) out[normalisePath(_unescape(m[1]!))] = position;
  }
  return out;
}

String _unescape(String s) => s
    .replaceAll('&apos;', "'")
    .replaceAll('&quot;', '"')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

// Moon Reader falls back to the raw file name when a book has no title, and keeps authors as
// stored ("Brown, Dan", "rick riordan"). Only clean values replace Quill's file-name guesses.
final _fileLike = RegExp(r'_|\.(epub|pdf|cbz|cbr)$|\.(com|net|org)\b', caseSensitive: false);

String? cleanMoonTitle(String raw) {
  final t = raw.trim();
  if (t.isEmpty || _fileLike.hasMatch(t) || t == t.toLowerCase()) return null;
  return t;
}

String? cleanMoonAuthor(String raw) {
  var a = raw.trim();
  if (a.isEmpty || _fileLike.hasMatch(a) || a == a.toLowerCase()) return null;
  final parts = a.split(',');
  if (parts.length == 2 && parts.every((p) => p.trim().isNotEmpty)) a = '${parts[1].trim()} ${parts[0].trim()}';
  return a;
}

String normalisePath(String p) => p.trim().toLowerCase().replaceAll(RegExp(r'/+'), '/');

String _key(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

// ---- Matching ----

enum MatchBy { path, fileName, titleAuthor }

// Moon Reader stores full device paths (/sdcard/Download/Books/<folder>/<file>); Quill stores the
// file's folder relative to the chosen Books folder. Prefer that relative path, then a unique file
// name, then a unique title + author. Anything ambiguous stays unmatched and is reported.
class BookMatcher {
  BookMatcher(List<Book> books) {
    for (final b in books) {
      final relative = normalisePath([if (b.folder.isNotEmpty) b.folder, b.name].join('/'));
      _byRelative.putIfAbsent(relative, () => []).add(b);
      _byName.putIfAbsent(b.name.toLowerCase(), () => []).add(b);
      _byCompact.putIfAbsent(_compact(b.name), () => []).add(b);
      _byTitle.putIfAbsent('${_key(b.title)}|${_key(b.author)}', () => []).add(b);
    }
  }

  final _byRelative = <String, List<Book>>{};
  final _byName = <String, List<Book>>{};
  // File names with only letters and digits: a rename like "_cs_lewis" → "_C_S_Lewis" still matches.
  final _byCompact = <String, List<Book>>{};

  static String _compact(String name) => name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final _byTitle = <String, List<Book>>{};

  ({Book book, MatchBy by})? match(String path, {String title = '', String author = ''}) {
    final p = normalisePath(path);
    final parts = p.split('/');
    // Longest relative suffix first: "<folder>/<file>", then "<file>" as a path.
    for (var i = 1; i < parts.length; i++) {
      final hits = _byRelative[parts.sublist(i).join('/')];
      if (hits != null && hits.length == 1) return (book: hits.single, by: MatchBy.path);
      if (hits != null && hits.length > 1) return null;
    }
    final named = _byName[parts.last];
    if (named != null && named.length == 1) return (book: named.single, by: MatchBy.fileName);
    final compact = _byCompact[_compact(parts.last)];
    if (compact != null && compact.length == 1) return (book: compact.single, by: MatchBy.fileName);
    if (title.isNotEmpty) {
      final titled = _byTitle['${_key(title)}|${_key(author)}'];
      if (titled != null && titled.length == 1) return (book: titled.single, by: MatchBy.titleAuthor);
    }
    return null;
  }
}

// ---- Preview ----

class BookChange {
  BookChange(this.before, this.after, this.by, {this.days = const [], this.highlights = const []});

  final Book before;
  final Book after;
  final MatchBy by;
  final List<ReadingDay> days;
  final List<MoonHighlight> highlights;

  List<String> get changed => [
    if (before.title != after.title) 'title',
    if (before.author != after.author) 'author',
    if (before.series != after.series || before.seriesIndex != after.seriesIndex) 'series',
    if (before.tags.join('|') != after.tags.join('|')) 'tags',
    if (before.description != after.description) 'description',
    if (before.addedAt != after.addedAt) 'added',
    if (before.startedAt != after.startedAt) 'started',
    if (before.progress != after.progress) 'progress',
    if (before.finished != after.finished) 'finished',
    if (days.isNotEmpty) 'stats',
    if (highlights.isNotEmpty) 'highlights',
  ];
}

class ImportPreview {
  ImportPreview({
    required this.hash,
    required this.changes,
    required this.unmatched,
    required this.keptQuillPosition,
    required this.alreadyImported,
  });

  final String hash;
  final List<BookChange> changes;
  // Moon Reader paths with no unique Quill book.
  final List<String> unmatched;
  // Books whose Quill position is newer than Moon Reader's, left as they are.
  final int keptQuillPosition;
  final bool alreadyImported;

  int get matchedByPath => changes.where((c) => c.by == MatchBy.path).length;
  int get matchedOther => changes.length - matchedByPath;
  int get withChanges => changes.where((c) => c.changed.isNotEmpty).length;
  int get positions => changes.where((c) => c.before.progress != c.after.progress).length;
  int get newlyFinished => changes.where((c) => c.after.finished && !c.before.finished).length;
  int get series => changes.where((c) => c.changed.contains('series')).length;
  int get statsDays => changes.fold(0, (n, c) => n + c.days.length);
  int get statsMs => changes.fold(0, (n, c) => n + c.days.fold(0, (m, d) => m + d.ms));
  int get highlights => changes.fold(0, (n, c) => n + c.highlights.length);
}

int _localNoon(int day) {
  final utc = DateTime.utc(1970, 1, 1).add(Duration(days: day));
  return DateTime(utc.year, utc.month, utc.day, 12).millisecondsSinceEpoch;
}

// Builds what an import would change. Rules (plan "Behaviour" 3):
// - a field the user edited in Quill is never overwritten; book metadata from the file is kept
//   for title/author; Moon Reader fills series, number, tags, description where not the user's;
// - a position is imported only for books not yet read in Quill, labelled approximate;
// - >= 99 % (position or last stats day) marks the book finished on its last reading day;
// - stats replace earlier Moon Reader rows for that book, never Quill's own rows.
ImportPreview previewImport(List<Book> books, MoonBackup backup, {String? previousHash}) {
  final matcher = BookMatcher(books);
  final unmatched = <String>[];
  final byBook = <String, ({Book book, MatchBy by, MoonBook? meta})>{};

  void add(String path, {MoonBook? meta}) {
    final hit = matcher.match(path, title: meta?.title ?? '', author: meta?.author ?? '');
    if (hit == null) {
      if (!unmatched.contains(path)) unmatched.add(path);
      return;
    }
    final prior = byBook[hit.book.id];
    byBook[hit.book.id] = (book: hit.book, by: prior?.by ?? hit.by, meta: meta ?? prior?.meta);
  }

  for (final b in backup.books) {
    add(b.path, meta: b);
  }
  for (final s in backup.stats) {
    add(s.path);
  }
  for (final path in backup.positions.keys) {
    if (!backup.books.any((b) => normalisePath(b.path) == path)) add(path);
  }
  final statsByBook = <String, List<MoonDay>>{};
  for (final s in backup.stats) {
    final hit = matcher.match(s.path);
    if (hit != null) statsByBook.putIfAbsent(hit.book.id, () => []).addAll(s.days);
  }
  final positionByBook = <String, MoonPosition>{};
  for (final e in backup.positions.entries) {
    final meta = backup.books.where((b) => normalisePath(b.path) == e.key).firstOrNull;
    final hit = matcher.match(e.key, title: meta?.title ?? '', author: meta?.author ?? '');
    if (hit != null) positionByBook[hit.book.id] = e.value;
  }
  final highlightsByBook = <String, List<MoonHighlight>>{};
  for (final h in backup.highlights) {
    final hit = matcher.match(h.path);
    if (hit != null) highlightsByBook.putIfAbsent(hit.book.id, () => []).add(h);
  }

  var kept = 0;
  final changes = <BookChange>[];
  for (final entry in byBook.values) {
    final before = entry.book;
    var after = before;
    final provenance = {...before.provenance};
    final meta = entry.meta;
    bool mine(String f) => before.editedByUser(f);

    if (meta != null) {
      final cat = parseCategory(meta.category);
      if (!mine('series') && cat.series.isNotEmpty) {
        after = after.copyWith(series: cat.series, seriesIndex: cat.index);
        provenance['series'] = moonSource;
      }
      if (!mine('tags') && cat.tags.isNotEmpty) {
        after = after.copyWith(tags: {...after.tags, ...cat.tags}.toList());
        provenance['tags'] = moonSource;
      }
      if (!mine('description') && after.description.isEmpty && meta.description.isNotEmpty) {
        after = after.copyWith(description: meta.description);
        provenance['description'] = moonSource;
      }
      // Titles and authors from the book file itself stay; file-name guesses are replaced.
      final titleGuessed = before.title == displayTitle(before.name) || before.title == legacyTitle(before.name);
      final moonTitle = cleanMoonTitle(meta.title);
      if (!mine('title') && titleGuessed && moonTitle != null) {
        after = after.copyWith(title: moonTitle);
        provenance['title'] = moonSource;
      }
      final moonAuthor = cleanMoonAuthor(meta.author);
      if (!mine('author') && before.author == displayAuthor(before.name) && moonAuthor != null) {
        after = after.copyWith(author: moonAuthor);
        provenance['author'] = moonSource;
      }
      if (meta.addedAt > 0 && (after.addedAt == 0 || meta.addedAt < after.addedAt)) {
        after = after.copyWith(addedAt: meta.addedAt);
      }
    }

    final days = (statsByBook[before.id] ?? const <MoonDay>[]).toList()..sort((a, b) => a.day.compareTo(b.day));
    final readingDays = [
      for (final d in days)
        if (d.ms > 0)
          ReadingDay(
            day: d.day,
            ms: d.ms,
            wordsImported: d.words,
            progressAtEnd: d.percent == null ? null : (d.percent! / 100).clamp(0.0, 1.0),
            source: moonSource,
          ),
    ];
    if (readingDays.isNotEmpty) {
      final first = _localNoon(readingDays.first.day);
      if (after.startedAt == 0 || first < after.startedAt) after = after.copyWith(startedAt: first);
    }

    final position = positionByBook[before.id];
    final readInQuill = before.opened > 0 || before.locator.isNotEmpty;
    if (position != null && position.percent > 0) {
      if (readInQuill) {
        kept++;
      } else {
        after = after.copyWith(progress: (position.percent / 100).clamp(0.0, 1.0), locator: '', approximate: true);
      }
    }
    final lastPercent = days.isEmpty ? null : days.last.percent;
    final done = (position != null && position.percent >= 99) || (lastPercent != null && lastPercent >= 99);
    if (done && !before.finished && !mine('finished')) {
      after = after.copyWith(
        finished: true,
        finishedAt: readingDays.isEmpty ? 0 : _localNoon(readingDays.last.day),
        progress: readInQuill ? after.progress : 1.0,
      );
    }

    after = after.copyWith(provenance: provenance);
    changes.add(
      BookChange(before, after, entry.by, days: readingDays, highlights: highlightsByBook[before.id] ?? const []),
    );
  }
  changes.sort((a, b) => a.before.title.toLowerCase().compareTo(b.before.title.toLowerCase()));
  return ImportPreview(
    hash: backup.hash,
    changes: changes,
    unmatched: unmatched,
    keptQuillPosition: kept,
    alreadyImported: previousHash != null && previousHash == backup.hash,
  );
}
