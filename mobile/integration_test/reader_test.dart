// On-device checks with synthetic books: opening, page turns, saved positions after reopen,
// and controls that overlay the page without resizing it.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quill/library/backup.dart';
import 'package:quill/library/book.dart';
import 'package:quill/library/cover_store.dart';
import 'package:quill/library/library.dart';
import 'package:quill/reader/reader_page.dart';
import 'package:quill/reader/reading_profile.dart';

import 'fixtures.dart';

late Directory _root;

Future<Library> _libraryWith(String name, File file) async {
  final dir = Directory('${_root.path}/${DateTime.now().microsecondsSinceEpoch}')..createSync();
  final lib = Library(directory: () async => dir);
  lib.books = [Book(id: name, uri: file.path, name: name, folder: '', size: file.lengthSync(), modified: 1)];
  return lib;
}

Future<void> _waitFor(WidgetTester tester, bool Function() done, String what, {int seconds = 20}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!done()) {
    if (DateTime.now().isAfter(end)) {
      final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data ?? '').where((t) => t.isNotEmpty);
      fail('Timed out waiting for $what. On screen: ${texts.join(' | ')}');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Locator? _saved(Library lib) =>
    lib.books.first.locator.isEmpty ? null : Locator.fromJsonString(lib.books.first.locator);

Future<void> _openReader(WidgetTester tester, Library lib) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ReaderPage(library: lib, book: lib.books.first),
    ),
  );
  await _waitFor(tester, () => find.byKey(const Key('reader')).evaluate().isNotEmpty, 'the reader');
}

// Closing the reader closes the publication; wait for it before reopening.
Future<void> _closeReader(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

// The saved locator once it has stopped changing for 1.5 s.
Future<Locator> _stableLocator(WidgetTester tester, Library lib) async {
  var last = lib.books.first.locator;
  var since = DateTime.now();
  final end = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().difference(since) < const Duration(milliseconds: 1500)) {
    if (DateTime.now().isAfter(end)) fail('The saved position kept changing');
    await tester.pump(const Duration(milliseconds: 200));
    if (lib.books.first.locator != last) {
      last = lib.books.first.locator;
      since = DateTime.now();
    }
  }
  return Locator.fromJsonString(last)!;
}

