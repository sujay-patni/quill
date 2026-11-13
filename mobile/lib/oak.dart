import 'dart:math';

import 'package:flutter/material.dart';

// Dark brown oak, for the app's bars and its main button: long grain and a bevel, the
// same wood family as the bookcase. Ivory text and icons sit on it.
const oak = Color(0xFF4E3220);
const oakDark = Color(0xFF2E1C10);
const oakLight = Color(0xFF7A5536);
const oakIvory = Color(0xFFF7EEDC);

class OakPanel extends StatelessWidget {
  const OakPanel({super.key, this.seed = 3, this.bevel = true});

  final int seed;
  final bool bevel;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _OakPainter(seed: seed, bevel: bevel),
    child: const SizedBox.expand(),
  );
}

class _OakPainter extends CustomPainter {
  const _OakPainter({required this.seed, required this.bevel});

  final int seed;
  final bool bevel;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5A3A26), oak, Color(0xFF41291A)],
        ).createShader(rect),
    );
    final random = Random(seed * 104729 + 7);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // Long grain along the board, darker and lighter streaks.
    final count = max(10, (size.height / 3).round());
    for (var i = 0; i < count; i++) {
      final y = random.nextDouble() * size.height;
      final dark = random.nextBool();
      final amplitude = 0.4 + random.nextDouble() * 1.8;
      final wave = 60 + random.nextDouble() * 160;
      final phase = random.nextDouble() * pi * 2;
      line
        ..color = (dark ? oakDark : oakLight).withValues(alpha: 0.18 + random.nextDouble() * 0.3)
        ..strokeWidth = 0.5 + random.nextDouble() * 1.6;
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width; x += 8) {
        path.lineTo(x, y + sin(x / wave + phase) * amplitude);
      }
      canvas.drawPath(path, line);
    }
    // A couple of oak "rays": short pale flecks across the grain.
    for (var i = 0; i < size.width / 70; i++) {
      final x = random.nextDouble() * size.width, y = random.nextDouble() * size.height;
      line
        ..color = oakLight.withValues(alpha: 0.25)
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(x, y), Offset(x + 6 + random.nextDouble() * 10, y + random.nextDouble() * 1.5), line);
    }
    if (bevel) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 1), Paint()..color = const Color(0x40E8C9A0));
      canvas.drawRect(Rect.fromLTWH(0, size.height - 1.5, size.width, 1.5), Paint()..color = const Color(0x881A0F07));
    }
  }

  @override
  bool shouldRepaint(_OakPainter old) => old.seed != seed || old.bevel != bevel;
}

// The shelf's main action (Continue) as an oak button.
class OakButton extends StatelessWidget {
  const OakButton({super.key, required this.icon, required this.label, required this.onPressed, this.semanticsLabel});

  final IconData icon;
  final String label;
  final String? semanticsLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticsLabel ?? label,
    excludeSemantics: true,
    child: Material(
      elevation: 4,
      shadowColor: Colors.black54,
      color: oak,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF2A190D), width: 1),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: OakPanel(seed: 11, bevel: false)),
          InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: oakIvory),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(color: oakIvory, fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// Ivory icons, text and slider for content placed on oak.
ThemeData onOak(ThemeData base) => base.copyWith(
  iconTheme: const IconThemeData(color: oakIvory),
  iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: oakIvory)),
  textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: oakIvory)),
  textTheme: base.textTheme.apply(bodyColor: oakIvory, displayColor: oakIvory),
  sliderTheme: base.sliderTheme.copyWith(
    activeTrackColor: oakIvory,
    inactiveTrackColor: oakIvory.withValues(alpha: 0.3),
    thumbColor: oakIvory,
    overlayColor: oakIvory.withValues(alpha: 0.15),
  ),
);

// A bar (reader controls) on oak, with ivory content.
class OakBar extends StatelessWidget {
  const OakBar({super.key, required this.child, this.seed = 5});

  final Widget child;
  final int seed;

  @override
  Widget build(BuildContext context) => Material(
    color: oak,
    child: Stack(
      children: [
        Positioned.fill(child: OakPanel(seed: seed)),
        Theme(data: onOak(Theme.of(context)), child: child),
      ],
    ),
  );
}
