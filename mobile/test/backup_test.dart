// Backup files, matching, merge and replace rules, and the Library round trip.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill/library/annotations.dart';
import 'package:quill/library/backup.dart';
import 'package:quill/library/book.dart';
import 'package:quill/library/library.dart';
import 'package:quill/library/shelf.dart';
import 'package:quill/library/stats.dart';
import 'package:quill/shelf/backup_page.dart';

Book _book(String id, {String? uri, String? name, int size = 100, double progress = 0, String locator = '', int opened = 0}) => Book(
  id: id,
  uri: uri ?? 'fixture:$id',
  name: name ?? '$id.epub',
  folder: '',
  size: size,
  modified: 1,
  progress: progress,
  locator: locator,
  opened: opened,
);

Annotation _note(String id, String book, {int updated = 1, String note = ''}) => Annotation(
  id: id,
  bookId: book,
  kind: AnnotationKind.highlight,
  spine: 0,
  start: 1,
  end: 5,
  quote: 'words',
  note: note,
  created: 1,
  updated: updated,
);

ReadingStats _stats(Map<String, Map<int, int>> ms) => ReadingStats({
  for (final e in ms.entries) e.key: [for (final d in e.value.entries) ReadingDay(day: d.key, ms: d.value)],
});

String _json(BackupContent c) => jsonEncode({
  'books': [for (final b in c.books) b.toJson()],
  'orders': c.orders,
  'saved': [for (final s in c.saved) s.toJson()],
  'stats': c.stats.toJson(),
  'notes': [for (final a in c.annotations) a.toJson()]..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String)),
  'reader': c.reader,
  'bookSettings': c.bookSettings,
  'themes': c.themes,
  'moon': c.moonHighlights,
  'covers': {for (final e in c.covers.entries) e.key: e.value.length},
});

