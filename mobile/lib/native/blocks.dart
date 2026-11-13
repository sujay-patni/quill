// Native engine: chapter XHTML → a flat list of styled text blocks (Moon Reader-like subset).
//
// Honoured: block structure, bold/italic/underline/sup/sub, line breaks, images, rules, and from
// the book's CSS: text-align (centre/right kept; start/justify → justify), font-weight,
// font-style, relative font-size, text-indent, margin-top/bottom, display:none,
// page-break-before. Ignored, as in Moon Reader: generated content, small caps, publisher fonts,
// min-height, floats, columns.
import 'package:xml/xml.dart' show XmlDefaultEntityMapping;
import 'package:xml/xml_events.dart';

enum BlockAlign { justify, center, right }

enum BlockKind { text, image, rule }

class Run {
  const Run(this.text,
      {this.bold = false, this.italic = false, this.underline = false, this.scale = 1, this.shift = 0, this.href, this.noteRef = false});

  Run withText(String t) =>
      Run(t, bold: bold, italic: italic, underline: underline, scale: scale, shift: shift, href: href, noteRef: noteRef);

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;

  /// Font size relative to body text.
  final double scale;

  /// -1 subscript, 1 superscript.
  final int shift;

  /// Link target as written in the book (relative), and whether the book marks it as a note
  /// reference (`epub:type="noteref"`).
  final String? href;
  final bool noteRef;
}

class Block {
  Block({
    required this.kind,
    required this.runs,
    required this.start,
    this.align = BlockAlign.justify,
    this.indentEm = 0,
    this.topEm = 0,
    this.bottomEm = 0,
    this.breakBefore = false,
    this.image,
    this.anchors = const [],
  });

  final BlockKind kind;
  final List<Run> runs;

  /// Offset of this block's first character in the chapter's text (blocks joined without gaps).
  final int start;
  final BlockAlign align;
  final double indentEm;
  final double topEm;
  final double bottomEm;
  final bool breakBefore;

  /// Archive path of an image block.
  final String? image;

  /// Element ids that start in this block (for contents and internal links).
  final List<String> anchors;

  late final String text = runs.map((r) => r.text).join();

  /// The run containing block-relative character [offset].
  Run? runAt(int offset) {
    var pos = 0;
    for (final r in runs) {
      if (offset < pos + r.text.length) return r;
      pos += r.text.length;
    }
    return null;
  }
  int get length => kind == BlockKind.text ? text.length : 1;
  int get end => start + length;
}

/// Declarations for one simple selector, from the book's CSS.
class _Rule {
  _Rule(this.tag, this.cls, this.props);
  final String? tag;
  final String? cls;
  final Map<String, String> props;
}

class Stylesheet {
  Stylesheet([Iterable<String> sources = const []]) {
    for (final s in sources) {
      add(s);
    }
  }

  final List<_Rule> _rules = [];

  void add(String css) {
    final clean = css.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    for (final m in RegExp(r'([^{}@]+)\{([^{}]*)\}').allMatches(clean)) {
      final props = <String, String>{};
      for (final decl in m[2]!.split(';')) {
        final i = decl.indexOf(':');
        if (i <= 0) continue;
        props[decl.substring(0, i).trim().toLowerCase()] =
            decl.substring(i + 1).replaceAll('!important', '').trim().toLowerCase();
      }
      for (final selector in m[1]!.split(',')) {
        // Only simple selectors: tag, .class, tag.class (the last compound of a descendant chain).
        final last = selector.trim().split(RegExp(r'[\s>+~]+')).last;
        if (last.contains(':') || last.contains('[') || last.isEmpty) continue;
        final dot = last.indexOf('.');
        final tag = dot == 0 ? null : (dot < 0 ? last : last.substring(0, dot)).toLowerCase();
        final cls = dot < 0 ? null : last.substring(dot + 1).split('.').first;
        _rules.add(_Rule(tag == '*' ? null : tag, cls, props));
      }
    }
  }

  Map<String, String> propsFor(String tag, List<String> classes, String? inline) {
    final out = <String, String>{};
    for (final r in _rules) {
      if (r.tag != null && r.tag != tag) continue;
      if (r.cls != null && !classes.contains(r.cls)) continue;
      out.addAll(r.props);
    }
    if (inline != null) out.addAll(Stylesheet([' x{$inline}'])._rules.first.props);
    return out;
  }
}

