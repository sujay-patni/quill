// Native engine: the parts of an EPUB package the reader needs (spine, manifest, chapter bytes).
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class SpineItem {
  const SpineItem(this.href, this.mediaType);

  /// Path inside the archive, e.g. `OEBPS/c1.xhtml`.
  final String href;
  final String mediaType;
}

class EpubBook {
  EpubBook._(this._archive, this.packagePath, this.title, this.spine, this.manifest, this.navPath, this.ncxPath, {this.authors = const [], this.identifiers = const []});

  /// The book's own authors and identifiers (ISBN, UUID…), as written in its package file.
  final List<String> authors;
  final List<String> identifiers;

  final Archive _archive;
  final String packagePath;
  final String title;
  final List<SpineItem> spine;

  /// Manifest id → archive path.
  final Map<String, String> manifest;

  /// EPUB 3 navigation document and EPUB 2 NCX, when present.
  final String? navPath;
  final String? ncxPath;

  static EpubBook open(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final container = XmlDocument.parse(_text(archive, 'META-INF/container.xml'));
    final opfPath = container.findAllElements('rootfile').first.getAttribute('full-path')!;
    final opf = XmlDocument.parse(_text(archive, opfPath));
    final base = opfPath.contains('/') ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1) : '';
    final manifest = <String, String>{};
    final types = <String, String>{};
    String? navPath;
    for (final item in opf.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = resolvePath(base, Uri.decodeFull(href));
      types[id] = item.getAttribute('media-type') ?? '';
      if ((item.getAttribute('properties') ?? '').split(' ').contains('nav')) navPath = manifest[id];
    }
    final tocId = opf.findAllElements('spine').firstOrNull?.getAttribute('toc');
    final ncxPath = manifest[tocId] ??
        manifest.entries.where((e) => types[e.key] == 'application/x-dtbncx+xml').map((e) => e.value).firstOrNull;
    final spine = [
      for (final ref in opf.findAllElements('itemref'))
        if (manifest[ref.getAttribute('idref')] case final href?) SpineItem(href, types[ref.getAttribute('idref')] ?? ''),
    ];
    final title = opf.findAllElements('dc:title').map((e) => e.innerText.trim()).firstWhere(
      (t) => t.isNotEmpty,
      orElse: () => '',
    );
    List<String> all(String tag) => [
      for (final e in opf.findAllElements(tag))
        if (e.innerText.trim().isNotEmpty) e.innerText.trim(),
    ];
    return EpubBook._(archive, opfPath, title, spine, manifest, navPath, ncxPath, authors: all('dc:creator'), identifiers: all('dc:identifier'));
  }

  /// Bytes of an archive entry, or null when it is missing.
  Uint8List? entry(String path) => _archive.findFile(path)?.content;

  /// Uncompressed size of each spine item, for book-wide progress without parsing.
  late final List<int> spineSizes = [for (final s in spine) _archive.findFile(s.href)?.size ?? 0];

  /// Text of any archive entry (stylesheets, navigation), or null.
  String? text(String path) {
    final bytes = entry(path);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  String chapterText(int spineIndex) => utf8.decode(entry(spine[spineIndex].href) ?? Uint8List(0), allowMalformed: true);

  static String _text(Archive archive, String path) {
    final file = archive.findFile(path);
    if (file == null) throw FormatException('Missing $path');
    return utf8.decode(file.content, allowMalformed: true);
  }
}

/// Resolves [relative] (no scheme) against the directory [base] (ending in `/` or empty).
String resolvePath(String base, String relative) {
  final parts = <String>[...base.split('/').where((p) => p.isNotEmpty)];
  for (final p in relative.split('/')) {
    if (p == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (p.isNotEmpty && p != '.') {
      parts.add(p);
    }
  }
  return parts.join('/');
}
