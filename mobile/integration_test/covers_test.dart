// On-device cover building with synthetic books: EPUB declared cover, CBZ first page,
// PDF first page; a CBR's first page too (RAR 4, or a ZIP with that name).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quill/library/book.dart';
import 'package:quill/library/cover_store.dart';

import 'fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('covers are built for EPUB, CBZ, PDF and CBR', (tester) async {
    final root = Directory(
      '${(await getTemporaryDirectory()).path}/quill-covers-${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    final books = Directory('${root.path}/books')..createSync();
    Book book(String name, File f) =>
        Book(id: name, uri: f.path, name: name, folder: '', size: f.lengthSync(), modified: 1);
    final epub = book('Cover Book.epub', await writeFixture(books, 'Cover Book.epub', syntheticEpub(withCover: true)));
    final cbz = book('Comic v01.cbz', await writeFixture(books, 'Comic v01.cbz', syntheticCbz()));
    final pdf = book('Pages.pdf', await writeFixture(books, 'Pages.pdf', syntheticPdf()));
    final cbr = book('Other v02.cbr', await writeFixture(books, 'Other v02.cbr', syntheticCbr()));
    final noCover = book('Plain.epub', await writeFixture(books, 'Plain.epub', syntheticEpub(chapters: 1)));

    final store = CoverStore(directory: () async => root);
    await store.load();
    await tester.runAsync(() => store.build([epub, cbz, pdf, cbr, noCover]));

    for (final b in [epub, cbz, pdf]) {
      expect(store.has(b.id), isTrue, reason: '${b.name} should have a cover');
      final bytes = store.fileFor(b.id).readAsBytesSync();
      expect(bytes.take(2), [0xFF, 0xD8], reason: '${b.name} cover should be a JPEG');
    }
    expect(store.has(cbr.id), isTrue, reason: 'the first page of a RAR comic');
    expect(store.has(noCover.id), isFalse, reason: 'a book with no images gets the generated card');

    // A second build does not retry known failures or rebuild existing covers.
    await tester.runAsync(() => store.build([epub, cbz, pdf, cbr, noCover]));
    expect(store.total, 0);
  });
}
