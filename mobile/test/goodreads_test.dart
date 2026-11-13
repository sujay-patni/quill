import 'package:flutter_test/flutter_test.dart';
import 'package:quill/library/book.dart';
import 'package:quill/library/goodreads.dart';

Book _book(String id, String title, String author, {String isbn = ''}) =>
    Book(id: id, uri: 'fixture:$id', name: '$id.epub', folder: '', size: 1, modified: 1, title: title, author: author, isbn: isbn);

const _export = '''Book Id,Title,Author,Author l-f,Additional Authors,ISBN,ISBN13,My Rating,Average Rating,Publisher,Binding,Number of Pages,Year Published,Original Publication Year,Date Read,Date Added,Bookshelves,Bookshelves with positions,Exclusive Shelf,My Review,Spoiler,Private Notes,Read Count,Owned Copies
1,"The Way of Kings (The Stormlight Archive, #1)",Brandon Sanderson,"Sanderson, Brandon",,="0765326353",="9780765326355",5,4.66,Tor,Hardcover,1007,2010,2010,2024/03/09,2023/01/02,"epic-fantasy, favourites","epic-fantasy (#1)",read,"Line one
line two, with a comma",,,1,0
2,Dune,Frank Herbert,"Herbert, Frank",,="",="",0,4.2,Ace,Paperback,600,1990,1965,,2023/05/05,to-read,to-read (#3),to-read,,,,0,0
3,Elantris,Brandon Sanderson,"Sanderson, Brandon",,="",="",4,4.1,Tor,Paperback,600,2006,2005,2022/01/15,2021/05/05,,,read,,,,1,0
''';

void main() {
  test('the Goodreads page: by ISBN, else a search', () {
    expect(goodreadsUrl(_book('a', 'Dune', 'Frank Herbert', isbn: '9780441172719')), 'https://www.goodreads.com/book/isbn/9780441172719');
    expect(goodreadsUrl(_book('a', 'Dune & Co', 'Frank Herbert')), 'https://www.goodreads.com/search?q=Dune+%26+Co+Frank+Herbert');
  });

  test('the file for Goodreads has its column names and only finished or rated books', () {
    final read = DateTime(2026, 11, 3).millisecondsSinceEpoch;
    final csv = goodreadsCsv([
      _book('a', 'Dune, Messiah', 'Frank Herbert', isbn: '9780441172696').copyWith(finished: true, finishedAt: read, rating: 5, tags: ['Sci Fi', 'classic']),
      _book('b', 'Unread', 'Nobody'),
      _book('c', 'Rated', 'Someone', isbn: '0441172717').copyWith(rating: 3, progress: 0.5),
    ]);
    final rows = parseCsv(csv);
    expect(rows.first, ['Title', 'Author', 'ISBN', 'ISBN13', 'My Rating', 'Date Read', 'Date Added', 'Bookshelves', 'Exclusive Shelf', 'Read Count']);
    expect(rows[1], ['Dune, Messiah', 'Frank Herbert', '', '9780441172696', '5', '2026/11/03', '', 'sci-fi, classic', 'read', '1']);
    expect(rows[2], ['Rated', 'Someone', '0441172717', '', '3', '', '', '', 'currently-reading', '0']);
    expect(rows, hasLength(3));
    expect(parseCsv(goodreadsCsv([_book('a', 'Old', 'X').copyWith(finished: true, finishedAt: read)], since: read + 1)), hasLength(1));
  });

  test('a Goodreads export is read, with quoted cells and ="…" ISBNs', () {
    final books = parseGoodreadsExport(_export);
    expect(books.map((b) => b.title), ['The Way of Kings (The Stormlight Archive, #1)', 'Dune', 'Elantris']);
    expect(books.first.isbns, {'0765326353', '9780765326355'});
    expect([books.first.rating, books.first.read, books.first.shelves], [5, true, ['epic-fantasy', 'favourites']]);
    expect(DateTime.fromMillisecondsSinceEpoch(books.first.readAt), DateTime(2024, 3, 9));
    expect([books[1].read, books[1].rating, books[1].shelves], [false, 0, <String>[]]);
    expect(() => parseGoodreadsExport('a,b\n1,2\n'), throwsFormatException);
  });

  test('an export fills what Quill lacks and overwrites nothing', () {
    final mine = [
      _book('k', 'The Way of Kings', 'Brandon Sanderson'),
      _book('e', 'Elantris: Tenth Anniversary Edition', 'Sanderson, Brandon').copyWith(rating: 2, finished: true, finishedAt: 5),
      _book('d', 'Dune', 'Frank Herbert'),
      _book('x', 'Not on Goodreads', 'Me'),
    ];
    final changes = {for (final c in previewGoodreads(mine, parseGoodreadsExport(_export))) c.before.id: c.after};
    final k = changes['k']!;
    expect([k.rating, k.finished, k.tags, k.isbn, k.provenance['rating']], [5, true, ['epic-fantasy', 'favourites'], '9780765326355', 'goodreads']);
    expect(DateTime.fromMillisecondsSinceEpoch(k.finishedAt), DateTime(2024, 3, 9));
    expect(changes.containsKey('e'), isFalse, reason: 'rating and finish date set in Quill stay');
    expect(changes.containsKey('d'), isFalse, reason: 'a to-read book with no rating adds nothing');
    expect(changes.containsKey('x'), isFalse);
  });
}
