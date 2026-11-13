import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

// Diagnostic: the last few hundred saved reading positions, in Quill's own storage
// (positions.log, one JSON line each). Kept to investigate a saved position that once fell
// back to its chapter start on the phone (HANDOFF.md). Holds no book text, only locations.
class PositionLog {
  PositionLog._();

  static const _keep = 300;
  static Future<void> _writes = Future.value();

  static void record(String bookId, String event, Map<String, Object?> locator) {
    final line = jsonEncode({'at': DateTime.now().toIso8601String(), 'book': bookId, 'event': event, ...locator});
    _writes = _writes.then((_) async {
      try {
        final file = File('${(await getApplicationSupportDirectory()).path}/positions.log');
        final lines = await file.exists() ? await file.readAsLines() : <String>[];
        lines.add(line);
        await file.writeAsString('${lines.skip(lines.length > _keep ? lines.length - _keep : 0).join('\n')}\n');
      } catch (_) {
        // Diagnostics never get in the way of reading.
      }
    });
  }
}
