import 'package:flutter/material.dart';

import '../library/library.dart';
import '../library/stats.dart';
import 'book_info_page.dart';
import '../oak.dart';

enum StatsPeriod {
  week('Week', 7),
  month('Month', 30),
  year('Year', 365),
  all('All time', 0);

  const StatsPeriod(this.label, this.days);
  final String label;
  final int days;
}

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.library});

  final Library library;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  StatsPeriod _period = StatsPeriod.month;

  @override
  Widget build(BuildContext context) {
    final lib = widget.library;
    final today = dayOf(DateTime.now());
    final from = _period.days == 0 ? null : today - _period.days + 1;
    final summary = lib.stats.summary(from: from, to: today, today: today);
    final finished = lib.books.where((b) {
      if (!b.finished || b.finishedAt == 0) return false;
      return from == null || dayOf(DateTime.fromMillisecondsSinceEpoch(b.finishedAt)) >= from;
    }).length;
    final perDay = lib.stats.msPerDay(from: from, to: today);
    final ranked = lib.stats.booksByTime(from: from, to: today);
    final titles = {for (final b in lib.books) b.id: b.title};
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(flexibleSpace: const OakPanel(), title: const Text('Reading statistics')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<StatsPeriod>(
              showSelectedIcon: false,
              segments: [
                for (final p in StatsPeriod.values)
                  ButtonSegment(value: p, label: Text(p.label, maxLines: 1, softWrap: false)),
              ],
              selected: {_period},
              onSelectionChanged: (s) => setState(() => _period = s.first),
            ),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 24) / 2;
              return Wrap(
                spacing: 24,
                runSpacing: 16,
                children: [
                  _Metric('Time read', formatDuration(summary.ms), width),
                  _Metric('Books finished', '$finished', width),
                  _Metric('Days read', '${summary.daysRead}', width),
                  _Metric(
                    'Current streak',
                    '${summary.currentStreak} day${summary.currentStreak == 1 ? '' : 's'}',
                    width,
                  ),
                  _Metric('Books read in', '${summary.books}', width),
                  _Metric(
                    'Longest streak',
                    '${summary.longestStreak} day${summary.longestStreak == 1 ? '' : 's'}',
                    width,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Text('Minutes per day', style: text.titleSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: perDay.isEmpty
                ? const Center(child: Text('No reading recorded in this period yet.'))
                : _DayChart(perDay: perDay, from: from ?? perDay.keys.reduce((a, b) => a < b ? a : b), to: today),
          ),
          const Divider(height: 28),
          if (ranked.isNotEmpty) Text('Most read', style: text.titleSmall),
          for (final e in ranked.take(10))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(titles[e.key] ?? 'Removed book', maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text(formatDuration(e.value)),
              onTap: titles.containsKey(e.key)
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => BookInfoPage(library: lib, bookId: e.key),
                      ),
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.width);
  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    padding: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 0.7)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w400)),
      ],
    ),
  );
}

// One bar per day in [from, to]; long ranges are grouped into weeks so bars stay readable.
class _DayChart extends StatelessWidget {
  const _DayChart({required this.perDay, required this.from, required this.to});

  final Map<int, int> perDay;
  final int from;
  final int to;

  @override
  Widget build(BuildContext context) {
    final span = to - from + 1;
    final group = span > 120 ? 7 : 1;
    final bars = <double>[];
    for (var start = from; start <= to; start += group) {
      var ms = 0;
      for (var d = start; d < start + group && d <= to; d++) {
        ms += perDay[d] ?? 0;
      }
      bars.add(ms / 60000 / group);
    }
    final peak = bars.fold<double>(1, (m, v) => v > m ? v : m);
    final color = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final v in bars)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: bars.length > 60 ? 0.3 : 1.5),
                    child: FractionallySizedBox(
                      heightFactor: v <= 0 ? 0.01 : (v / peak).clamp(0.03, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: v <= 0 ? color.withValues(alpha: 0.15) : color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Peak ${peak.round()} min${group > 1 ? ' a day (weekly average)' : ''}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
