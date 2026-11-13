import 'package:flutter/material.dart';

// 1–5 stars. Tapping the current rating clears it.
class RatingStars extends StatelessWidget {
  const RatingStars({super.key, required this.rating, this.onChanged, this.size = 32});

  final int rating;
  final ValueChanged<int>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            key: Key('star$i'),
            visualDensity: VisualDensity.compact,
            iconSize: size,
            tooltip: '$i star${i == 1 ? '' : 's'}',
            onPressed: onChanged == null ? null : () => onChanged!(i == rating ? 0 : i),
            icon: Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, color: color),
          ),
      ],
    );
  }
}
