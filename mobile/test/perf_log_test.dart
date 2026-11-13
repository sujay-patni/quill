import 'package:flutter_test/flutter_test.dart';
import 'package:quill/reader/perf_log.dart';

void main() {
  test('frame summary reports median, 90th percentile, worst and misses', () {
    final us = [for (var i = 1; i <= 10; i++) i * 2000]; // 2..20 ms
    final s = PerfLog.summary(us, 2, 8333, 'profile');
    expect(s, {
      'mode': 'profile',
      'frames': 10,
      'missed': 2,
      'budgetMs': '8.3',
      'p50Ms': '12.0',
      'p90Ms': '20.0',
      'worstMs': '20.0',
    });
  });

  test('the log is off in release builds only', () {
    expect(PerfLog.enabled, isTrue, reason: 'tests run in debug mode');
  });
}
