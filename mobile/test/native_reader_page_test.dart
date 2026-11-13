import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill/library/annotations.dart';
import 'package:quill/library/book.dart';
import 'package:quill/library/library.dart';
import 'package:quill/native/native_reader_page.dart';
import 'package:quill/native/page_view.dart';
import 'package:quill/reader/reading_profile.dart';

import '../integration_test/fixtures.dart';

void main() {
  late Directory dir;
  late Library lib;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('quill-native');
    final file = File('${dir.path}/Native.epub')
      ..writeAsBytesSync(syntheticEpub(chapters: 3, paragraphCounts: [3, 40, 3]));
    lib = Library(directory: () async => dir);
    lib.books = [Book(id: 'n', uri: file.path, name: 'Native.epub', folder: '', size: file.lengthSync(), modified: 1)];
  });
  tearDown(() => dir.delete(recursive: true));

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: NativeReaderPage(library: lib, book: lib.books.first)));
    for (var i = 0; i < 100 && find.byKey(const Key('nativePage')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.byKey(const Key('nativePage')), findsOneWidget);
  }

  int startOfShownPage(WidgetTester tester) => tester.widget<NativePage>(find.byKey(const Key('nativePage'))).page.start;

  Future<void> turn(WidgetTester tester, {required bool forward}) async {
    final rect = tester.getRect(find.byKey(const Key('nativePage')));
    await tester.tapAt(Offset(forward ? rect.right - 5 : rect.left + 5, rect.center.dy));
    // Let the 300 ms turn animation play out, and saves land.
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.byKey(const Key('pageTurn')), findsNothing, reason: 'the turn has settled');
  }

  testWidgets('opens, turns across a chapter boundary, saves only on turns and resumes exactly', (tester) async {
    await open(tester);
    expect(lib.books.first.locator, isEmpty, reason: 'opening must not save a place');
    // Turn until chapter 2, then one more page into it.
    var turns = 0;
    while (lib.books.first.locator.isEmpty || jsonDecode(lib.books.first.locator)['href'] != 'OEBPS/c2.xhtml') {
      await turn(tester, forward: true);
      expect(++turns, lessThan(30));
    }
    await turn(tester, forward: true);
    final shown = startOfShownPage(tester);
    final saved = jsonDecode(lib.books.first.locator) as Map<String, dynamic>;
    expect(saved['href'], 'OEBPS/c2.xhtml');
    expect(saved['quillNative']['offset'], shown);
    expect(lib.books.first.progress, inExclusiveRange(0, 1));

    // Back across the boundary into chapter 1, then forward again to the same page.
    await turn(tester, forward: false);
    await turn(tester, forward: false);
    expect(jsonDecode(lib.books.first.locator)['href'], 'OEBPS/c1.xhtml');
    await turn(tester, forward: true);
    await turn(tester, forward: true);
    expect(startOfShownPage(tester), shown);

    await tester.pumpWidget(const SizedBox());
    await open(tester);
    expect(startOfShownPage(tester), shown, reason: 'reopen lands on the same page');
  });

  Future<void> settle(WidgetTester tester, bool Function() done, String what) async {
    for (var i = 0; i < 400 && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done(), isTrue, reason: what);
  }

  String? footerPage(WidgetTester tester) {
    final m = find.descendant(
      of: find.byKey(const Key('currentStatus')),
      matching: find.byWidgetPredicate((w) => w is Text && RegExp(r'^\d+/\d+$').hasMatch(w.data ?? '')),
    );
    return m.evaluate().isEmpty ? null : tester.widget<Text>(m.first).data;
  }

  testWidgets('book-wide page numbers, slider jump, jump-back and contents', (tester) async {
    await open(tester);
    await settle(tester, () => footerPage(tester) != null, 'the book count finishes');
    final first = footerPage(tester)!;
    final total = int.parse(first.split('/')[1]);
    expect(first, '1/$total');
    expect(total, greaterThan(5));

    // Show the bars and jump to the end with the slider.
    final rect = tester.getRect(find.byKey(const Key('nativePage')));
    await tester.tapAt(rect.center);
    await tester.pump(const Duration(milliseconds: 200));
    (tester.widget(find.byKey(const Key('progress'))) as Slider).onChangeEnd!(1.0);
    await settle(tester, () => footerPage(tester) == '$total/$total', 'slider reaches the last page');
    expect(jsonDecode(lib.books.first.locator)['href'], 'OEBPS/c3.xhtml');
    // Reaching the end offers to mark the book finished; decline.
    await settle(tester, () => find.byKey(const Key('markFinished')).evaluate().isNotEmpty, 'finish prompt');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not yet'));
    await tester.pumpAndSettle();

    // Jump back to where reading was.
    await tester.tap(find.byKey(const Key('returnToReadingPosition')));
    await settle(tester, () => footerPage(tester) == '1/$total', 'jump-back returns to page 1');
    expect(find.byKey(const Key('returnToReadingPosition')), findsNothing);

    // Contents: chapter 2 starts on a later page and its entry becomes current.
    await tester.tap(find.byTooltip('Contents'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byKey(const Key('nativeContents')), matching: find.text('Chapter 2')));
    await settle(tester, () => (jsonDecode(lib.books.first.locator)['href'] ?? '') == 'OEBPS/c2.xhtml', 'contents jump');
    expect(tester.widget<NativePage>(find.byKey(const Key('nativePage'))).page.start, 0);
  });

  testWidgets('a held drag shows the turn, reverses without moving, and commits on release', (tester) async {
    await open(tester);
    final rect = tester.getRect(find.byKey(const Key('nativePage')));
    final start = startOfShownPage(tester);

    Future<TestGesture> drag(double dx) async {
      final g = await tester.startGesture(Offset(rect.right - 30, rect.center.dy));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(Offset(dx / 6, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      return g;
    }

    Future<void> finish() async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    // Hold a forward turn, then drag back and let go: nothing moves, nothing is saved.
    final held = await drag(-rect.width * 0.5);
    expect(find.byKey(const Key('pageTurn')), findsOneWidget, reason: 'the turning sheet is shown while held');
    expect(lib.books.first.locator, isEmpty, reason: 'a held turn saves nothing');
    await held.moveBy(Offset(rect.width * 0.45, 0));
    await tester.pump(const Duration(milliseconds: 600)); // slow, so the release has no fling
    await held.up();
    await finish();
    expect(find.byKey(const Key('pageTurn')), findsNothing);
    expect(startOfShownPage(tester), start);
    expect(lib.books.first.locator, isEmpty);

    // Drag past the middle and let go: the turn commits and saves.
    final committed = await drag(-rect.width * 0.6);
    await tester.pump(const Duration(milliseconds: 600));
    await committed.up();
    await finish();
    expect(startOfShownPage(tester), greaterThan(start));
    expect(lib.books.first.locator, isNotEmpty);
  });

  testWidgets('search jumps to a match; the last page offers to mark the book finished', (tester) async {
    await open(tester);
    await settle(tester, () => footerPage(tester) != null, 'the book count finishes');
    final total = int.parse(footerPage(tester)!.split('/')[1]);
    expect(find.textContaining('left in chapter'), findsWidgets, reason: 'time left is shown');

    final rect = tester.getRect(find.byKey(const Key('nativePage')));
    await tester.tapAt(rect.center);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byTooltip('Search in book'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('nativeSearchField')), 'chapter 3 paragraph 2');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester, () => find.byKey(const Key('nativeSearchResults')).evaluate().isNotEmpty, 'search results');
    await tester.tap(find.descendant(of: find.byKey(const Key('nativeSearchResults')), matching: find.byType(ListTile)).first);
    await settle(tester, () => (jsonDecode(lib.books.first.locator.isEmpty ? '{}' : lib.books.first.locator)['href'] ?? '') == 'OEBPS/c3.xhtml',
        'search result jump');
    final marked = tester.widget<NativePage>(find.byKey(const Key('nativePage')));
    expect(marked.highlight, isNotNull, reason: 'the match is highlighted on the page');
    expect(marked.highlight!.$2 - marked.highlight!.$1, 'chapter 3 paragraph 2'.length);
    expect(marked.highlight!.$1, inInclusiveRange(marked.page.start, marked.page.end - 1), reason: 'the match is on the shown page');

    // Go to the last page: the finish prompt appears once; "Not yet" leaves the book unfinished.
    (tester.widget(find.byKey(const Key('progress'))) as Slider).onChangeEnd!(1.0);
    await settle(tester, () => footerPage(tester) == '$total/$total', 'last page');
    await settle(tester, () => find.byKey(const Key('markFinished')).evaluate().isNotEmpty, 'finish prompt');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not yet'));
    await tester.pumpAndSettle();
    expect(lib.books.first.finished, isFalse);
  });

  testWidgets('status bar taps: right half opens contents; auto page turn turns and a tap stops it', (tester) async {
    await open(tester);
    final status = tester.getRect(find.byKey(const Key('currentStatus')));
    await tester.tapAt(Offset(status.right - 40, status.center.dy));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nativeContents')), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    final start = startOfShownPage(tester);
    final rect = tester.getRect(find.byKey(const Key('nativePage')));
    await tester.tapAt(rect.center);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const Key('autoTurn')));
    await tester.pump(const Duration(seconds: 31)); // default interval is 30 s
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 40));
    }
    final afterAuto = startOfShownPage(tester);
    expect(afterAuto, greaterThan(start), reason: 'auto page turn moved forward');
    await tester.tapAt(rect.center); // any tap stops it (and does not open the bars)
    await tester.pump(const Duration(seconds: 40));
    await tester.pump(const Duration(milliseconds: 500));
    expect(startOfShownPage(tester), afterAuto, reason: 'stopped');
  });

  testWidgets('landscape re-lays the page at the same text', (tester) async {
    await open(tester);
    await turn(tester, forward: true);
    await turn(tester, forward: true);
    final place = startOfShownPage(tester);
    final before = tester.widget<NativePage>(find.byKey(const Key('nativePage'))).page;
    // Rotate the test surface: wider and shorter.
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 40));
    }
    final after = tester.widget<NativePage>(find.byKey(const Key('nativePage'))).page;
    expect(identical(before, after), isFalse, reason: 'laid out again for the new size');
    expect(place, inInclusiveRange(after.start, after.end - 1), reason: 'the same text is still on screen');
  });

  testWidgets('two pages in landscape: both pages show and a turn moves two pages', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: NativeReaderPage(library: lib, book: lib.books.first, profile: const ReadingProfile(dualPage: true)),
    ));
    for (var i = 0; i < 100 && find.byKey(const Key('nativePage')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 40));
    }
    final left = tester.widget<NativePage>(find.byKey(const Key('nativePage'))).page;
    final pages = tester.widgetList<NativePage>(find.byType(NativePage)).map((w) => w.page).toList();
    final right = pages.firstWhere((p) => p.start == left.end, orElse: () => throw StateError('no right-hand page'));
    expect(left.items.first.paragraph!.width, lessThan(400), reason: 'pages are half the screen wide');

    Future<void> tapEdge(bool forward) async {
      await tester.tapAt(Offset(forward ? 780 : 20, 220));
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    await tapEdge(true);
    expect(startOfShownPage(tester), right.end, reason: 'the turn skipped the page that was on the right');
    await tapEdge(false);
    expect(startOfShownPage(tester), left.start);
  });

  testWidgets('long-press selects, highlight saves, tap edits a note, bookmark shows a ribbon; all survive reopen', (tester) async {
    await open(tester);
    final rect = tester.getRect(find.byKey(const Key('nativePage')));
    Future<void> wait() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    // Long-press a word in the body text, then extend the selection to the right.
    final at = Offset(rect.left + 120, rect.top + 150);
    final press = await tester.startGesture(at);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(const Key('selectionBar')), findsOneWidget);
    await press.moveBy(const Offset(160, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await press.up();
    await wait();
    final start = startOfShownPage(tester);
    expect(lib.books.first.locator, isEmpty, reason: 'a long press never turns the page');

    // Dictionary for the selection, then back to the selection bar.
    await tester.tap(find.byKey(const Key('selectionDictionary')));
    for (var i = 0; i < 20 && find.byKey(const Key('dictionarySheet')).evaluate().isEmpty; i++) {
      await wait();
    }
    expect(find.byKey(const Key('dictionarySheet')), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selectionBar')), findsOneWidget, reason: 'the selection is kept after a lookup');

    await tester.tap(find.byKey(const Key('highlightColor2')));
    await wait();
    final store = await tester.runAsync(() => lib.annotations());
    var notes = store!.forBook('n');
    expect(notes.length, 1);
    expect(notes.single.kind, AnnotationKind.highlight);
    expect(notes.single.color, 2);
    expect(notes.single.quote.split(' ').length, greaterThan(1), reason: 'the drag extended the selection');
    expect(find.byKey(const Key('selectionBar')), findsNothing);
    final marks = tester.widget<NativePage>(find.byKey(const Key('nativePage'))).marks;
    expect(marks.single.$1, notes.single.start);

    // Tap the highlight: edit sheet; add a note.
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('noteField')), 'remember this');
    await tester.tap(find.byKey(const Key('saveHighlight')));
    await tester.pumpAndSettle();
    await wait();
    expect(store.forBook('n').single.note, 'remember this');
    expect(startOfShownPage(tester), start, reason: 'tapping a highlight does not turn the page');

    // Bookmark the page from the menu.
    await tester.tapAt(Offset(rect.center.dx, rect.top + 330));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const Key('readerMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bookmarkItem')));
    await tester.pumpAndSettle();
    await wait();
    expect(find.byKey(const Key('bookmarkRibbon')), findsOneWidget);
    expect(store.forBook('n').map((a) => a.kind).toSet(), {AnnotationKind.bookmark, AnnotationKind.highlight});

    // Reopen: the highlight and the ribbon are still there.
    await tester.pumpWidget(const SizedBox());
    await open(tester);
    await wait();
    expect(tester.widget<NativePage>(find.byKey(const Key('nativePage'))).marks.length, 1);
    expect(find.byKey(const Key('bookmarkRibbon')), findsOneWidget);
  });

  testWidgets('selection handles: dragging an end changes the selection without turning the page', (tester) async {
    await open(tester);
    final rect = tester.getRect(find.byKey(const Key('nativePage')));
    Future<void> wait() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    final press = await tester.startGesture(Offset(rect.left + 120, rect.top + 150));
    await tester.pump(const Duration(milliseconds: 700));
    await press.up();
    await wait();
    expect(find.byKey(const Key('selectionStart')), findsOneWidget);
    expect(find.byKey(const Key('selectionEnd')), findsOneWidget);

    // Pull the end handle down a few lines and to the right.
    final end = tester.getCenter(find.byKey(const Key('selectionEnd')));
    final drag = await tester.startGesture(end);
    await drag.moveBy(const Offset(30, 30));
    await drag.moveBy(const Offset(40, 50));
    await tester.pump(const Duration(milliseconds: 50));
    await drag.up();
    await wait();
    expect(lib.books.first.locator, isEmpty, reason: 'dragging a handle never turns the page');
    expect(tester.getCenter(find.byKey(const Key('selectionEnd'))).dy, greaterThan(end.dy + 20), reason: 'the end moved down');

    await tester.tap(find.byKey(const Key('highlightColor2')));
    await wait();
    final saved = (await tester.runAsync(() async => (await lib.annotations()).forBook(lib.books.first.id)))!.single;
    expect(saved.end - saved.start, greaterThan(40), reason: 'several lines are selected, not one word');
    expect(find.byKey(const Key('selectionStart')), findsNothing);
  });
}
