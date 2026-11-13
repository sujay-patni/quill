// Reading statistics: per book, per local day. Pure rules plus a small JSON store.
import 'dart:convert';
import 'dart:io';

// One book on one day. `wordsImported` exists only for days imported from Moon Reader.
class ReadingDay {
  const ReadingDay({
    required this.day,
    this.ms = 0,
    this.pages = 0,
    this.wordsImported,
    this.progressAtEnd,
    this.source = 'quill',
  });

  // Local calendar day as days since 1970-01-01 (the same count Moon Reader uses).
  final int day;
  final int ms;
  final int pages;
  final int? wordsImported;
  final double? progressAtEnd;
  // 'quill' for time counted here, 'moon-reader' for imported days.
  final String source;

  ReadingDay add({int ms = 0, int pages = 0, double? progressAtEnd}) => ReadingDay(
    day: day,
    ms: this.ms + ms,
    pages: this.pages + pages,
    wordsImported: wordsImported,
    progressAtEnd: progressAtEnd ?? this.progressAtEnd,
    source: source,
  );

  Map<String, Object> toJson() => {
    'day': day,
    'ms': ms,
    'pages': pages,
    'wordsImported': ?wordsImported,
    'progressAtEnd': ?progressAtEnd,
    'source': source,
  };

  static ReadingDay fromJson(Map<String, dynamic> j) => ReadingDay(
    day: (j['day'] as num).toInt(),
    ms: (j['ms'] as num?)?.toInt() ?? 0,
    pages: (j['pages'] as num?)?.toInt() ?? 0,
    wordsImported: (j['wordsImported'] as num?)?.toInt(),
    progressAtEnd: (j['progressAtEnd'] as num?)?.toDouble(),
    source: (j['source'] ?? 'quill') as String,
  );
}

int dayOf(DateTime local) => DateTime.utc(local.year, local.month, local.day).millisecondsSinceEpoch ~/ 86400000;
DateTime dateOfDay(int day) => DateTime.utc(1970).add(Duration(days: day));

// Counts active reading time. Time counts only while the reader is in front and the reader
// did something (page turn or position change) within [idleCutoff]. Spans shorter than
// [minimumSession] are dropped, so a quick peek does not count as reading.
class ReadingTimer {
  ReadingTimer({this.idleCutoff = const Duration(minutes: 2), this.minimumSession = const Duration(seconds: 10)});

  final Duration idleCutoff;
  final Duration minimumSession;
  DateTime? _sessionStart;
  DateTime? _lastActivity;
  int _pages = 0;

  bool get running => _sessionStart != null;

  // A page turn or position change.
  void activity(DateTime now, {bool pageTurn = false}) {
    if (_lastActivity != null && now.difference(_lastActivity!) > idleCutoff) {
      // The reader went idle: the earlier span ended at its last activity.
      _pending.add(_close(_lastActivity!));
    }
    _sessionStart ??= now;
    _lastActivity = now;
    if (pageTurn) _pages++;
  }

  final List<ReadingSpan> _pending = [];

  // Ends the session (reader closed, app in background). Idle time at the end is not counted:
  // the session stops at the last activity, or [idleCutoff] after it, whichever is earlier.
  List<ReadingSpan> stop(DateTime now) {
    if (_lastActivity != null) {
      final end = now.difference(_lastActivity!) > idleCutoff ? _lastActivity! : now;
      _pending.add(_close(end));
    }
    final done = _pending.where((s) => s.duration >= minimumSession).toList();
    _pending.clear();
    return done;
  }

  ReadingSpan _close(DateTime end) {
    final span = ReadingSpan(_sessionStart!, end.isBefore(_sessionStart!) ? _sessionStart! : end, _pages);
    _sessionStart = null;
    _lastActivity = null;
    _pages = 0;
    return span;
  }
}

class ReadingSpan {
  const ReadingSpan(this.start, this.end, this.pages);
  final DateTime start;
  final DateTime end;
  final int pages;
  Duration get duration => end.difference(start);
}

// Splits a span across local midnights so each day gets its own share.
Map<int, int> msByDay(ReadingSpan span) {
  final out = <int, int>{};
  var cursor = span.start;
  while (cursor.isBefore(span.end)) {
    final midnight = DateTime(cursor.year, cursor.month, cursor.day + 1);
    final stop = midnight.isBefore(span.end) ? midnight : span.end;
    out.update(
      dayOf(cursor),
      (v) => v + stop.difference(cursor).inMilliseconds,
      ifAbsent: () => stop.difference(cursor).inMilliseconds,
    );
    cursor = stop;
  }
  return out;
}

