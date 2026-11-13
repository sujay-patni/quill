// Builds and keeps cover thumbnails in Quill's own storage. Book files are only read.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'book.dart';
import 'covers.dart';

class ZipIndex {
  const ZipIndex(this.names, this.texts);
  final List<String> names;
  final Map<String, String> texts;
}

// Platform access to a book's bytes.
abstract class CoverSource {
  Future<ZipIndex> zipIndex(String uri);
  Future<bool> zipImage(String uri, String entry, File out);
  Future<bool> pdfImage(String uri, File out);

  /// The first page of a CBR comic. Only Android can read RAR archives.
  Future<bool> cbrImage(String uri, File out) async => false;

  static CoverSource forPlatform() => Platform.isAndroid ? AndroidCoverSource() : FileCoverSource();
}

// Android reads content:// URIs natively and writes downscaled JPEGs.
class AndroidCoverSource implements CoverSource {
  static const _channel = MethodChannel('app.quill/covers');
  static const maxWidth = 480;

  @override
  Future<ZipIndex> zipIndex(String uri) async {
    final m = await _channel.invokeMapMethod<String, Object?>('zipIndex', {'uri': uri}) ?? const {};
    return ZipIndex(
      [for (final n in (m['names'] as List? ?? const [])) n as String],
      {for (final e in ((m['texts'] as Map?) ?? const {}).entries) e.key as String: e.value as String},
    );
  }

  @override
  Future<bool> zipImage(String uri, String entry, File out) async =>
      await _channel.invokeMethod<bool>('zipImage', {
        'uri': uri,
        'entry': entry,
        'out': out.path,
        'maxWidth': maxWidth,
      }) ??
      false;

  @override
  Future<bool> pdfImage(String uri, File out) async =>
      await _channel.invokeMethod<bool>('pdfImage', {'uri': uri, 'out': out.path, 'maxWidth': maxWidth}) ?? false;

  @override
  Future<bool> cbrImage(String uri, File out) async =>
      await _channel.invokeMethod<bool>('cbrImage', {'uri': uri, 'out': out.path, 'maxWidth': maxWidth}) ?? false;
}

// iOS (and tests): books are plain files inside the granted folder. The image is stored as
// found; the shelf decodes it at thumbnail size. PDF thumbnails need native rendering (later).
class FileCoverSource extends CoverSource {
  String _path(String uri) => uri.startsWith('file://') ? Uri.parse(uri).toFilePath() : uri;

  @override
  Future<ZipIndex> zipIndex(String uri) async {
    final input = InputFileStream(_path(uri));
    try {
      final archive = ZipDecoder().decodeStream(input);
      final names = <String>[];
      final texts = <String, String>{};
      for (final f in archive.files) {
        if (!f.isFile) continue;
        names.add(f.name);
        final lower = f.name.toLowerCase();
        if ((lower == 'meta-inf/container.xml' || lower.endsWith('.opf')) && f.size < (2 << 20)) {
          texts[f.name] = utf8.decode(f.readBytes() ?? const [], allowMalformed: true);
        }
      }
      return ZipIndex(names, texts);
    } finally {
      await input.close();
    }
  }

  @override
  Future<bool> zipImage(String uri, String entry, File out) async {
    final input = InputFileStream(_path(uri));
    try {
      final file = ZipDecoder().decodeStream(input).findFile(entry);
      final bytes = file?.readBytes();
      if (bytes == null || bytes.isEmpty) return false;
      final temp = File('${out.path}.tmp');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(out.path);
      return true;
    } finally {
      await input.close();
    }
  }

  @override
  Future<bool> pdfImage(String uri, File out) async => false;
}

// Picks a book's cover entry from its archive index (EPUB declared cover, else a fallback).
String? coverEntryFor(Book book, ZipIndex index) {
  if (book.format == 'EPUB') {
    final container = index.texts.entries
        .firstWhere((e) => e.key.toLowerCase() == 'meta-inf/container.xml', orElse: () => const MapEntry('', ''))
        .value;
    final opf = opfPath(container) ?? index.names.firstWhere((n) => n.toLowerCase().endsWith('.opf'), orElse: () => '');
    final opfXml = index.texts[opf];
    if (opf.isNotEmpty && opfXml != null) {
      final declared = epubCoverEntry(opf, opfXml, index.names.toSet());
      if (declared != null) return declared;
    }
    return fallbackCoverEntry(index.names);
  }
  return fallbackCoverEntry(index.names, preferCoverName: false);
}

