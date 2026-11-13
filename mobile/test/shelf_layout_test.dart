import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill/library/book.dart';
import 'package:quill/library/library.dart';
import 'package:quill/library/shelf.dart';
import 'package:quill/main.dart';

void main() {
  testWidgets('landscape filters remain reachable above navigation insets with large text', (tester) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final library = _FilterLibrary();
    await tester.pumpWidget(QuillApp(library: library));
    await tester.tap(find.byTooltip('Filter and sort'));
    await tester.pumpAndSettle();
    final finished = find.widgetWithText(ChoiceChip, 'Finished');
    await tester.ensureVisible(finished);
    await tester.tap(finished);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Clear filters')).bottom, lessThanOrEqualTo(320 - 48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('filters scroll without overflow after applying one on a small enlarged-text phone', (tester) async {
    tester.view.physicalSize = const Size(354, 480);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final library = _FilterLibrary()
      ..books = [Book(id: 'synthetic', uri: 'fixture:book', name: 'Book.epub', folder: '', size: 1, modified: 1)];
    await tester.pumpWidget(QuillApp(library: library));
    await tester.tap(find.byTooltip('Filter and sort'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Finished'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Finished'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Clear filters'));
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('parchment bookcase stays light with long metadata and enlarged phone text', (tester) async {
    tester.view.physicalSize = const Size(354, 792);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final library = Library()
      ..books = [
        for (var i = 0; i < 6; i++)
          Book(
            id: '$i',
            uri: 'fixture:$i',
            name: 'Fixture $i.epub',
            folder: '',
            size: 1,
            modified: 1,
            title: i.isEven ? 'A Long Synthetic Title with an Even Longer Publisher Subtitle' : 'Short Title',
            author: 'Ann Writer and Several Other Synthetic Authors',
            series: 'A Very Long Series Name',
            seriesIndex: 2.5,
          ),
      ];
    await tester.pumpWidget(QuillApp(library: library));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold).first);
    final theme = Theme.of(context);
    expect(
      theme.brightness,
      Brightness.light,
      reason: 'the requested parchment library is independent of OS dark mode',
    );
    expect(
      theme.appBarTheme.backgroundColor,
      isNot(theme.scaffoldBackgroundColor),
      reason: 'header is a distinct vellum band',
    );
    // Bookcase (Moon Reader style): covers stand on shelves; titles are in each book's label.
    expect(find.bySemanticsLabel(RegExp('^A Long Synthetic Title')), findsWidgets);
    expect(find.text('A Very Long Series Name'), findsNothing);
    expect(tester.takeException(), isNull, reason: 'long metadata and enlarged text must not overflow the bookcase');
  });
}

// Filter-sheet layout is independent of filesystem persistence, which is covered separately.
class _FilterLibrary extends Library {
  @override
  Future<void> setShelf({ShelfView? view, ShelfFilters? filters, bool? compact}) async {
    if (view != null) this.view = view;
    if (filters != null) this.filters = filters;
    if (compact != null) this.compact = compact;
    notifyListeners();
  }
}
