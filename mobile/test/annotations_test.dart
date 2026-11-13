import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quill/library/annotations.dart';

void main() {
  test('annotations persist, sort by place, edit and delete independently', () async {
    final dir = await Directory.systemTemp.createTemp('quill-notes');
    final file = File('${dir.path}/annotations.json');
    final store = AnnotationStore(file);
    await store.load();
    Annotation make(String id, String book, int spine, int start, {AnnotationKind kind = AnnotationKind.highlight}) => Annotation(
      id: id, bookId: book, kind: kind, spine: spine, start: start, end: start + 5, quote: 'q$id', created: 1, updated: 1);
    await store.put(make('a', 'b1', 2, 10));
    await store.put(make('b', 'b1', 1, 99, kind: AnnotationKind.bookmark));
    await store.put(make('c', 'b2', 0, 0));
    expect(store.forBook('b1').map((a) => a.id).toList(), ['b', 'a'], reason: 'ordered by place in the book');
    await store.put(store.forBook('b1').last.copyWith(note: 'mine', color: 3, updated: 2));
    await store.remove('c');

    final again = AnnotationStore(file);
    await again.load();
    final b1 = again.forBook('b1');
    expect(b1.length, 2);
    expect([b1.last.note, b1.last.color, b1.last.quote, b1.last.kind], ['mine', 3, 'qa', AnnotationKind.highlight]);
    expect(again.forBook('b2'), isEmpty);
    expect(store.newId(), isNot(store.newId()));
    expect(File('${file.path}.tmp').existsSync(), isFalse, reason: 'writes are atomic renames');
    await dir.delete(recursive: true);
  });

  test('an unreadable file is left alone and shows nothing', () async {
    final dir = await Directory.systemTemp.createTemp('quill-notes');
    final file = File('${dir.path}/annotations.json')..writeAsStringSync('{not json');
    final store = AnnotationStore(file);
    await store.load();
    expect(store.forBook('x'), isEmpty);
    expect(file.readAsStringSync(), '{not json');
    await dir.delete(recursive: true);
  });

  test('readable export groups by chapter and keeps notes with their quotes', () {
    Annotation a(String id, AnnotationKind kind, String chapter, String quote, [String note = '']) => Annotation(
      id: id, bookId: 'b', kind: kind, spine: 0, start: 0, end: 1, chapter: chapter, quote: quote, note: note, created: 1, updated: 1);
    final text = annotationsAsText('My Book', [
      a('1', AnnotationKind.highlight, 'One', 'first words', 'a thought'),
      a('2', AnnotationKind.bookmark, 'One', 'page start'),
      a('3', AnnotationKind.highlight, 'Two', 'later words'),
    ]);
    expect(text, '# My Book\n\n## One\n\n> first words\n\na thought\n\n- Bookmark: page start…\n\n## Two\n\n> later words\n');
  });

  test('a standard-reader bookmark keeps its locator and sorts first', () {
    const a = Annotation(id: 'b', bookId: 'x', kind: AnnotationKind.bookmark, spine: -1, start: 0, end: 0, created: 1, updated: 1, locator: '{"href":"c1"}');
    final back = Annotation.fromJson(a.toJson().cast<String, dynamic>())!;
    expect([back.spine, back.locator], [-1, '{"href":"c1"}']);
    const plain = Annotation(id: 'n', bookId: 'x', kind: AnnotationKind.highlight, spine: 0, start: 1, end: 2, created: 1, updated: 1);
    expect(plain.toJson().containsKey('locator'), isFalse);
  });
}
