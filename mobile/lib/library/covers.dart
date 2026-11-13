// Which file inside a book is its cover. Pure rules, shared by Android and iOS.
import 'names.dart';

final _imageName = RegExp(r'\.(jpe?g|png|gif|webp)$', caseSensitive: false);

bool isImageName(String name) => _imageName.hasMatch(name);

// The OPF package path named by META-INF/container.xml.
String? opfPath(String containerXml) => RegExp(r'full-path\s*=\s*"([^"]+)"').firstMatch(containerXml)?.group(1);

String _attr(String tag, String name) =>
    RegExp('\\b$name\\s*=\\s*["\']([^"\']*)["\']', caseSensitive: false).firstMatch(tag)?.group(1) ?? '';

// Resolves an href relative to the OPF's folder, as a zip entry name.
String resolveHref(String opf, String href) {
  final base = opf.contains('/') ? opf.substring(0, opf.lastIndexOf('/') + 1) : '';
  final baseParts = base.split('/').where((p) => p.isNotEmpty).toList();
  final joined = <String>[...baseParts];
  for (final p in Uri.decodeComponent(href.split('#').first).replaceAll('\\', '/').split('/')) {
    if (p == '..') {
      if (joined.isNotEmpty) joined.removeLast();
    } else if (p.isNotEmpty && p != '.') {
      joined.add(p);
    }
  }
  return joined.join('/');
}

// The EPUB's declared cover image: EPUB 3 `properties="cover-image"`, then EPUB 2
// `<meta name="cover" content="id">`, then an image item whose id or name says "cover".
// Returns a zip entry name, or null when the book declares nothing usable.
String? epubCoverEntry(String opf, String opfXml, Set<String> entries) {
  final items = RegExp(r'<item\b[^>]*>', caseSensitive: false).allMatches(opfXml).map((m) => m[0]!).toList();
  String? pick(bool Function(String tag) test) {
    for (final tag in items) {
      final href = _attr(tag, 'href');
      final type = _attr(tag, 'media-type');
      if (href.isEmpty || !(type.startsWith('image/') || isImageName(href))) continue;
      if (!test(tag)) continue;
      final entry = resolveHref(opf, href);
      if (entries.contains(entry)) return entry;
    }
    return null;
  }

  final epub3 = pick((t) => _attr(t, 'properties').split(' ').contains('cover-image'));
  if (epub3 != null) return epub3;
  final meta = RegExp(
    r'<meta\b[^>]*>',
    caseSensitive: false,
  ).allMatches(opfXml).map((m) => m[0]!).firstWhere((t) => _attr(t, 'name').toLowerCase() == 'cover', orElse: () => '');
  final coverId = meta.isEmpty ? '' : _attr(meta, 'content');
  if (coverId.isNotEmpty) {
    final byId = pick((t) => _attr(t, 'id') == coverId);
    if (byId != null) return byId;
  }
  return pick((t) => '${_attr(t, 'id')} ${_attr(t, 'href')}'.toLowerCase().contains('cover'));
}

// Last resort for EPUBs, and the rule for comics: an image named "cover", else the first
// image in natural page order. Hidden and macOS resource-fork entries are ignored.
String? fallbackCoverEntry(Iterable<String> entries, {bool preferCoverName = true}) {
  final images =
      entries.where((e) => isImageName(e) && !e.split('/').any((p) => p.startsWith('.') || p == '__MACOSX')).toList()
        ..sort(naturalCompare);
  if (images.isEmpty) return null;
  if (preferCoverName) {
    for (final e in images) {
      if (e.split('/').last.toLowerCase().contains('cover')) return e;
    }
  }
  return images.first;
}
