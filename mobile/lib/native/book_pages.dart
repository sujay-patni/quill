// Native engine: screen-page counts for a whole book at one layout (Moon Reader-style page
// numbers). Counts are kept per chunk, so a jump to "page N" lays out only the chunk holding it.
import 'dart:convert';
import 'dart:io';

class BookPages {
  BookPages(int chapters) : chunkPages = List<List<int>?>.filled(chapters, null);

  BookPages.fromJson(List<dynamic> json)
    : chunkPages = [for (final c in json) c == null ? null : [for (final n in c as List) n as int]];

  /// Per spine item: pages in each chunk, or null while not counted yet.
  final List<List<int>?> chunkPages;

  bool get complete => chunkPages.every((c) => c != null);
  int get counted => chunkPages.where((c) => c != null).length;

  int? pagesIn(int spine) => chunkPages[spine]?.fold<int>(0, (a, b) => a + b);
  int? get total => complete ? [for (final c in chunkPages) ...c!].fold<int>(0, (a, b) => a + b) : null;

  /// 0-based page within the chapter for (chunk, page in chunk); null until that chapter is counted.
  int? chapterPage(int spine, int chunk, int page) {
    final c = chunkPages[spine];
    if (c == null || chunk >= c.length) return null;
    return c.take(chunk).fold<int>(0, (a, b) => a + b) + page;
  }

  /// 0-based page in the book; null until every earlier chapter (and this one) is counted.
  int? bookPage(int spine, int chunk, int page) {
    var before = 0;
    for (var s = 0; s < spine; s++) {
      final n = pagesIn(s);
      if (n == null) return null;
      before += n;
    }
    final within = chapterPage(spine, chunk, page);
    return within == null ? null : before + within;
  }

  /// (spine, chunk, page in chunk) of 0-based book page [n]; requires [complete].
  (int, int, int) locate(int n) {
    var left = n.clamp(0, (total ?? 1) - 1);
    for (var s = 0; s < chunkPages.length; s++) {
      final chunks = chunkPages[s]!;
      for (var c = 0; c < chunks.length; c++) {
        if (left < chunks[c]) return (s, c, left);
        left -= chunks[c];
      }
    }
    final last = chunkPages.length - 1;
    return (last, chunkPages[last]!.length - 1, chunkPages[last]!.last - 1);
  }

  List<dynamic> toJson() => chunkPages;
}

/// Completed counts on disk, keyed by book + layout; a small most-recent-first list.
class PageCountCache {
  PageCountCache(this.file);
  final File file;
  static const _keep = 40;

  Future<BookPages?> load(String key) async {
    try {
      final all = jsonDecode(await file.readAsString()) as List;
      final hit = all.cast<Map<String, dynamic>>().where((e) => e['key'] == key).firstOrNull;
      return hit == null ? null : BookPages.fromJson(hit['pages'] as List);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String key, BookPages pages) async {
    if (!pages.complete) return;
    try {
      List<dynamic> all = [];
      if (await file.exists()) {
        try {
          all = jsonDecode(await file.readAsString()) as List;
        } catch (_) {}
      }
      all.removeWhere((e) => (e as Map)['key'] == key);
      all.insert(0, {'key': key, 'pages': pages.toJson()});
      await file.writeAsString(jsonEncode(all.take(_keep).toList()));
    } catch (_) {
      // A cache that cannot be written only costs a recount.
    }
  }
}
