// Shows one native-engine page on a device long enough for a host screenshot (font check).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quill/native/blocks.dart';
import 'package:quill/native/hyphenation.dart';
import 'package:quill/native/page_view.dart';
import 'package:quill/native/paginator.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('native page renders serif text with styles', (tester) async {
    await Hyphenator.english();
    final blocks = parseChapter('''<html><head><style>.c{text-align:center}</style></head><body>
<h1 class="c">Chapter Eighteen</h1>
<p class="c"><b>Views: 1.9 Quadrillion</b></p>
${List.generate(14, (i) => '<p style="text-indent:1.5em">The quiet lantern keeps its <i>steady</i> light while the harbour sleeps under rain; paragraph $i of an extraordinarily complicated justified demonstration that should wrap across several lines.</p>').join()}
</body></html>''');
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final layout = ChapterLayout(
      blocks,
      PageStyle(width: size.width - 48, height: size.height - 140, fontSize: 21, lineHeight: 1.58, hyphenate: true),
    );
    final page = layout.pagesOf(0).first;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFFEDEAE4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 70, 24, 70),
          child: NativePage(
            key: const Key('nativePage'),
            page: page,
            paper: const Color(0x00000000),
            // "steady light" in the third indented paragraph.
            highlight: (blocks[4].start + blocks[4].text.indexOf('steady'), blocks[4].start + blocks[4].text.indexOf('steady') + 12),
          ),
        ),
      ),
    ));
    final end = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byKey(const Key('nativePage')), findsOneWidget);
  });
}
