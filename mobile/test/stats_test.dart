import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quill/library/stats.dart';

void main() {
  final t0 = DateTime(2026, 11, 5, 20, 0);
  DateTime at(int minutes, [int seconds = 0]) => t0.add(Duration(minutes: minutes, seconds: seconds));

  group('reading timer', () {
    test('counts active time and page turns, stops at last activity when idle', () {
      final timer = ReadingTimer();
      timer.activity(at(0));
      timer.activity(at(1), pageTurn: true);
      timer.activity(at(2), pageTurn: true);
      final spans = timer.stop(at(30)); // put down after minute 2
      expect(spans, hasLength(1));
      expect(spans.single.duration, const Duration(minutes: 2));
      expect(spans.single.pages, 2);
    });

    test('a long pause splits the session and is not counted', () {
      final timer = ReadingTimer();
      timer.activity(at(0));
      timer.activity(at(1), pageTurn: true);
      timer.activity(at(20), pageTurn: true); // 19 min idle in between
      timer.activity(at(21), pageTurn: true);
      final spans = timer.stop(at(21, 30));
      expect(spans.map((s) => s.duration.inSeconds), [60, 90]);
      expect(spans.map((s) => s.pages), [1, 2]);
    });

    test('short peeks are dropped', () {
      final timer = ReadingTimer();
      timer.activity(at(0));
      expect(timer.stop(at(0, 5)), isEmpty);
    });
  });

  group('stats', () {
    test('spans crossing midnight are split by local day', () {
      final span = ReadingSpan(DateTime(2026, 11, 5, 23, 50), DateTime(2026, 11, 6, 0, 20), 3);
      final shares = msByDay(span);
      expect(shares.values.map((ms) => ms ~/ 60000), [10, 20]);
      final stats = ReadingStats()..record('b', span, progressAtEnd: 0.4);
      expect(stats.daysFor('b').map((d) => d.pages), [3, 0]);
      expect(stats.daysFor('b').last.progressAtEnd, 0.4);
    });

    test('summary: totals, books, streaks and periods', () {
      final today = dayOf(DateTime(2026, 11, 5));
      final stats = ReadingStats({
        'a': [
          for (final d in [today - 5, today - 4, today - 3]) ReadingDay(day: d, ms: 600000, pages: 10),
        ],
        'b': [ReadingDay(day: today - 1, ms: 1200000, pages: 20), ReadingDay(day: today, ms: 300000, pages: 5)],
      });
      final all = stats.summary(today: today);
      expect(all.ms, 3300000);
      expect(all.daysRead, 5);
      expect(all.books, 2);
      expect(all.pages, 55);
      expect(all.currentStreak, 2);
      expect(all.longestStreak, 3);
      expect(stats.summary(from: today - 1, to: today, today: today).books, 1);
      expect(stats.booksByTime().map((e) => e.key), ['a', 'b']);
      expect(stats.msPerDay(from: today, to: today), {today: 300000});
    });

    test('a streak is still current if the last read was yesterday', () {
      final today = dayOf(DateTime(2026, 11, 5));
      final stats = ReadingStats({
        'a': [ReadingDay(day: today - 2, ms: 1), ReadingDay(day: today - 1, ms: 1)],
      });
      expect(stats.summary(today: today).currentStreak, 2);
      // Last read two days before: the streak has broken.
      expect(stats.summary(today: today + 1).currentStreak, 0);
    });

    test('replacing one source keeps the other; resets are scoped', () {
      final stats = ReadingStats()
        ..replaceSource('a', 'moon-reader', [const ReadingDay(day: 10, ms: 5, source: 'moon-reader', wordsImported: 9)])
        ..record('a', ReadingSpan(DateTime(2026, 1, 1, 10), DateTime(2026, 1, 1, 10, 5), 1))
        ..replaceSource('a', 'moon-reader', [const ReadingDay(day: 11, ms: 7, source: 'moon-reader')]);
      expect(stats.daysFor('a').map((d) => d.source).toSet(), {'quill', 'moon-reader'});
      expect(stats.daysFor('a').where((d) => d.source == 'moon-reader').single.day, 11);
      stats.record('b', ReadingSpan(DateTime(2026, 1, 1, 10), DateTime(2026, 1, 1, 10, 5), 1));
      stats.resetBook('a');
      expect(stats.byBook.keys, ['b']);
      stats.resetAll();
      expect(stats.byBook, isEmpty);
    });

    test('saves and loads', () async {
      final dir = await Directory.systemTemp.createTemp('quill-stats');
      final file = File('${dir.path}/stats.json');
      final stats = ReadingStats({
        'a': [const ReadingDay(day: 3, ms: 4, pages: 5, wordsImported: 6, progressAtEnd: 0.5, source: 'moon-reader')],
      });
      await stats.save(file);
      final back = await ReadingStats.load(file);
      expect(back.toJson(), stats.toJson());
      expect((await ReadingStats.load(File('${dir.path}/missing.json'))).byBook, isEmpty);
    });

    test('durations read naturally', () {
      expect(formatDuration(59000), '0m');
      expect(formatDuration(45 * 60000), '45m');
      expect(formatDuration(120 * 60000), '2h');
      expect(formatDuration(135 * 60000), '2h 15m');
    });
  });
}
