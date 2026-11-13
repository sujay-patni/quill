import 'dart:async';

import 'package:flutter/material.dart';

import 'library/library.dart';
import 'shelf/shelf_page.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final library = Library();
  await library.load();
  runApp(QuillApp(library: library));
  // One automatic backup a day, after the shelf is on screen.
  WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(library.dailyBackup()));
}

class QuillApp extends StatelessWidget {
  const QuillApp({super.key, required this.library});

  final Library library;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quill',
      debugShowCheckedModeBanner: false,
      // The user chose a lighter parchment library; night reading is independent.
      themeMode: ThemeMode.light,
      theme: quillTheme(Brightness.light),
      darkTheme: quillTheme(Brightness.dark),
      home: ShelfPage(library: library),
    );
  }
}
