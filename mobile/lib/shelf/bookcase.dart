import 'dart:math';

import 'package:flutter/material.dart';

import '../library/book.dart';

// The shelf as a bookcase, like Moon Reader's: covers stand on wooden planks against a pine back
// panel. Everything is drawn (no image assets). Titles live in each cover's semantics label;
// the compact list remains for reading titles at a glance.
class Bookcase extends StatelessWidget {
  const Bookcase({
    super.key,
    required this.books,
    required this.cover,
    required this.onTap,
    required this.onLongPress,
    this.bottomPadding = 88,
  });

  final List<Book> books;
  final Widget Function(Book book) cover;
  final ValueChanged<Book> onTap;
  final ValueChanged<Book> onLongPress;
  final double bottomPadding;

  // Measured from Moon Reader's shelf on the phone (dp): frame 12 + inner wall 10, plank 9 + 10 + 1.
  static const _side = 22.0;
  static const _gap = 12.0; // between covers
  static const _headroom = 30.0; // above the covers
  static const _plank = 20.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final inner = box.maxWidth - 2 * _side;
      final columns = max(3, ((inner - _gap) / 124).floor());
      final coverWidth = (inner - (columns + 1) * _gap) / columns;
      final coverHeight = coverWidth * 1.48;
      final rows = max((books.length / columns).ceil(), _minimumRows(box.maxHeight, coverHeight));
      return ColoredBox(
        color: _Wood.back,
        child: ListView.builder(
          padding: EdgeInsets.only(bottom: bottomPadding),
          itemCount: rows + 1,
          itemBuilder: (context, r) {
            // A last, empty shelf below the books keeps the case from ending abruptly.
            if (r == rows) return _ShelfRow(index: r, height: coverHeight * 0.45, children: const []);
            final row = books.skip(r * columns).take(columns).toList();
            return _ShelfRow(
              index: r,
              height: coverHeight + _headroom,
              children: [
                for (final b in row)
                  SizedBox(
                    width: coverWidth,
                    height: coverHeight,
                    child: _StandingBook(
                      book: b,
                      cover: cover(b),
                      onTap: () => onTap(b),
                      onLongPress: () => onLongPress(b),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    },
  );

  // Fill the screen with shelves even for a small library.
  static int _minimumRows(double viewport, double coverHeight) =>
      viewport.isFinite ? (viewport / (coverHeight + _headroom + _plank)).ceil() : 0;
}

// Moon Reader's wood, sampled from its shelf.
class _Wood {
  static const back = Color(0xFFC7B193);
  static const grain = Color(0xFF7A5E40);
  static const shadowTop = Color(0xFF5F4635);
  static const shadowMid = Color(0xFFAA9379);
  static const frameOuter = Color(0xFF634331);
  static const frameInner = Color(0xFF402418);
  static const wallLight = Color(0xFF604936);
  static const wallDark = Color(0xFF5C4D3D);
  static const lip = [Color(0xFF6F583E), Color(0xFF60442E), Color(0xFF80634C), Color(0xFF957A60)];
  static const front = [Color(0xFFCFB18E), Color(0xFFC7A884), Color(0xFFC3A27F), Color(0xFFC7A584)];
  static const frontEdge = Color(0xFFB19275);
}

class _ShelfRow extends StatelessWidget {
  const _ShelfRow({required this.index, required this.height, required this.children});

  final int index;
  final double height;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height + Bookcase._plank,
    child: Stack(
      children: [
        // Back panel with grain, darker toward the shelf above (its shadow).
        Positioned.fill(
          bottom: Bookcase._plank,
          child: CustomPaint(painter: _BackPanelPainter(seed: index)),
        ),
        // Inner side walls, seen in perspective.
        const Positioned(left: 12, top: 0, bottom: 0, width: 10, child: _InnerWall(left: true)),
        const Positioned(right: 12, top: 0, bottom: 0, width: 10, child: _InnerWall(left: false)),
        // The books, standing on the plank.
        Positioned(
          left: Bookcase._side + Bookcase._gap,
          right: Bookcase._side + Bookcase._gap,
          bottom: Bookcase._plank - 1,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, child) in children.indexed) ...[if (i > 0) const SizedBox(width: Bookcase._gap), child],
            ],
          ),
        ),
        // The side frames sit behind the continuous, edge-to-edge shelf front.
        const Positioned(left: 0, top: 0, bottom: 0, width: 12, child: _Frame(left: true)),
        const Positioned(right: 0, top: 0, bottom: 0, width: 12, child: _Frame(left: false)),
        // The plank: a lit top face and a darker front edge, casting a shadow on the panel below.
        const Positioned(left: 0, right: 0, bottom: 0, height: Bookcase._plank, child: _Plank()),
      ],
    ),
  );
}