const _blockTags = {
  'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'blockquote', 'pre', 'dt', 'dd', 'figure', //
  'figcaption', 'section', 'article', 'header', 'footer', 'aside', 'nav', 'table', 'tr', 'caption', 'body',
};
// <svg> is not skipped: covers are often an <image> inside one.
const _skipTags = {'head', 'script', 'style', 'title', 'math', 'text', 'desc'};
// HTML void elements: never have content or an end tag, whether or not written as `<x/>`.
const _voidTags = {
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'image', 'input', 'link', 'meta', 'param', //
  'source', 'track', 'wbr',
};
// Moon mode: headings keep body size (bold, own margins), as Moon Reader and the WebView path
// with typeScale 1 show them; a book's explicit font-size still scales them.
const _headingScale = {'h1': 1.0, 'h2': 1.0, 'h3': 1.0, 'h4': 1.0, 'h5': 1.0, 'h6': 1.0};

class _Ctx {
  _Ctx({
    required this.tag,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.scale = 1,
    this.shift = 0,
    this.hidden = false,
    this.align,
    this.pre = false,
    this.href,
    this.noteRef = false,
  });
  final String? href;
  final bool noteRef;
  final String tag;
  final bool bold, italic, underline, hidden, pre;
  final double scale;
  final int shift;
  final BlockAlign? align;
}