class CoverStore extends ChangeNotifier {
  CoverStore({required this.directory, CoverSource? source}) : _source = source ?? CoverSource.forPlatform();

  // Quill's storage root; covers live in its `covers/` folder.
  final Future<Directory> Function() directory;
  final CoverSource _source;
  Directory? _dir;
  final Set<String> _ready = {};
  // Books without a usable cover, keyed by id → "size:modified", so a changed file is retried.
  Map<String, String> _failed = {};
  bool _building = false;
  int done = 0;
  int total = 0;

  bool get building => _building;
  // Covers the user chose (an image or a page of the book), in covers/custom/<id>-<time>.jpg.
  // A new file name per change, so a cached image of the old cover is never shown. Building
  // covers never replaces these.
  final Map<String, String> _custom = {};

  bool has(String id) => _custom.containsKey(id) || _ready.contains(id);
  bool isCustom(String id) => _custom.containsKey(id);
  Iterable<String> get customIds => _custom.keys;
  bool get loaded => _dir != null;
  File fileFor(String id) =>
      _custom[id] != null ? File('${_dir!.path}/custom/${_custom[id]}') : File('${_dir!.path}/$id.jpg');

  Future<void> setCustom(String id, File jpeg) async {
    final dir = Directory('${_dir!.path}/custom');
    await dir.create(recursive: true);
    final name = '$id-${DateTime.now().millisecondsSinceEpoch}.jpg';
    await jpeg.copy('${dir.path}/$name');
    final old = _custom[id];
    _custom[id] = name;
    if (old != null) await _deleteQuietly(File('${dir.path}/$old'));
    notifyListeners();
  }

  // Back to the book's own cover (or the generated title card).
  Future<void> clearCustom(String id) async {
    final old = _custom.remove(id);
    if (old != null) await _deleteQuietly(File('${_dir!.path}/custom/$old'));
    notifyListeners();
  }

  static Future<void> _deleteQuietly(File f) async {
    try {
      await f.delete();
    } catch (_) {}
  }

  Future<void> load() async {
    final dir = Directory('${(await directory()).path}/covers');
    await dir.create(recursive: true);
    _dir = dir;
    await for (final f in dir.list()) {
      final name = f.uri.pathSegments.last;
      if (name.endsWith('.jpg')) _ready.add(name.substring(0, name.length - 4));
    }
    final custom = Directory('${dir.path}/custom');
    if (await custom.exists()) {
      await for (final f in custom.list()) {
        final name = f.uri.pathSegments.last;
        final cut = name.lastIndexOf('-');
        if (!name.endsWith('.jpg') || cut <= 0) continue;
        final id = name.substring(0, cut);
        // Keep the newest if an interrupted change left two.
        if (_custom[id] == null || _custom[id]!.compareTo(name) < 0) _custom[id] = name;
      }
    }
    try {
      _failed = Map<String, String>.from(jsonDecode(await File('${dir.path}/failed.json').readAsString()) as Map);
    } catch (_) {
      _failed = {};
    }
    notifyListeners();
  }

  static String _stamp(Book b) => '${b.size}:${b.modified}';

  bool _wanted(Book b) => !b.missing && !_ready.contains(b.id) && _failed[b.id] != _stamp(b);

  // Builds missing covers one book at a time. Safe to call again; a running build continues.
  Future<void> build(List<Book> books) async {
    if (_building || _dir == null) return;
    final todo = books.where(_wanted).toList();
    if (todo.isEmpty) {
      done = total = 0;
      return;
    }
    _building = true;
    done = 0;
    total = todo.length;
    notifyListeners();
    try {
      for (final book in todo) {
        final ok = await _buildOne(book);
        if (ok) {
          _ready.add(book.id);
          _failed.remove(book.id);
        } else {
          _failed[book.id] = _stamp(book);
        }
        done++;
        if (done % 8 == 0 || done == total) notifyListeners();
      }
      await File('${_dir!.path}/failed.json').writeAsString(jsonEncode(_failed));
    } finally {
      _building = false;
      notifyListeners();
    }
  }

  Future<bool> _buildOne(Book book) async {
    final out = fileFor(book.id);
    try {
      if (book.format == 'PDF') return await _source.pdfImage(book.uri, out);
      if (book.format == 'CBR') return await _source.cbrImage(book.uri, out);
      final index = await _source.zipIndex(book.uri);
      final entry = coverEntryFor(book, index);
      return entry != null && await _source.zipImage(book.uri, entry, out);
    } catch (e) {
      debugPrint('Quill cover failed for ${book.format}: $e');
      return false;
    }
  }
}
