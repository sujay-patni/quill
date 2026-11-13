// Native engine: lays out blocks into screen pages, one chunk at a time.
//
// A chapter is cut into chunks of roughly [chunkChars] characters at block boundaries, and each
// chunk starts on a new page. Opening at any position therefore lays out only the chunk that
// contains it (Moon Reader-like: never the whole book), and page boundaries stay deterministic
// for a given layout. Paragraphs split across pages at line boundaries.
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextAlign;

import 'blocks.dart';
import 'hyphenation.dart';

class PageStyle {
  const PageStyle({
    required this.width,
    required this.height,
    this.fontSize = 18,
    this.lineHeight = 1.5,
    this.fontFamily = 'serif',
    this.ink = const ui.Color(0xFF000000),
    this.link = const ui.Color(0xFF1A5FB4),
    this.paragraphSpacingEm = 0,
    this.bold = false,
    this.hyphenate = false,
    this.italic = false,
    this.underline = false,
    this.shadow = false,
  });

  /// Text area in logical pixels.
  final double width;
  final double height;
  final double fontSize;
  final double lineHeight;
  final String fontFamily;
  final ui.Color ink;

  /// Colour of links in the text.
  final ui.Color link;
  final double paragraphSpacingEm;

  /// All text bold (Moon Reader's font bold).
  final bool bold;

  /// Break long words at line ends (English patterns; needs [Hyphenator.english] loaded).
  final bool hyphenate;

  /// Moon Reader's font styling switches, applied to all text.
  final bool italic;
  final bool underline;
  final bool shadow;

  String get signature => '$width:$height:$fontSize:$lineHeight:$fontFamily:$paragraphSpacingEm:$bold:$hyphenate:$italic:$underline:$shadow';
}

/// A block, or the part of it from [from] to [to] (block-relative character offsets).
/// Lines [from, to) of a block's single laid-out paragraph, drawn at [top] on the page. The
/// paragraph is laid out once and sliced by clipping, so a paragraph split across pages keeps
/// its justification (a separately laid-out part would leave its last line ragged).
class PageItem {
  PageItem(this.block, this.from, this.to, this.paragraph, this.top,
      {this.clipTop = 0,
      double? clipHeight,
      this.image,
      this.imageRect,
      this.blockStart = 0,
      this.shift = 0,
      this.soft = const [],
      this.hyphens = const [],
      this.hyphenGlyph})
    : clipHeight = clipHeight ?? paragraph?.height ?? 0;

  /// Chapter offset of the block's first character, and how many positions the paragraph's own
  /// text is shifted by (1 when it starts with an indent placeholder).
  final int blockStart;
  final int shift;

  /// Block offsets where a soft hyphen was inserted into the paragraph's text (hyphenation), the
  /// points (paragraph coordinates: right edge, baseline) of lines in this slice that end in one,
  /// and the hyphen to draw there.
  final List<int> soft;
  final List<ui.Offset> hyphens;
  final ui.Paragraph? hyphenGlyph;

  /// Block offset of position [q] in the paragraph's text (inverse of [paragraphPosition]).
  int blockOffset(int q) {
    var o = q - shift;
    var n = 0;
    while (n < soft.length && soft[n] + n < o) {
      n++;
    }
    o -= n;
    return o < 0 ? 0 : o;
  }

  /// Position in the paragraph's text of block offset [o].
  int paragraphPosition(int o) {
    var n = 0;
    while (n < soft.length && soft[n] <= o) {
      n++;
    }
    return o + shift + n;
  }

  /// An image block: archive path and where it is drawn on the page.
  final String? image;
  final ui.Rect? imageRect;
  final int block;

  /// Block-relative character offsets.
  final int from;
  final int to;
  final ui.Paragraph? paragraph;
  final double top;

  /// The slice of the paragraph shown: from [clipTop], [clipHeight] tall.
  final double clipTop;
  final double clipHeight;
}

class LaidOutPage {
  LaidOutPage(this.items, this.start, this.end);
  final List<PageItem> items;