Future<void> _settle(WidgetTester tester, [int ms = 1500]) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final readium = FlutterReadium();

  setUpAll(() async {
    _root = Directory('${(await getTemporaryDirectory()).path}/quill-it')..createSync(recursive: true);
  });

  testWidgets('EPUB: held curl previews the next resource, reverses and commits only on release', (tester) async {
    final file = await writeFixture(
      _root,
      'Interactive Turn.epub',
      // Chapter 2 spans several pages so the committed turn never reaches the book's end
      // (which opens the finish prompt over the page).
      syntheticEpub(chapters: 2, paragraphCounts: [1, 6]),
    );
    final lib = await _libraryWith('Interactive Turn.epub', file);
    await _openReader(tester, lib);
    await _waitFor(tester, () => _saved(lib) != null, 'initial page');
    final origin = await _stableLocator(tester, lib);
    final originJson = lib.books.single.locator;
    final rect = tester.getRect(find.byKey(const Key('reader')));
    final image = File('${_root.path}/underlying-page.jpg');
    expect(await readium.snapshotPage(image.path, maxWidth: 500), isTrue);
    final before = sha256.convert(await image.readAsBytes()).toString();

    Future<TestGesture> drag(bool forward) async {
      final gesture = await tester.startGesture(Offset(rect.left + rect.width * (forward ? .85 : .15), rect.center.dy));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 35));
        await gesture.moveBy(Offset(rect.width * (forward ? -.1 : .1), 0));
      }
      await _settle(tester, 900);
      return gesture;
    }

    // What the curl draws, not just where the locator goes: a blank capture once let the live
    // destination show through while every locator check passed.
    Future<void> expectBothPagesDrawn(String when) async {
      final state = await readium.pageTurnDebugState();
      expect(state['active'], isTrue, reason: '$when: the curl is showing');
      expect(state['ready'], isTrue, reason: '$when: both pages are captured');
      expect(state['frontInk'] as num, greaterThan(0.005), reason: '$when: the turning page has text');
      expect(state['underInk'] as num, greaterThan(0.005), reason: '$when: the page underneath has text');
      expect(state['pagesDiffer'], isTrue, reason: '$when: the two pages are different pages');
    }

    final cancelled = await drag(true);
    await expectBothPagesDrawn('held forward turn');
    expect(lib.books.single.locator, originJson, reason: 'holding a turn must not save the preview destination');
    expect(await readium.snapshotPage(image.path, maxWidth: 500), isTrue);
    expect(
      sha256.convert(await image.readAsBytes()).toString(),
      isNot(before),
      reason: 'the next page is prepared underneath',
    );
    await cancelled.moveBy(Offset(rect.width * .42, 0));
    await _settle(tester, 500);
    await cancelled.up();
    await _settle(tester, 1200);
    expect(lib.books.single.locator, originJson, reason: 'reversing the gesture retains the confirmed origin');

    final committed = await drag(true);
    expect(lib.books.single.locator, originJson);
    await committed.up();
    await _waitFor(tester, () => (_saved(lib)?.href ?? '').contains('c2.xhtml'), 'committed next resource');
    final next = await _stableLocator(tester, lib);
    final returning = await drag(false);
    await expectBothPagesDrawn('held backward turn');
    expect(_saved(lib)?.href, next.href, reason: 'backward preview is also uncommitted while held');
    await returning.up();
    await _waitFor(tester, () => _saved(lib)?.href == origin.href, 'committed backward turn');
    await _stableLocator(tester, lib);
    await _closeReader(tester);
    await _openReader(tester, lib);
    await _waitFor(tester, () => _saved(lib)?.href == origin.href, 'reopen after interactive turns');
    await _closeReader(tester);
  });

  testWidgets('EPUB: page turns in a one-file book do not stall opening the next book', (tester) async {
    // Smoke check for Q02-03: books stored as one huge XHTML file once started a quadratic scan
    // on every page change that outlived the book and starved the next open. The phone hang
    // (a one-file novel) did not reproduce at this size on the emulator; the fix was verified on a phone.
    final huge = await writeFixture(_root, 'One File.epub', syntheticEpub(chapters: 1, paragraphCounts: [4000], inlineMarkup: true));
    final hugeLib = await _libraryWith('One File.epub', huge);
    await _openReader(tester, hugeLib);
    await _waitFor(tester, () => _saved(hugeLib) != null, 'the one-file book', seconds: 30);
    final rect = tester.getRect(find.byKey(const Key('reader')));
    for (var i = 0; i < 6; i++) {
      await tester.tapAt(Offset(rect.right - 20, rect.center.dy));
      await _settle(tester, 400);
    }
    await _closeReader(tester);
    final next = await writeFixture(_root, 'Next.epub', syntheticEpub(chapters: 2));
    final nextLib = await _libraryWith('Next.epub', next);
    final clock = Stopwatch()..start();
    await _openReader(tester, nextLib);
    await _waitFor(tester, () => _saved(nextLib) != null, 'the next book after the one-file book', seconds: 15);
    expect(clock.elapsed, lessThan(const Duration(seconds: 15)));
    await _closeReader(tester);
  });

  testWidgets('EPUB: fast replacement of a reader cannot retain the closed publication', (tester) async {
    final first = await writeFixture(_root, 'Single Resource.epub', syntheticEpub(chapters: 1));
    final second = await writeFixture(
      _root,
      'Replacement.epub',
      syntheticEpub(chapters: 3, paragraphCounts: [60, 25, 45]),
    );
    for (var i = 0; i < 2; i++) {
      final a = await _libraryWith('Single Resource.epub', first);
      await _openReader(tester, a);
      await _waitFor(tester, () => _saved(a) != null, 'first publication');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
      final b = await _libraryWith('Replacement.epub', second);
      final clock = Stopwatch()..start();
      await _openReader(tester, b);
      await _waitFor(tester, () => _saved(b) != null, 'replacement publication');
      debugPrint('PERF synthetic replacement first locator: ${clock.elapsedMilliseconds} ms');
      final publication = await readium.openPublication(second.path);
      final link = publication.tocFlattened.last;
      expect(await readium.goByLink(link, publication), isTrue);
      await _waitFor(tester, () => (_saved(b)?.href ?? '').contains('c3.xhtml'), 'new publication third resource');
      final destination = await _stableLocator(tester, b);
      await _closeReader(tester);
      await _openReader(tester, b);
      await _waitFor(tester, () => _saved(b)?.href == destination.href, 'resume without clearing cache');
      await _closeReader(tester);
    }
  });

  testWidgets('EPUB: page turns, saved locator and resume after reopen', (tester) async {
    final file = await writeFixture(_root, 'Synthetic Navigation - Quill Tests.epub', syntheticEpub());
    final lib = await _libraryWith('Synthetic Navigation - Quill Tests.epub', file);
    await _openReader(tester, lib);
    await _waitFor(tester, () => _saved(lib) != null, 'the first saved locator');
    expect(lib.books.first.touched, isTrue);
    expect(lib.books.first.opened, greaterThan(0));

    for (var i = 0; i < 4; i++) {
      await readium.goForward();
      await _settle(tester, 700);
    }
    final before = await _stableLocator(tester, lib);
    final progress = lib.books.first.progress;
    expect(before.locations?.progression ?? 0, greaterThan(0));
    expect(progress, greaterThan(0), reason: 'four page turns should move forward: ${jsonEncode(before.toJson())}');

    // The page-cover capture must contain the rendered synthetic text, rather than a black surface.
    final snapshot = File('${_root.path}/page-cover.jpg');
    expect(await readium.snapshotPage(snapshot.path, maxWidth: 600), isTrue);
    final codec = await ui.instantiateImageCodec(await snapshot.readAsBytes());
    final image = (await codec.getNextFrame()).image;
    final pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    var dark = 0;
    var light = 0;
    for (var i = 0; i < pixels.lengthInBytes; i += 4) {
      final luminance = (pixels.getUint8(i) + pixels.getUint8(i + 1) + pixels.getUint8(i + 2)) / 3;
      if (luminance < 90) dark++;
      if (luminance > 150) light++;
    }
    expect(dark, greaterThan(100), reason: 'the page capture includes printed text');
    expect(light, greaterThan(image.width * image.height ~/ 2), reason: 'the capture is paper, not a black surface');
    image.dispose();
    codec.dispose();

    await _closeReader(tester);
    Locator? reopened;
    readium.onTextLocatorChanged.first.then((l) => reopened = l);
    await _openReader(tester, lib);
    await _waitFor(tester, () => reopened != null, 'the locator after reopening');
    // Compare where the reader settles, not intermediate events while it restores.
    final settled = await _stableLocator(tester, lib);
    expect(settled.href, before.href);
    expect(
      (settled.locations?.progression ?? 0) - (before.locations?.progression ?? 0),
      closeTo(0, 0.02),
      reason: 'before ${jsonEncode(before.toJson())} after ${jsonEncode(settled.toJson())}',
    );
    await _closeReader(tester);
  });

  testWidgets('EPUB: book metadata replaces a file-name title on open', (tester) async {
    const name = '_Example.com_quiet_harbour_-_Ann_Writer.epub';
    final file = await writeFixture(
      _root,
      name,
      syntheticEpub(chapters: 2, title: 'Quiet Harbour', author: 'Ann Writer'),
    );
    final lib = await _libraryWith(name, file);
    expect(lib.books.first.title, 'quiet harbour', reason: 'file-name guess before opening');
    await _openReader(tester, lib);
    await _waitFor(tester, () => _saved(lib) != null, 'the first saved locator');
    expect(lib.books.first.title, 'Quiet Harbour');
    expect(lib.books.first.author, 'Ann Writer');
    await _closeReader(tester);
  });

  testWidgets('EPUB: controls overlay the page without resizing it', (tester) async {
    final file = await writeFixture(_root, 'Overlay Check.epub', syntheticEpub(chapters: 2));
    final lib = await _libraryWith('Overlay Check.epub', file);
    await _openReader(tester, lib);
    await _waitFor(tester, () => _saved(lib) != null, 'the first saved locator');
    final reader = find.byKey(const Key('reader'));
    final pageBefore = tester.getRect(reader);
    final locatorBefore = lib.books.first.locator;

    await tester.tapAt(pageBefore.center);
    await _waitFor(
      tester,
      () => find.byKey(const Key('progress')).evaluate().isNotEmpty,
      'controls after a centre tap',
    );
    expect(tester.getRect(reader), pageBefore, reason: 'showing controls must not resize the page');
    expect(find.byTooltip('Contents'), findsOneWidget);
    expect(find.byKey(const Key('readerMenu')), findsOneWidget);
    expect(find.byTooltip('Previous chapter'), findsOneWidget);
    // A person does not tap twice within the double-tap window.
    await _settle(tester, 900);

    await tester.tapAt(pageBefore.center);
    await _waitFor(tester, () => find.byKey(const Key('progress')).evaluate().isEmpty, 'controls to hide');
    await _settle(tester, 800);
    expect(tester.getRect(reader), pageBefore);
    expect(
      Locator.fromJsonString(lib.books.first.locator)?.href,
      Locator.fromJsonString(locatorBefore)?.href,
      reason: 'toggling controls must not move the reading position',
    );
    await _closeReader(tester);
  });

  testWidgets('EPUB: swipes, rapid seeks and typed pages stay at their destination', (tester) async {
    final file = await writeFixture(
      _root,
      'Seek Stability.epub',
      syntheticEpub(chapters: 3, paragraphCounts: [60, 60, 60]),
    );
    final lib = await _libraryWith('Seek Stability.epub', file);
    await _openReader(tester, lib);
    await _waitFor(tester, () => _saved(lib) != null, 'initial position');
    final before = await _stableLocator(tester, lib);
    final rect = tester.getRect(find.byKey(const Key('reader')));
    await tester.timedDragFrom(
      rect.center + Offset(rect.width * .25, 0),
      Offset(-rect.width * .55, 0),
      const Duration(milliseconds: 250),
    );
    await _waitFor(
      tester,
      () => (_saved(lib)?.locations?.progression ?? 0) > (before.locations?.progression ?? 0),
      'a swipe turn',
    );
    final turned = await _stableLocator(tester, lib);
    await _settle(tester, 2000);
    expect(
      _saved(lib)?.locations?.progression,
      turned.locations?.progression,
      reason: 'the swipe must not spring back',
    );
    await tester.tapAt(rect.center);
    await _waitFor(tester, () => find.byKey(const Key('progress')).evaluate().isNotEmpty, 'slider controls');
    final slider = tester.widget<Slider>(find.byKey(const Key('progress')));
    slider.onChangeEnd!(.2);
    slider.onChangeEnd!(.65);
    slider.onChangeEnd!(.8);
    await _waitFor(tester, () => (lib.books.first.progress - .8).abs() < .03, 'the latest rapid seek');
    await _stableLocator(tester, lib);
    await _settle(tester, 2000);
    expect(lib.books.first.progress, closeTo(.8, .03));
    final page = find.byKey(const Key('pageNumber'));
    await _waitFor(tester, () => tester.widget<TextButton>(page).onPressed != null, 'page count');
    final pageRect = tester.getRect(find.byKey(const Key('reader')));
    await tester.tap(page);
    await _waitFor(tester, () => find.byKey(const Key('pageNumberInput')).evaluate().isNotEmpty, 'page input');
    await tester.enterText(find.byKey(const Key('pageNumberInput')), '0');
    await tester.tap(find.byKey(const Key('goToPage')));
    await tester.pump();
    expect(find.textContaining('Enter a number from 1 to'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('reader'))),
      pageRect,
      reason: 'the page-entry keyboard must not reflow the book',
    );
    await tester.enterText(find.byKey(const Key('pageNumberInput')), '10');
    await tester.tap(find.byKey(const Key('goToPage')));
    await _waitFor(
      tester,
      () => (_saved(lib)?.locations?.position ?? 999) <= 12 && (_saved(lib)?.locations?.position ?? 0) >= 8,
      'typed page 10',
    );
    await _stableLocator(tester, lib);
    await _settle(tester, 2000);
    expect(_saved(lib)?.locations?.position, inInclusiveRange(8, 12));
    await _closeReader(tester);
  });

  testWidgets('EPUB: visual options and themes apply without losing the place', (tester) async {
    final file = await writeFixture(
      _root,
      'Options Check.epub',
      syntheticEpub(chapters: 3, paragraphCounts: [2, 30, 2]),
    );
    final lib = await _libraryWith('Options Check.epub', file);
    // The profile is saved on the device; start and end on the defaults so other tests are unaffected.
    await const ReadingProfile().save();
    addTearDown(() => const ReadingProfile().save());
    await _openReader(tester, lib);
    await _waitFor(tester, () => _saved(lib) != null, 'the first saved locator');
    final reader = find.byKey(const Key('reader'));
    await tester.tapAt(tester.getRect(reader).center);
    await _waitFor(tester, () => find.byKey(const Key('progress')).evaluate().isNotEmpty, 'the controls');
    // Go into the long chapter so a reflow has something to keep.
    await tester.tap(find.byTooltip('Next chapter'));
    await _waitFor(tester, () => _saved(lib)?.href.endsWith('c2.xhtml') == true, 'the next chapter');
    await _settle(tester);
    final before = await _stableLocator(tester, lib);

    await tester.tap(find.byKey(const Key('readerMenu')));
    await _settle(tester, 600);
    await tester.tap(find.text('Visual options'));
    await _settle(tester, 800);
    final fontRow = find.byKey(const Key('option-Font size'));
    expect(
      find.descendant(of: fontRow, matching: find.text('12.5')),
      findsOneWidget,
      reason: 'Moon Reader default',
    );
    await tester.tap(find.descendant(of: fontRow, matching: find.byTooltip('More')));
    await _settle(tester, 1500);
    expect(find.descendant(of: fontRow, matching: find.text('13')), findsOneWidget);
    expect((await _stableLocator(tester, lib)).href, before.href, reason: 'a reflow keeps the chapter');
    Navigator.of(tester.element(fontRow)).pop();
    await _settle(tester, 800);

    await tester.tap(find.byKey(const Key('readerMenu')));
    await _settle(tester, 600);
    await tester.tap(find.text('Themes'));
    await _settle(tester, 800);
    await tester.tap(find.byKey(const Key('theme-sepia')));
    await _settle(tester, 1000);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, readerTheme('sepia').background);
    expect((await _stableLocator(tester, lib)).href, before.href, reason: 'a theme change keeps the chapter');
    Navigator.of(tester.element(find.byKey(const Key('theme-sepia')))).pop();
    await _settle(tester, 800);
    await _closeReader(tester);
  });

  // Regression: on the phone a saved mid-chapter position once fell back to the chapter start
  // the first time a book opened after the page frame changed its pagination.
  testWidgets('EPUB: reopening after a re-pagination never saves the chapter start', (tester) async {
    final file = await writeFixture(
      _root,
      'Repaginate Check.epub',
      syntheticEpub(chapters: 2, paragraphCounts: [40, 2]),
    );
    final lib = await _libraryWith('Repaginate Check.epub', file);
    await const ReadingProfile().save();
    addTearDown(() => const ReadingProfile().save());
    await _openReader(tester, lib);
    await _waitFor(tester, () => _saved(lib) != null, 'the first saved locator');
    final right = tester.getRect(find.byKey(const Key('reader'))).centerRight - const Offset(20, 0);
    for (var i = 0; i < 4; i++) {
      await tester.tapAt(right);
      await _settle(tester, 1200);
    }
    final before = await _stableLocator(tester, lib);
    final beforeProgression = before.locations?.progression ?? 0;
    expect(beforeProgression, greaterThan(0.05), reason: 'the test needs a mid-chapter position');
    await _closeReader(tester);

    // Re-paginate between sessions, as the page-frame change did.
    await const ReadingProfile(topMargin: 90, bottomMargin: 70).save();
    final saved = <String>[];
    void record() {
      final l = lib.books.first.locator;
      if (saved.isEmpty || saved.last != l) saved.add(l);
    }

    lib.addListener(record);
    await _openReader(tester, lib);
    await _settle(tester, 4000);
    final after = await _stableLocator(tester, lib);
    lib.removeListener(record);
    for (final l in saved) {
      final loc = Locator.fromJsonString(l)?.toJson()['locations'] as Map?;
      debugPrint(
        'REPAGINATE saved: page ${loc?['currentPage']}/${loc?['totalPages']} progression ${loc?['progression']}',
      );
    }
    for (final l in saved) {
      final loc = Locator.fromJsonString(l)!;
      expect(loc.href, before.href);
      expect(loc.locations?.progression ?? 0, greaterThan(beforeProgression - 0.15), reason: 'saved a fall-back: $l');
    }
    expect(after.locations?.progression ?? 0, closeTo(beforeProgression, 0.15));
    await _closeReader(tester);
  });

  testWidgets('EPUB: an approximate imported position opens there and becomes exact', (tester) async {
    final file = await writeFixture(_root, 'Imported Check.epub', syntheticEpub(chapters: 5));
    final lib = await _libraryWith('Imported Check.epub', file);
    lib.books = [lib.books.first.copyWith(progress: 0.6, approximate: true)];
    await _openReader(tester, lib);
    await _waitFor(tester, () => _saved(lib) != null, 'a saved locator');
    await _stableLocator(tester, lib);
    expect(lib.books.first.progress, closeTo(0.6, 0.15), reason: 'opened near the imported 60 %');
    expect(lib.books.first.approximate, isFalse);
    await _closeReader(tester);
  });

  testWidgets('EPUB: whole-book slider crosses resources, reaches the end and returns', (tester) async {
    final file = await writeFixture(
      _root,
      'Slider Check.epub',
      syntheticEpub(chapters: 3, paragraphCounts: [2, 50, 2]),
    );
    final lib = await _libraryWith('Slider Check.epub', file);
    await _openReader(tester, lib);
    await _waitFor(tester, () => _saved(lib) != null, 'initial slider position');
    final before = await _stableLocator(tester, lib);
    await tester.tapAt(tester.getRect(find.byKey(const Key('reader'))).center);
    await _waitFor(tester, () => find.byKey(const Key('progress')).evaluate().isNotEmpty, 'the slider');
    final slider = find.byKey(const Key('progress'));
    final sliderWidth = tester.getSize(slider).width;
    (tester.widget(slider) as Slider).onChangeEnd!(0.5);
    await _waitFor(tester, () => _saved(lib)?.href.endsWith('c2.xhtml') == true, 'middle resource');
    await _settle(tester);
    // The long middle resource still contains 80% of this book. Equal resource
    // weighting would incorrectly jump to c3 and disagree with displayed progress.
    (tester.widget(slider) as Slider).onChangeEnd!(0.8);
    await _waitFor(tester, () => lib.books.first.progress > 0.75, 'weighted book progression');
    expect((await _stableLocator(tester, lib)).href, endsWith('c2.xhtml'));
    expect(lib.books.first.progress, closeTo(0.8, 0.04));
    (tester.widget(slider) as Slider).onChangeEnd!(1.0);
    await _waitFor(tester, () => find.byKey(const Key('markFinished')).evaluate().isNotEmpty, 'finish prompt');
    expect(_saved(lib)?.href, endsWith('c3.xhtml'));
    // Let the prompt finish sliding in, and then out, so each tap lands on its button.
    await _settle(tester, 500);
    await tester.tap(find.text('Not yet'));
    await _waitFor(tester, () => find.byKey(const Key('markFinished')).evaluate().isEmpty, 'finish prompt closed');
    await _settle(tester, 500);
    expect(lib.books.first.finished, isFalse);
    expect(find.text('Back to reading position'), findsOneWidget);
    expect(tester.getSize(slider).width, sliderWidth, reason: 'jump undo must not squeeze the slider');
    await tester.tap(find.byKey(const Key('returnToReadingPosition')));
    await _waitFor(tester, () => _saved(lib)?.href == before.href, 'return to original resource');
    final returned = await _stableLocator(tester, lib);
    expect(returned.locations?.progression ?? 0, closeTo(before.locations?.progression ?? 0, 0.02));
    (tester.widget(slider) as Slider).onChangeEnd!(0.5);
    await _waitFor(tester, () => find.byKey(const Key('returnToReadingPosition')).evaluate().isNotEmpty, 'jump undo');
    expect(tester.getSize(slider).width, sliderWidth);
    await _waitFor(
      tester,
      () => find.byKey(const Key('returnToReadingPosition')).evaluate().isEmpty,
      'jump undo to expire',
      seconds: 8,
    );
    expect(tester.getSize(slider).width, sliderWidth, reason: 'expiry does not resize the slider');
    await _closeReader(tester);
  });

  testWidgets('PDF: middle page persists after reopen', (tester) async {
    final file = await writeFixture(_root, 'Synthetic Pages.pdf', syntheticPdf());
    final lib = await _libraryWith('Synthetic Pages.pdf', file);
    await _openReader(tester, lib);
    await _waitFor(tester, () => _saved(lib) != null, 'the first saved PDF locator');

    // Edge taps on PDFs are checked by hand with `adb shell input tap`: the PDF view does not
    // receive taps synthesised by the test framework.
    // The PDF view can refuse a jump until its first layout settles; retry like a user would.
    await _settle(tester, 1000);
    for (var i = 0; i < 3 && (_saved(lib)?.locations?.position ?? 1) <= 1; i++) {
      await readium.goToProgression(0.5);
      await _settle(tester, 1500);
    }
    await _waitFor(tester, () => (_saved(lib)?.locations?.position ?? 1) > 1, 'a page past the first', seconds: 10);
    await _settle(tester);
    final middle = _saved(lib)!;
    final middlePage = middle.locations?.position;
    expect(middlePage, inInclusiveRange(2, 4), reason: 'halfway through five pages: ${jsonEncode(middle.toJson())}');

    await _closeReader(tester);
    Locator? reopened;
    readium.onTextLocatorChanged.first.then((l) => reopened = l);
    await _openReader(tester, lib);
    await _waitFor(tester, () => reopened != null, 'the PDF locator after reopening');
    expect(reopened!.locations?.position, middlePage);
    await _closeReader(tester);
  });

  testWidgets('CBZ: page turn persists after reopen', (tester) async {
    final file = await writeFixture(_root, 'Synthetic Comic v01.cbz', syntheticCbz());
    final lib = await _libraryWith('Synthetic Comic v01.cbz', file);
    await _openReader(tester, lib);
    await _waitFor(tester, () => _saved(lib) != null, 'the first saved comic locator');

    await readium.goForward();
    await _waitFor(tester, () => _saved(lib)?.href != null && _saved(lib)!.href.contains('page02'), 'page 2');
    await _settle(tester);
    final saved = _saved(lib)!;

    await _closeReader(tester);
    Locator? reopened;
    readium.onTextLocatorChanged.first.then((l) => reopened = l);
    await _openReader(tester, lib);
    await _waitFor(tester, () => reopened != null, 'the comic locator after reopening');
    expect(reopened!.href, saved.href);
    await _closeReader(tester);
  });

  testWidgets('CBR: a RAR comic is rewritten as a cached CBZ, opens in page order and keeps its place', (tester) async {
    final file = await writeFixture(_root, 'Synthetic Comic v02.cbr', syntheticCbr());
    final lib = await _libraryWith('Synthetic Comic v02.cbr', file);
    final before = await file.readAsBytes();
    await _openReader(tester, lib);
    await _waitFor(tester, () => _saved(lib) != null, 'the first saved comic locator');
    expect(_saved(lib)!.href, contains('page01'), reason: 'pages are sorted by name, not archive order');

    await readium.goForward();
    await _waitFor(tester, () => _saved(lib)?.href != null && _saved(lib)!.href.contains('page02'), 'page 2');
    await _settle(tester);
    final saved = _saved(lib)!;

    await _closeReader(tester);
    Locator? reopened;
    readium.onTextLocatorChanged.first.then((l) => reopened = l);
    await _openReader(tester, lib);
    await _waitFor(tester, () => reopened != null, 'the comic locator after reopening');
    expect(reopened!.href, saved.href);
    await _closeReader(tester);
    expect(await file.readAsBytes(), before, reason: 'the original is only read');

    final cover = File('${_root.path}/cbr-cover.jpg');
    expect(await AndroidCoverSource().cbrImage(file.path, cover), isTrue);
    expect(await cover.length(), greaterThan(100));
  });

  testWidgets('CBR: a ZIP named .cbr opens; other files are refused with a reason', (tester) async {
    final file = await writeFixture(_root, 'Zip In Disguise.cbr', syntheticCbz());
    final lib = await _libraryWith('Zip In Disguise.cbr', file);
    await _openReader(tester, lib);
    await _waitFor(tester, () => _saved(lib) != null, 'the first saved comic locator');
    await _closeReader(tester);

    final bad = await writeFixture(_root, 'Not A Comic.cbr', Uint8List.fromList(List.filled(64, 7)));
    final badLib = await _libraryWith('Not A Comic.cbr', bad);
    await tester.pumpWidget(MaterialApp(home: ReaderPage(library: badLib, book: badLib.books.first)));
    await _waitFor(tester, () => find.textContaining('not a comic archive').evaluate().isNotEmpty, 'the refusal');
    await _closeReader(tester);
  });

  testWidgets('Backup: a backup made on the device restores the place after a reset', (tester) async {
    final file = await writeFixture(_root, 'Backup Book.epub', syntheticEpub(chapters: 2));
    final lib = await _libraryWith('Backup Book.epub', file);
    await lib.update(lib.books.first.id, (b) => b.copyWith(progress: 0.5, rating: 4, opened: 9));
    final bytes = await lib.backupBytes();
    await lib.resetAllProgress();
    expect(lib.books.first.progress, 0);
    final (result, summary) = await lib.previewRestore(parseBackup(bytes), merge: true);
    expect([summary.books, summary.exact, summary.positions], [1, 1, 1]);
    await lib.applyRestore(result);
    expect([lib.books.first.progress, lib.books.first.rating], [0.5, 4]);
    expect(await lib.backups(), hasLength(2), reason: 'one before the reset, one before the restore');
  });

  testWidgets('EPUB: a bookmark in the standard reader is listed and returns to its page', (tester) async {
    final file = await writeFixture(_root, 'Bookmark Check.epub', syntheticEpub(chapters: 3));
    final lib = await _libraryWith('Bookmark Check.epub', file);
    await _openReader(tester, lib);
    await _waitFor(tester, () => _saved(lib) != null, 'the first saved locator');
    await readium.goToBookProgression(0.5);
    await _settle(tester, 2000);
    final marked = (await _stableLocator(tester, lib)).href;

    Future<void> menu(String key) async {
      if (find.byKey(const Key('readerMenu')).evaluate().isEmpty) {
        await tester.tapAt(tester.getRect(find.byKey(const Key('reader'))).center);
        await _waitFor(tester, () => find.byKey(const Key('readerMenu')).evaluate().isNotEmpty, 'the controls');
      }
      await tester.tap(find.byKey(const Key('readerMenu')));
      await _waitFor(tester, () => find.byKey(Key(key)).evaluate().isNotEmpty, 'the menu');
      await tester.tap(find.byKey(Key(key)));
      await _settle(tester, 800);
    }

    await menu('bookmarkItem');
    final notes = (await lib.annotations()).forBook(lib.books.first.id);
    expect(notes.single.spine, -1);
    expect(Locator.fromJsonString(notes.single.locator)!.href, marked);

    await readium.goToBookProgression(0);
    await _settle(tester, 2000);
    expect((await _stableLocator(tester, lib)).href, isNot(marked));

    await menu('bookmarksItem');
    await _waitFor(tester, () => find.byKey(const Key('bookmarksList')).evaluate().isNotEmpty, 'the bookmark list');
    await tester.tap(find.descendant(of: find.byKey(const Key('bookmarksList')), matching: find.byType(ListTile)).first);
    await _settle(tester, 2000);
    expect((await _stableLocator(tester, lib)).href, marked);
    await _closeReader(tester);
  });
}
