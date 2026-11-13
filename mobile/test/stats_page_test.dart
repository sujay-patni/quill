import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quill/library/library.dart';
import 'package:quill/shelf/stats_page.dart';

void main() {
  for (final scale in [1.0, 1.6]) {
    testWidgets('statistics periods stay on one line on a narrow phone at text scale $scale', (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: const Size(320, 740), textScaler: TextScaler.linear(scale)),
            child: StatsPage(library: Library()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final month = find.text('Month');
      final paragraph = tester.renderObject<RenderParagraph>(month);
      final boxes = paragraph.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 5));
      expect(boxes.map((b) => b.top).toSet(), hasLength(1), reason: 'Month must not wrap');
      await tester.ensureVisible(find.text('All time'));
      await tester.tap(find.text('All time'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'period selector and metrics must fit with larger text');
    });
  }
}
