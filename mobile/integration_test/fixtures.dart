// Synthetic books written at test time. No personal books, text or covers.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

const _sentence = 'The quiet lantern keeps its steady light while the harbour sleeps under rain. ';

String _chapter(int n, {bool nested = false, int paragraphCount = 18, bool inlineMarkup = false, bool images = false}) {
  // Inline markup mimics real books (italics, spans) and multiplies the element count.
  final body = inlineMarkup
      ? '<span>${_sentence * 2}</span><i>${_sentence * 2}</i><span>$_sentence</span><b>$_sentence</b>'
      : _sentence * 6;
  final paragraphs = List.generate(
    paragraphCount,
    (i) => '<p>${body}Chapter $n paragraph ${i + 1}.</p>',
  ).join('\n');
  final section = nested ? '<h2 id="nested">Chapter $n, nested part</h2>\n$paragraphs' : '';
  return '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter $n</title></head>
<body>${images ? '<div><svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 120 180"><image width="120" height="180" xlink:href="images/front.png"/></svg></div>' : ''}<h1 id="top">Chapter $n</h1>
${images ? '<p><img src="images/front.png" alt=""/></p><p><img src="images/missing.png" alt=""/></p>' : ''}
$paragraphs
$section
</body></html>''';
}

Uint8List syntheticEpub({
  bool withCover = false,
  int chapters = 4,
  List<int>? paragraphCounts,
  bool inlineMarkup = false,
  // Chapter 1 starts with an SVG-wrapped cover image and has an inline <img> (needs withCover).
  bool imagesInText = false,
  String title = 'Synthetic Navigation',
  String author = 'Quill Tests',
}) {
  final archive = Archive();
  final mimetype = ArchiveFile.string('mimetype', 'application/epub+zip')..compression = CompressionType.none;
  archive.addFile(mimetype);
  archive.addFile(
    ArchiveFile.string('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>'''),
  );
  final items = List.generate(
    chapters,
    (i) => '<item id="c${i + 1}" href="c${i + 1}.xhtml" media-type="application/xhtml+xml"/>',
  ).join('\n');
  final spine = List.generate(chapters, (i) => '<itemref idref="c${i + 1}"/>').join('\n');
  archive.addFile(
    ArchiveFile.string('OEBPS/content.opf', '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">urn:uuid:00000000-0000-4000-8000-00000000a11c</dc:identifier>
<dc:title>$title</dc:title><dc:creator>$author</dc:creator><dc:language>en</dc:language>
<meta property="dcterms:modified">2026-11-05T00:00:00Z</meta>
</metadata>
<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
${withCover ? '<item id="art" href="images/front.png" media-type="image/png" properties="cover-image"/>' : ''}
$items
</manifest>
<spine>$spine</spine>
</package>'''),
  );
  final toc = List.generate(chapters, (i) {
    final n = i + 1;
    final nested = n == 2 ? '<ol><li><a href="c2.xhtml#nested">Chapter 2, nested part</a></li></ol>' : '';
    return '<li><a href="c$n.xhtml">Chapter $n</a>$nested</li>';
  }).join('\n');
  archive.addFile(
    ArchiveFile.string('OEBPS/nav.xhtml', '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head>
<body><nav epub:type="toc"><ol>
$toc
</ol></nav></body></html>'''),
  );
  if (withCover) archive.addFile(ArchiveFile.bytes('OEBPS/images/front.png', _png(120, 180, const [40, 70, 160])));
  for (var n = 1; n <= chapters; n++) {
    final chapter = ArchiveFile.string(
      'OEBPS/c$n.xhtml',
      _chapter(n, nested: n == 2, paragraphCount: paragraphCounts?[n - 1] ?? 18, inlineMarkup: inlineMarkup, images: imagesInText && n == 1),
    );
    // Readium's position service uses archive-entry lengths, including compression.
    // Store unequal test resources so repeated synthetic prose remains unequal.
    if (paragraphCounts != null) chapter.compression = CompressionType.none;
    archive.addFile(chapter);
  }
  return ZipEncoder().encodeBytes(archive);
}

