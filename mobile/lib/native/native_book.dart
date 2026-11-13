// Native engine: one open EPUB — chapters parsed on demand (off the UI isolate), the book's CSS,
// contents titles, and conversion between Quill's saved locators and native positions.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:xml/xml.dart';

import 'blocks.dart';
import 'epub_book.dart';

/// A place in the book: spine item and character offset in that chapter's text.
class NativePosition {
  const NativePosition(this.spine, this.offset, {this.approximate = false});
  final int spine;
  final int offset;

  /// Converted from a WebView locator's page fraction, not an exact native place.
  final bool approximate;

  @override
  String toString() => 'NativePosition($spine, $offset${approximate ? ', ~' : ''})';
}

class TocEntry {
  const TocEntry(this.title, this.path, this.fragment, [this.depth = 0]);
  final String title;
  final String path;
  final String? fragment;

  /// Nesting level in the book's contents (0 = top level).
  final int depth;
}

class NativeBook {
  NativeBook._(this.epub, this._css, this.toc);

  final EpubBook epub;
  final Map<String, String> _css;
  final List<TocEntry> toc;
  final Map<int, Future<List<Block>>> _chapters = {};

  static const _channel = MethodChannel('app.quill/books');

  /// Reads a book from a content:// URI (Android) or a file path.
  static Future<Uint8List> readBytes(String uri) async {
    if (uri.startsWith('content://')) {
      final bytes = await _channel.invokeMethod<Uint8List>('read', {'uri': uri});
      if (bytes == null) throw const FileSystemException('Book could not be read');
      return bytes;
    }
    return File(uri.startsWith('file://') ? Uri.parse(uri).toFilePath() : uri).readAsBytes();
  }

  static Future<NativeBook> open(Uint8List bytes) async {
    final epub = EpubBook.open(bytes);
    final css = <String, String>{
      for (final path in epub.manifest.values.where((p) => p.toLowerCase().endsWith('.css')))
        path: ?epub.text(path),
    };
    return NativeBook._(epub, css, _readToc(epub));
  }

  int get length => epub.spine.length;

