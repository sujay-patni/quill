import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quill/import/moon_import.dart';
import 'package:quill/import/moon_import_page.dart';
import 'package:quill/library/book.dart';
import 'package:quill/library/library.dart';

import 'moon_fixture.dart';

// Preview then apply against a synthetic Moon Reader backup, through the real native reader.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Moon Reader import: preview changes nothing, Import applies it', (tester) async {
    final root = await Directory('${(await getTemporaryDirectory()).path}/moon-it').create(recursive: true);
    addTearDown(() => root.delete(recursive: true));
    final backup = File('${root.path}/synthetic.mrstd')..writeAsBytesSync(base64Decode(syntheticMoonBackup));
    final dir = await Directory('${root.path}/lib').create();
    final lib = Library(directory: () async => dir);
    Book book(String id, String folder, String name) =>
        Book(id: id, uri: 'content://x/$id', name: name, folder: folder, size: 1, modified: 1);
    lib.books = [
      book('first', 'Saga', 'First Light.epub'),
      book('second', 'Saga', 'Second Dark.epub'),
      book('quill-only', '', 'Only Here.epub'),
    ];
    final before = jsonEncode([for (final b in lib.books) b.toJson()]);

    await tester.pumpWidget(
      MaterialApp(
        home: MoonImportPage(library: lib, uri: backup.path),
      ),
    );
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (find.byKey(const Key('applyImport')).evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        fail('No preview: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).join(' | ')}');
      }
      await tester.pump(const Duration(milliseconds: 200));
    }
    String value(Key row) =>
        (tester.widgetList<Text>(find.descendant(of: find.byKey(row), matching: find.byType(Text))).last).data!;
    expect(value(const Key('importMatched')), '2');
    expect(value(const Key('importUnmatched')), '1', reason: 'Gone Away is not in the library');
    expect(jsonEncode([for (final b in lib.books) b.toJson()]), before, reason: 'the preview writes nothing');

    await tester.tap(find.byKey(const Key('applyImport')));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(find.text('Done'), findsOneWidget);

    final first = lib.books.firstWhere((b) => b.id == 'first');
    expect(
      [first.series, first.seriesIndex, first.tags, first.finished],
      [
        'The Lamp Saga',
        1.0,
        ['fantasy'],
        true,
      ],
    );
    expect(first.title, 'First Light');
    final second = lib.books.firstWhere((b) => b.id == 'second');
    expect([second.progress, second.approximate, second.finished], [0.12, true, false]);
    expect(
      lib.books.firstWhere((b) => b.id == 'quill-only').toJson(),
      book('quill-only', '', 'Only Here.epub').toJson(),
    );
    expect(lib.stats.daysFor('first').map((d) => d.source).toSet(), {moonSource});
    expect(lib.stats.daysFor('first').length, 2);
    final highlights = jsonDecode(File('${dir.path}/moon-highlights.json').readAsStringSync()) as Map;
    expect((highlights['highlights'] as List).single['text'], 'lamp glow');
    expect(await lib.moonImportHash(), hasLength(64));
    expect(Directory('${dir.path}/backups').listSync(), hasLength(1), reason: 'a full backup is taken before the import');
  });
}
