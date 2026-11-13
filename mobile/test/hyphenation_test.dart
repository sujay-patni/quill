import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quill/native/blocks.dart';
import 'package:quill/native/hyphenation.dart';
import 'package:quill/native/paginator.dart';

void main() {
  final h = Hyphenator(File('assets/hyph-en-us.txt').readAsStringSync());
  String show(String w) {
    final b = h.breaks(w);
    final out = StringBuffer();
    for (var i = 0; i < w.length; i++) {
      if (b.contains(i)) out.write('-');
      out.write(w[i]);
    }
    return out.toString();
  }

  test('known words break as in TeX', () {
    expect(show('hyphenation'), 'hy-phen-ation');
    expect(show('computer'), 'com-puter');
    expect(show('associate'), 'as-so-ciate', reason: 'from the exception list');
    expect(show('the'), 'the');
    expect(show('table'), 'ta-ble');
  });

  test('soft breaks are offsets in running text; short, accented and numeric words are left alone', () {
    const text = 'A hyphenation café x2computer.';
    final at = h.softBreaks(text);
    expect(at.map((i) => text.substring(0, i).split(' ').last).toList(), ['hy', 'hyphen']);
  });

  test('hyphenated layout: pages still tile the text exactly, hyphens are drawn, offsets stay original', () {
    Hyphenator.install(h);
    addTearDown(() => Hyphenator.install(null));
    final blocks = parseChapter('<html><body>${List.generate(40, (i) => '<p style="text-indent:1.5em">Extraordinarily complicated hyphenation demonstrations considerably lengthen paragraph $i unnecessarily.</p>').join()}</body></html>');
    PageStyle style(bool on) => PageStyle(width: 170, height: 300, fontSize: 14, hyphenate: on);
    final plain = ChapterLayout(blocks, style(false));
    final hyph = ChapterLayout(blocks, style(true));
    var hyphens = 0, expected = 0, pages = 0;
    for (var c = 0; c < hyph.chunks.length; c++) {
      for (final p in hyph.pagesOf(c)) {
        expect(p.start, expected);
        expected = p.end;
        pages++;
        for (final i in p.items) {
          hyphens += i.hyphens.length;
          expect(i.to, greaterThan(i.from));
        }
      }
    }
    expect(expected, blocks.last.end, reason: 'offsets are in the original text');
    expect(hyphens, greaterThan(10));
    final plainPages = [for (var c = 0; c < plain.chunks.length; c++) plain.pagesOf(c).length].fold(0, (a, b) => a + b);
    expect(pages, lessThanOrEqualTo(plainPages), reason: 'hyphenation never needs more pages');
    expect(style(true).signature, isNot(style(false).signature));
  });
}
