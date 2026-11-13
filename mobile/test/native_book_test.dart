import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/painting.dart' show Size;
import 'package:quill/native/blocks.dart';
import 'package:quill/native/native_book.dart';
import 'package:quill/native/paginator.dart';

import '../integration_test/fixtures.dart';

void main() {
  late NativeBook book;
  setUpAll(() async {
    book = await NativeBook.open(Uint8List.fromList(syntheticEpub(chapters: 3, paragraphCounts: [4, 30, 4])));
  });

  test('spine, contents and chapters', () async {
    expect(book.length, 3);
    expect(book.toc.map((e) => e.path).toSet(), containsAll(['OEBPS/c1.xhtml', 'OEBPS/c2.xhtml', 'OEBPS/c3.xhtml']));
    final c2 = await book.chapter(1);
    expect(c2.first.text, 'Chapter 2');
    expect(book.titleAt(const NativePosition(1, 0), c2), isNotEmpty);
  });

  test('a native place round-trips exactly and stays readable by the WebView reader', () async {
    final c2 = await book.chapter(1);
    final place = NativePosition(1, c2[10].start + 7);
    final json = book.toLocator(place, c2);
    final back = book.fromLocator(json, (_) => c2);
    expect([back.spine, back.offset, back.approximate], [1, place.offset, false]);
    final readium = Locator.fromJsonString(json)!;
    expect(readium.href, 'OEBPS/c2.xhtml');
    expect(readium.locations?.progression, closeTo(place.offset / c2.last.end, 1e-9));
    expect((jsonDecode(json)['locations']['totalProgression'] as num), inExclusiveRange(0, 1));
  });

  test('a WebView locator converts approximately, by anchor when it has one', () async {
    final c2 = await book.chapter(1);
    final byProgress = book.fromLocator(
      jsonEncode({'href': 'OEBPS/c2.xhtml', 'locations': {'progression': 0.5}}),
      (_) => c2,
    );
    expect(byProgress.spine, 1);
    expect(byProgress.approximate, isTrue);
    expect(byProgress.offset, closeTo(c2.last.end / 2, 1));
    final nested = c2.firstWhere((b) => b.anchors.contains('nested')).start;
    final byAnchor = book.fromLocator(
      jsonEncode({'href': 'OEBPS/c2.xhtml', 'locations': {'progression': nested / c2.last.end + 0.005, 'cssSelector': '#nested'}}),
      (_) => c2,
    );
    expect(byAnchor.offset, nested, reason: 'an anchor that agrees with the page fraction wins');
    expect(book.fromLocator('', (_) => c2).offset, 0);
  });

  test('places are never guessed: missing chapters refuse, disagreeing anchors are ignored', () async {
    final c2 = await book.chapter(1);
    expect(() => book.fromLocator(jsonEncode({'href': 'OEBPS/elsewhere.xhtml', 'locations': {'progression': 0.5}}), (_) => c2),
        throwsStateError);
    expect(book.spineOf('OEBPS%2Fc2.xhtml'), 1, reason: 'percent-encoded hrefs still match');
    expect(book.spineOf('/OEBPS/c3.xhtml#x'), 2);
    // #top is at the chapter start but the page fraction says the middle: trust the fraction.
    final p = book.fromLocator(
      jsonEncode({'href': 'OEBPS/c2.xhtml', 'locations': {'progression': 0.6, 'cssSelector': '#top'}}),
      (_) => c2,
    );
    expect(p.offset, closeTo(c2.last.end * 0.6, 1));
  });

  test('the first native save keeps the previous place as a backup', () async {
    final c2 = await book.chapter(1);
    const webView = '{"href":"OEBPS/c2.xhtml","locations":{"progression":0.25}}';
    final first = jsonDecode(book.toLocator(const NativePosition(1, 40), c2, previous: webView)) as Map;
    expect(first['quillPrevious'], webView);
    final second = jsonDecode(book.toLocator(const NativePosition(1, 80), c2, previous: jsonEncode(first))) as Map;
    expect(second['quillPrevious'], webView, reason: 'the backup survives later native saves');
    expect((second['quillNative'] as Map)['quote'], isNotEmpty);
  });

  test('images: sizes are read, covers in <svg> are kept, pages fit them', () async {
    final b = await NativeBook.open(Uint8List.fromList(
      syntheticEpub(chapters: 2, paragraphCounts: [3, 3], withCover: true, imagesInText: true),
    ));
    final blocks = await b.chapter(0);
    final images = blocks.where((x) => x.kind == BlockKind.image).toList();
    expect(images.map((x) => x.image).toList(),
        ['OEBPS/images/front.png', 'OEBPS/images/front.png', 'OEBPS/images/missing.png']);
    expect(b.imageSizes(0), {'OEBPS/images/front.png': const Size(120, 180)});

    final layout = ChapterLayout(blocks, const PageStyle(width: 300, height: 400, fontSize: 14), imageSizes: b.imageSizes(0));
    final items = [for (var c = 0; c < layout.chunks.length; c++) ...layout.pagesOf(c)].expand((p) => p.items).where((i) => i.image != null).toList();
    expect(items.length, 2, reason: 'the missing image takes no space');
    for (final i in items) {
      final r = i.imageRect!;
      expect(r.width / r.height, closeTo(120 / 180, 0.01), reason: 'aspect ratio kept');
      expect(r.bottom, lessThanOrEqualTo(400.5));
      expect(r.left, closeTo((300 - r.width) / 2, 0.01), reason: 'centred');
    }
    // Pages still tile the text exactly with images in the flow.
    var expected = 0;
    for (var c = 0; c < layout.chunks.length; c++) {
      for (final p in layout.pagesOf(c)) {
        expect(p.start, expected);
        expected = p.end;
      }
    }
    expect(expected, blocks.last.end);
    final decoded = await b.decodeImage('OEBPS/images/front.png', 60);
    expect(decoded, isNotNull);
    decoded!.dispose();
  });

  test('links resolve to places in the book; external and missing targets do not', () async {
    final c2 = await book.chapter(1);
    final nested = c2.firstWhere((b) => b.anchors.contains('nested')).start;
    final to = await book.resolveLink(0, 'c2.xhtml#nested');
    expect([to!.spine, to.offset], [1, nested]);
    expect((await book.resolveLink(1, '#nested'))!.offset, nested, reason: 'same-file link');
    expect((await book.resolveLink(0, 'c3.xhtml'))!.spine, 2);
    expect(await book.resolveLink(0, 'https://example.com/x'), isNull);
    expect(await book.resolveLink(0, 'c2.xhtml#nowhere'), isNull);
    expect(await book.resolveLink(0, 'missing.xhtml'), isNull);
  });
}
