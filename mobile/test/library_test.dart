// Ported from the Android prototype's LibraryRulesTest and ShelfTest. Synthetic names only.
import 'package:flutter_test/flutter_test.dart';
import 'package:quill/library/book.dart';
import 'package:quill/library/names.dart';
import 'package:quill/library/shelf.dart';

Book book(
  String id, {
  String extension = 'epub',
  String author = '',
  String series = '',
  String folder = '',
  double progress = 0,
  bool finished = false,
  int opened = 0,
  bool missing = false,
}) => Book(
  id: id,
  uri: 'fixture:$id',
  name: '$id.$extension',
  folder: folder,
  size: 1,
  modified: 1,
  title: id,
  author: author,
  series: series,
  progress: progress,
  finished: finished,
  opened: opened,
  missing: missing,
);

void main() {
  test('whole-book slider maps boundaries and middle positions to reading order', () {
    expect(readingOrderPosition(0, 0.5), isNull);
    expect(readingOrderPosition(3, double.nan), isNull);
    expect(readingOrderPosition(3, -1), (index: 0, progression: 0.0));
    expect(readingOrderPosition(3, 0.5), (index: 1, progression: 0.5));
    expect(readingOrderPosition(3, 1), (index: 2, progression: 1.0));
    expect(readingOrderPosition(3, 2), (index: 2, progression: 1.0));
    const order = ['a.xhtml', 'b.xhtml', 'c.xhtml'];
    final target = readingOrderPosition(order.length, 0.75)!;
    expect(bookProgress(order, order[target.index], progression: target.progression), 0.75);
  });
  group('library rules', () {
    test('storage aliases match without losing subdirectories', () {
      expect(
        canonicalPath('/sdcard/Download/Books/Series/Book.epub'),
        canonicalPath('primary:Download/Books/Series/Book.epub'),
      );
      expect(
        canonicalPath('/storage/emulated/0/Download/Books/Series/Book.epub'),
        canonicalPath('/sdcard/Download/Books/Series/Book.epub'),
      );
      expect(canonicalPath('/sdcard/Books/A/Book.epub'), isNot(canonicalPath('/sdcard/Books/B/Book.epub')));
    });

    test('comic pages sort numerically rather than lexically', () {
      final names = ['chapter10/page1.jpg', 'chapter2/page10.jpg', 'chapter2/page2.jpg', 'chapter2/page1.jpg'];
      expect(names..sort(naturalCompare), [
        'chapter2/page1.jpg',
        'chapter2/page2.jpg',
        'chapter2/page10.jpg',
        'chapter10/page1.jpg',
      ]);
    });

    test('book identity is stable and distinct', () {
      expect(stableId('one'), stableId('one'));
      expect(stableId('one'), isNot(stableId('two')));
    });

    test('titles from file names', () {
      expect(displayTitle('Example Title - Some Author.epub'), 'Example Title');
      expect(displayTitle('! - Improvised Tools.pdf'), 'Improvised Tools');
      expect(displayTitle('Series Name - Volume 02.cbr'), 'Series Name - Volume 02');
      expect(displayTitle('_Example.com_Plain.epub'), 'Plain');
      expect(displayAuthor('Example Title - Some Author.epub'), 'Some Author');
    });

    test('author-first and category names', () {
      expect(displayTitle('Writer, Ann - Field Notes.pdf'), 'Field Notes');
      expect(displayAuthor('Writer, Ann - Field Notes.pdf'), 'Ann Writer');
      expect(displayTitle('Writer, Ann - Long Title - The Subtitle (1).pdf'), 'Long Title - The Subtitle');
      expect(displayTitle('hobby - ! - Garden Guide.pdf'), 'Garden Guide');
      expect(displayAuthor('hobby - ! - Garden Guide.pdf'), '');
      expect(displayTitle('hobby - Pen Name - Part One - The Book.pdf'), 'Part One - The Book');
      expect(displayAuthor('hobby - Pen Name - Part One - The Book.pdf'), 'Pen Name');
      expect(displayTitle('hobby - Writer, Ann - Guide (3rd ed).pdf'), 'Guide (3rd ed)');
      expect(displayAuthor('hobby - Writer, Ann - Guide (3rd ed).pdf'), 'Ann Writer');
      expect(displayTitle('_Example.com_Example_Guide_-_Some_Author.pdf'), 'Example Guide');
    });

    test('comics lose release tags', () {
      expect(
        displayTitle('Series - Issue 001 (2017) (2 covers) (digital) (Some-Group).cbr'),
        'Series - Issue 001 (2017)',
      );
      expect(displayTitle('Series v02 - Arc (2020) (digital) (Some-Group).cbz'), 'Series v02 - Arc (2020)');
    });

    test('rescan repairs only guessed titles', () {
      expect(refreshedTitle('!', '! - Improvised Tools.pdf'), 'Improvised Tools');
      expect(refreshedTitle('Series Name', 'Series Name - Volume 02.cbr'), 'Series Name - Volume 02');
      expect(refreshedTitle('hobby', 'hobby - ! - Garden Guide.pdf'), 'Garden Guide');
      expect(refreshedTitle('Writer, Ann', 'Writer, Ann - Field Notes.pdf'), 'Field Notes');
      expect(
        refreshedTitle(
          'Series - Issue 001 (2017) (digital) (Some-Group)',
          'Series - Issue 001 (2017) (digital) (Some-Group).cbr',
        ),
        'Series - Issue 001 (2017)',
      );
      expect(refreshedTitle('Edited Title', 'File Name.epub'), 'Edited Title');
    });

    test('scan merge keeps records, flags changed and missing files', () {
      final kept = book('Kept', progress: 0.4).copyWith(locator: '{"href":"a"}');
      final changed = book('Changed', progress: 0.2).copyWith(locator: '{"href":"b"}');
      final gone = book('Gone', progress: 0.7);
      final merged = mergeScan(
        [kept, changed, gone],
        [
          const FoundFile('fixture:Kept', 'Kept.epub', '', 1, 1),
          const FoundFile('fixture:Changed', 'Changed.epub', '', 2, 5),
          const FoundFile('fixture:New', 'New Book - Some Author.epub', 'Novels', 3, 3),
        ],
      );
      final byUri = {for (final b in merged) b.uri: b};
      expect(byUri['fixture:Kept']!.locator, '{"href":"a"}');
      expect(byUri['fixture:Changed']!.locator, '');
      expect(byUri['fixture:Changed']!.approximate, isTrue);
      expect(byUri['fixture:Changed']!.progress, 0.2);
      expect(byUri['fixture:Gone']!.missing, isTrue);
      expect(byUri['fixture:New']!.author, 'Some Author');
      expect(byUri['fixture:New']!.folder, 'Novels');
    });

    test('book JSON round trip', () {
      final b = book('Round', series: 'S', progress: 0.5, opened: 9).copyWith(locator: '{"href":"x"}');
      final back = Book.fromJson(b.toJson());
      expect(back.toJson(), b.toJson());
    });
  });

  group('shelf', () {
    test('combined filters and search respect view', () {
      final matches = book('Quiet Book', author: 'A Writer', series: 'Example', folder: 'Novels', progress: 0.4);
      final books = [
        matches,
        book('Unread', series: 'Example'),
        book('Comic', extension: 'cbr', series: 'Example', progress: 0.5),
        book('Elsewhere', series: 'Other', progress: 0.5),
      ];
      expect(
        shelfBooks(
          books,
          const ShelfView(ShelfKind.series, 'Example'),
          const ShelfFilters(status: ReadStatus.reading, type: FileType.epub),
          ' writer ',
        ),
        [matches],
      );
      expect(shelfBooks(books, const ShelfView(), const ShelfFilters(type: FileType.comics), '').length, 1);
    });

    test('reading and finished remain distinct', () {
      expect(statusOf(book('a')), ReadStatus.unread);
      expect(statusOf(book('a', progress: 0.99)), ReadStatus.reading);
      expect(statusOf(book('a', progress: 1.0)), ReadStatus.finished);
      expect(statusOf(book('a', progress: 0.2, finished: true)), ReadStatus.finished);
    });

    test('group counts and author membership', () {
      final books = [
        book('a', author: 'Writer A, Writer B', series: 'First'),
        book('b', author: 'Writer B', series: 'First'),
        book('c'),
      ];
      expect(shelfGroups(books, ShelfKind.authors).map((e) => '${e.key}:${e.value}'), ['Writer A:1', 'Writer B:2']);
      expect(shelfGroups(books, ShelfKind.series).map((e) => '${e.key}:${e.value}'), ['First:2']);
      expect(shelfBooks(books, const ShelfView(ShelfKind.authors, 'Writer B'), const ShelfFilters(), '').length, 2);
    });

    test('recent sort and continue skip unavailable books', () {
      final a = book('Alpha', opened: 10);
      final z = book('Zulu', opened: 20);
      final lost = book('Lost', opened: 30, missing: true);
      expect(continueBook([a, z, lost]), z);
      expect(continueBook([book('Never opened'), lost]), isNull);
      expect(shelfBooks([a, lost, z], const ShelfView(), const ShelfFilters(sort: SortBy.recent), ''), [lost, z, a]);
    });

    test('contents select one anchor and conservative fallback', () {
      const targets = [
        ContentsTarget('one.xhtml', 'Part'),
        ContentsTarget('one.xhtml#nested', 'Nested'),
        ContentsTarget('two.xhtml', 'Next'),
      ];
      expect(contentsIndex(targets, 'one.xhtml', fragments: ['nested']), 1);
      expect(contentsIndex(targets, 'one.xhtml#nested'), 1);
      expect(contentsIndex(targets, 'one.xhtml', title: 'Nested'), 1);
      expect(contentsIndex(targets, 'one.xhtml'), 0);
      expect(contentsIndex(targets, 'unknown.xhtml'), -1);
    });
  });

  test('book progress falls back to reading order when Readium reports 0', () {
    const order = ['c1.xhtml', 'c2.xhtml', 'c3.xhtml', 'c4.xhtml'];
    expect(bookProgress(order, 'c1.xhtml', progression: 0.5, totalProgression: 0), closeTo(0.125, 1e-9));
    expect(bookProgress(order, 'c3.xhtml#x', progression: 0), closeTo(0.5, 1e-9));
    expect(bookProgress(order, 'c2.xhtml', progression: 0.1, totalProgression: 0.3), 0.3);
    expect(bookProgress(const [], 'page02.png', progression: 0.4), 0.4);
  });

  test('book metadata replaces only file-name guesses', () {
    const name = 'empire of silence.epub';
    expect(metadataTitle(displayTitle(name), name, 'Empire of Silence'), 'Empire of Silence');
    expect(metadataTitle('My Edited Title', name, 'Empire of Silence'), 'My Edited Title');
    expect(metadataTitle(displayTitle(name), name, 'empire of silence'), displayTitle(name));
    expect(metadataTitle('Plain', 'Plain.epub', ''), 'Plain');
    expect(metadataAuthor('', name, ['Ann Writer', 'Ann Writer', 'Ben Artist']), 'Ann Writer, Ben Artist');
    expect(metadataAuthor('Some Author', 'Title - Some Author.epub', ['Real Name']), 'Real Name');
    expect(metadataAuthor('Imported Author', 'Title - Some Author.epub', ['Real Name']), 'Imported Author');
    expect(metadataAuthor('Kept', name, const []), 'Kept');
  });

  test('series shelves read in series order; tags form shelves', () {
    final first = book('Zeta', series: 'Saga').copyWith(seriesIndex: 1, tags: ['epic']);
    final second = book('Alpha', series: 'Saga').copyWith(seriesIndex: 2.5, tags: ['epic', 'reread']);
    final loose = book('Middle', series: 'Saga');
    final shown = shelfBooks(
      [loose, second, first],
      const ShelfView(ShelfKind.series, 'Saga'),
      const ShelfFilters(),
      '',
    );
    expect(shown.map((b) => b.title), ['Zeta', 'Alpha', 'Middle']);
    expect(shelfGroups([first, second], ShelfKind.tags).map((e) => '${e.key}:${e.value}'), ['epic:2', 'reread:1']);
    expect(shelfBooks([first, second], const ShelfView(ShelfKind.tags, 'reread'), const ShelfFilters(), ''), [second]);
  });

  test('ISBNs come only from valid identifiers', () {
    expect(isbnFrom('urn:isbn:978-0-306-40615-7'), '9780306406157');
    expect(isbnFrom('0306406152'), '0306406152');
    expect(isbnFrom('urn:uuid:9780306406158'), '');
    expect(isbnFrom(null), '');
  });

  test('end of book uses page counters, not 100 %', () {
    const order = ['c1.xhtml', 'c2.xhtml', 'c3.xhtml'];
    expect(isAtEnd(readingOrder: order, href: 'c3.xhtml', currentPage: 5, totalPages: 6, progression: 0.83), isTrue);
    expect(isAtEnd(readingOrder: order, href: 'c3.xhtml', currentPage: 4, totalPages: 6, progression: 0.66), isFalse);
    expect(isAtEnd(readingOrder: order, href: 'c2.xhtml', currentPage: 5, totalPages: 6), isFalse);
    expect(isAtEnd(readingOrder: order, href: 'c3.xhtml#end', progression: 0.95), isTrue);
    expect(isAtEnd(readingOrder: const ['doc.pdf'], href: 'doc.pdf', position: 5, numberOfPages: 5), isTrue);
    expect(isAtEnd(readingOrder: const ['doc.pdf'], href: 'doc.pdf', position: 4, numberOfPages: 5), isFalse);
    expect(isAtEnd(readingOrder: const [], href: 'x', progress: 0.99), isTrue);
  });
}
