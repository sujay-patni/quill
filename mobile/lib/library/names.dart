// Title and author guessed from a file name. Ported from the Android prototype (Library.kt).
// - "Title - Author.epub" is title-first.
// - "Last, First - Title.pdf" is author-first.
// - A lowercase category lead ("drug - Author - Title.pdf") is dropped, and what follows is author-first.
// - A punctuation-only part ("! - Title.pdf") means "no author": the title is what follows it.
// - Comics keep every part (the part after " - " is usually the volume) but lose release tags
//   ("(2 covers) (digital) (group)"). A trailing download marker like " (1)" is dropped.
import 'dart:convert';

import 'package:crypto/crypto.dart';

const bookExtensions = {'epub', 'pdf', 'cbr', 'cbz'};
const comicExtensions = {'cbr', 'cbz'};

final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);
// A download site's tag before the name ("_Example.com_Title.epub").
final _sitePrefix = RegExp(r'^_?[A-Za-z0-9-]+\.(?:com|net|org|info|io|co|in|me)_', caseSensitive: false);

String extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

String _withoutExtension(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? name : name.substring(0, dot);
}

bool _hasText(String part) => _letterOrDigit.hasMatch(part);

class NameParts {
  const NameParts(this.title, this.author);
  final String title;
  final String author;
}

NameParts nameParts(String name) {
  final comic = comicExtensions.contains(extensionOf(name));
  var base = _withoutExtension(name).replaceFirst(_sitePrefix, '').replaceAll('_', ' ');
  base = comic
      ? base
            .replaceFirst(RegExp(r'\s*\(digital\).*$', caseSensitive: false), '')
            .replaceAll(RegExp(r'\s*\(\d+ covers?\)', caseSensitive: false), '')
      : base.replaceFirst(RegExp(r'\s+\(\d\)$'), '');
  base = base.replaceAll(RegExp(r'\s+'), ' ').trim();
  var parts = base.split(' - ').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  if (comic) {
    final kept = parts.skipWhile((p) => !_hasText(p)).join(' - ');
    return NameParts(kept.isEmpty ? base : kept, '');
  }
  final category = parts.length >= 3 && RegExp(r'^[a-z]+$').hasMatch(parts[0]);
  if (category) parts = parts.sublist(1);
  final bare = parts.lastIndexWhere((p) => !_hasText(p));
  final lastFirst =
      parts.length >= 2 && RegExp(r'^[^,]+, [^,]+$').hasMatch(parts[0]) && parts[0].split(' ').length <= 4;
  String title;
  String author;
  if (bare >= 0) {
    title = parts.sublist(bare + 1).join(' - ');
    author = '';
  } else if (category || lastFirst) {
    title = parts.sublist(1).join(' - ');
    author = parts[0];
  } else {
    title = parts.isEmpty ? '' : parts.first;
    author = parts.length == 2 ? parts[1] : '';
  }
  final names = author.split(', ');
  final person = names.length == 2 ? '${names[1]} ${names[0]}' : author;
  return NameParts(title.isEmpty ? base : title, person);
}

String displayTitle(String name) => nameParts(name).title;
String displayAuthor(String name) => nameParts(name).author;

// The rule up to commit 21d8d4f: first part only (comics: all parts), "!" leads dropped.
String legacyTitle(String name) {
  final base = _withoutExtension(name).replaceFirst(_sitePrefix, '').replaceAll('_', ' ').trim();
  final parts = base.split(' - ').map((p) => p.trim()).skipWhile((p) => !_hasText(p)).toList();
  if (parts.isEmpty) return base;
  return comicExtensions.contains(extensionOf(name)) ? parts.join(' - ') : parts.first;
}

// On rescan, replace only titles an earlier file-name rule produced ("!", a comic missing its
// volume, or the legacy first-part guess). EPUB metadata and imported titles are kept.
String refreshedTitle(String saved, String name) {
  final derived = displayTitle(name);
  if (!_hasText(saved) ||
      saved == legacyTitle(name) ||
      (derived.length > saved.length && derived.startsWith('$saved - '))) {
    return derived;
  }
  return saved;
}

String stableId(String value) => sha256.convert(utf8.encode(value)).toString();

String canonicalPath(String path) => path
    .replaceAll('\\', '/')
    .replaceFirst(RegExp(r'^/(storage/emulated/0|sdcard)/'), '')
    .replaceFirst(RegExp(r'^primary:'), '')
    .replaceAll(RegExp(r'^/+|/+$'), '')
    .toLowerCase();

// Natural order for comic page names: "page2" before "page10".
int naturalCompare(String a, String b) {
  final chunks = RegExp(r'[0-9]+|[^0-9]+');
  final x = chunks.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final y = chunks.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    final u = x[i], v = y[i];
    int result;
    if (_isDigit(u) && _isDigit(v)) {
      final un = u.replaceFirst(RegExp(r'^0+'), '').padLeft(1, '0');
      final vn = v.replaceFirst(RegExp(r'^0+'), '').padLeft(1, '0');
      result = un.length != vn.length ? un.length.compareTo(vn.length) : un.compareTo(vn);
    } else {
      result = u.compareTo(v);
    }
    if (result != 0) return result;
  }
  return x.length != y.length ? x.length.compareTo(y.length) : a.compareTo(b);
}

bool _isDigit(String s) => s.codeUnitAt(0) >= 48 && s.codeUnitAt(0) <= 57;

// Title and author from the book's own metadata. They replace only guesses made from the file
// name; a title or author the user (or an import) set is kept.
String metadataTitle(String saved, String fileName, String? fromBook) {
  final value = fromBook?.trim() ?? '';
  final raw = _withoutExtension(fileName).trim();
  if (value.isEmpty || !_hasText(value) || value == raw) return saved;
  final guessed = saved == displayTitle(fileName) || saved == legacyTitle(fileName) || !_hasText(saved);
  return guessed ? value : saved;
}

String metadataAuthor(String saved, String fileName, List<String> fromBook) {
  final names = <String>[];
  for (final n in fromBook.map((n) => n.trim())) {
    if (n.isNotEmpty && !names.contains(n)) names.add(n);
  }
  if (names.isEmpty) return saved;
  return saved.isEmpty || saved == displayAuthor(fileName) ? names.join(', ') : saved;
}

// An ISBN-13 or ISBN-10 from a book identifier such as "urn:isbn:9780000000000"; '' if none.
String isbnFrom(String? identifier) {
  final raw = (identifier ?? '').toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  final m13 = RegExp(r'97[89]\d{10}').firstMatch(raw);
  if (m13 != null && _isbn13Valid(m13[0]!)) return m13[0]!;
  final m10 = RegExp(r'(?<!\d)\d{9}[\dX](?!\d)').firstMatch(raw);
  if (m10 != null && _isbn10Valid(m10[0]!)) return m10[0]!;
  return '';
}

bool _isbn13Valid(String s) {
  var sum = 0;
  for (var i = 0; i < 13; i++) {
    sum += int.parse(s[i]) * (i.isEven ? 1 : 3);
  }
  return sum % 10 == 0;
}

bool _isbn10Valid(String s) {
  var sum = 0;
  for (var i = 0; i < 10; i++) {
    sum += (s[i] == 'X' ? 10 : int.parse(s[i])) * (10 - i);
  }
  return sum % 11 == 0;
}