  /// Case-insensitive matches of [query] in chapter [spine]: (offset, snippet around it).
  Future<List<(int, String)>> search(int spine, String query, {int limit = 50}) async {
    final blocks = await chapter(spine);
    final needle = query.toLowerCase();
    final out = <(int, String)>[];
    if (needle.isEmpty) return out;
    for (final b in blocks) {
      if (b.kind != BlockKind.text) continue;
      final hay = b.text.toLowerCase();
      var at = hay.indexOf(needle);
      while (at >= 0 && out.length < limit) {
        final from = (at - 40).clamp(0, b.text.length), to = (at + needle.length + 60).clamp(0, b.text.length);
        out.add((b.start + at, '${from > 0 ? '…' : ''}${b.text.substring(from, to).replaceAll('\n', ' ')}${to < b.text.length ? '…' : ''}'));
        at = hay.indexOf(needle, at + needle.length);
      }
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Parsed blocks of spine item [i]; parsed once, off the UI isolate.
  Future<List<Block>> chapter(int i) {
    final href = epub.spine[i].href;
    return _chapters[i] ??=
        _parseOffThread(epub.chapterText(i), _css, href.contains('/') ? href.substring(0, href.lastIndexOf('/') + 1) : '')
            .then((blocks) async {
              _imageSizes[i] = await _measureImages(blocks);
              return blocks;
            });
  }

  final Map<int, Map<String, ui.Size>> _imageSizes = {};

  /// Natural sizes of chapter [i]'s images; available once [chapter] has completed.
  Map<String, ui.Size> imageSizes(int i) => _imageSizes[i] ?? const {};

  // Reads only each image's header (no pixel decode).
  Future<Map<String, ui.Size>> _measureImages(List<Block> blocks) async {
    final out = <String, ui.Size>{};
    for (final b in blocks) {
      final path = b.image;
      if (b.kind != BlockKind.image || path == null || out.containsKey(path)) continue;
      final bytes = epub.entry(path);
      if (bytes == null) continue;
      try {
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        final d = await ui.ImageDescriptor.encoded(buffer);
        out[path] = ui.Size(d.width.toDouble(), d.height.toDouble());
        d.dispose();
        buffer.dispose();
      } catch (_) {
        // Not a decodable image (e.g. SVG): it takes no space.
      }
    }
    return out;
  }

  /// Decodes an image for display, at most [maxWidth] pixels wide.
  Future<ui.Image?> decodeImage(String path, int maxWidth) async {
    final bytes = epub.entry(path);
    if (bytes == null) return null;
    try {
      final natural = _imageSizes.values.map((m) => m[path]).whereType<ui.Size>().firstOrNull;
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: natural != null && natural.width > maxWidth ? maxWidth : null,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  // Static, so the isolate's closure captures only these plain values (not this book or its
  // cache of futures, which cannot cross isolates).
  static Future<List<Block>> _parseOffThread(String xhtml, Map<String, String> css, String dir) => Isolate.run(
    () => parseChapter(
      xhtml,
      resolve: (src) => resolvePath(dir, Uri.decodeFull(src.split('#').first)),
      loadCss: (h) => css[resolvePath(dir, Uri.decodeFull(h))],
    ),
  );

  /// Spine index for a locator href, or -1 when no chapter matches (never guess chapter 1).
  int spineOf(String href) {
    String norm(String h) => Uri.decodeFull(h.split('#').first).replaceFirst(RegExp(r'^/+'), '');
    final path = norm(href);
    if (path.isEmpty) return -1;
    return epub.spine.indexWhere((s) {
      final h = norm(s.href);
      return h == path || h.endsWith('/$path') || path.endsWith('/$h');
    });
  }

  /// Book progress 0..1 at [p], weighting chapters by their uncompressed size.
  double progressOf(NativePosition p, int chapterLength) {
    final sizes = epub.spineSizes;
    final total = sizes.fold<int>(0, (a, b) => a + b);
    if (total == 0) return 0;
    final before = sizes.take(p.spine).fold<int>(0, (a, b) => a + b);
    final within = chapterLength == 0 ? 0.0 : p.offset / chapterLength;
    return ((before + within * sizes[p.spine]) / total).clamp(0.0, 1.0);
  }

  /// Index in [toc] of the entry containing [p]: the last entry in this chapter whose anchor is
  /// at or before it, else the last entry of the nearest earlier chapter; -1 when none.
  int tocIndexAt(NativePosition p, List<Block> blocks) {
    for (var s = p.spine; s >= 0; s--) {
      final path = epub.spine[s].href;
      var first = -1, last = -1, best = -1;
      for (var i = 0; i < toc.length; i++) {
        final e = toc[i];
        if (e.path != path) continue;
        if (first < 0) first = i;
        last = i;
        if (s == p.spine) {
          final at = e.fragment == null ? 0 : _anchorOffset(blocks, e.fragment!);
          if (at == null || at <= p.offset) best = i;
        }
      }
      if (first < 0) continue;
      if (s < p.spine) return last;
      return best < 0 ? first : best;
    }
    return -1;
  }

  /// Where the contents chapter containing [p] ends within this spine item: the next entry's
  /// anchor in the same file, else the end of the file.
  int chapterEnd(NativePosition p, List<Block> blocks) {
    final end = blocks.isEmpty ? 0 : blocks.last.end;
    final i = tocIndexAt(p, blocks);
    if (i < 0) return end;
    final path = epub.spine[p.spine].href;
    for (var n = i + 1; n < toc.length; n++) {
      if (toc[n].path != path) break;
      final at = toc[n].fragment == null ? null : _anchorOffset(blocks, toc[n].fragment!);
      if (at != null && at > p.offset) return at;
    }
    return end;
  }

  String titleAt(NativePosition p, List<Block> blocks) {
    final i = tocIndexAt(p, blocks);
    return i < 0 ? '' : toc[i].title;
  }

  /// Where a link written in chapter [fromSpine] leads: a place in this book, or null for
  /// external links and missing targets.
  Future<NativePosition?> resolveLink(int fromSpine, String href) async {
    if (href.contains('://') || href.startsWith('mailto:')) return null;
    final from = epub.spine[fromSpine].href;
    final dir = from.contains('/') ? from.substring(0, from.lastIndexOf('/') + 1) : '';
    final parts = href.split('#');
    final spine = parts.first.isEmpty ? fromSpine : spineOf(resolvePath(dir, Uri.decodeFull(parts.first)));
    if (spine < 0) return null;
    final blocks = await chapter(spine);
    if (parts.length < 2 || parts[1].isEmpty) return NativePosition(spine, 0);
    final at = _anchorOffset(blocks, Uri.decodeFull(parts[1]));
    return at == null ? null : NativePosition(spine, at);
  }

  /// Where contents entry [index] starts, or null when its chapter is not in the spine.
  Future<NativePosition?> positionOfToc(int index) async {
    final e = toc[index];
    final spine = spineOf(e.path);
    if (spine < 0) return null;
    final blocks = await chapter(spine);
    return NativePosition(spine, e.fragment == null ? 0 : (_anchorOffset(blocks, e.fragment!) ?? 0));
  }

  static int? _anchorOffset(List<Block> blocks, String id) {
    for (final b in blocks) {
      if (b.anchors.contains(id)) return b.start;
    }
    return null;
  }

  /// Saved locator JSON → native position. An exact native place is used when present;
  /// otherwise a WebView locator converts approximately (its progression is a page fraction).
  /// Throws [StateError] when the locator's chapter is not in this book.
  NativePosition fromLocator(String json, List<Block> Function(int spine) blocksOf) {
    if (json.isEmpty) return const NativePosition(0, 0);
    final map = jsonDecode(json) as Map<String, dynamic>;
    final spine = spineOf(map['href'] as String? ?? '');
    if (spine < 0) throw StateError('Saved chapter not found in this book');
    final native = map['quillNative'];
    if (native is Map && native['spine'] == spine && native['offset'] is int) {
      return NativePosition(spine, native['offset'] as int);
    }
    final blocks = blocksOf(spine);
    final length = blocks.isEmpty ? 0 : blocks.last.end;
    final locations = (map['locations'] as Map?) ?? const {};
    final progression = (locations['progression'] as num?)?.toDouble() ?? 0;
    final byProgress = (progression * length).round().clamp(0, length);
    // An element anchor is more precise, but only trusted when it agrees with the page fraction
    // (Readium may report a chapter-level selector such as #top).
    final selector = (locations['cssSelector'] ?? (locations['otherLocations'] as Map?)?['cssSelector']) as String?;
    if (selector != null && selector.startsWith('#')) {
      final at = _anchorOffset(blocks, selector.substring(1));
      if (at != null && (at - byProgress).abs() <= length * 0.02 + 200) return NativePosition(spine, at, approximate: true);
    }
    return NativePosition(spine, byProgress, approximate: true);
  }

  /// Native position → locator JSON the WebView path can also read (href + progression), with the
  /// exact native place and a short quote for repair.
  /// [previous] is the saved locator being replaced; a non-native one is kept as a backup.
  String toLocator(NativePosition p, List<Block> blocks, {String previous = ''}) {
    final length = blocks.isEmpty ? 0 : blocks.last.end;
    final block = blocks.lastWhere((b) => b.start <= p.offset, orElse: () => blocks.isEmpty ? Block(kind: BlockKind.text, runs: const [], start: 0) : blocks.first);
    final from = (p.offset - block.start).clamp(0, block.text.length);
    final quote = block.kind == BlockKind.text ? block.text.substring(from, (from + 60).clamp(0, block.text.length)) : '';
    Object? backup;
    if (previous.isNotEmpty) {
      try {
        final old = jsonDecode(previous) as Map<String, dynamic>;
        backup = old['quillNative'] == null ? previous : old['quillPrevious'];
      } catch (_) {
        backup = previous;
      }
    }
    return jsonEncode({
      'href': epub.spine[p.spine].href,
      'type': 'application/xhtml+xml',
      'locations': {
        'progression': length == 0 ? 0 : p.offset / length,
        'totalProgression': progressOf(p, length),
      },
      'quillNative': {'spine': p.spine, 'offset': p.offset, 'quote': quote},
      'quillPrevious': ?backup,
    });
  }

  static List<TocEntry> _readToc(EpubBook epub) {
    final out = <TocEntry>[];
    void add(String title, String base, String? href, int depth) {
      if (href == null || title.trim().isEmpty) return;
      final parts = href.split('#');
      out.add(TocEntry(title.trim().replaceAll(RegExp(r'\s+'), ' '), resolvePath(base, Uri.decodeFull(parts.first)),
          parts.length > 1 ? parts[1] : null, depth));
    }

    int nesting(XmlElement e, String tag) => e.ancestorElements.where((a) => a.localName == tag).length;

    String dirOf(String p) => p.contains('/') ? p.substring(0, p.lastIndexOf('/') + 1) : '';
    try {
      if (epub.navPath case final nav? when epub.text(nav) != null) {
        final doc = XmlDocument.parse(epub.text(nav)!);
        final tocNav = doc.findAllElements('nav').where((n) => (n.getAttribute('epub:type') ?? n.getAttribute('type') ?? '') == 'toc').firstOrNull ??
            doc.findAllElements('nav').firstOrNull;
        for (final a in tocNav?.findAllElements('a') ?? const <XmlElement>[]) {
          add(a.innerText, dirOf(nav), a.getAttribute('href'), (nesting(a, 'ol') - 1).clamp(0, 8));
        }
      }
      if (out.isEmpty && epub.ncxPath != null && epub.text(epub.ncxPath!) != null) {
        final doc = XmlDocument.parse(epub.text(epub.ncxPath!)!);
        for (final point in doc.findAllElements('navPoint')) {
          final label = point.findElements('navLabel').firstOrNull?.innerText ?? '';
          add(label, dirOf(epub.ncxPath!), point.findElements('content').firstOrNull?.getAttribute('src'),
              nesting(point, 'navPoint').clamp(0, 8));
        }
      }
    } catch (_) {
      // A broken contents file only costs chapter names.
    }
    return out;
  }
}