Uint8List _zipOf(Map<String, Object> files) {
  final archive = Archive();
  for (final e in files.entries) {
    final bytes = e.value is String ? utf8.encode(e.value as String) : e.value as List<int>;
    archive.addFile(ArchiveFile.bytes(e.key, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  final full = BackupContent(
    books: [
      _book('a', progress: 0.4, locator: '{"href":"c1"}', opened: 50).copyWith(rating: 4, series: 'Saga', seriesIndex: 2.5, tags: ['x']),
      _book('b'),
    ],
    folder: 'content://books',
    shelf: const {'kind': 'all', 'value': '', 'status': 'all', 'type': 'all', 'sort': 'title', 'compact': true},
    orders: const {'Cosmere': ['b', 'a']},
    saved: const [SavedShelf('Unread epics', ShelfView(ShelfKind.all), ShelfFilters(status: ReadStatus.unread))],
    stats: _stats({'a': {20000: 60000, 20001: 120000}}),
    annotations: [_note('n1', 'a', note: 'mine')],
    reader: const {'fontSize': 14.0},
    bookSettings: const {'a': {'fontSize': 18.0}},
    themes: const {'Night': {'fontSize': 15.0}},
    moonHighlights: const [{'book': 'a', 'text': 'quoted'}],
    moonImport: const {'hash': 'h'},
    covers: {'a': Uint8List.fromList([1, 2, 3])},
  );

  group('backup file', () {
    test('everything survives writing and reading', () async {
      final bytes = await buildBackup(full, now: DateTime(2026, 11, 12, 9));
      final back = parseBackup(bytes);
      expect(_json(back), _json(full));
      expect(back.folder, 'content://books');
      expect(back.shelf['compact'], true);
      expect(back.moonImport, {'hash': 'h'});
      expect(back.covers['a'], [1, 2, 3]);
      expect(back.created, DateTime(2026, 11, 12, 9));
      final manifest = jsonDecode(utf8.decode(ZipDecoder().decodeBytes(bytes).findFile('manifest.json')!.content)) as Map;
      expect([manifest['app'], manifest['format'], manifest['books'], manifest['statsDays'], manifest['annotations'], manifest['covers']],
          ['Quill', 1, 2, 2, 1, 1]);
    });

    test('other files, damaged files and newer backups are refused with a reason', () {
      String message(Uint8List bytes) {
        try {
          parseBackup(bytes);
          return '';
        } on BackupException catch (e) {
          return e.message;
        }
      }

      expect(message(Uint8List.fromList([1, 2, 3])), contains('not a Quill backup'));
      expect(message(_zipOf({'mimetype': 'application/epub+zip'})), contains('not a Quill backup'));
      expect(message(_zipOf({'manifest.json': '{"app":"Quill","format":2}', 'library.json': '{"books":[]}'})), contains('newer Quill'));
      expect(message(_zipOf({'manifest.json': '{"app":"Quill","format":1}'})), contains('no library'));
      expect(message(_zipOf({'manifest.json': '{"app":"Quill","format":1}', 'library.json': '{"books":[{"id":7}]}'})), contains('damaged'));
    });

    test('only known entries are read; cover names cannot point anywhere', () {
      final back = parseBackup(_zipOf({
        'manifest.json': '{"app":"Quill","format":1}',
        'library.json': '{"books":[]}',
        'covers/../../library.jpg': [1],
        'covers/a/b.jpg': [1],
        'covers/ok-1.jpg': [9],
        'elsewhere/x.jpg': [1],
      }));
      expect(back.covers.keys, ['ok-1']);
    });
  });

  group('matching', () {
    test('by id, then place, then name and size, then a unique name', () {
      final here = [
        _book('a'),
        _book('new-b', uri: 'fixture:b'),
        _book('new-c', uri: 'content://other/c', name: 'c.epub', size: 300),
        _book('new-d', uri: 'content://other/d', name: 'd.epub', size: 999),
        _book('dup1', uri: 'content://x/e', name: 'e.epub', size: 5),
        _book('dup2', uri: 'content://y/e', name: 'e.epub', size: 5),
      ];
      final backup = [
        _book('a'),
        _book('b'),
        _book('c', size: 300),
        _book('d', size: 400),
        _book('e', size: 5),
        _book('f'),
      ];
      final m = matchBooks(here, backup);
      expect({for (final e in m.entries) e.key: '${e.value.current.id}:${e.value.kind.name}'}, {
        'a': 'a:exact',
        'b': 'new-b:exact',
        'c': 'new-c:exact',
        'd': 'new-d:approximate',
      }, reason: 'two files with the same name and size are never guessed between');
    });
  });

  group('restore', () {
    final now = BackupContent(
      books: [
        _book('a', progress: 0.9, locator: '{"href":"c9"}', opened: 80).copyWith(tags: ['y']),
        _book('phone-b', uri: 'content://new/b', name: 'b.epub'),
        _book('only-here', progress: 0.2, opened: 5),
      ],
      folder: 'content://new',
      shelf: const {'kind': 'all'},
      orders: const {'Mine': ['a']},
      stats: _stats({'a': {20001: 300000, 20002: 60000}, 'only-here': {20000: 1000}}),
      annotations: [_note('n1', 'a', updated: 5, note: 'newer here'), _note('n2', 'only-here')],
      reader: const {'fontSize': 12.0},
      covers: {'only-here': Uint8List.fromList([7])},
    );

    test('merge keeps both sides, the more recent place, and is idempotent', () {
      final (merged, summary) = restoreBackup(now, full, merge: true);
      final a = merged.books.firstWhere((b) => b.id == 'a');
      expect([a.progress, a.locator, a.rating, a.series, a.seriesIndex, a.tags], [0.9, '{"href":"c9"}', 4, 'Saga', 2.5, ['y', 'x']],
          reason: 'this phone read further more recently; missing details are filled in');
      expect(merged.books.map((b) => b.id), ['a', 'phone-b', 'only-here']);
      expect(merged.orders, {'Cosmere': ['phone-b', 'a'], 'Mine': ['a']});
      expect(merged.stats.daysFor('a').map((d) => '${d.day}:${d.ms}'), ['20000:60000', '20001:300000', '20002:60000'],
          reason: 'per day the longer record, never the sum');
      expect(merged.annotations.firstWhere((n) => n.id == 'n1').note, 'newer here');
      expect(merged.annotations.map((n) => n.id).toSet(), {'n1', 'n2'});
      expect(merged.reader, {'fontSize': 12.0});
      expect(merged.themes.keys, ['Night']);
      expect(merged.covers.keys.toSet(), {'a', 'only-here'});
      expect([summary.books, summary.exact, summary.approximate, summary.notHere, summary.positions], [2, 2, 0, 0, 0]);

      final (again, _) = restoreBackup(merged, full, merge: true);
      expect(_json(again), _json(merged), reason: 'restoring the same backup twice changes nothing');
    });

    test('merge takes the backup place when it is the more recent one', () {
      final older = BackupContent(books: [_book('a', progress: 0.1, locator: '{"href":"c0"}', opened: 10)]);
      final (merged, summary) = restoreBackup(older, full, merge: true);
      expect([merged.books.first.progress, merged.books.first.locator], [0.4, '{"href":"c1"}']);
      expect(summary.positions, 1);
    });

    test('replace puts the backup records on the files that are here', () {
      final (replaced, summary) = restoreBackup(now, full, merge: false);
      final a = replaced.books.firstWhere((b) => b.id == 'a');
      expect([a.progress, a.locator, a.tags], [0.4, '{"href":"c1"}', ['x']]);
      final b = replaced.books.firstWhere((b) => b.id == 'phone-b');
      expect(b.uri, 'content://new/b', reason: 'the file on this phone is kept');
      final only = replaced.books.firstWhere((b) => b.id == 'only-here');
      expect([only.progress, only.opened], [0.0, 0], reason: 'a file the backup does not know starts clean');
      expect(replaced.orders, {'Cosmere': ['phone-b', 'a']});
      expect(replaced.stats.byBook.keys, ['a']);
      expect(replaced.annotations.single.note, 'mine');
      expect(replaced.reader, {'fontSize': 14.0});
      expect(replaced.folder, 'content://new');
      expect(replaced.covers.keys, ['a']);
      expect(summary.positions, 2);
    });

    test('a changed file keeps its record but not its exact place; absent books wait as missing', () {
      final here = BackupContent(books: [_book('x', uri: 'content://new/a', name: 'a.epub', size: 777)]);
      final (result, summary) = restoreBackup(here, full, merge: false);
      final a = result.books.first;
      expect([a.id, a.locator, a.approximate, a.progress, a.rating, a.size], ['x', '', true, 0.4, 4, 777]);
      expect(result.stats.daysFor('x'), hasLength(2), reason: 'records follow the book to its id on this phone');
      expect(result.annotations.single.bookId, 'x');
      expect(result.bookSettings.keys, ['x']);
      expect(result.moonHighlights.single['book'], 'x');
      expect(result.covers.keys, ['x']);
      final waiting = result.books.last;
      expect([waiting.id, waiting.missing], ['b', true]);
      expect([summary.exact, summary.approximate, summary.notHere], [0, 1, 1]);
    });
  });

  test('a scan moves a waiting record to its file by name and size', () {
    final saved = [
      _book('old', uri: 'content://old/a', name: 'a.epub', progress: 0.5, locator: '{"href":"c1"}').copyWith(missing: true, rating: 5),
      _book('changed', uri: 'content://old/z', name: 'z.epub', size: 10, progress: 0.3, locator: '{"href":"c2"}'),
      _book('twin', uri: 'content://old/t', name: 't.epub'),
    ];
    final merged = mergeScan(saved, const [
      FoundFile('content://new/a', 'a.epub', 'Sub', 100, 9),
      FoundFile('content://new/z', 'z.epub', '', 20, 9),
      FoundFile('content://new/1/t', 't.epub', '1', 100, 9),
      FoundFile('content://new/2/t', 't.epub', '2', 100, 9),
    ]);
    final a = merged.firstWhere((b) => b.name == 'a.epub');
    expect([a.id, a.uri, a.folder, a.progress, a.locator, a.rating, a.missing], ['old', 'content://new/a', 'Sub', 0.5, '{"href":"c1"}', 5, false]);
    final z = merged.firstWhere((b) => b.name == 'z.epub');
    expect([z.id, z.uri, z.size, z.progress, z.locator, z.approximate], ['changed', 'content://new/z', 20, 0.3, '', true]);
    expect(merged.where((b) => b.name == 't.epub').map((b) => b.missing).toList(), [false, false, true],
        reason: 'two candidates: the record is not guessed onto either');
    expect(merged, hasLength(5));
  });

  test('the book list as a spreadsheet', () {
    final csv = booksCsv(
      [
        _book('a', progress: 1).copyWith(title: 'Dune, Part "One"', author: 'Frank Herbert', series: 'Dune', seriesIndex: 1, rating: 5, finished: true, tags: ['sf', 'classic']),
        _book('b', progress: 0.25),
      ],
      _stats({'a': {20000: 600000}}),
    );
    final lines = csv.trim().split('\r\n');
    expect(lines.first, startsWith('Title,Author,Series,Number in series,Universe,Status,Progress %,Rating'));
    expect(lines[1], startsWith('"Dune, Part ""One""",Frank Herbert,Dune,1,,finished,100,5,,sf; classic,'));
    expect(lines[1], contains(',10,EPUB,'));
    expect(lines[2], contains(',reading,25,,'));
  });

  group('library', () {
    Future<Library> library() async {
      final dir = await Directory.systemTemp.createTemp('quill-backup');
      final lib = Library(directory: () async => dir);
      await lib.load();
      lib.books = [_book('a', progress: 0.4, locator: '{"href":"c1"}', opened: 50), _book('b')];
      await lib.edit('a', {'rating'}, (b) => b.copyWith(rating: 4));
      await lib.setOrder('Order', ['b', 'a']);
      await lib.recordReading('a', [ReadingSpan(DateTime(2026, 11, 5, 9), DateTime(2026, 11, 5, 9, 30), 12)], progress: 0.4);
      await (await lib.annotations()).put(_note('n1', 'a', note: 'kept'));
      await File('${dir.path}/reader.json').writeAsString('{"fontSize":14.0}');
      await File('${dir.path}/reader-extras.json').writeAsString('{"books":{"a":{"fontSize":18.0}},"themes":{"Night":{"fontSize":15.0}}}');
      final cover = File('${dir.path}/c.jpg')..writeAsBytesSync([1, 2, 3, 4]);
      await lib.covers.setCustom('a', cover);
      return lib;
    }

    test('backup, reset, restore returns the same records', () async {
      final lib = await library();
      final dir = await lib.covers.directory();
      final before = _json(await lib.content());
      final bytes = await lib.backupBytes();

      await lib.resetAllProgress();
      await lib.resetAllStats();
      await (await lib.annotations()).remove('n1');
      await lib.covers.clearCustom('a');
      await File('${dir.path}/reader-extras.json').delete();
      expect(_json(await lib.content()), isNot(before));

      final (result, summary) = await lib.previewRestore(parseBackup(bytes), merge: false);
      expect([summary.books, summary.exact, summary.positions], [2, 2, 1]);
      await lib.applyRestore(result);
      expect(_json(await lib.content()), before);

      // And from disk, as after a restart.
      final fresh = Library(directory: () async => dir);
      await fresh.load();
      expect(_json(await fresh.content()), before);
      expect(fresh.covers.isCustom('a'), isTrue);
      expect((await lib.backups()).map((f) => f.uri.pathSegments.last).where((n) => n.contains('-restore.')), hasLength(1));
    });

    test('a daily backup is written once a day and can be restored', () async {
      final lib = await library();
      await lib.dailyBackup();
      await lib.dailyBackup();
      final daily = (await lib.backups()).where((f) => f.uri.pathSegments.last.startsWith('Quill-auto-')).toList();
      expect(daily, hasLength(1));
      expect(parseBackup(await daily.single.readAsBytes()).books, hasLength(2));
    });
  });

  testWidgets('the backup page offers backup, restore, spreadsheet and resets', (tester) async {
    late Library lib;
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('quill-backup-page');
      lib = Library(directory: () async => dir);
      await lib.load();
    });
    lib.books = [_book('a', progress: 0.4)];
    await tester.pumpWidget(MaterialApp(home: BackupPage(library: lib)));
    for (final key in ['backupNow', 'restoreFile', 'exportCsv']) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
    await tester.scrollUntilVisible(find.byKey(const Key('resetAllStats')), 200);
    await tester.tap(find.byKey(const Key('resetAllProgress')));
    await tester.pumpAndSettle();
    expect(find.text('Reset all reading progress?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(lib.books.single.progress, 0.4);
  });
}
