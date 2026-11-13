// M0 measurements for the native engine on a device (debug build: JIT, so pessimistic).
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quill/native/blocks.dart';
import 'package:quill/native/epub_book.dart';
import 'package:quill/native/paginator.dart';

import 'fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native engine: one-file 2 MB book opens in the middle quickly', (tester) async {
    // One-file-novel shaped: one spine item, ~7,000 paragraphs with inline markup (~1.9 MB XHTML).
    final bytes = syntheticEpub(chapters: 1, paragraphCounts: [7000], inlineMarkup: true);
    final t = <String, int>{};
    final clock = Stopwatch()..start();
    int lap() {
      final ms = clock.elapsedMilliseconds;
      clock.reset();
      return ms;
    }

    final book = EpubBook.open(bytes);
    t['zip+opf'] = lap();
    final xhtml = book.chapterText(0);
    t['decode'] = lap();
    final blocks = parseChapter(xhtml);
    t['parse'] = lap();
    final layout = ChapterLayout(blocks, const PageStyle(width: 306, height: 690, fontSize: 13, lineHeight: 1.58));
    final middle = blocks[blocks.length ~/ 2].start;
    final (chunk, page) = layout.pageAt(middle);
    t['layout middle chunk'] = lap();
    final recorder = ui.PictureRecorder();
    layout.pagesOf(chunk)[page].paint(ui.Canvas(recorder), ui.Offset.zero);
    final image = await recorder.endRecording().toImage(306, 690);
    t['draw page image'] = lap();
    final next = page + 1 < layout.pagesOf(chunk).length ? layout.pagesOf(chunk)[page + 1] : layout.pagesOf(chunk + 1).first;
    expect(next.start, greaterThan(0));
    t['next page (cached)'] = lap();
    var total = 0;
    for (var c = 0; c < layout.chunks.length; c++) {
      total += layout.pagesOf(c).length;
    }
    t['layout whole book (background count)'] = lap();
    image.dispose();

    final open = t['zip+opf']! + t['decode']! + t['parse']! + t['layout middle chunk']! + t['draw page image']!;
    // ignore: avoid_print
    print('NATIVE-BENCH ${xhtml.length} chars, ${blocks.length} blocks, ${layout.chunks.length} chunks, '
        '$total pages, open-to-middle ${open}ms: $t');
    expect(total, greaterThan(500));
  });
}
