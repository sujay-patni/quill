// Cover-entry rules with synthetic package documents.
import 'package:flutter_test/flutter_test.dart';
import 'package:quill/library/covers.dart';

void main() {
  test('container.xml names the package document', () {
    expect(
      opfPath('<rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'),
      'OEBPS/content.opf',
    );
    expect(opfPath('<container/>'), isNull);
  });

  test('hrefs resolve against the package folder', () {
    expect(resolveHref('OEBPS/content.opf', 'images/cover.jpg'), 'OEBPS/images/cover.jpg');
    expect(resolveHref('OEBPS/content.opf', '../Images/Cover%20Art.png'), 'Images/Cover Art.png');
    expect(resolveHref('content.opf', './cover.jpeg'), 'cover.jpeg');
  });

  test('EPUB 3 cover-image property wins', () {
    const opf = '''<manifest>
      <item id="c" href="images/cover.jpg" media-type="image/jpeg"/>
      <item id="art" href="images/front.png" media-type="image/png" properties="cover-image"/>
    </manifest>''';
    expect(
      epubCoverEntry('OEBPS/content.opf', opf, {'OEBPS/images/cover.jpg', 'OEBPS/images/front.png'}),
      'OEBPS/images/front.png',
    );
  });

  test('EPUB 2 meta cover id, in either attribute order', () {
    const opf = '''<metadata><meta content="img-7" name="cover"/></metadata>
      <manifest><item href="a.jpg" id="img-1" media-type="image/jpeg"/>
      <item media-type="image/jpeg" href="b.jpg" id="img-7"/></manifest>''';
    expect(epubCoverEntry('content.opf', opf, {'a.jpg', 'b.jpg'}), 'b.jpg');
  });

  test('falls back to an image item called cover; ignores missing entries', () {
    const opf = '''<manifest><item id="x" href="pic1.jpg" media-type="image/jpeg"/>
      <item id="cover-image" href="titlepage.jpg" media-type="image/jpeg"/>
      <item id="cover2" href="gone.jpg" media-type="image/jpeg"/></manifest>''';
    expect(epubCoverEntry('content.opf', opf, {'pic1.jpg', 'titlepage.jpg'}), 'titlepage.jpg');
    expect(epubCoverEntry('content.opf', '<manifest/>', {'a.jpg'}), isNull);
  });

  test('comic and last-resort covers use natural order and skip hidden files', () {
    final pages = ['p10.jpg', 'p2.jpg', '__MACOSX/._p1.jpg', '.thumb.png', 'p1.jpg', 'info.txt'];
    expect(fallbackCoverEntry(pages, preferCoverName: false), 'p1.jpg');
    expect(fallbackCoverEntry([...pages, 'extras/Cover.jpg']), 'extras/Cover.jpg');
    expect(fallbackCoverEntry(['readme.txt']), isNull);
  });
}
