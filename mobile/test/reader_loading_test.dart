import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill/library/book.dart';
import 'package:quill/library/library.dart';
import 'package:quill/reader/reader_page.dart';

class _StalledReader extends FlutterReadiumPlatform {
  final errors = StreamController<ReadiumError>.broadcast();
  final requests = <Completer<Publication>>[];
  int closes = 0;

  @override
  Stream<ReadiumError> get onErrorEvent => errors.stream;

  @override
  Future<Publication> openPublication(String pubUrl) {
    final request = Completer<Publication>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<void> closePublication() async => closes++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FlutterReadiumPlatform previous;
  late _StalledReader platform;
  late Library library;
  const locator = '{"href":"c2.xhtml","type":"application/xhtml+xml","locations":{"progression":0.4}}';

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dk.nota.flutter_readium/main'),
      (call) async => true,
    );
    previous = FlutterReadiumPlatform.instance;
    platform = _StalledReader();
    FlutterReadiumPlatform.instance = platform;
    library = Library()
      ..books = [
        Book(
          id: 'fixture',
          uri: 'fixture.epub',
          name: 'Fixture.epub',
          folder: '',
          size: 1,
          modified: 1,
          locator: locator,
        ),
      ];
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dk.nota.flutter_readium/main'),
      null,
    );
    FlutterReadiumPlatform.instance = previous;
    await platform.errors.close();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(library: library, book: library.books.first),
      ),
    );
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 40)));
    for (var i = 0; i < 30 && platform.requests.isEmpty; i++) {
      await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(
      platform.requests,
      hasLength(1),
      reason: tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(' | '),
    );
  }

  testWidgets('stalled open becomes retryable without discarding resume or clearing cache', (tester) async {
    await open(tester);
    await tester.pump(const Duration(seconds: 26));
    await tester.pump();
    expect(find.byKey(const Key('retryReader')), findsOneWidget);
    expect(library.books.single.locator, locator);
    expect(platform.closes, 1);
    await tester.tap(find.byKey(const Key('retryReader')));
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 40)));
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(platform.requests, hasLength(2));
    expect(library.books.single.locator, locator);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 26));
  });

  testWidgets('asynchronous native failure exits loading and retains confirmed position', (tester) async {
    await open(tester);
    platform.errors.add(ReadiumError('Synthetic renderer failure'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('retryReader')), findsOneWidget);
    expect(library.books.single.locator, locator);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 26));
    expect(tester.takeException(), isNull);
  });

  testWidgets('late open failure after reader disposal cannot update the closed route', (tester) async {
    await open(tester);
    await tester.pumpWidget(const SizedBox());
    platform.requests.single.completeError(StateError('Synthetic late failure'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(library.books.single.locator, locator);
  });
}
