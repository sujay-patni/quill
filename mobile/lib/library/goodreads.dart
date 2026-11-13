// Goodreads, without an account link: Goodreads has no API for apps any more, so Quill opens a
// book's Goodreads page for the reader to mark there, writes a CSV that Goodreads' own
// "Import" page accepts, and reads the CSV that its "Export" page makes.
import 'book.dart';

/// The book's Goodreads page by ISBN when known, else a title and author search.
String goodreadsUrl(Book b) => b.isbn.isNotEmpty
    ? 'https://www.goodreads.com/book/isbn/${Uri.encodeComponent(b.isbn)}'
    : 'https://www.goodreads.com/search?q=${Uri.encodeQueryComponent('${b.title} ${b.author}'.trim())}';

String _cell(Object? v) {
  final s = '${v ?? ''}';
  return s.contains(RegExp('[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

String _date(int ms) {
  if (ms == 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}

/// Finished or rated books in the columns Goodreads' import reads (the names of its own export).
/// With [since], only books finished after that time.
String goodreadsCsv(List<Book> books, {int since = 0}) {
  final rows = <List<Object?>>[
    const ['Title', 'Author', 'ISBN', 'ISBN13', 'My Rating', 'Date Read', 'Date Added', 'Bookshelves', 'Exclusive Shelf', 'Read Count'],
    for (final b in books)
      if ((b.finished || b.rating > 0) && (since == 0 || b.finishedAt > since))
        [
          b.title,
          b.author,
          b.isbn.length == 10 ? b.isbn : '',
          b.isbn.length == 13 ? b.isbn : '',
          b.rating,
          b.finished ? _date(b.finishedAt) : '',
          _date(b.addedAt),
          b.tags.map((t) => t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')).join(', '),
          b.finished ? 'read' : (b.progress > 0 ? 'currently-reading' : 'to-read'),
          b.finished ? 1 : 0,
        ],
  ];
  return '${rows.map((r) => r.map(_cell).join(',')).join('\r\n')}\r\n';
}

/// Rows of a CSV text (quoted cells, doubled quotes, line breaks inside quotes).
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  void endCell() {
    row.add(cell.toString());
    cell.clear();
  }

  void endRow() {
    endCell();
    if (row.length > 1 || row.single.isNotEmpty) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      endCell();
    } else if (c == '\n') {
      endRow();
    } else if (c != '\r' && c != '﻿') {
      cell.write(c);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

/// One book from a Goodreads export.
class GoodreadsBook {
  const GoodreadsBook({required this.title, required this.author, this.isbns = const {}, this.rating = 0, this.readAt = 0, this.read = false, this.shelves = const []});
  final String title;
  final String author;
  final Set<String> isbns;
  final int rating;
  final int readAt;
  final bool read;
  final List<String> shelves;
}

String _digits(String s) => s.toUpperCase().replaceAll(RegExp('[^0-9X]'), '');

/// The books in a Goodreads export file. Throws [FormatException] when it is not one.
List<GoodreadsBook> parseGoodreadsExport(String text) {
  final rows = parseCsv(text);
  if (rows.isEmpty) throw const FormatException('This file is empty.');
  final columns = {for (var i = 0; i < rows.first.length; i++) rows.first[i].trim().toLowerCase(): i};
  if (!columns.containsKey('title') || !columns.containsKey('author')) {
    throw const FormatException('This is not a Goodreads export (no Title and Author columns).');
  }
  String at(List<String> row, String column) {
    final i = columns[column];
    return i == null || i >= row.length ? '' : row[i].trim();
  }

  int date(String s) {
    final m = RegExp(r'^(\d{4})[/-](\d{1,2})[/-](\d{1,2})').firstMatch(s);
    return m == null ? 0 : DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)).millisecondsSinceEpoch;
  }

  const builtIn = {'read', 'to-read', 'currently-reading'};
  return [
    for (final row in rows.skip(1))
      if (at(row, 'title').isNotEmpty)
        GoodreadsBook(
          title: at(row, 'title'),
          author: at(row, 'author'),
          isbns: {_digits(at(row, 'isbn')), _digits(at(row, 'isbn13'))}..remove(''),
          rating: (int.tryParse(at(row, 'my rating')) ?? 0).clamp(0, 5),
          readAt: date(at(row, 'date read')),
          read: at(row, 'exclusive shelf') == 'read' || at(row, 'date read').isNotEmpty,
          shelves: [
            for (final s in at(row, 'bookshelves').split(','))
              if (s.trim().isNotEmpty && !builtIn.contains(s.trim())) s.trim(),
          ],
        ),
  ];
}

// Title without a "(Series, #2)" suffix or subtitle, lower case, letters and digits only.
String _titleKey(String title) =>
    title.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '').split(':').first.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

String _authorKey(String author) {
  final first = author.split(RegExp(r',\s*|\s+&\s+|\s+and\s+')).first.trim();
  final words = first.toLowerCase().split(RegExp(r'[^\p{L}]+', unicode: true)).where((w) => w.isNotEmpty);
  return words.isEmpty ? '' : words.last;
}

/// A Quill book and what a Goodreads export would add to it.
class GoodreadsChange {
  const GoodreadsChange(this.before, this.after);
  final Book before;
  final Book after;
}

/// What a Goodreads export adds to the library: a rating where Quill has none, read and its
/// date where Quill does not have the book finished, and Goodreads shelves as tags. Nothing set
/// in Quill is overwritten. Books are matched by ISBN, else by title and the author's surname.
List<GoodreadsChange> previewGoodreads(List<Book> books, List<GoodreadsBook> export) {
  final byIsbn = <String, GoodreadsBook>{};
  final byName = <String, GoodreadsBook>{};
  for (final g in export) {
    for (final isbn in g.isbns) {
      byIsbn[isbn] = g;
    }
    byName.putIfAbsent('${_titleKey(g.title)}|${_authorKey(g.author)}', () => g);
  }
  final changes = <GoodreadsChange>[];
  for (final b in books) {
    final g = (b.isbn.isNotEmpty ? byIsbn[_digits(b.isbn)] : null) ?? byName['${_titleKey(b.title)}|${_authorKey(b.author)}'];
    if (g == null) continue;
    var next = b;
    final provenance = {...b.provenance};
    if (b.rating == 0 && g.rating > 0) {
      next = next.copyWith(rating: g.rating);
      provenance['rating'] = 'goodreads';
    }
    if (!b.finished && g.read) next = next.copyWith(finished: true, finishedAt: g.readAt);
    if (b.finished && b.finishedAt == 0 && g.readAt != 0) next = next.copyWith(finishedAt: g.readAt);
    final tags = [...b.tags, ...g.shelves.where((s) => !b.tags.any((t) => t.toLowerCase() == s.toLowerCase()))];
    if (tags.length != b.tags.length) next = next.copyWith(tags: tags);
    if (b.isbn.isEmpty && g.isbns.isNotEmpty) {
      next = next.copyWith(isbn: g.isbns.firstWhere((i) => i.length == 13, orElse: () => g.isbns.first));
    }
    if (!identical(next, b)) changes.add(GoodreadsChange(b, next.copyWith(provenance: provenance)));
  }
  return changes;
}
