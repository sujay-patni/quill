import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quill/library/dictionary.dart';

void main() {
  final d = Dictionary(load: (asset) => File(asset).readAsString());

  test('finds words, inflected and irregular forms, and phrases', () async {
    final lantern = await d.lookup('Lantern,');
    expect(lantern!.word, 'lantern');
    expect(lantern.senses.first, ('noun', 'light in a transparent protective case'));
    expect((await d.lookup('lanterns'))!.word, 'lantern');
    expect((await d.lookup('ran'))!.word, 'run');
    expect((await d.lookup('mice'))!.word, 'mouse');
    expect((await d.lookup('walking'))!.word, anyOf('walking', 'walk'));
    expect((await d.lookup("harbour's"))!.word, 'harbour');
    expect((await d.lookup('ice cream'))!.word, 'ice cream');
    expect(await d.lookup('zzzqqq'), isNull);
    expect(await d.lookup('  ... '), isNull);
  });
}
