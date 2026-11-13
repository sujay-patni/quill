import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quill/library/book.dart';
import 'package:quill/library/library.dart';
import 'package:quill/library/shelf.dart';

Book book(String id, {String series = '', double? index, String universe = '', bool finished = false, double progress = 0}) => Book(
  id: id, uri: '/b/$id.epub', name: '$id.epub', folder: '', size: 1, modified: 1,
  title: id, series: series, seriesIndex: index, universe: universe, finished: finished, progress: progress);

void main() {
  final books = [
    book('Warbreaker', universe: 'Cosmere'),
    book('Well of Ascension', series: 'Mistborn', index: 2, universe: 'Cosmere'),
    book('Final Empire', series: 'Mistborn', index: 1, universe: 'Cosmere', finished: true),
    book('Elantris', series: 'Elantris', index: 1, universe: 'Cosmere', finished: true),
    book('Dune'),
  ];
  const orders = {'Cosmere publication': ['Elantris', 'Final Empire', 'Well of Ascension', 'Warbreaker', 'gone']};

  test('universe shelf groups series in their order, standalones last', () {
    final shown = shelfBooks(books, const ShelfView(ShelfKind.universes, 'Cosmere'), const ShelfFilters(), '');
    expect(shown.map((b) => b.id).toList(), ['Elantris', 'Final Empire', 'Well of Ascension', 'Warbreaker']);
    expect(shelfGroups(books, ShelfKind.universes).single.value, 4);
    expect(nextToRead(shown)!.id, 'Well of Ascension');
  });

  test('a reading order keeps the user\'s own sequence and offers the next unread book', () {
    const view = ShelfView(ShelfKind.orders, 'Cosmere publication');
    final shown = shelfBooks(books, view, const ShelfFilters(), '', orders: orders);
    expect(shown.map((b) => b.id).toList(), ['Elantris', 'Final Empire', 'Well of Ascension', 'Warbreaker']);
    expect(shelfGroups(books, ShelfKind.orders, orders: orders).single.value, 4, reason: 'books no longer in the library are not counted');
    expect(nextToRead(shown)!.id, 'Well of Ascension');
    expect(nextToRead([book('x', finished: true)]), isNull);
    final unread = shelfBooks(books, view, const ShelfFilters(status: ReadStatus.unread), '', orders: orders);
    expect(unread.map((b) => b.id).toList(), ['Well of Ascension', 'Warbreaker']);
  });

  test('orders, saved shelves and universes persist with the library', () async {
    final dir = await Directory.systemTemp.createTemp('quill-orders');
    final lib = Library(directory: () async => dir)..books = books;
    await lib.setOrder('Mine', ['Dune', 'Elantris']);
    await lib.setShelf(view: const ShelfView(ShelfKind.universes, 'Cosmere'), filters: const ShelfFilters(status: ReadStatus.unread));
    await lib.saveShelf('Unread Cosmere');
    await lib.edit('Dune', {'universe'}, (b) => b.copyWith(universe: 'Dune'));

    final again = Library(directory: () async => dir);
    await again.load();
    expect(again.orders, {'Mine': ['Dune', 'Elantris']});
    final s = again.saved.single;
    expect([s.name, s.view.kind, s.view.value, s.filters.status], ['Unread Cosmere', ShelfKind.universes, 'Cosmere', ReadStatus.unread]);
    expect(again.books.firstWhere((b) => b.id == 'Dune').universe, 'Dune');
    await again.setOrder('Mine', const []);
    expect(again.orders, isEmpty);
    await again.removeSaved('Unread Cosmere');
    expect(again.saved, isEmpty);
    await dir.delete(recursive: true);
  });
}
