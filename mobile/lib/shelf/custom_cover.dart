import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:path_provider/path_provider.dart';

import '../library/library.dart';

// Covers the user chooses, as in Moon Reader: an image from the phone (for example one saved
// from Chrome) or a page of the book. Both are stored as the book's custom cover.
const _covers = MethodChannel('app.quill/covers');
const _coverWidth = 600;

Future<File> _temp() async =>
    File('${(await getTemporaryDirectory()).path}/cover-${DateTime.now().microsecondsSinceEpoch}.jpg');

// Returns false when the picker was cancelled or the image could not be read.
Future<bool> chooseCoverImage(Library library, String bookId) async {
  final uri = await _covers.invokeMethod<String>('pickImage');
  if (uri == null) return false;
  final out = await _temp();
  try {
    final ok =
        await _covers.invokeMethod<bool>('imageFile', {'uri': uri, 'out': out.path, 'maxWidth': _coverWidth}) ?? false;
    if (ok) await library.covers.setCustom(bookId, out);
    return ok;
  } finally {
    if (await out.exists()) await out.delete();
  }
}

// The current EPUB page as the reading engine draws it (paper included).
Future<bool> capturePageAsCover(Library library, String bookId, FlutterReadium readium) async {
  final out = await _temp();
  try {
    final ok = await readium.snapshotPage(out.path, maxWidth: _coverWidth);
    if (ok) await library.covers.setCustom(bookId, out);
    return ok;
  } finally {
    if (await out.exists()) await out.delete();
  }
}

Future<void> showCoverOptions(BuildContext context, Library library, String bookId) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (sheet) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          key: const Key('coverChooseImage'),
          leading: const Icon(Icons.image_outlined),
          title: const Text('Choose an image'),
          subtitle: const Text('From your phone, e.g. one saved from Chrome'),
          onTap: () async {
            Navigator.pop(sheet);
            final messenger = ScaffoldMessenger.of(context);
            try {
              final ok = await chooseCoverImage(library, bookId);
              if (ok) messenger.showSnackBar(const SnackBar(content: Text('Cover updated')));
            } on PlatformException catch (e) {
              messenger.showSnackBar(SnackBar(content: Text('That image could not be used: ${e.message}')));
            }
          },
        ),
        const ListTile(
          leading: Icon(Icons.menu_book_outlined),
          title: Text('Use a page of the book'),
          subtitle: Text('Open the book at that page, then ⋮ → Use this page as cover'),
        ),
        if (library.covers.isCustom(bookId))
          ListTile(
            key: const Key('coverReset'),
            leading: const Icon(Icons.restart_alt),
            title: const Text("Use the book's own cover"),
            onTap: () {
              Navigator.pop(sheet);
              library.covers.clearCustom(bookId);
            },
          ),
      ],
    ),
  ),
);