class StatsSummary {
  const StatsSummary({
    required this.ms,
    required this.daysRead,
    required this.pages,
    required this.books,
    required this.currentStreak,
    required this.longestStreak,
  });
  final int ms;
  final int daysRead;
  final int pages;
  final int books;
  final int currentStreak;
  final int longestStreak;
}

class ReadingStats {
  ReadingStats([Map<String, List<ReadingDay>>? byBook]) : byBook = byBook ?? {};

  // Book id → days, sorted by day.
  final Map<String, List<ReadingDay>> byBook;

  List<ReadingDay> daysFor(String bookId) => byBook[bookId] ?? const [];

  // Adds a finished reading span for a book, split by day.
  void record(String bookId, ReadingSpan span, {double? progressAtEnd}) {
    final days = {for (final d in daysFor(bookId)) '${d.day}:${d.source}': d};
    final shares = msByDay(span);
    var first = true;
    for (final e in shares.entries) {
      final key = '${e.key}:quill';
      final prior = days[key] ?? ReadingDay(day: e.key);
      // Pages go to the first day of the span; progress to the last.
      days[key] = prior.add(
        ms: e.value,
        pages: first ? span.pages : 0,
        progressAtEnd: e.key == shares.keys.last ? progressAtEnd : null,
      );
      first = false;
    }
    byBook[bookId] = days.values.toList()..sort((a, b) => a.day.compareTo(b.day));
  }

  // Replaces one source's days for a book (re-importing Moon Reader replaces its own days only).
  void replaceSource(String bookId, String source, List<ReadingDay> days) {
    final kept = daysFor(bookId).where((d) => d.source != source);
    byBook[bookId] = [...kept, ...days]..sort((a, b) => a.day.compareTo(b.day));
    if (byBook[bookId]!.isEmpty) byBook.remove(bookId);
  }

  void resetBook(String bookId) => byBook.remove(bookId);
  void resetAll() => byBook.clear();

  // Totals for days in [from, to] (inclusive, day numbers); null bounds mean unbounded.
  StatsSummary summary({int? from, int? to, int? today, Set<String>? books}) {
    var ms = 0, pages = 0;
    final days = <int>{};
    final readBooks = <String>{};
    for (final e in byBook.entries) {
      if (books != null && !books.contains(e.key)) continue;
      for (final d in e.value) {
        if ((from != null && d.day < from) || (to != null && d.day > to)) continue;
        if (d.ms <= 0 && d.pages <= 0) continue;
        ms += d.ms;
        pages += d.pages;
        days.add(d.day);
        readBooks.add(e.key);
      }
    }
    final sorted = days.toList()..sort();
    var longest = 0, run = 0;
    int? previous;
    for (final d in sorted) {
      run = previous != null && d == previous + 1 ? run + 1 : 1;
      if (run > longest) longest = run;
      previous = d;
    }
    // A streak is current if it includes today or yesterday.
    var current = 0;
    final now = today ?? dayOf(DateTime.now());
    var cursor = days.contains(now) ? now : now - 1;
    while (days.contains(cursor)) {
      current++;
      cursor--;
    }
    return StatsSummary(
      ms: ms,
      daysRead: days.length,
      pages: pages,
      books: readBooks.length,
      currentStreak: current,
      longestStreak: longest,
    );
  }

  // Milliseconds per day across all books, for charts.
  Map<int, int> msPerDay({int? from, int? to}) {
    final out = <int, int>{};
    for (final days in byBook.values) {
      for (final d in days) {
        if ((from != null && d.day < from) || (to != null && d.day > to)) continue;
        out.update(d.day, (v) => v + d.ms, ifAbsent: () => d.ms);
      }
    }
    return out;
  }

  // Books ranked by time read in the period.
  List<MapEntry<String, int>> booksByTime({int? from, int? to}) {
    final out = <String, int>{};
    for (final e in byBook.entries) {
      final ms = e.value
          .where((d) => (from == null || d.day >= from) && (to == null || d.day <= to))
          .fold<int>(0, (s, d) => s + d.ms);
      if (ms > 0) out[e.key] = ms;
    }
    return out.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  Map<String, Object> toJson() => {
    'version': 1,
    'books': {for (final e in byBook.entries) e.key: e.value.map((d) => d.toJson()).toList()},
  };

  static ReadingStats fromJson(Map<String, dynamic> j) => ReadingStats({
    for (final e in ((j['books'] ?? const <String, dynamic>{}) as Map<String, dynamic>).entries)
      e.key: [for (final d in e.value as List) ReadingDay.fromJson(d as Map<String, dynamic>)],
  });

  static Future<ReadingStats> load(File file) async {
    try {
      return ReadingStats.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return ReadingStats();
    }
  }

  Future<void> save(File file) async {
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(toJson()), flush: true);
    await temp.rename(file.path);
  }
}

String formatDuration(int ms) {
  final minutes = ms ~/ 60000;
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}
