import 'package:flutter_test/flutter_test.dart';
import 'package:quill/native/blocks.dart';
import 'package:quill/native/paginator.dart';

const _css = '''
.center { text-align: center; }
.start { text-align: left; }
.gone { display: none }
.title::before { content: "[ "; }
.lead { font-variant: small-caps; font-weight: bold }
p.subsq { text-indent: 1.5em; }
''';

String _doc(String body) => '''<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml"><head><title>T</title><style>p{}</style></head>
<body>$body</body></html>''';

void main() {
  group('parseChapter', () {
    test('keeps structure, inline styles and the Moon-like CSS subset', () {
      final blocks = parseChapter(
        _doc('''
<h1 id="ch" class="title">18</h1>
<p class="center">Views: <b>1.9</b></p>
<p class="start">Left   aligned&nbsp;text
  across lines.</p>
<p class="subsq">Indented <i>italic</i> words.<br/>Next line.</p>
<p class="gone">Hidden</p>
<p><span class="lead">Bold lead</span> rest.</p>
<img src="../images/a.png"/>
<hr/>'''),
        css: Stylesheet([_css]),
        resolve: (src) => 'OEBPS/images/a.png',
      );
      expect(blocks.map((b) => b.kind).toList(), [
        ...List.filled(5, BlockKind.text),
        BlockKind.image,
        BlockKind.rule,
      ]);
      expect(blocks[0].text, '18', reason: 'generated content is not text');
      expect(blocks[0].anchors, ['ch']);
      expect(blocks[0].runs.single.bold, isTrue);
      expect(blocks[1].align, BlockAlign.center);
      expect(blocks[1].runs.map((r) => (r.text, r.bold)).toList(), [('Views: ', false), ('1.9', true)]);
      expect(blocks[2].align, BlockAlign.justify, reason: 'start/left alignment is justified like Moon');
      expect(blocks[2].text, 'Left aligned text across lines.');
      expect(blocks[3].indentEm, 1.5);
      expect(blocks[3].text, 'Indented italic words.\nNext line.');
      expect(blocks[3].runs.firstWhere((r) => r.text == 'italic').italic, isTrue);
      expect(blocks.any((b) => b.text.contains('Hidden')), isFalse);
      expect(blocks[4].runs.first.bold, isTrue);
      expect(blocks[5].image, 'OEBPS/images/a.png');
    });

    test("the book's <style> blocks and linked stylesheets apply", () {
      final blocks = parseChapter(
        '<html><head><link rel="stylesheet" href="../css/book.css"/><style>.r{text-align:right}</style></head>'
        '<body><h1 class="c">Title</h1><p class="r">Right</p><p>Body</p></body></html>',
        loadCss: (href) => href == '../css/book.css' ? '.c { text-align: center }' : null,
      );
      expect(blocks.map((b) => b.align).toList(), [BlockAlign.center, BlockAlign.right, BlockAlign.justify]);
    });

    test('links keep their target; note references are recognised', () {
      final b = parseChapter('<html xmlns:epub="http://www.idpf.org/2007/ops"><body>'
          '<p>See <a href="notes.xhtml#n1" epub:type="noteref"><sup>1</sup></a> and <a href="c2.xhtml">the <i>next</i> chapter</a>.</p>'
          '</body></html>').single;
      expect(b.text, 'See 1 and the next chapter.');
      final note = b.runAt(b.text.indexOf('1'))!;
      expect([note.href, note.noteRef, note.shift], ['notes.xhtml#n1', true, 1]);
      final link = b.runAt(b.text.indexOf('next'))!;
      expect([link.href, link.noteRef, link.italic], ['c2.xhtml', false, true]);
      expect(b.runAt(0)!.href, isNull);
      expect(b.runAt(b.text.length - 1)!.href, isNull);
    });

    test('block offsets tile the chapter text without gaps', () {
      final blocks = parseChapter(_doc('<p>one</p><div><p>two</p>three</div><p>four</p>'));
      expect(blocks.map((b) => b.text).toList(), ['one', 'two', 'three', 'four']);
      for (var i = 1; i < blocks.length; i++) {
        expect(blocks[i].start, blocks[i - 1].end);
      }
    });

    test('real-book markup: void tags, head links, bare ampersands, unclosed elements', () {
      String html(String head, String body) => '<html><head>$head</head><body>$body</body></html>';
      List<String> texts(String h) => parseChapter(h).map((b) => b.kind == BlockKind.text ? b.text : b.kind.name).toList();
      expect(texts(html('<meta charset="utf-8"><link rel="stylesheet" href="s.css">', '<p>visible</p>')), ['visible'],
          reason: 'an unclosed <meta>/<link> in <head> must not hide the body');
      expect(texts(html('', '<p>a<br>b</p><p>c</p>')), ['a\nb', 'c']);
      expect(texts(html('', '<p>a</p><img src="x.png"><p>b</p>')), ['a', 'image', 'b']);
      expect(texts(html('', '<p>Fish & chips</p>')), ['Fish & chips']);
      final leak = parseChapter(html('', '<p><i>a<br>b</i></p><p>plain</p>'));
      expect(leak.last.runs.single.italic, isFalse, reason: 'styles must not leak past an unclosed tag');
      expect(texts(html('', '<div><p>one</div><p>two</p>')), ['one', 'two'], reason: 'a stray end tag closes inner blocks');
    });

    test('a 2 MB one-file chapter parses into thousands of blocks', () {
      final p = List.generate(7000, (i) => '<p class="subsq">Paragraph $i with <i>some</i> words in it.</p>').join();
      final clock = Stopwatch()..start();
      final blocks = parseChapter(_doc(p), css: Stylesheet([_css]));
      expect(blocks.length, 7000);
      // Generous bound for CI hosts; the phone figure is recorded in M0.
      expect(clock.elapsedMilliseconds, lessThan(5000));
    });
  });

  group('ChapterLayout', () {
    final blocks = parseChapter(_doc(List.generate(
      400,
      (i) => '<p class="subsq">Paragraph $i. ${'The quiet lantern keeps its steady light. ' * (i % 7 + 1)}</p>',
    ).join()), css: Stylesheet([_css]));
    final layout = ChapterLayout(blocks, const PageStyle(width: 300, height: 500, fontSize: 14), chunkChars: 8000);

    test('pages tile every chunk exactly, splitting paragraphs at line ends', () {
      expect(layout.chunks.length, greaterThan(3));
      var expected = 0;
      for (var c = 0; c < layout.chunks.length; c++) {
        for (final page in layout.pagesOf(c)) {
          expect(page.start, expected, reason: 'no gap or overlap before chunk $c page');
          expect(page.end, greaterThan(page.start));
          for (final item in page.items) {
            expect(item.top + item.clipHeight, lessThanOrEqualTo(500.5), reason: 'the shown slice fits the page');
            expect(item.to, greaterThan(item.from));
          }
          expected = page.end;
        }
      }
      expect(expected, blocks.last.end);
    });

    test('paragraphs ending in a line break split across pages without failing', () {
      final b = parseChapter('<html><body>${List.generate(60, (i) => '<p>Line $i of verse<br/>second line<br/></p>').join()}</body></html>');
      expect(b.first.text.endsWith('\n'), isFalse, reason: 'a trailing <br/> is dropped');
      final l = ChapterLayout(b, const PageStyle(width: 200, height: 90, fontSize: 14));
      var pages = 0;
      for (var c = 0; c < l.chunks.length; c++) {
        pages += l.pagesOf(c).length;
      }
      expect(pages, greaterThan(10));
    });

    test('opening in the middle lays out only that chunk', () {
      final fresh = ChapterLayout(blocks, layout.style, chunkChars: 8000);
      final middle = blocks[blocks.length ~/ 2].start + 3;
      final (chunk, page) = fresh.pageAt(middle);
      expect([for (var c = 0; c < fresh.chunks.length; c++) fresh.isLaidOut(c)].where((x) => x).length, 1);
      final p = fresh.pagesOf(chunk)[page];
      expect(middle, inInclusiveRange(p.start, p.end - 1));
    });
  });
}
