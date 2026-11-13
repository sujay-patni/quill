// Saving a file where the reader chooses and picking one to read, through the system pickers
// (so Drive and other providers work). Files cross the channel as paths in Quill's own cache,
// never as bytes.
import 'dart:io';

import 'package:flutter/services.dart';

class BackupFiles {
  const BackupFiles();
  static const _channel = MethodChannel('app.quill/backup');

  /// Asks where to save [source] (suggesting [name]) and copies it there. False when cancelled.
  Future<bool> save(File source, String name, String mime) async =>
      await _channel.invokeMethod<bool>('save', {'path': source.path, 'name': name, 'mime': mime}) ?? false;

  /// Asks for a file and returns a private copy of it; null when cancelled.
  Future<File?> open() async {
    final path = await _channel.invokeMethod<String>('open');
    return path == null ? null : File(path);
  }

  /// Opens a web page outside Quill. False when nothing on the phone can open it.
  Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
    } catch (_) {
      return false;
    }
  }
}
