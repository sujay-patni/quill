// Shelf rules kept free of Flutter so they can be unit tested. Ported from Shelf.kt.
import 'book.dart';

enum ShelfKind {
  all('All Books'),
  series('Series'),
  universes('Universes'),
  orders('Reading orders'),
  authors('Authors'),
  tags('Tags'),
  folders('Folders');

  const ShelfKind(this.label);
  final String label;
}

class ShelfView {
  const ShelfView([this.kind = ShelfKind.all, this.value = '']);
  final ShelfKind kind;
  final String value;
  String get title => kind == ShelfKind.all ? kind.label : value;
}

enum ReadStatus { all, unread, reading, finished }

enum SortBy {
  title('Title'),
  author('Author'),
  recent('Recently read'),
  fileDate('File date');

  const SortBy(this.label);
  final String label;
}

enum FileType {
  all('All'),
  epub('EPUB'),
  pdf('PDF'),
  comics('Comics');

  const FileType(this.label);
  final String label;
}

class ShelfFilters {
  const ShelfFilters({this.status = ReadStatus.all, this.type = FileType.all, this.sort = SortBy.title});
  final ReadStatus status;
  final FileType type;
  final SortBy sort;
  bool get isDefault => status == ReadStatus.all && type == FileType.all;

  ShelfFilters copyWith({ReadStatus? status, FileType? type, SortBy? sort}) =>
      ShelfFilters(status: status ?? this.status, type: type ?? this.type, sort: sort ?? this.sort);
}

ReadStatus statusOf(Book b) {
  if (b.finished || b.progress >= 1) return ReadStatus.finished;
  if (b.progress > 0) return ReadStatus.reading;
  return ReadStatus.unread;
}

List<String> authorsOf(Book b) => b.author.split(', ').map((a) => a.trim()).where((a) => a.isNotEmpty).toList();

/// A named view the user saved: a shelf with its filters and sort (a "smart shelf").
class SavedShelf {
  const SavedShelf(this.name, this.view, this.filters);
  final String name;
  final ShelfView view;
  final ShelfFilters filters;

  Map<String, Object> toJson() => {
    'name': name,
    'kind': view.kind.name,
    'value': view.value,
    'status': filters.status.name,
    'type': filters.type.name,
    'sort': filters.sort.name,
  };

  static SavedShelf? fromJson(Map<String, dynamic> j) {
    T? pick<T extends Enum>(List<T> values, Object? name) => values.where((v) => v.name == name).firstOrNull;
    final kind = pick(ShelfKind.values, j['kind']);
    if (kind == null || j['name'] is! String) return null;
    return SavedShelf(
      j['name'] as String,
      ShelfView(kind, (j['value'] ?? '') as String),
      ShelfFilters(
        status: pick(ReadStatus.values, j['status']) ?? ReadStatus.all,
        type: pick(FileType.values, j['type']) ?? FileType.all,
        sort: pick(SortBy.values, j['sort']) ?? SortBy.title,
      ),
    );
  }
}

/// [orders] are the user's named reading orders: name → book ids in reading order.
bool inView(Book b, ShelfView view, {Map<String, List<String>> orders = const {}}) => switch (view.kind) {
  ShelfKind.all => true,
  ShelfKind.series => b.series == view.value,
  ShelfKind.universes => b.universe == view.value,
  ShelfKind.orders => orders[view.value]?.contains(b.id) ?? false,
  ShelfKind.authors => authorsOf(b).contains(view.value),
  ShelfKind.tags => b.tags.contains(view.value),
  ShelfKind.folders => b.folder == view.value,
};

// Names for a shelf picker tab, with book counts, alphabetical.
List<MapEntry<String, int>> shelfGroups(List<Book> books, ShelfKind kind, {Map<String, List<String>> orders = const {}}) {
  if (kind == ShelfKind.orders) {
    final ids = {for (final b in books) b.id};
    return [for (final e in orders.entries) MapEntry(e.key, e.value.where(ids.contains).length)]
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
  }
  final names = switch (kind) {
    ShelfKind.all || ShelfKind.orders => <String>[],
    ShelfKind.series => books.map((b) => b.series).toList(),
    ShelfKind.universes => books.map((b) => b.universe).toList(),
    ShelfKind.authors => books.expand(authorsOf).toList(),
    ShelfKind.tags => books.expand((b) => b.tags).toList(),
    ShelfKind.folders => books.map((b) => b.folder).toList(),
  }.where((n) => n.trim().isNotEmpty);
  final counts = <String, int>{};
  for (final n in names) {
    counts[n] = (counts[n] ?? 0) + 1;
  }
  return counts.entries.toList()..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
}

bool _typeMatches(Book b, FileType type) => switch (type) {
  FileType.all => true,
  FileType.epub => b.format == 'EPUB',
  FileType.pdf => b.format == 'PDF',
  FileType.comics => b.isComic,
};

