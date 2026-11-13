// Bookmarks, highlights and notes, kept in Quill's own storage (annotations.json) and never
// written into a book. Places are chapter + character offsets in the book's text with the quoted
// words, so they survive font and layout changes.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

enum AnnotationKind { bookmark, highlight }

class Annotation {
  const Annotation({
    required this.id,
    required this.bookId,
    required this.kind,
    required this.spine,
    required this.start,
    required this.end,
    this.href = '',
    this.quote = '',
    this.note = '',
    this.color = 0,
    this.chapter = '',
    required this.created,
    required this.updated,
    this.source = '',
    this.locator = '',
  });

  final String id;
  final String bookId;
  final AnnotationKind kind;

  /// Spine index and character range in that chapter's text (a bookmark has start == end).
  final int spine;
  final int start;
  final int end;

  /// The chapter file, so the place can be re-found if the spine order ever differs.
  final String href;

  /// The marked words (or the first words of a bookmarked page), for lists and for repair.
  final String quote;
  final String note;

  /// Index into [highlightColors].
  final int color;
  final String chapter;
  final int created;
  final int updated;

  /// Where an imported annotation came from (e.g. a Moon Reader record id); empty for Quill's own.
  final String source;

  /// The place as a reader locator (JSON), so either reader can go there. A bookmark made in
  /// the standard reader (any format) has only this: its [spine] is -1.
  final String locator;

  Annotation copyWith({String? note, int? color, int? updated}) => Annotation(
    id: id,
    bookId: bookId,
    kind: kind,
    spine: spine,
    start: start,
    end: end,
    href: href,
    quote: quote,
    note: note ?? this.note,
    color: color ?? this.color,
    chapter: chapter,
    created: created,
    updated: updated ?? this.updated,
    source: source,
    locator: locator,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'book': bookId,
    'kind': kind.name,
    'spine': spine,
    'start': start,
    'end': end,
    'href': href,
    'quote': quote,
    'note': note,
    'color': color,
    'chapter': chapter,
    'created': created,
    'updated': updated,
    'source': source,
    if (locator.isNotEmpty) 'locator': locator,
  };

  static Annotation? fromJson(Map<String, dynamic> j) {
    final kind = AnnotationKind.values.where((k) => k.name == j['kind']).firstOrNull;
    if (kind == null || j['id'] is! String || j['book'] is! String) return null;
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return Annotation(
      id: j['id'] as String,
      bookId: j['book'] as String,
      kind: kind,
      spine: n('spine'),
      start: n('start'),
      end: n('end'),
      href: j['href'] as String? ?? '',
      quote: j['quote'] as String? ?? '',
      note: j['note'] as String? ?? '',
      color: n('color'),
      chapter: j['chapter'] as String? ?? '',
      created: n('created'),
      updated: n('updated'),
      source: j['source'] as String? ?? '',
      locator: j['locator'] as String? ?? '',
    );
  }
}

/// A book's bookmarks, highlights and notes as readable text (Markdown), in reading order.
String annotationsAsText(String title, List<Annotation> notes) {
  final out = StringBuffer('# $title\n');
  var chapter = '';
  for (final a in notes) {
    if (a.chapter != chapter) {
      chapter = a.chapter;
      if (chapter.isNotEmpty) out.write('\n## $chapter\n');
    }
    if (a.kind == AnnotationKind.bookmark) {
      out.write('\n- Bookmark: ${a.quote.isEmpty ? '(page)' : '${a.quote}…'}\n');
    } else {
      out.write('\n> ${a.quote}\n');
      if (a.note.isNotEmpty) out.write('\n${a.note}\n');
    }
  }
  return out.toString();
}

/// Highlight colours as ARGB (drawn translucent over the page).
const highlightColors = [0xFFFFD54F, 0xFF81C784, 0xFF64B5F6, 0xFFF48FB1, 0xFFFFB74D];

class AnnotationStore extends ChangeNotifier {
  AnnotationStore(this.file);

  final File file;
  static const version = 1;
  List<Annotation> _all = [];
  Future<void> _writes = Future.value();
  final _random = Random();

  /// Set when the last write failed: the change is in memory but not yet on disk.
  bool unsaved = false;

  Future<void> load() async {
    try {
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _all = [
        for (final j in (data['annotations'] as List? ?? const []))
          ?Annotation.fromJson((j as Map).cast<String, dynamic>()),
      ];
      notifyListeners();
    } catch (_) {
      // An unreadable file is left untouched on disk; nothing is shown rather than guessed.
      unsaved = false;
    }
  }

  List<Annotation> forBook(String bookId) =>
      _all.where((a) => a.bookId == bookId).toList()..sort((a, b) => a.spine != b.spine ? a.spine - b.spine : (a.start != b.start ? a.start - b.start : a.created - b.created));

  List<Annotation> get all => List.unmodifiable(_all);

  /// Replaces every annotation (restoring a backup).
  Future<void> replaceAll(List<Annotation> all) {
    _all = [...all];
    notifyListeners();
    return _save();
  }

  /// Completes when every change so far is on disk (or has failed and is marked [unsaved]).
  Future<void> flush() => _writes;

  String newId() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_random.nextInt(1 << 32).toRadixString(36)}';

  Future<void> put(Annotation a) {
    _all = [..._all.where((x) => x.id != a.id), a];
    notifyListeners();
    return _save();
  }

  Future<void> remove(String id) {
    _all = _all.where((x) => x.id != id).toList();
    notifyListeners();
    return _save();
  }

  // Queued, atomic: write a temporary file, then rename over the old one.
  Future<void> _save() {
    final snapshot = jsonEncode({'v': version, 'annotations': [for (final a in _all) a.toJson()]});
    return _writes = _writes.then((_) async {
      try {
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(snapshot, flush: true);
        await temp.rename(file.path);
        unsaved = false;
      } catch (_) {
        unsaved = true;
        notifyListeners();
      }
    });
  }
}
