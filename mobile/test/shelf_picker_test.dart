import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill/library/book.dart';
import 'package:quill/library/shelf.dart';
import 'package:quill/shelf/shelf_picker.dart';

final books = [
  for (var i = 0; i < 3; i++)
    Book(
      id: '$i',
      uri: 'fixture:$i',
      name: 'Book $i.epub',
      folder: 'Stories',
      size: 1,
      modified: 1,
      series: i < 2 ? 'Harbour Stories' : 'Mountain Tales',
      author: 'Ann Writer',
    ),
];

Future<void> showPicker(
  WidgetTester tester,
  ValueChanged<ShelfView> onSelected, {
  ShelfView view = const ShelfView(),
}) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: ShelfPicker(books: books, view: view, onSelected: onSelected),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('shelfPicker')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shelf title opens a compact menu; selecting All Books returns to the full library', (tester) async {
    ShelfView? picked;
    await showPicker(tester, (view) => picked = view, view: const ShelfView(ShelfKind.series, 'Harbour Stories'));
    expect(find.byType(TabBar), findsNothing);
    for (final label in ['All Books', 'Series', 'Authors', 'Tags', 'Folders']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('All Books'));
    await tester.pumpAndSettle();
    expect(picked?.kind, ShelfKind.all);
    expect(picked?.value, '');
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('series search narrows groups and selecting one applies that shelf', (tester) async {
    ShelfView? picked;
    await showPicker(tester, (view) => picked = view);
    await tester.tap(find.text('Series'));
    await tester.pumpAndSettle();
    expect(find.text('Harbour Stories'), findsOneWidget);
    expect(find.text('Mountain Tales'), findsOneWidget);
    expect(find.text('2'), findsOneWidget, reason: 'two books in Harbour Stories');
    await tester.enterText(find.byKey(const Key('shelfGroupSearch')), 'MOUNTAIN');
    await tester.pumpAndSettle();
    expect(find.text('Harbour Stories'), findsNothing);
    await tester.tap(find.text('Mountain Tales'));
    await tester.pumpAndSettle();
    expect(picked?.kind, ShelfKind.series);
    expect(picked?.value, 'Mountain Tales');
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('empty groups explain the next step and current group is marked', (tester) async {
    await showPicker(tester, (_) {}, view: const ShelfView(ShelfKind.series, 'Harbour Stories'));
    await tester.tap(find.text('Series'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.enterText(find.byKey(const Key('shelfGroupSearch')), 'Not a series');
    await tester.pumpAndSettle();
    expect(find.text('No series match your search.'), findsOneWidget);
    await tester.tap(find.byTooltip('Close bookshelf picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelfPicker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tags'));
    await tester.pumpAndSettle();
    expect(find.text('No tags yet. Add details in Book information.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