List<Book> shelfBooks(
  List<Book> books,
  ShelfView view,
  ShelfFilters filters,
  String query, {
  Map<String, List<String>> orders = const {},
}) {
  final q = query.trim().toLowerCase();
  final shown = books.where(
    (b) =>
        inView(b, view, orders: orders) &&
        (filters.status == ReadStatus.all || statusOf(b) == filters.status) &&
        _typeMatches(b, filters.type) &&
        (q.isEmpty || '${b.title} ${b.author} ${b.series} ${b.universe} ${b.folder}'.toLowerCase().contains(q)),
  );
  int byTitle(Book a, Book b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
  final list = shown.toList();
  switch (filters.sort) {
    case SortBy.title:
      // A series shelf reads in series order; unnumbered books follow, by title.
      int bySeries(Book a, Book b) {
        final x = a.seriesIndex, y = b.seriesIndex;
        if (x != null && y != null && x != y) return x.compareTo(y);
        if ((x == null) != (y == null)) return x == null ? 1 : -1;
        return byTitle(a, b);
      }

      if (view.kind == ShelfKind.series) {
        list.sort(bySeries);
      } else if (view.kind == ShelfKind.orders) {
        // The user's own order.
        final order = orders[view.value] ?? const <String>[];
        final at = {for (var i = 0; i < order.length; i++) order[i]: i};
        list.sort((a, b) => (at[a.id] ?? 1 << 30).compareTo(at[b.id] ?? 1 << 30));
      } else if (view.kind == ShelfKind.universes) {
        // Series together (each in its own order), then standalones by title.
        list.sort((a, b) {
          if (a.series.isEmpty != b.series.isEmpty) return a.series.isEmpty ? 1 : -1;
          final c = a.series.toLowerCase().compareTo(b.series.toLowerCase());
          return c != 0 ? c : bySeries(a, b);
        });
      } else {
        list.sort(byTitle);
      }
    case SortBy.author:
      list.sort((a, b) {
        if (a.author.isEmpty != b.author.isEmpty) return a.author.isEmpty ? 1 : -1;
        final c = a.author.toLowerCase().compareTo(b.author.toLowerCase());
        return c != 0 ? c : byTitle(a, b);
      });
    case SortBy.recent:
      list.sort((a, b) => a.opened != b.opened ? b.opened.compareTo(a.opened) : byTitle(a, b));
    case SortBy.fileDate:
      list.sort((a, b) => a.modified != b.modified ? b.modified.compareTo(a.modified) : byTitle(a, b));
  }
  return list;
}

// The book "Continue reading" opens: the last one opened in Quill, if any.
Book? continueBook(List<Book> books) {
  Book? best;
  for (final b in books) {
    if (b.opened > 0 && !b.missing && (best == null || b.opened > best.opened)) best = b;
  }
  return best;
}

// A screen locator may omit an anchor. In that case choose one contents entry,
// rather than marking every chapter in the resource as current. Ported from Contents.kt.
class ContentsTarget {
  const ContentsTarget(this.href, this.title);
  final String href;
  final String title;
}

int contentsIndex(List<ContentsTarget> targets, String href, {List<String> fragments = const [], String? title}) {
  String resourceOf(String h) => h.split('#').first;
  String anchorOf(String h) => h.contains('#') ? h.substring(h.indexOf('#') + 1) : '';
  final resource = resourceOf(href);
  final candidates = [
    for (var i = 0; i < targets.length; i++)
      if (resourceOf(targets[i].href) == resource) i,
  ];
  if (candidates.isEmpty) return -1;
  final anchors = [...fragments, if (anchorOf(href).isNotEmpty) anchorOf(href)];
  for (final i in candidates.reversed) {
    final a = anchorOf(targets[i].href);
    if (a.isNotEmpty && anchors.contains(a)) return i;
  }
  if (title != null && title.isNotEmpty) {
    for (final i in candidates) {
      if (targets[i].title == title) return i;
    }
  }
  for (final i in candidates) {
    if (!targets[i].href.contains('#')) return i;
  }
  return candidates.first;
}

// Whole-book progress. Readium's totalProgression can be 0 for EPUBs whose positions list is
// not computed, so fall back to the resource's place in the reading order plus progress in it.
double bookProgress(List<String> readingOrder, String href, {double? progression, double? totalProgression}) {
  if (totalProgression != null && totalProgression > 0) return totalProgression.clamp(0.0, 1.0);
  final resource = href.split('#').first;
  final index = readingOrder.indexWhere((h) => h.split('#').first == resource);
  if (index < 0 || readingOrder.isEmpty) return (totalProgression ?? progression ?? 0).clamp(0.0, 1.0);
  return ((index + (progression ?? 0).clamp(0.0, 1.0)) / readingOrder.length).clamp(0.0, 1.0);
}

// Inverse of the reading-order fallback above. Spine resources are navigation
// targets, not chapters or stable screen pages. 100% means the end of the last resource.
({int index, double progression})? readingOrderPosition(int count, double progress) {
  if (count <= 0 || !progress.isFinite) return null;
  final scaled = progress.clamp(0.0, 1.0) * count;
  final index = scaled.floor().clamp(0, count - 1);
  return (index: index, progression: (scaled - index).clamp(0.0, 1.0));
}

// Whether the reader is on the book's last page. Readium reports where a page starts, so the
// last page of a book is below 100%; use the page counters it provides instead.
bool isAtEnd({
  required List<String> readingOrder,
  required String href,
  int? currentPage,
  int? totalPages,
  double? progression,
  int? position,
  int? numberOfPages,
  double progress = 0,
}) {
  if (numberOfPages != null && numberOfPages > 0 && position != null) return position >= numberOfPages;
  final resource = href.split('#').first;
  final last = readingOrder.isNotEmpty && readingOrder.last.split('#').first == resource;
  // Readium's currentPage is a 0-based page index, so the last page is totalPages - 1.
  if (last && currentPage != null && totalPages != null && totalPages > 0) return currentPage >= totalPages - 1;
  if (last && progression != null) return progression >= 0.9;
  return progress >= 0.98;
}

// The next book to read on an ordered shelf (series, universe or reading order): the first one
// not finished. Null when all are finished or the shelf is empty.
Book? nextToRead(List<Book> ordered) {
  for (final b in ordered) {
    if (!b.missing && statusOf(b) != ReadStatus.finished) return b;
  }
  return null;
}
