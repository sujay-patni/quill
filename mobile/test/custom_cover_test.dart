import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quill/library/cover_store.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('quill-custom-cover-');
    await Directory('${root.path}/covers').create();
  });
  tearDown(() => root.delete(recursive: true));

  test('custom cover survives reopening and reset reveals the untouched original', () async {
    final original = File('${root.path}/covers/book.jpg');
    await original.writeAsBytes([1, 2, 3]);
    final chosen = File('${root.path}/chosen.jpg');
    await chosen.writeAsBytes([4, 5, 6]);
    final store = CoverStore(directory: () async => root);
    await store.load();
    await store.setCustom('book', chosen);
    await chosen.delete();

    final reopened = CoverStore(directory: () async => root);
    await reopened.load();
    expect(reopened.isCustom('book'), isTrue);
    expect(await reopened.fileFor('book').readAsBytes(), [4, 5, 6]);
    await reopened.clearCustom('book');
    expect(reopened.has('book'), isTrue);
    expect(reopened.isCustom('book'), isFalse);
    expect(await reopened.fileFor('book').readAsBytes(), [1, 2, 3]);
    expect(await original.readAsBytes(), [1, 2, 3]);
  });

  test('replacing and resetting a custom cover leaves other books alone', () async {
    final image = File('${root.path}/chosen.jpg');
    await image.writeAsBytes([7, 8, 9]);
    final store = CoverStore(directory: () async => root);
    await store.load();
    await store.setCustom('first', image);
    await store.setCustom('second', image);
    final old = store.fileFor('first');
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await image.writeAsBytes([10, 11, 12]);
    await store.setCustom('first', image);
    expect(await old.exists(), isFalse);
    expect(await store.fileFor('first').readAsBytes(), [10, 11, 12]);
    await store.clearCustom('first');
    expect(store.has('first'), isFalse);
    expect(store.isCustom('second'), isTrue);
    expect(await store.fileFor('second').readAsBytes(), [7, 8, 9]);
  });
}
