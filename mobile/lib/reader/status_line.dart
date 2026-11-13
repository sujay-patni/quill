import 'package:flutter/material.dart';

// Moon Reader's footer: time left on the page itself, then a slightly darker band with battery,
// clock, chapter (page in chapter) and page in book.
class StatusLine extends StatelessWidget {
  const StatusLine({
    super.key,
    required this.chapter,
    required this.ink,
    required this.page,
    this.chapterPage,
    this.chapterPages,
    this.position,
    this.positions,
    this.chapterMinutes,
    this.bookMinutes,
    this.battery,
  });

  final String chapter;
  final Color ink;
  final Color page;
  final int? chapterPage;
  final int? chapterPages;
  final int? position;
  final int? positions;
  final int? chapterMinutes;
  final int? bookMinutes;
  final int? battery;

  static String _duration(int minutes) {
    if (minutes < 60) return '$minutes min${minutes == 1 ? '' : 's'}';
    final h = minutes ~/ 60, m = minutes % 60;
    return '$h hr${h == 1 ? '' : 's'}${m == 0 ? '' : ' $m min${m == 1 ? '' : 's'}'}';
  }

  @override
  Widget build(BuildContext context) {
    final small = TextStyle(fontSize: 12.5, color: ink.withValues(alpha: 0.82), height: 1.2);
    final bold = small.copyWith(fontWeight: FontWeight.w700, color: ink.withValues(alpha: 0.9));
    final band = Color.lerp(page, ink, 0.16)!;
    final chapterText = [
      if (chapter.isNotEmpty) chapter,
      if (chapterPage != null && chapterPages != null && chapterPages! > 0) '($chapterPage/$chapterPages)',
    ].join(' ');
    return Column(
      key: const Key('statusLine'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(5, 0, 5, 1),
          child: Row(
            children: [
              // Keep this line laid out while Readium's page counts are arriving. Otherwise
              // the first estimate shortens the reading view and re-paginates the book.
              Expanded(
                child: Text(
                  chapterMinutes == null ? ' ' : '${_duration(chapterMinutes!)} left in chapter',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small,
                ),
              ),
              Expanded(
                child: Text(
                  bookMinutes == null ? ' ' : '${_duration(bookMinutes!)} left in book',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: small,
                ),
              ),
            ],
          ),
        ),
        ColoredBox(
          color: band,
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 18,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    if (battery != null) ...[
                      BatteryIcon(level: battery!, color: ink.withValues(alpha: 0.85)),
                      const SizedBox(width: 4),
                    ],
                    Text(TimeOfDay.now().format(context), style: bold),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        chapterText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: small,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (position != null && positions != null) Text('$position/$positions', style: bold),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// A small battery outline with the level written inside, as in Moon Reader.
class BatteryIcon extends StatelessWidget {
  const BatteryIcon({super.key, required this.level, required this.color});

  final int level;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 2, height: 5, color: color),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          '$level',
          style: TextStyle(fontSize: 10.5, height: 1.15, color: color, fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}
