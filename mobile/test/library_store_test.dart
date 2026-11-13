// Library edits, finishing, reading time and resets, against a temporary directory.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quill/library/book.dart';
import 'package:quill/library/library.dart';
import 'package:quill/library/stats.dart';

Future<Library> _library() async {
  final dir = await Directory.systemTemp.createTemp('quill-lib');
  final lib = Library(directory: () async => dir);
  await lib.load();
  lib.books = [
    Book(id: 'a', uri: 'fixture:a', name: 'A Title - Some Author.epub', folder: '', size: 1, modified: 1),
    Book(id: 'b', uri: 'fixture:b', name: 'B.epub', folder: '', size: 1, modified: 1),
  ];
  return lib;
}

ReadingSpan _span(int minutes) =>
    ReadingSpan(DateTime(2026, 11, 5, 9), DateTime(2026, 11, 5, 9).add(Duration(minutes: minutes)), 4);

void main() {
  test('edits are marked as the user\'s', () async {
    final lib = await _library();
    await lib.edit('a', {'series', 'rating'}, (b) => b.copyWith(series: 'Saga', seriesIndex: 2, rating: 4));
    final a = lib.books.first;
    expect([a.series, a.seriesIndex, a.rating], ['Saga', 2.0, 4]);
    expect(a.editedByUser('series'), isTrue);
    expect(a.editedByUser('title'), isFalse);
  });

  test('reading time is recorded and sets the start date once', () async {
    final lib = await _library();
    await lib.recordReading('a', [_span(15)], progress: 0.3);
    await lib.recordReading('a', [_span(5)]);
    expect(lib.stats.summary().ms, 20 * 60000);
    expect(lib.books.first.startedAt, DateTime(2026, 11, 5, 9).millisecondsSinceEpoch);
  });

  test('finishing sets and clears the finish date', () async {
    final lib = await _library();
    await lib.setFinished('a', true, rating: 5);
    expect(lib.books.first.finished, isTrue);
    expect(lib.books.first.finishedAt, greaterThan(0));
    expect(lib.books.first.rating, 5);
    await lib.setFinished('a', false);
    expect(lib.books.first.finishedAt, 0);
    expect(lib.books.first.rating, 5, reason: 'unfinishing keeps the rating');
  });

  test('resets are scoped and keep a snapshot', () async {
    final lib = await _library();
    await lib.update('a', (b) => b.copyWith(progress: 0.5, locator: '{"href":"x"}', rating: 3, series: 'S'));
    await lib.recordReading('a', [_span(10)]);
    await lib.recordReading('b', [_span(10)]);

    await lib.resetProgress('a');
    final a = lib.books.first;
    expect([a.progress, a.locator, a.rating, a.series], [0.0, '', 3, 'S']);
    expect(lib.stats.daysFor('a'), isNotEmpty, reason: 'progress reset keeps stats');

    await lib.resetBookStats('a');
    expect(lib.stats.daysFor('a'), isEmpty);
    expect(lib.stats.daysFor('b'), isNotEmpty);

    await lib.resetAllStats();
    expect(lib.stats.byBook, isEmpty);

    expect((await lib.backups()).map((f) => f.uri.pathSegments.last.split('-').skip(3).join('-')).toSet(), {
      'reset-progress.quill',
      'reset-stats.quill',
      'reset-all-stats.quill',
    });
  });

  test('only the newest seven backups of a kind are kept', () async {
    final lib = await _library();
    for (var i = 0; i < 9; i++) {
      await lib.autoBackup('test$i');
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final names = (await lib.backups()).map((f) => f.uri.pathSegments.last).toList();
    expect(names, hasLength(7));
    expect(names.any((n) => n.endsWith('-test0.quill') || n.endsWith('-test1.quill')), isFalse);
  });
}
