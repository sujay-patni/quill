import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'position_log.dart';

// Quill Dev builds only (debug and profile): frame smoothness while a book is open, written to
// positions.log every 10 s as `frames` events. Measure in a profile build — debug (JIT) frames
// are slower than the real app. No book text, only counts and milliseconds.
class PerfLog {
  PerfLog._();

  static bool get enabled => !kReleaseMode;
  static String get mode => kProfileMode ? 'profile' : 'debug';

  static String? _book;
  static final List<int> _worstUs = []; // per frame: max(build, raster) in microseconds
  static int _missed = 0;
  static DateTime _since = DateTime.now();

  static void start(String bookId) {
    if (!enabled) return;
    stop();
    _book = bookId;
    _since = DateTime.now();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void stop() {
    if (_book == null) return;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _flush();
    _book = null;
  }

  static double get _budgetUs {
    final views = PlatformDispatcher.instance.views;
    final rate = views.isEmpty ? 60.0 : views.first.display.refreshRate;
    return 1e6 / (rate > 0 ? rate : 60.0);
  }

  static void _onTimings(List<FrameTiming> timings) {
    final budget = _budgetUs;
    for (final t in timings) {
      final us = max(t.buildDuration.inMicroseconds, t.rasterDuration.inMicroseconds);
      _worstUs.add(us);
      if (us > budget) _missed++;
    }
    if (DateTime.now().difference(_since) >= const Duration(seconds: 10)) _flush();
  }

  static void _flush() {
    final book = _book;
    if (book == null || _worstUs.isEmpty) return;
    final sorted = [..._worstUs]..sort();
    PositionLog.record(book, 'frames', summary(sorted, _missed, _budgetUs, mode));
    _worstUs.clear();
    _missed = 0;
    _since = DateTime.now();
  }

  /// The logged fields, from per-frame costs in microseconds (sorted ascending).
  @visibleForTesting
  static Map<String, Object?> summary(List<int> sortedUs, int missed, double budgetUs, String mode) => {
    'mode': mode,
    'frames': sortedUs.length,
    'missed': missed,
    'budgetMs': (budgetUs / 1000).toStringAsFixed(1),
    'p50Ms': (sortedUs[sortedUs.length ~/ 2] / 1000).toStringAsFixed(1),
    'p90Ms': (sortedUs[min(sortedUs.length - 1, (sortedUs.length * 0.9).floor())] / 1000).toStringAsFixed(1),
    'worstMs': (sortedUs.last / 1000).toStringAsFixed(1),
  };
}