  /// Chapter text offsets covered by this page.
  final int start;
  final int end;

  /// [imageOf] returns a decoded image for an archive path, or null while it is loading.
  /// The chapter offset of the character at [at] (page coordinates), and the word around it as
  /// a (start, end) range; null when [at] is not on text.
  (int, (int, int))? hitTest(ui.Offset at) {
    for (final i in items) {
      final p = i.paragraph;
      if (p == null || at.dy < i.top || at.dy >= i.top + i.clipHeight) continue;
      final position = p.getPositionForOffset(ui.Offset(at.dx, at.dy - i.top + i.clipTop));
      final word = p.getWordBoundary(position);
      int chapter(int q) => i.blockStart + i.blockOffset(q).clamp(i.from, i.to);
      final start = chapter(word.start), end = chapter(word.end);
      return (chapter(position.offset), end > start ? (start, end) : (start, start + 1));
    }
    return null;
  }

  /// Where chapter range [start, end) begins and ends on this page (page coordinates): the
  /// bottom-left of its first glyph and the bottom-right of its last. An end that is on another
  /// page is null.
  (ui.Offset?, ui.Offset?) rangeEnds(int start, int end) {
    ui.Offset? first, last;
    for (final i in items) {
      final p = i.paragraph;
      if (p == null) continue;
      final from = start - i.blockStart, to = end - i.blockStart;
      if (to <= i.from || from >= i.to) continue;
      final boxes = p.getBoxesForRange(i.paragraphPosition(from.clamp(i.from, i.to)), i.paragraphPosition(to.clamp(i.from, i.to)));
      if (boxes.isEmpty) continue;
      final shift = ui.Offset(0, i.top - i.clipTop);
      if (first == null && from >= i.from) first = ui.Offset(boxes.first.left, boxes.first.bottom) + shift;
      if (to <= i.to) last = ui.Offset(boxes.last.right, boxes.last.bottom) + shift;
    }
    return (start >= this.start ? first : null, end <= this.end ? last : null);
  }

  /// Whether [at] (page coordinates) lies on the glyphs of chapter range [start, end).
  bool rangeContains(int start, int end, ui.Offset at) {
    for (final i in items) {
      final p = i.paragraph;
      if (p == null || at.dy < i.top || at.dy >= i.top + i.clipHeight) continue;
      final from = start - i.blockStart, to = end - i.blockStart;
      if (to <= i.from || from >= i.to) continue;
      final local = ui.Offset(at.dx, at.dy - i.top + i.clipTop);
      for (final box in p.getBoxesForRange(i.paragraphPosition(from.clamp(0, 1 << 30)), i.paragraphPosition(to))) {
        if (box.toRect().inflate(6).contains(local)) return true;
      }
    }
    return false;
  }

  /// [marks] are (start, end, colour) ranges of chapter offsets to tint: highlights, the
  /// selection, a search match.
  void paint(ui.Canvas canvas, ui.Offset origin,
      {ui.Image? Function(String path)? imageOf, List<(int, int, ui.Color)> marks = const []}) {
    for (final i in items) {
      final rect = i.imageRect;
      if (i.image != null && rect != null) {
        final image = imageOf?.call(i.image!);
        if (image != null) {
          canvas.drawImageRect(
            image,
            ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
            rect.shift(origin),
            ui.Paint()..filterQuality = ui.FilterQuality.medium,
          );
        }
        continue;
      }
      final p = i.paragraph;
      if (p == null) continue;
      canvas.save();
      canvas.clipRect(ui.Rect.fromLTWH(origin.dx - 2, origin.dy + i.top, p.width + 14, i.clipHeight));
      for (final (markStart, markEnd, color) in marks) {
        // The part of the range inside this block, as positions in its paragraph.
        final from = markStart - i.blockStart, to = markEnd - i.blockStart;
        if (to > i.from && from < i.to) {
          final paint = ui.Paint()..color = color;
          for (final box in p.getBoxesForRange(i.paragraphPosition(from.clamp(0, 1 << 30)), i.paragraphPosition(to))) {
            canvas.drawRRect(
              ui.RRect.fromRectAndRadius(box.toRect().shift(origin.translate(0, i.top - i.clipTop)).inflate(1), const ui.Radius.circular(2)),
              paint,
            );
          }
        }
      }
      canvas.drawParagraph(p, origin.translate(0, i.top - i.clipTop));
      final glyph = i.hyphenGlyph;
      if (glyph != null) {
        for (final h in i.hyphens) {
          canvas.drawParagraph(glyph, origin.translate(h.dx, i.top - i.clipTop + h.dy - glyph.alphabeticBaseline));
        }
      }
      canvas.restore();
    }
  }
}

