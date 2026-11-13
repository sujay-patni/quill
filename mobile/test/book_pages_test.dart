import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quill/native/book_pages.dart';

void main() {
  test('book pages: totals, page numbers and locate are consistent', () {
    final p = BookPages(3);
    expect(p.total, isNull);
    p.chunkPages[1] = [4, 6];
    expect(p.chapterPage(1, 1, 2), 6);
    expect(p.bookPage(1, 0, 0), isNull, reason: 'earlier chapter not counted yet');
    p.chunkPages[0] = [3];
    p.chunkPages[2] = [2];
    expect(p.total, 15);
    for (var n = 0; n < 15; n++) {
      final (s, c, i) = p.locate(n);
      expect(p.bookPage(s, c, i), n);
    }
    expect(p.locate(99), (2, 0, 1));
  });

  test('the cache round-trips complete counts and keeps the newest first', () async {
    final dir = await Directory.systemTemp.createTemp('quill-pages');
    final cache = PageCountCache(File('${dir.path}/page-counts.json'));
    final p = BookPages(2)
      ..chunkPages[0] = [1, 2]
      ..chunkPages[1] = [3];
    await cache.save('a|1', p);
    await cache.save('b|1', p);
    expect((await cache.load('a|1'))!.total, 6);
    expect(await cache.load('missing'), isNull);
    await cache.save('incomplete', BookPages(2));
    expect(await cache.load('incomplete'), isNull);
    await dir.delete(recursive: true);
  });
}