// A minimal text PDF with numbered pages.
Uint8List syntheticPdf({int pages = 5}) {
  final objects = <String>[];
  objects.add('<< /Type /Catalog /Pages 2 0 R >>');
  final kids = List.generate(pages, (i) => '${4 + i * 2} 0 R').join(' ');
  objects.add('<< /Type /Pages /Kids [$kids] /Count $pages >>');
  objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  for (var i = 0; i < pages; i++) {
    final content = 'BT /F1 36 Tf 72 700 Td (Page ${i + 1}) Tj ET';
    objects.add(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Resources << /Font << /F1 3 0 R >> >> /Contents ${5 + i * 2} 0 R >>',
    );
    objects.add('<< /Length ${content.length} >>\nstream\n$content\nendstream');
  }
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(out.toString()));
}

Uint8List _png(int width, int height, List<int> rgb) {
  List<int> chunk(String kind, List<int> data) {
    final body = [...ascii.encode(kind), ...data];
    return [..._u32(data.length), ...body, ..._u32(getCrc32(body))];
  }

  final row = [0, for (var x = 0; x < width; x++) ...rgb];
  final raw = [for (var y = 0; y < height; y++) ...row];
  return Uint8List.fromList([
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    ...chunk('IHDR', [..._u32(width), ..._u32(height), 8, 2, 0, 0, 0]),
    ...chunk('IDAT', ZLibCodec().encode(raw)),
    ...chunk('IEND', const []),
  ]);
}

List<int> _u32(int v) => [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

Uint8List syntheticCbz({int pages = 4}) {
  final colours = [
    [200, 60, 60],
    [60, 160, 80],
    [60, 90, 200],
    [200, 180, 60],
  ];
  final archive = Archive();
  for (var i = 0; i < pages; i++) {
    archive.addFile(ArchiveFile.bytes('page${(i + 1).toString().padLeft(2, '0')}.png', _png(60, 90, colours[i % 4])));
  }
  return ZipEncoder().encodeBytes(archive);
}

List<int> _le(int v, int bytes) => [for (var i = 0; i < bytes; i++) (v >> (8 * i)) & 0xff];

// A RAR 4 block: its header checksum is the low 16 bits of the CRC-32 of the rest of the header.
List<int> _rarBlock(int type, int flags, List<int> fields) {
  final rest = [type, ..._le(flags, 2), ..._le(7 + fields.length, 2), ...fields];
  return [..._le(getCrc32(rest) & 0xffff, 2), ...rest];
}

/// A RAR 4 archive of page images, stored without compression (what a .cbr usually is).
Uint8List syntheticCbr({int pages = 4}) {
  final colours = [
    [200, 60, 60],
    [60, 160, 80],
    [60, 90, 200],
    [200, 180, 60],
  ];
  final out = <int>[0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00, ..._rarBlock(0x73, 0, List.filled(6, 0))];
  // Written out of order: Quill sorts pages by name.
  for (final i in [for (var p = pages - 1; p >= 0; p--) p]) {
    final data = _png(60, 90, colours[i % 4]);
    final name = ascii.encode('Comic\\page${(i + 1).toString().padLeft(2, '0')}.png');
    out.addAll(_rarBlock(0x74, 0x8000, [
      ..._le(data.length, 4), // packed size
      ..._le(data.length, 4), // size
      0, // host: MS-DOS
      ..._le(getCrc32(data), 4),
      ..._le(0x5A6B0000, 4), // a DOS date
      20, // version needed
      0x30, // method: stored
      ..._le(name.length, 2),
      ..._le(0x20, 4),
      ...name,
    ]));
    out.addAll(data);
  }
  out.addAll(_rarBlock(0x7B, 0x4000, const []));
  return Uint8List.fromList(out);
}

Future<File> writeFixture(Directory dir, String name, Uint8List bytes) async {
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}
