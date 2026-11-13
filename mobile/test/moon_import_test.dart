import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quill/import/moon_import.dart';
import 'package:quill/library/book.dart';
import 'package:quill/library/library.dart';
import 'package:quill/library/stats.dart';

// Synthetic data only: the shapes match a real backup, the contents are invented.
Book _book(String id, String folder, String name, {String? title, String? author}) => Book(
  id: id,
  uri: 'content://x/$id',
  name: name,
  folder: folder,
  size: 1,
  modified: 1,
  title: title,
  author: author,
);

const _root = '/sdcard/Download/Books';

MoonBackup _backup({
  List<MoonBook> books = const [],
  List<MoonStats> stats = const [],
  String positions = '',
  String hash = 'h1',
}) => MoonBackup(hash: hash, books: books, stats: stats, positions: parsePositionsXml(positions));

String _xml(Map<String, String> entries) =>
    "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n<map>\n"
    '${entries.entries.map((e) => '    <string name="${e.key}">${e.value}</string>').join('\n')}\n</map>';

void main() {
  group('parsers', () {
    test('category: series, number and tags', () {
      final c = parseCategory('<The Glass Road>\n#2.0#\n(fantasy)\nFavourites\n');
      expect(c.series, 'The Glass Road');
      expect(c.index, 2.0);
      expect(c.tags, ['fantasy', 'Favourites']);
      expect(parseCategory('<Solo>\n#0.0#\n').index, isNull);
      expect(parseCategory('').series, '');
    });

    test('statistics day lines, including decimal percentages', () {
      final days = parseDays('20598|162953@852 #6.2%\n20599|5903315@24082 #32%\nbad line\n20600|10@1\n');
      expect(days.map((d) => d.day), [20598, 20599, 20600]);
      expect(days.first.ms, 162953);
      expect(days.first.words, 852);
      expect(days.first.percent, 6.2);
      expect(days[1].percent, 32);
      expect(days[2].percent, isNull);
    });

    test('positions: reflowable, paged, unopened and unknown forms', () {
      expect(parsePosition('11@1#605:100%')!.percent, 100);
      expect(parsePosition('11@1#605:100%')!.chapter, 11);
      expect(parsePosition('24:5.5%')!.percent, 5.5);
      expect(parsePosition('0'), isNull);
      expect(parsePosition('1.0#0.38:900.35@false*18'), isNull);
      final map = parsePositionsXml(_xml({'$_root/Series A/One&apos;s Book.epub': '3@0#10:42.5%'}));
      expect(map.keys.single, "/sdcard/download/books/series a/one's book.epub");
      expect(map.values.single.percent, 42.5);
    });
  });

  test('only clean Moon Reader titles and authors are used', () {
    expect(cleanMoonTitle('_Example.com_Some_Title_-_Some_Author'), isNull);
    expect(cleanMoonTitle('some book.epub'), isNull);
    expect(cleanMoonTitle('all lower case'), isNull);
    expect(cleanMoonTitle(' The Real Title '), 'The Real Title');
    expect(cleanMoonAuthor('Brown, Dan'), 'Dan Brown');
    expect(cleanMoonAuthor('rick riordan'), isNull);
    expect(cleanMoonAuthor('Ada Inkwell'), 'Ada Inkwell');
    expect(cleanMoonAuthor(''), isNull);
  });

  group('matching', () {
    final books = [
      _book('a', 'Series A', 'one.epub'),
      _book('b', '', 'loose.pdf'),
      _book('c', 'X', 'same.epub'),
      _book('d', 'Y', 'same.epub', title: 'Twin', author: 'Writer'),
    ];
    final m = BookMatcher(books);

    test('by relative path, case-insensitively', () {
      expect(m.match('$_root/series a/ONE.epub')?.book.id, 'a');
      expect(m.match('$_root/series a/one.epub')?.by, MatchBy.path);
      expect(m.match('$_root/loose.pdf')?.book.id, 'b');
    });

    test('by unique file name when the folder moved', () {
      expect(m.match('/sdcard/Elsewhere/one.epub')?.by, MatchBy.fileName);
    });

    test('a renamed file still matches when only punctuation or case changed', () {
      final renamed = BookMatcher([_book('r', 'Narnia', '_Example.com_The_Silver_Chair_-_C_S_Lewis.epub')]);
      expect(renamed.match('$_root/narnia/_example.com_the_silver_chair_-_cs_lewis.epub')?.book.id, 'r');
      expect(renamed.match('$_root/narnia/the_silver_chair_2.epub'), isNull);
    });

    test('ambiguous names stay unmatched unless title and author decide', () {
      expect(m.match('/sdcard/Elsewhere/same.epub'), isNull);
      expect(m.match('/sdcard/Elsewhere/same.epub', title: 'Twin', author: 'Writer')?.book.id, 'd');
      expect(m.match('$_root/X/same.epub')?.book.id, 'c');
    });
  });

  group('preview', () {
    test('fills Moon Reader metadata but never the user’s own edits', () {
      final books = [
        _book('a', 'S', 'a_file.epub'),
        _book('b', 'S', 'b.epub').copyWith(series: 'Mine', provenance: {'series': 'user'}),
      ];
      final p = previewImport(
        books,
        _backup(
          books: [
            MoonBook(
              path: '$_root/S/a_file.epub',
              title: 'Real Title',
              author: 'Real Author',
              category: '<Saga>\n#3.0#\n(tag)\n',
              description: 'About',
              addedAt: 5,
            ),
            MoonBook(path: '$_root/S/b.epub', category: '<Theirs>\n#1.0#\n'),
          ],
        ),
      );
      final a = p.changes.firstWhere((c) => c.before.id == 'a').after;
      expect(
        [a.title, a.author, a.series, a.seriesIndex, a.tags, a.description, a.addedAt],
        [
          'Real Title',
          'Real Author',
          'Saga',
          3.0,
          ['tag'],
          'About',
          5,
        ],
      );
      expect(a.provenance['series'], moonSource);
      final b = p.changes.firstWhere((c) => c.before.id == 'b').after;
      expect(b.series, 'Mine');
    });

    test('positions only for books not read in Quill; 99 % or more marks finished', () {
      final books = [
        _book('new', '', 'new.epub'),
        _book('read', '', 'read.epub').copyWith(opened: 1, locator: '{"href":"x"}', progress: 0.3),
        _book('done', '', 'done.epub'),
      ];
      final p = previewImport(
        books,
        _backup(
          positions: _xml({
            '$_root/new.epub': '2@0#1:40%',
            '$_root/read.epub': '2@0#1:80%',
            '$_root/done.epub': '9@0#1:100%',
          }),
          stats: [MoonStats(path: '$_root/done.epub', days: parseDays('20000|1000@10 #50%\n20003|2000@20 #100%'))],
        ),
      );
      Book after(String id) => p.changes.firstWhere((c) => c.before.id == id).after;
      expect(after('new').progress, 0.4);
      expect(after('new').approximate, isTrue);
      expect(after('read').progress, 0.3, reason: 'Quill’s own position is newer');
      expect(p.keptQuillPosition, 1);
      expect(after('done').finished, isTrue);
      expect(
        DateTime.fromMillisecondsSinceEpoch(after('done').finishedAt).difference(DateTime(1970)).inDays,
        closeTo(20003, 1),
      );
      expect(after('done').startedAt, lessThan(after('done').finishedAt));
      expect(p.newlyFinished, 1);
      expect(p.statsDays, 2);
      expect(p.statsMs, 3000);
    });

    test('reports unmatched paths and an already-imported backup', () {
      final p = previewImport(
        [_book('a', '', 'a.epub')],
        _backup(
          books: [MoonBook(path: '$_root/gone.epub')],
          hash: 'same',
        ),
        previousHash: 'same',
      );
      expect(p.unmatched, ['$_root/gone.epub']);
      expect(p.alreadyImported, isTrue);
    });
  });

  test('apply: snapshot, books, Moon Reader stats replace only their own rows, idempotent', () async {
    final dir = await Directory.systemTemp.createTemp('quill-moon');
    addTearDown(() => dir.delete(recursive: true));
    final lib = Library(directory: () async => dir);
    lib.books = [_book('a', 'S', 'a.epub')];
    lib.stats.replaceSource('a', 'quill', [const ReadingDay(day: 20010, ms: 500)]);
    final backup = _backup(
      books: [const MoonBook(path: '$_root/S/a.epub', category: '<Saga>\n#1.0#\n')],
      stats: [MoonStats(path: '$_root/S/a.epub', days: parseDays('20000|1000@10 #5%'))],
      hash: 'abc',
    );

    await lib.applyMoonImport(previewImport(lib.books, backup));
    expect(lib.books.single.series, 'Saga');
    expect(lib.stats.daysFor('a').map((d) => '${d.day}:${d.source}'), ['20000:$moonSource', '20010:quill']);
    expect(await lib.moonImportHash(), 'abc');
    expect(Directory('${dir.path}/backups').listSync().single.path, contains('moon-import'));

    // Same backup again: same result, no duplicated days.
    final again = previewImport(lib.books, backup, previousHash: await lib.moonImportHash());
    expect(again.alreadyImported, isTrue);
    await lib.applyMoonImport(again);
    expect(lib.stats.daysFor('a').length, 2);
    final saved = jsonDecode(File('${dir.path}/moon-import.json').readAsStringSync()) as Map;
    expect(saved['hash'], 'abc');
  });
}