class Chunk {
  Chunk(this.firstBlock, this.lastBlock);
  final int firstBlock;

  /// Exclusive.
  final int lastBlock;
}

class ChapterLayout {
  ChapterLayout(this.blocks, this.style, {this.chunkChars = 40000, this.imageSizes = const {}})
    : chunks = _chunk(blocks, chunkChars);

  /// Natural pixel size of each image block's file, by archive path.
  final Map<String, ui.Size> imageSizes;

  final List<Block> blocks;
  final PageStyle style;
  final int chunkChars;
  final List<Chunk> chunks;
  final Map<int, List<LaidOutPage>> _pages = {};

  static List<Chunk> _chunk(List<Block> blocks, int size) {
    final out = <Chunk>[];
    var first = 0;
    var chars = 0;
    for (var i = 0; i < blocks.length; i++) {
      chars += blocks[i].length;
      final next = i + 1 < blocks.length ? blocks[i + 1] : null;
      if (next == null || chars >= size || next.breakBefore) {
        out.add(Chunk(first, i + 1));
        first = i + 1;
        chars = 0;
      }
    }
    if (out.isEmpty) out.add(Chunk(0, 0));
    return out;
  }

  int chunkAt(int offset) {
    for (var c = 0; c < chunks.length; c++) {
      final ch = chunks[c];
      if (ch.lastBlock > ch.firstBlock && offset < blocks[ch.lastBlock - 1].end) return c;
    }
    return chunks.length - 1;
  }

  /// Pages of chunk [c], laid out on first use.
  List<LaidOutPage> pagesOf(int c) => _pages[c] ??= _layout(chunks[c]);

  bool isLaidOut(int c) => _pages.containsKey(c);

  /// Drops laid-out chunks other than [keep] (paragraph layouts are memory-heavy).
  void keepOnly(Set<int> keep) => _pages.removeWhere((c, _) => !keep.contains(c));

  /// The page containing chapter offset [offset]: (chunk, page index within chunk).
  (int, int) pageAt(int offset) {
    final c = chunkAt(offset);
    final pages = pagesOf(c);
    for (var p = 0; p < pages.length; p++) {
      if (offset < pages[p].end) return (c, p);
    }
    return (c, pages.length - 1);
  }

