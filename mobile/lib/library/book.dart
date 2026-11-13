import 'names.dart';

const Object _keep = Object();

// A source reference plus Quill's own reading record. The original file is never changed.
class Book {
  Book({
    required this.id,
    required this.uri,
    required this.name,
    required this.folder,
    required this.size,
    required this.modified,
    String? title,
    String? author,
    this.series = '',
    this.universe = '',
    this.progress = 0,
    this.locator = '',
    this.approximate = false,
    this.missing = false,
    this.touched = false,
    this.finished = false,
    this.opened = 0,
    this.seriesIndex,
    this.tags = const [],
    this.description = '',
    this.rating = 0,
    this.favorite = false,
    this.addedAt = 0,
    this.startedAt = 0,
    this.finishedAt = 0,
    this.isbn = '',
    this.provenance = const {},
  }) : title = title ?? displayTitle(name),
       author = author ?? displayAuthor(name);

  final String id;
  final String uri;
  final String name;
  final String folder;
  final int size;
  final int modified;
  final String title;
  final String author;
  final String series;
  // A wider setting several series and standalones share (e.g. the Cosmere); empty when none.
  final String universe;
  final double progress;
  // Readium locator JSON. Empty when the book was never opened or its file changed.
  final String locator;
  final bool approximate;
  final bool missing;
  final bool touched;
  final bool finished;
  final int opened;
  // Position in its series (1, 2, 2.5…); null when unknown.
  final double? seriesIndex;
  final List<String> tags;
  final String description;
  // 0 = not rated, else 1–5 stars.
  final int rating;
  final bool favorite;
  // Milliseconds since epoch; 0 = unknown.
  final int addedAt;
  final int startedAt;
  final int finishedAt;
  final String isbn;
  // Where an edited field's value came from: 'book', 'moon-reader' or 'user'. User wins.
  final Map<String, String> provenance;

  bool editedByUser(String field) => provenance[field] == 'user';

  String get format => extensionOf(name).toUpperCase();
  bool get isComic => format == 'CBR' || format == 'CBZ';

  Book copyWith({
    int? size,
    int? modified,
    String? title,
    String? author,
    String? series,
    String? universe,
    double? progress,
    String? locator,
    bool? approximate,
    bool? missing,
    bool? touched,
    bool? finished,
    int? opened,
    Object? seriesIndex = _keep,
    List<String>? tags,
    String? description,
    int? rating,
    bool? favorite,
    int? addedAt,
    int? startedAt,
    int? finishedAt,
    String? isbn,
    Map<String, String>? provenance,
  }) => Book(
    id: id,
    uri: uri,
    name: name,
    folder: folder,
    size: size ?? this.size,
    modified: modified ?? this.modified,
    title: title ?? this.title,
    author: author ?? this.author,
    series: series ?? this.series,
    universe: universe ?? this.universe,
    progress: progress ?? this.progress,
    locator: locator ?? this.locator,
    approximate: approximate ?? this.approximate,
    missing: missing ?? this.missing,
    touched: touched ?? this.touched,
    finished: finished ?? this.finished,
    opened: opened ?? this.opened,
    seriesIndex: identical(seriesIndex, _keep) ? this.seriesIndex : (seriesIndex as num?)?.toDouble(),
    tags: tags ?? this.tags,
    description: description ?? this.description,
    rating: rating ?? this.rating,
    favorite: favorite ?? this.favorite,
    addedAt: addedAt ?? this.addedAt,
    startedAt: startedAt ?? this.startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
    isbn: isbn ?? this.isbn,
    provenance: provenance ?? this.provenance,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'uri': uri,
    'name': name,
    'folder': folder,
    'size': size,
    'modified': modified,
    'title': title,
    'author': author,
    'series': series,
    'universe': universe,
    'progress': progress,
    'locator': locator,
    'approximate': approximate,
    'missing': missing,
    'touched': touched,
    'finished': finished,
    'opened': opened,
    'seriesIndex': ?seriesIndex,
    'tags': tags,
    'description': description,
    'rating': rating,
    'favorite': favorite,
    'addedAt': addedAt,
    'startedAt': startedAt,
    'finishedAt': finishedAt,
    'isbn': isbn,
    'provenance': provenance,
  };

