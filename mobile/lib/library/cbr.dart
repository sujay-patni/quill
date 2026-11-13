// CBR comics are RAR archives, which the reader cannot open. Android rewrites one as a CBZ in
// Quill's cache the first time it is opened (the original is only read) and the reader opens
// that; the most recently read stay cached, up to 1.5 GB.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'book.dart';

const _channel = MethodChannel('app.quill/books');
const _budget = 1500 << 20; // bytes of converted comics kept

/// The cached CBZ for [book] (a CBR), made now if needed. Throws [PlatformException] with a
/// message for the reader when the comic cannot be read (RAR 5, password, not an archive).
Future<File> cbzFor(Book book, {Future<Directory> Function()? cache, void Function()? onConverting}) async {
  final dir = Directory('${(await (cache ?? getApplicationCacheDirectory)()).path}/cbr');
  await dir.create(recursive: true);
  final file = File('${dir.path}/${book.id}-${book.size}-${book.modified}.cbz');
  if (await file.exists()) {
    await file.setLastModified(DateTime.now());
    return file;
  }
  onConverting?.call();
  await _channel.invokeMethod<int>('cbrToCbz', {'uri': book.uri, 'out': file.path});
  // Converted comics are large: keep the newest while they fit in the budget (always this one).
  final all = [
    await for (final e in dir.list())
      if (e is File && e.path.endsWith('.cbz')) e,
  ];
  final times = {for (final f in all) f.path: (await f.lastModified()).millisecondsSinceEpoch};
  all.sort((a, b) => times[b.path]!.compareTo(times[a.path]!));
  var total = 0;
  for (final f in all) {
    total += await f.length();
    if (f.path != file.path && total > _budget) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }
  return file;
}
