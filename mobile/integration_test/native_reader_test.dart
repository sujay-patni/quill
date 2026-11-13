// Native reader on a device: opens a synthetic book, holds a forward and a backward turn long
// enough for host screenshots, and checks turns commit and save.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quill/library/book.dart';
import 'package:quill/library/library.dart';
import 'package:quill/native/native_reader_page.dart';
import 'package:quill/native/page_view.dart';

import 'fixtures.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('native reader: held curl forward and back, commit saves', (tester) async {
    final root = Directory('${(await getTemporaryDirectory()).path}/quill-native-it')..createSync(recursive: true);
    final file = await writeFixture(root, 'Native Turn.epub', syntheticEpub(chapters: 2, paragraphCounts: [30, 30], withCover: true, imagesInText: true));
    final lib = Library(directory: () async => root);
    lib.books = [Book(id: 'nt', uri: file.path, name: 'Native Turn.epub', folder: '', size: file.lengthSync(), modified: 1)];
    await tester.pumpWidget(MaterialApp(home: NativeReaderPage(library: lib, book: lib.books.first)));
    Future<void> wait(int ms) async {
      final end = DateTime.now().add(Duration(milliseconds: ms));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    // ignore: avoid_print
    print('NATIVE-OPEN');
    await wait(4000);
    final page = find.byKey(const Key('nativePage'));
    expect(page, findsOneWidget);
    final rect = tester.getRect(page);
    int shown() => tester.widget<NativePage>(page).page.start;
    final first = shown();

    Future<TestGesture> hold(bool forward, double fraction) async {
      final g = await tester.startGesture(Offset(forward ? rect.right - 20 : rect.left + 20, rect.center.dy + 200));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(Offset((forward ? -1 : 1) * rect.width * fraction / 10, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      return g;
    }

    // ignore: avoid_print
    print('NATIVE-HOLD forward');
    final f = await hold(true, 0.5);
    expect(find.byKey(const Key('pageTurn')), findsOneWidget);
    await wait(4000);
    await f.up();
    await wait(1000);
    expect(shown(), greaterThan(first));
    expect(lib.books.first.locator, isNotEmpty);

    // ignore: avoid_print
    print('NATIVE-HOLD backward');
    final b = await hold(false, 0.5);
    expect(find.byKey(const Key('pageTurn')), findsOneWidget);
    await wait(4000);
    await b.up();
    await wait(1000);
    expect(shown(), first);
  });
}