  static Book fromJson(Map<String, dynamic> j) => Book(
    id: j['id'] as String,
    uri: j['uri'] as String,
    name: j['name'] as String,
    folder: (j['folder'] ?? '') as String,
    size: (j['size'] as num?)?.toInt() ?? 0,
    modified: (j['modified'] as num?)?.toInt() ?? 0,
    title: (j['title'] ?? '') as String,
    author: (j['author'] ?? '') as String,
    series: (j['series'] ?? '') as String,
    universe: (j['universe'] ?? '') as String,
    progress: (j['progress'] as num?)?.toDouble() ?? 0,
    locator: (j['locator'] ?? '') as String,
    approximate: (j['approximate'] ?? false) as bool,
    missing: (j['missing'] ?? false) as bool,
    touched: (j['touched'] ?? false) as bool,
    finished: (j['finished'] ?? false) as bool,
    opened: (j['opened'] as num?)?.toInt() ?? 0,
    seriesIndex: (j['seriesIndex'] as num?)?.toDouble(),
    tags: [for (final t in (j['tags'] as List? ?? const [])) t as String],
    description: (j['description'] ?? '') as String,
    rating: (j['rating'] as num?)?.toInt() ?? 0,
    favorite: (j['favorite'] ?? false) as bool,
    addedAt: (j['addedAt'] as num?)?.toInt() ?? 0,
    startedAt: (j['startedAt'] as num?)?.toInt() ?? 0,
    finishedAt: (j['finishedAt'] as num?)?.toInt() ?? 0,
    isbn: (j['isbn'] ?? '') as String,
    provenance: Map<String, String>.from((j['provenance'] as Map?) ?? const {}),
  );
}

// A file found by a folder scan.
class FoundFile {
  const FoundFile(this.uri, this.name, this.folder, this.size, this.modified);
  final String uri;
  final String name;
  final String folder;
  final int size;
  final int modified;

  static FoundFile fromMap(Map<Object?, Object?> m) => FoundFile(
    m['uri'] as String,
    m['name'] as String,
    (m['folder'] ?? '') as String,
    (m['size'] as num?)?.toInt() ?? 0,
    (m['modified'] as num?)?.toInt() ?? 0,
  );
}

// Merge a fresh scan into the saved library. Keeps reading records; a changed file loses only
// its exact locator (marked approximate); files no longer found are kept and marked missing.
// A record whose file is gone moves to a new file with the same name and size (a moved file, a
// re-selected Books folder, or a backup restored on another phone); with the same name only,
// it moves too but loses its exact place. Only pairs that are unique on both sides are moved.
List<Book> mergeScan(List<Book> saved, List<FoundFile> found) {
  final old = {for (final b in saved) b.uri: b};
  final uris = found.map((f) => f.uri).toSet();
  final gone = saved.where((b) => !uris.contains(b.uri)).toList();
  final moved = <String, Book>{}; // new uri → the record that moves there
  final carried = <String>{}; // ids of moved records
  void pair(String Function(String name, int size) key) {
    final records = <String, List<Book>>{};
    for (final b in gone.where((b) => !carried.contains(b.id))) {
      records.putIfAbsent(key(b.name, b.size), () => []).add(b);
    }
    final files = <String, List<FoundFile>>{};
    for (final f in found.where((f) => old[f.uri] == null && moved[f.uri] == null)) {
      files.putIfAbsent(key(f.name, f.size), () => []).add(f);
    }
    for (final e in files.entries) {
      final candidates = records[e.key];
      if (e.value.length != 1 || candidates == null || candidates.length != 1) continue;
      moved[e.value.single.uri] = candidates.single;
      carried.add(candidates.single.id);
    }
  }

  pair((name, size) => '$name\n$size');
  pair((name, _) => name);
  final merged = found.map((f) {
    var stale = old[f.uri];
    if (stale == null && moved[f.uri] != null) {
      stale = Book.fromJson({...moved[f.uri]!.toJson(), 'uri': f.uri, 'folder': f.folder});
      if (stale.size == f.size) return stale.copyWith(modified: f.modified, missing: false);
    }
    if (stale == null) {
      return Book(id: stableId(f.uri), uri: f.uri, name: f.name, folder: f.folder, size: f.size, modified: f.modified);
    }
    final prior = stale.copyWith(
      title: refreshedTitle(stale.title, f.name),
      author: stale.author.isEmpty ? displayAuthor(f.name) : stale.author,
    );
    if (prior.size == f.size && prior.modified == f.modified) return prior.copyWith(missing: false);
    return prior.copyWith(size: f.size, modified: f.modified, locator: '', approximate: true, missing: false);
  }).toList();
  return [...merged, ...gone.where((b) => !carried.contains(b.id)).map((b) => b.copyWith(missing: true))];
}
