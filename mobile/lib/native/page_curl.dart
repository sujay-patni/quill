// Native engine: page-turn drawing. The rolled curl is the same geometry as the Android
// PageCurlView (a page wrapped around a cylinder, Apple Books / Moon Reader "real page turning"),
// drawn from two page images with Canvas.drawVertices.
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

enum TurnStyle { curl, slide }

/// [front] is the sheet that moves; [under] lies beneath it. [progress] 0 = front flat and
/// covering, 1 = front fully turned away over the left edge.
class PageTurnPainter extends CustomPainter {
  PageTurnPainter({
    required this.front,
    required this.under,
    required this.progress,
    required this.paper,
    required this.pixelRatio,
    this.style = TurnStyle.curl,
  });

  final ui.Image front;
  final ui.Image under;
  final double progress;
  final Color paper;
  final double pixelRatio;
  final TurnStyle style;

  static const _cols = 24, _rows = 36;

  Paint _imagePaint(ui.Image image, {double opacity = 1}) => Paint()
    ..filterQuality = FilterQuality.low
    ..color = Color.fromRGBO(255, 255, 255, opacity)
    ..shader = ui.ImageShader(
      image,
      TileMode.clamp,
      TileMode.clamp,
      (Matrix4.identity()..scaleByDouble(1 / pixelRatio, 1 / pixelRatio, 1, 1)).storage,
    );

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final all = Offset.zero & size;
    final p = progress.clamp(0.0, 1.0);
    canvas.drawRect(all, _imagePaint(under));
    if (p >= 0.999) return;
    if (p <= 0.001) {
      canvas.drawRect(all, _imagePaint(front));
      return;
    }
    if (style == TurnStyle.slide) {
      // The front sheet slides off to the left, with a soft edge shadow on the page beneath.
      final x = -p * w;
      canvas.drawRect(
        Rect.fromLTWH(x + w, 0, 18, h),
        Paint()..shader = ui.Gradient.linear(Offset(x + w, 0), Offset(x + w + 18, 0), const [Color(0x40000000), Color(0x00000000)]),
      );
      canvas.save();
      canvas.translate(x, 0);
      canvas.drawRect(all, _imagePaint(front));
      canvas.restore();
      return;
    }

    final roll = Roll.at(p, w, h, 0.11 * min(w, h));
    final crest = Offset(roll.ax + roll.nx * roll.r, roll.ay + roll.ny * roll.r);
    final n = Offset(roll.nx, roll.ny);

    // 1. Shadow the rolled page casts on the page underneath, beyond the crest.
    final reach = roll.r * 0.7 + 12;
    canvas.save();
    canvas.clipPath(_halfPlane(crest, n, w, h));
    canvas.drawPaint(Paint()..shader = ui.Gradient.linear(crest, crest + n * reach, const [Color(0x55000000), Color(0x00000000)]));
    canvas.restore();

    // 2. The page itself: flat part and the side rising over the roll.
    final frontMesh = roll.mesh(w, h, _cols, _rows, RollSide.front);
    canvas.drawVertices(_vertices(frontMesh, w, h), BlendMode.srcOver, _imagePaint(front));

    // 3. Light on the roll: bright where it faces up, dark toward the crest.
    canvas.save();
    canvas.clipPath(_strip(Offset(roll.ax, roll.ay), crest, n, w, h));
    canvas.drawPaint(Paint()
      ..shader = ui.Gradient.linear(
        Offset(roll.ax, roll.ay),
        crest,
        const [Color(0x00000000), Color(0x12FFFFFF), Color(0x30000000), Color(0x66000000)],
        const [0, 0.35, 0.8, 1],
      ));
    canvas.restore();