// Seen slightly from above: a dark strip of shelf surface behind the books, then the pale front
// edge and a thin darker bottom line. Its shadow is painted on the panel below (next row).
class _Plank extends StatelessWidget {
  const _Plank();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        height: 9,
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: _Wood.lip),
        ),
      ),
      const Expanded(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: _Wood.front),
          ),
          child: SizedBox.expand(),
        ),
      ),
      Container(height: 1, color: _Wood.frontEdge),
    ],
  );
}

class _Frame extends StatelessWidget {
  const _Frame({required this.left});

  final bool left;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: left ? Alignment.centerLeft : Alignment.centerRight,
        end: left ? Alignment.centerRight : Alignment.centerLeft,
        colors: const [_Wood.frameOuter, _Wood.frameInner],
      ),
    ),
  );
}

class _InnerWall extends StatelessWidget {
  const _InnerWall({required this.left});

  final bool left;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: left ? Alignment.centerLeft : Alignment.centerRight,
        end: left ? Alignment.centerRight : Alignment.centerLeft,
        colors: const [_Wood.wallLight, _Wood.wallDark],
      ),
    ),
  );
}

class _BackPanelPainter extends CustomPainter {
  const _BackPanelPainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = _Wood.back);
    // Vertical grain, as on Moon Reader's back panel; the same every time for a row.
    final random = Random(seed * 7919 + 17);
    final grain = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 26; i++) {
      final x = random.nextDouble() * size.width;
      final amplitude = 0.6 + random.nextDouble() * 1.6;
      final phase = random.nextDouble() * pi * 2;
      grain
        ..color = _Wood.grain.withValues(alpha: 0.04 + random.nextDouble() * 0.08)
        ..strokeWidth = 0.6 + random.nextDouble() * 2.2;
      final path = Path()..moveTo(x, 0);
      for (var y = 0.0; y <= size.height; y += 10) {
        path.lineTo(x + sin(y / 55 + phase) * amplitude, y);
      }
      canvas.drawPath(path, grain);
    }
    // The shelf above casts a strong shadow that fades over ~45 dp, then gently further.
    final shadow = Rect.fromLTWH(0, 0, size.width, min(size.height, 90));
    canvas.drawRect(
      shadow,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_Wood.shadowTop, _Wood.shadowMid.withValues(alpha: 0.55), _Wood.back.withValues(alpha: 0)],
          stops: const [0, 0.5, 1],
        ).createShader(shadow),
    );
  }

  @override
  bool shouldRepaint(_BackPanelPainter old) => old.seed != seed;
}

class _StandingBook extends StatelessWidget {
  const _StandingBook({required this.book, required this.cover, required this.onTap, required this.onLongPress});

  final Book book;
  final Widget cover;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reading = book.progress > 0 && !book.finished;
    return Semantics(
      button: true,
      label: [
        book.title,
        if (book.author.isNotEmpty) book.author,
        if (book.finished) 'finished' else if (reading) '${(book.progress * 100).round()}% read',
      ].join(', '),
      excludeSemantics: true,
      child: Opacity(
        opacity: book.missing ? 0.45 : 1,
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(2), right: Radius.circular(3)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.38), blurRadius: 5, offset: const Offset(3, 2)),
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(2), right: Radius.circular(3)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: scheme.surfaceContainerLow, child: cover),
                  // The spine: a light crease and a little shade along the left edge.
                  const Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 9,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0x40000000), Color(0x33FFFFFF), Color(0x00FFFFFF)],
                          stops: [0, 0.35, 1],
                        ),
                      ),
                    ),
                  ),
                  if (reading)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 4,
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.35),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: book.progress.clamp(0.0, 1.0),
                          child: const ColoredBox(color: Color(0xFFE9D8B4)),
                        ),
                      ),
                    ),
                  if (book.finished)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.check, size: 13, color: Color(0xFFF2E6CC)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