/// Parses one chapter. [resolve] turns an `src` attribute into an archive path.
/// [loadCss] returns the text of a linked stylesheet (`<link rel="stylesheet" href>`), or null.
List<Block> parseChapter(
  String xhtml, {
  Stylesheet? css,
  String Function(String src)? resolve,
  String? Function(String href)? loadCss,
}) {
  final sheet = css ?? Stylesheet();
  // The book's own CSS from <style> blocks and linked stylesheets (usually in <head>).
  StringBuffer? styleText;
  final blocks = <Block>[];
  final stack = <_Ctx>[_Ctx(tag: '#root')];
  var runs = <Run>[];
  var anchors = <String>[];
  var offset = 0;
  // Properties of the innermost open block element.
  var blockAlign = BlockAlign.justify;
  var indent = 0.0, top = 0.0, bottom = 0.0;
  var breakBefore = false;
  // Inside a skipped element: its tag and nesting depth (only the same tag name nests).
  String? skipTag;
  var skipDepth = 0;

  void flush() {
    // Collapse whitespace across run boundaries; drop empty paragraphs.
    final merged = <Run>[];
    var lastSpace = true;
    for (final r in runs) {
      // Source whitespace collapses; <br/> was recorded as U+2028 and becomes a real line break.
      var t = r.text.replaceAll(RegExp(r'[ \t\r\n\f]+'), ' ');
      if (lastSpace && t.startsWith(' ')) t = t.substring(1);
      t = t.replaceAll(' \u2028', '\u2028').replaceAll('\u2028', '\n');
      if (t.isEmpty) continue;
      lastSpace = t.endsWith(' ') || t.endsWith('\n');
      merged.add(r.withText(t));
    }
    // Trailing spaces and line breaks (`text<br/></p>`, common in Calibre books) are dropped.
    while (merged.isNotEmpty && RegExp(r'\s$').hasMatch(merged.last.text)) {
      final l = merged.removeLast();
      final t = l.text.trimRight();
      if (t.isNotEmpty) {
        merged.add(l.withText(t));
      }
    }
    if (merged.every((r) => r.text.trim().isEmpty)) {
      runs = [];
      return;
    }
    final b = Block(
      kind: BlockKind.text,
      runs: merged,
      start: offset,
      align: blockAlign,
      indentEm: indent,
      topEm: top,
      bottomEm: bottom,
      breakBefore: breakBefore,
      anchors: anchors,
    );
    blocks.add(b);
    offset = b.end;
    runs = [];
    anchors = [];
    breakBefore = false;
  }

  double em(String? v, double fallback) {
    if (v == null) return fallback;
    final m = RegExp(r'^(-?[\d.]+)(em|rem|%|px|pt)?').firstMatch(v);
    if (m == null) return fallback;
    final n = double.tryParse(m[1]!) ?? 0;
    return switch (m[2]) {
      '%' => n / 100,
      'px' => n / 16,
      'pt' => n / 12,
      _ => n,
    };
  }

  for (final event in parseEvents(xhtml, entityMapping: const XmlDefaultEntityMapping.html5(), validateNesting: false)) {
    if (event is XmlStartElementEvent) {
      final tag = event.localName.toLowerCase();
      final attrs = {for (final a in event.attributes) a.localName.toLowerCase(): a.value};
      final parent = stack.last;
      final selfClosing = event.isSelfClosing || _voidTags.contains(tag);
      if (tag == 'style' && !selfClosing) styleText = StringBuffer();
      if (tag == 'link' && (attrs['rel'] ?? '').toLowerCase().contains('stylesheet')) {
        final href = attrs['href'];
        final text = href == null ? null : loadCss?.call(href);
        if (text != null) sheet.add(text);
      }
      if (skipTag != null) {
        if (tag == skipTag && !selfClosing) skipDepth++;
        continue;
      }
      if (_skipTags.contains(tag)) {
        if (!selfClosing) {
          skipTag = tag;
          skipDepth = 1;
        }
        continue;
      }
      final classes = (attrs['class'] ?? '').split(RegExp(r'\s+')).where((c) => c.isNotEmpty).toList();
      final p = sheet.propsFor(tag, classes, attrs['style']);
      final hidden = parent.hidden || p['display'] == 'none' || attrs['hidden'] != null;
      final weight = p['font-weight'];
      final bold = switch (weight) {
        'bold' || 'bolder' || '600' || '700' || '800' || '900' => true,
        'normal' || '400' || 'lighter' || '300' => false,
        _ => parent.bold || tag == 'b' || tag == 'strong' || _headingScale.containsKey(tag),
      };
      final italic = switch (p['font-style']) {
        'italic' || 'oblique' => true,
        'normal' => false,
        _ => parent.italic || tag == 'i' || tag == 'em' || tag == 'cite',
      };
      final size = p['font-size'];
      final scale = parent.scale *
          (size != null && (size.endsWith('em') || size.endsWith('%')) ? em(size, 1).clamp(0.6, 2.0) : 1) *
          (_headingScale[tag] ?? (tag == 'small' || tag == 'sup' || tag == 'sub' ? 0.8 : 1));
      final align = switch (p['text-align']) {
        'center' => BlockAlign.center,
        'right' || 'end' => BlockAlign.right,
        'left' || 'start' || 'justify' => BlockAlign.justify,
        _ => parent.align,
      };
      final link = tag == 'a' ? attrs['href'] : null;
      final ctx = _Ctx(
        href: link ?? parent.href,
        noteRef: link != null ? (attrs['type'] ?? '').contains('noteref') : parent.noteRef,
        tag: tag,
        bold: bold,
        italic: italic,
        underline: parent.underline || tag == 'u' || (p['text-decoration'] ?? '').contains('underline'),
        scale: scale,
        shift: tag == 'sup' ? 1 : (tag == 'sub' ? -1 : parent.shift),
        hidden: hidden,
        align: align,
        pre: parent.pre || tag == 'pre',
      );
      if (attrs['id'] case final id? when !hidden) anchors.add(id);
      if (_blockTags.contains(tag) && !hidden) {
        flush();
        blockAlign = align ?? BlockAlign.justify;
        indent = em(p['text-indent'], 0);
        top = _headingScale.containsKey(tag) ? em(p['margin-top'], 1) : em(p['margin-top'], 0);
        bottom = _headingScale.containsKey(tag) ? em(p['margin-bottom'], 0.6) : em(p['margin-bottom'], 0);
        breakBefore = breakBefore || p['page-break-before'] == 'always' || p['break-before'] == 'page';
      }
      if (tag == 'br' && !hidden) runs.add(const Run('\u2028'));
      if (tag == 'img' || tag == 'image') {
        final src = attrs['src'] ?? attrs['href'];
        if (src != null && !hidden) {
          flush();
          blocks.add(Block(
            kind: BlockKind.image,
            runs: const [],
            start: offset,
            image: resolve?.call(src) ?? src,
            align: BlockAlign.center,
            anchors: anchors,
          ));
          offset += 1;
          anchors = [];
        }
      }
      if (tag == 'hr' && !hidden) {
        flush();
        blocks.add(Block(kind: BlockKind.rule, runs: const [], start: offset, topEm: 0.5, bottomEm: 0.5));
        offset += 1;
      }
      if (!selfClosing) stack.add(ctx);
    } else if (event is XmlEndElementEvent) {
      final tag = event.localName.toLowerCase();
      if (tag == 'style' && styleText != null) {
        sheet.add(styleText.toString());
        styleText = null;
      }
      if (skipTag != null) {
        if (tag == skipTag && --skipDepth == 0) skipTag = null;
        continue;
      }
      // Close up to the matching open element; ignore stray end tags (lenient, like browsers).
      final at = stack.lastIndexWhere((c) => c.tag == tag);
      if (at > 0) {
        while (stack.length > at) {
          if (_blockTags.contains(stack.removeLast().tag)) flush();
        }
      }
    } else if (event is XmlTextEvent || event is XmlCDATAEvent) {
      final value = event is XmlTextEvent ? event.value : (event as XmlCDATAEvent).value;
      if (styleText != null) {
        styleText.write(value);
        continue;
      }
      if (skipTag != null) continue;
      final c = stack.last;
      if (c.hidden) continue;
      runs.add(Run(value,
          bold: c.bold, italic: c.italic, underline: c.underline, scale: c.scale, shift: c.shift, href: c.href, noteRef: c.noteRef));
    }
  }
  flush();
  return blocks;
}