    // 4. The back of the sheet, over what it covers: paper with the print faintly through.
    final backMesh = roll.mesh(w, h, _cols, _rows, RollSide.back);
    final back = _vertices(backMesh, w, h);
    canvas.drawVertices(back, BlendMode.srcOver, Paint()..color = paper.withValues(alpha: 1));
    canvas.drawVertices(back, BlendMode.srcOver, _imagePaint(front, opacity: 0.13));
    canvas.save();
    canvas.clipPath(_halfPlane(crest, -n, w, h));
    canvas.clipPath(_outline(backMesh));
    final inner = roll.r * 1.4 + 8;
    canvas.drawPaint(Paint()
      ..shader = ui.Gradient.linear(
        crest,
        crest - n * inner,
        const [Color(0x40000000), Color(0x10FFFFFF), Color(0x00000000)],
        const [0, 0.5, 1],
      ));
    canvas.restore();
  }

  ui.Vertices _vertices(Float32List positions, double w, double h) {
    final tex = Float32List(positions.length);
    var i = 0;
    for (var row = 0; row <= _rows; row++) {
      for (var col = 0; col <= _cols; col++) {
        tex[i++] = w * col / _cols;
        tex[i++] = h * row / _rows;
      }
    }
    final indices = Uint16List(_cols * _rows * 6);
    var k = 0;
    for (var row = 0; row < _rows; row++) {
      for (var col = 0; col < _cols; col++) {
        final a = row * (_cols + 1) + col, b = a + 1, c = a + _cols + 1, d = c + 1;
        indices
          ..[k++] = a
          ..[k++] = b
          ..[k++] = c
          ..[k++] = b
          ..[k++] = d
          ..[k++] = c;
      }
    }
    return ui.Vertices.raw(ui.VertexMode.triangles, positions, textureCoordinates: tex, indices: indices);
  }

  static Path _halfPlane(Offset at, Offset n, double w, double h) {
    final far = 4 * (w + h);
    final t = Offset(-n.dy, n.dx);
    return Path()
      ..moveTo(at.dx + t.dx * far, at.dy + t.dy * far)
      ..lineTo(at.dx - t.dx * far, at.dy - t.dy * far)
      ..lineTo(at.dx - t.dx * far + n.dx * far, at.dy - t.dy * far + n.dy * far)
      ..lineTo(at.dx + t.dx * far + n.dx * far, at.dy + t.dy * far + n.dy * far)
      ..close();
  }

  static Path _strip(Offset axis, Offset crest, Offset n, double w, double h) {
    final far = 4 * (w + h);
    final t = Offset(-n.dy, n.dx);
    return Path()
      ..moveTo(axis.dx + t.dx * far, axis.dy + t.dy * far)
      ..lineTo(axis.dx - t.dx * far, axis.dy - t.dy * far)
      ..lineTo(crest.dx - t.dx * far, crest.dy - t.dy * far)
      ..lineTo(crest.dx + t.dx * far, crest.dy + t.dy * far)
      ..close();
  }

  static Path _outline(Float32List mesh) {
    final path = Path();
    void to(int col, int row) {
      final i = (row * (_cols + 1) + col) * 2;
      if (col == 0 && row == 0) {
        path.moveTo(mesh[i], mesh[i + 1]);
      } else {
        path.lineTo(mesh[i], mesh[i + 1]);
      }
    }

    for (var c = 0; c <= _cols; c++) {
      to(c, 0);
    }
    for (var r = 1; r <= _rows; r++) {
      to(_cols, r);
    }
    for (var c = _cols - 1; c >= 0; c--) {
      to(c, _rows);
    }
    for (var r = _rows - 1; r >= 1; r--) {
      to(0, r);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(PageTurnPainter old) =>
      old.progress != progress || old.front != front || old.under != under || old.style != style;
}

enum RollSide { front, back }

/// A page rolled around a cylinder of radius [r] lying on the page along the line through
/// ([ax], [ay]) perpendicular to ([nx], [ny]); n points toward the pulled corner.
class Roll {
  const Roll(this.ax, this.ay, this.nx, this.ny, this.r);
  final double ax, ay, nx, ny, r;

  /// The roll for a turn [p] of a [w]x[h] page: the corner (w, h) travels to
  /// (w − 2pw, h − 0.16h·sin(πp)); the axis is placed so the rolled-over corner lands there.
  factory Roll.at(double p, double w, double h, double maxRadius) {
    final tx = w - p * 2 * w;
    final ty = h - h * 0.16 * sin(pi * p);
    final len = max(sqrt((w - tx) * (w - tx) + (h - ty) * (h - ty)), 0.01);
    final nx = (w - tx) / len, ny = (h - ty) / len;
    final r = min(maxRadius, len / pi);
    final a = (len + pi * r) / 2;
    return Roll(w - nx * a, h - ny * a, nx, ny, r);
  }

  /// Where page point (x, y) appears seen from above, for the given side of the sheet.
  Offset project(double x, double y, RollSide side) {
    final quarter = pi * r / 2;
    final raw = (x - ax) * nx + (y - ay) * ny;
    // The front shows up to the crest, the back from the crest on; the rest collapses onto it.
    final d = side == RollSide.front ? min(raw, quarter) : max(raw, quarter);
    final shown = d <= 0 ? d : (d < pi * r ? r * sin(d / r) : -(d - pi * r));
    return Offset(x + nx * (shown - raw), y + ny * (shown - raw));
  }

  Float32List mesh(double w, double h, int cols, int rows, RollSide side) {
    final out = Float32List((cols + 1) * (rows + 1) * 2);
    var i = 0;
    for (var row = 0; row <= rows; row++) {
      for (var col = 0; col <= cols; col++) {
        final o = project(w * col / cols, h * row / rows, side);
        out[i++] = o.dx;
        out[i++] = o.dy;
      }
    }
    return out;
  }
}
