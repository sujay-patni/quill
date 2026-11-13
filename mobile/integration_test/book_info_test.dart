// On-device: reading time, the finish prompt and book information, with synthetic books.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quill/library/book.dart';
import 'package:quill/library/library.dart';
import 'package:quill/reader/reader_page.dart';
import 'package:quill/shelf/book_info_page.dart';

import 'fixtures.dart';

Future<void> _pumpFor(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() done,
  String what, {
  int seconds = 20,
  String Function()? detail,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for $what ${detail?.call() ?? ''}');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<Library> _library(String name) async {
  final root = Directory('${(await getTemporaryDirectory()).path}/quill-info-${DateTime.now().microsecondsSinceEpoch}')
    ..createSync(recursive: true);
  final file = await writeFixture(root, name, syntheticEpub(chapters: 3));
  final lib = Library(directory: () async => root);
  lib.books = [Book(id: name, uri: file.path, name: name, folder: '', size: file.lengthSync(), modified: 1)];
  return lib;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final readium = FlutterReadium();

  testWidgets('reading time and page turns are recorded when the reader closes', (tester) async {
    final lib = await _library('Timed Book.epub');
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(library: lib, book: lib.books.first),
      ),
    );
    await _waitFor(tester, () => lib.books.first.locator.isNotEmpty, 'the reader');
    for (var i = 0; i < 4; i++) {
      await _pumpFor(tester, const Duration(seconds: 3));
      await readium.goForward();
    }
    await _pumpFor(tester, const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
    await _waitFor(tester, () => lib.stats.daysFor(lib.books.first.id).isNotEmpty, 'saved reading time');
    final summary = lib.stats.summary();
    expect(summary.ms, greaterThan(10000), reason: 'about 12 s of page turning');
    expect(summary.pages, greaterThanOrEqualTo(3));
    expect(lib.books.first.startedAt, greaterThan(0));
  });

  testWidgets('reaching the end asks to mark the book finished, with a rating', (tester) async {
    final lib = await _library('Ending Book.epub');
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(library: lib, book: lib.books.first),
      ),
    );
    await _waitFor(tester, () => lib.books.first.locator.isNotEmpty, 'the reader');
    await _pumpFor(tester, const Duration(seconds: 1));
    // Jump into the last chapter, then turn pages to its end.
    await readium.goToLocator(
      const Locator(href: 'OEBPS/c3.xhtml', type: 'application/xhtml+xml', locations: Locations(progression: 0.8)),
    );
    await _pumpFor(tester, const Duration(seconds: 1));
    for (var i = 0; i < 12 && find.byKey(const Key('markFinished')).evaluate().isEmpty; i++) {
      await readium.goForward();
      await _pumpFor(tester, const Duration(milliseconds: 800));
    }
    await _waitFor(
      tester,
      () => find.byKey(const Key('markFinished')).evaluate().isNotEmpty,
      'the finish prompt',
      detail: () => lib.books.first.locator,
    );
    // Presence precedes the sheet's slide-in animation; wait until the rating is on-screen.
    await _pumpFor(tester, const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const Key('star4')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('markFinished')));
    await _waitFor(tester, () => lib.books.first.finished, 'finished');
    expect(lib.books.first.rating, 4);
    expect(lib.books.first.finishedAt, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('book information edits persist and reset progress clears only progress', (tester) async {
    final lib = await _library('Info Book.epub');
    await lib.update(lib.books.first.id, (b) => b.copyWith(progress: 0.4, locator: '{"href":"c1.xhtml"}'));
    await tester.pumpWidget(
      MaterialApp(
        home: BookInfoPage(library: lib, bookId: lib.books.first.id),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('star3')).first);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('field:Series')), 'Synthetic Saga');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(lib.books.first.rating, 3);
    expect(lib.books.first.series, 'Synthetic Saga');
    expect(lib.books.first.editedByUser('series'), isTrue);

    FocusManager.instance.primaryFocus?.unfocus();
    await _pumpFor(tester, const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const Key('bookMenu')));
    await _waitFor(tester, () => find.byKey(const Key('resetProgress')).evaluate().isNotEmpty, 'the book menu');
    await tester.tap(find.byKey(const Key('resetProgress')));
    await _waitFor(tester, () => find.byKey(const Key('confirmReset')).evaluate().isNotEmpty, 'the confirm dialog');
    await tester.tap(find.byKey(const Key('confirmReset')));
    await _waitFor(tester, () => lib.books.first.progress == 0, 'progress reset');
    expect(lib.books.first.locator, '');
    expect(lib.books.first.rating, 3, reason: 'reset keeps the rating');
    expect(lib.books.first.series, 'Synthetic Saga');
  });
}