  /// The whole block as one paragraph; [soft] are block offsets that get a soft hyphen.
  ui.Paragraph _paragraph(Block b, List<int> soft) {
    final s = style;
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: switch (b.align) {
        BlockAlign.center => TextAlign.center,
        BlockAlign.right => TextAlign.right,
        BlockAlign.justify => TextAlign.justify,
      },
      fontFamily: s.fontFamily,
      fontSize: s.fontSize,
      height: s.lineHeight,
    ));
    var pos = 0;
    var next = 0; // index into soft
    var first = true;
    for (final r in b.runs) {
      final rs = pos, re = pos + r.text.length;
      pos = re;
      var text = r.text;
      if (next < soft.length && soft[next] < re) {
        final out = StringBuffer();
        var at = rs;
        while (next < soft.length && soft[next] < re) {
          out.write(r.text.substring(at - rs, soft[next] - rs));
          out.write('\u00AD');
          at = soft[next++];
        }
        out.write(r.text.substring(at - rs));
        text = out.toString();
      }
      if (first && b.indentEm > 0) {
        // Text indent as leading space of the right width (ParagraphStyle has no indent).
        builder.addPlaceholder(b.indentEm * s.fontSize * r.scale, 1, ui.PlaceholderAlignment.baseline,
            baseline: ui.TextBaseline.alphabetic, baselineOffset: 0);
      }
      first = false;
      builder.pushStyle(ui.TextStyle(
        color: r.href != null ? s.link : s.ink,
        fontFamily: s.fontFamily,
        fontSize: s.fontSize * r.scale,
        height: s.lineHeight,
        fontWeight: r.bold || s.bold ? ui.FontWeight.bold : ui.FontWeight.normal,
        fontStyle: r.italic || s.italic ? ui.FontStyle.italic : ui.FontStyle.normal,
        decoration: r.underline || s.underline ? ui.TextDecoration.underline : null,
        shadows: s.shadow ? [ui.Shadow(color: s.ink.withValues(alpha: 0.35), offset: const ui.Offset(1, 1), blurRadius: 1.5)] : null,
        fontFeatures: [if (r.shift > 0) const ui.FontFeature.superscripts(), if (r.shift < 0) const ui.FontFeature.subscripts()],
      ));
      builder.addText(text);
      builder.pop();
    }
    return builder.build()..layout(ui.ParagraphConstraints(width: s.width));
  }

  List<LaidOutPage> _layout(Chunk chunk) {
    final s = style;
    final pages = <LaidOutPage>[];
    var items = <PageItem>[];
    var y = 0.0;
    var pageStart = chunk.firstBlock < blocks.length ? blocks[chunk.firstBlock].start : 0;

    void newPage(int nextStart) {
      final end = items.isEmpty ? pageStart : blocks[items.last.block].start + items.last.to;
      pages.add(LaidOutPage(items, pageStart, end));
      items = [];
      y = 0;
      pageStart = nextStart;
    }

    for (var bi = chunk.firstBlock; bi < chunk.lastBlock; bi++) {
      final b = blocks[bi];
      if (b.kind == BlockKind.image) {
        final natural = imageSizes[b.image];
        if (natural == null || natural.width <= 0 || natural.height <= 0) {
          continue; // unreadable image: takes no space
        }
        // Fit the text width (never upscaled past it) and the page height, centred.
        var scale = s.width / natural.width;
        if (natural.height * scale > s.height) scale = s.height / natural.height;
        if (scale > 1 && natural.width < s.width * 0.5) scale = 1; // small ornaments keep their size
        final w = natural.width * scale, h = natural.height * scale;
        if (y + h > s.height + 0.5 && items.isNotEmpty) newPage(b.start);
        final gap = items.isEmpty ? 0.0 : s.fontSize * 0.5;
        items.add(PageItem(bi, 0, 1, null, y + gap,
            clipHeight: h, image: b.image, imageRect: ui.Rect.fromLTWH((s.width - w) / 2, y + gap, w, h)));
        y += gap + h + s.fontSize * 0.5;
        continue;
      }
      if (b.kind != BlockKind.text) {
        final h = s.fontSize * s.lineHeight;
        if (y + h > s.height && items.isNotEmpty) newPage(b.start);
        items.add(PageItem(bi, 0, 1, null, y));
        y += h;
        continue;
      }
      if (items.isNotEmpty) y += (b.topEm + s.paragraphSpacingEm) * s.fontSize;
      final soft = style.hyphenate ? (Hyphenator.loaded?.softBreaks(b.text) ?? const <int>[]) : const <int>[];
      final para = _paragraph(b, soft);
      final lines = para.computeLineMetrics();
      final hyphenPoints = <int, ui.Offset>{};
      final starts = _lineStarts(para, b, soft, lines, hyphenPoints);
      var line = 0;
      var paraY = 0.0; // top of [line] inside the paragraph
      while (line < lines.length) {
        // Fit as many whole lines as remain on this page.
        var fit = 0;
        var used = 0.0;
        while (line + fit < lines.length && y + used + lines[line + fit].height <= s.height + 0.5) {
          used += lines[line + fit].height;
          fit++;
        }
        if (fit == 0) {
          if (items.isNotEmpty) {
            newPage(b.start + _at(starts, line, b.text.length));
            continue;
          }
          fit = 1; // a line taller than the page: place it anyway
          used = lines[line].height;
        }
        final last = line + fit;
        final from = _at(starts, line, b.text.length);
        final to = last < lines.length ? _at(starts, last, b.text.length) : b.text.length;
        items.add(PageItem(bi, from, to, para, y,
            clipTop: paraY,
            clipHeight: used,
            blockStart: b.start,
            shift: b.indentEm > 0 ? 1 : 0,
            soft: soft,
            hyphens: [for (var l = line; l < last; l++) ?hyphenPoints[l]],
            hyphenGlyph: hyphenPoints.isEmpty ? null : _hyphenGlyph()));
        y += used;
        paraY += used;
        line = last;
        if (line < lines.length) {
          newPage(b.start + to);
        } else {
          y += b.bottomEm * s.fontSize;
        }
      }
    }
    if (items.isNotEmpty || pages.isEmpty) newPage(pageStart);
    return pages;
  }

  // A line index past the computed starts (should not happen) maps to the paragraph's end.
  static int _at(List<int> starts, int line, int end) => line < starts.length ? starts[line] : end;

  ui.Paragraph? _hyphen;

  ui.Paragraph _hyphenGlyph() => _hyphen ??= (ui.ParagraphBuilder(
          ui.ParagraphStyle(fontFamily: style.fontFamily, fontSize: style.fontSize, height: style.lineHeight))
        ..pushStyle(ui.TextStyle(color: style.ink, fontWeight: style.bold ? ui.FontWeight.bold : ui.FontWeight.normal))
        ..addText('-'))
      .build()
    ..layout(const ui.ParagraphConstraints(width: 100));

  /// Block-relative character offset where each line starts. Lines that end at a soft hyphen
  /// get a point in [hyphenPoints] (line index → right edge of the last letter, baseline).
  static List<int> _lineStarts(
    ui.Paragraph p,
    Block b,
    List<int> soft,
    List<ui.LineMetrics> lines,
    Map<int, ui.Offset> hyphenPoints,
  ) {
    // An indent placeholder occupies one position at the start of the paragraph's text.
    final shift = b.indentEm > 0 ? 1 : 0;
    final total = b.text.length + shift + soft.length;
    // Paragraph position (after the placeholder) → block offset, skipping inserted soft hyphens.
    final softAt = {for (var k = 0; k < soft.length; k++) soft[k] + k};
    int original(int q) {
      var n = 0;
      while (n < soft.length && soft[n] + n < q) {
        n++;
      }
      return q - n;
    }

    final starts = <int>[];
    var pos = 0;
    while (pos < total) {
      final range = p.getLineBoundary(ui.TextPosition(offset: pos));
      final q = range.start - shift;
      starts.add(original(q.clamp(0, total)).clamp(0, b.text.length));
      // The previous line ended in a soft hyphen: draw one after its last letter.
      if (starts.length > 1 && softAt.contains(q - 1) && q >= 2) {
        final boxes = p.getBoxesForRange(range.start - 2, range.start - 1);
        final line = starts.length - 2;
        if (boxes.isNotEmpty && line < lines.length) hyphenPoints[line] = ui.Offset(boxes.last.right, lines[line].baseline);
      }
      if (range.end <= pos) {
        pos++;
      } else {
        pos = range.end;
        // A hard line break ends before its newline; the next line starts after it.
        final o = original(pos - shift);
        if (pos - shift >= 0 && o < b.text.length && !softAt.contains(pos - shift) && b.text[o] == '\n') pos++;
      }
    }
    if (starts.isEmpty) starts.add(0);
    return starts;
  }
}
