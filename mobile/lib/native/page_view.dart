// Native engine: draws one laid-out page on the reading paper.
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'paginator.dart';

/// Decoded images for the pages on screen: loads on first use, keeps the most recent few.
class PageImages extends ChangeNotifier {
  PageImages(this.load, {this.keep = 8});

  final Future<ui.Image?> Function(String path) load;
  final int keep;
  final Map<String, ui.Image?> _images = {}; // insertion order = recency
  final Set<String> _loading = {};
  bool _disposed = false;

  ui.Image? get(String path) {
    if (_images.containsKey(path)) {
      final image = _images.remove(path);
      _images[path] = image;
      return image;
    }
    if (_loading.add(path)) {
      load(path).then((image) {
        _loading.remove(path);
        if (_disposed) {
          image?.dispose();
          return;
        }
        _images[path] = image;
        while (_images.length > keep) {
          _images.remove(_images.keys.first)?.dispose();
        }
        notifyListeners();
      });
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image?.dispose();
    }
    _images.clear();
    super.dispose();
  }
}

class NativePage extends StatelessWidget {
  const NativePage({super.key, required this.page, required this.paper, this.images, this.highlight, this.marks = const []});

  final LaidOutPage page;
  final Color paper;
  final PageImages? images;

  /// A (start, end) range of chapter offsets to mark on this page (search match).
  final (int, int)? highlight;

  /// Further (start, end, colour) ranges: highlights and the selection.
  final List<(int, int, Color)> marks;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _PagePainter(page, paper, images, highlight, marks),
    child: const SizedBox.expand(),
  );
}

class _PagePainter extends CustomPainter {
  _PagePainter(this.page, this.paper, this.images, this.highlight, this.marks) : super(repaint: images);
  final (int, int)? highlight;
  final List<(int, int, Color)> marks;
  final LaidOutPage page;
  final Color paper;
  final PageImages? images;

  @override
  void paint(Canvas canvas, Size size) {
    if (paper.a > 0) canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    page.paint(canvas, Offset.zero, imageOf: images?.get, marks: [
      ...marks,
      if (highlight != null) (highlight!.$1, highlight!.$2, const Color(0x66FFD54F)),
    ]);
  }

  @override
  bool shouldRepaint(_PagePainter old) => old.page != page || old.paper != paper || old.images != images || old.highlight != highlight || !_same(old.marks, marks);

  static bool _same(List<(int, int, Color)> a, List<(int, int, Color)> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
