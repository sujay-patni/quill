// Writes the synthetic test books into a folder: dart run tool/make_fixtures.dart <dir>
import 'dart:io';

import '../integration_test/fixtures.dart';

Future<void> main(List<String> args) async {
  final root = Directory(args.isEmpty ? 'build/fixtures' : args.first);
  final series = Directory('${root.path}/Series')..createSync(recursive: true);
  await writeFixture(root, 'Synthetic Navigation - Quill Tests.epub', syntheticEpub());
  await writeFixture(series, 'Synthetic Comic v01 (2020) (digital) (Group).cbz', syntheticCbz());
  await writeFixture(root, 'Tests, Quill - Synthetic Pages.pdf', syntheticPdf());
  stdout.writeln('Wrote fixtures to ${root.path}');
}
