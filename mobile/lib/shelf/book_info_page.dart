import 'package:flutter/material.dart';

import '../library/backup_files.dart';
import '../library/goodreads.dart';
import '../library/book.dart';
import '../library/library.dart';
import '../library/shelf.dart';
import '../library/stats.dart';
import 'custom_cover.dart';
import 'rating_stars.dart';
import '../oak.dart';

// Everything Quill knows about one book, editable in place.
class BookInfoPage extends StatelessWidget {
  const BookInfoPage({super.key, required this.library, required this.bookId});

  final Library library;
  final String bookId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([library, library.covers]),
      builder: (context, _) {
        final b = library.books.firstWhere((x) => x.id == bookId);
        final text = Theme.of(context).textTheme;
        final days = library.stats.daysFor(b.id);
        final summary = library.stats.summary(books: {b.id});
        return Scaffold(
          appBar: AppBar(
            flexibleSpace: const OakPanel(),
            title: const Text('Book information'),
            actions: [
              PopupMenuButton<String>(
                key: const Key('bookMenu'),
                onSelected: (v) => switch (v) {
                  'progress' => _confirm(
                    context,
                    'Reset reading progress?',
                    'Position, percentage and finished status are cleared. Stats, rating and details stay. '
                        'A backup is taken first.',
                    () => library.resetProgress(b.id),
                  ),
                  'stats' => _confirm(
                    context,
                    'Reset this book\'s statistics?',
                    'Reading time and days for this book are cleared. A backup is taken first.',
                    () => library.resetBookStats(b.id),
                  ),
                  'goodreads' => const BackupFiles().openUrl(goodreadsUrl(b)),
                  _ => null,
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'goodreads', key: Key('bookGoodreads'), child: Text('Open in Goodreads')),
                  PopupMenuItem(value: 'progress', key: Key('resetProgress'), child: Text('Reset progress')),
                  PopupMenuItem(value: 'stats', key: Key('resetStats'), child: Text('Reset statistics')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tap the cover to choose your own (an image or a page of the book).
                  GestureDetector(
                    key: const Key('bookCover'),
                    onTap: () => showCoverOptions(context, library, b.id),
                    child: SizedBox(
                      width: 76,
                      height: 114,
                      child: library.covers.has(b.id)
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: Image.file(library.covers.fileFor(b.id), fit: BoxFit.cover, cacheWidth: 240),
                            )
                          : ColoredBox(
                              color: Theme.of(context).colorScheme.secondaryContainer,
                              child: Center(child: Text(b.format, style: text.labelSmall)),
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: [
                        _Field(
                          label: 'Title',
                          value: b.title,
                          onSave: (v) => library.edit(b.id, {'title'}, (x) => x.copyWith(title: v)),
                        ),
                        _Field(
                          label: 'Author',
                          value: b.author,
                          onSave: (v) => library.edit(b.id, {'author'}, (x) => x.copyWith(author: v)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  RatingStars(
                    rating: b.rating,
                    size: 22,
                    onChanged: (r) => library.edit(b.id, {'rating'}, (x) => x.copyWith(rating: r)),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: b.favorite,
                        visualDensity: VisualDensity.compact,
                        onChanged: (v) => library.edit(b.id, {'favorite'}, (x) => x.copyWith(favorite: v ?? false)),
                      ),
                      const Text('Favourite'),
                    ],
                  ),
                ],
              ),
              _Field(
                label: 'Description',
                value: b.description,
                maxLines: 4,
                onSave: (v) => library.edit(b.id, {'description'}, (x) => x.copyWith(description: v)),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Field(
                      label: 'Series',
                      value: b.series,
                      onSave: (v) => library.edit(b.id, {'series'}, (x) => x.copyWith(series: v)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 90,
                    child: _Field(
                      label: 'Number',
                      value: b.seriesIndex == null ? '' : _number(b.seriesIndex!),
                      keyboard: const TextInputType.numberWithOptions(decimal: true),
                      onSave: (v) => library.edit(b.id, {
                        'seriesIndex',
                      }, (x) => x.copyWith(seriesIndex: double.tryParse(v.trim()))),
                    ),
                  ),
                ],
              ),
              _Field(
                label: 'Universe',
                value: b.universe,
                onSave: (v) => library.edit(b.id, {'universe'}, (x) => x.copyWith(universe: v.trim())),
              ),
              _OrderChips(library: library, bookId: b.id),
              _Field(
                label: 'Tags (comma separated)',
                value: b.tags.join(', '),
                onSave: (v) => library.edit(
                  b.id,
                  {'tags'},
                  (x) => x.copyWith(
                    tags: [
                      for (final t in v.split(','))
                        if (t.trim().isNotEmpty) t.trim(),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(_statusLine(b), key: const Key('statusLine'), style: text.bodyMedium),
                  ),
                  TextButton(
                    key: const Key('toggleFinished'),
                    onPressed: () => library.setFinished(b.id, !b.finished),
                    child: Text(b.finished ? 'Mark unread' : 'Mark finished'),
                  ),
                ],
              ),
              const Divider(height: 24),
              Text('Reading', style: text.titleSmall),
              const SizedBox(height: 4),
              _Row('Progress', '${(b.progress * 100).round()}%${b.approximate ? ' (approximate)' : ''}'),
              _Row('Time read', formatDuration(summary.ms)),
              _Row('Days read', '${summary.daysRead}'),
              if (summary.daysRead > 0) _Row('Average per day', formatDuration(summary.ms ~/ summary.daysRead)),
              if (summary.pages > 0) _Row('Pages turned', '${summary.pages}'),
              if (days.any((d) => d.wordsImported != null))
                _Row('Words (Moon Reader)', '${days.fold<int>(0, (s, d) => s + (d.wordsImported ?? 0))}'),
              if (b.startedAt > 0) _Row('Started', _date(b.startedAt)),
              if (b.finishedAt > 0) _Row('Finished', _date(b.finishedAt)),
              const Divider(height: 24),
              Text('File', style: text.titleSmall),
              const SizedBox(height: 4),
              _Row('Name', b.name),
              if (b.folder.isNotEmpty) _Row('Folder', b.folder),
              _Row('Format', b.format),
              _Row('Size', _size(b.size)),
              if (b.isbn.isNotEmpty) _Row('ISBN', b.isbn),
              if (b.missing) const _Row('Status', 'Missing from your Books folder'),
            ],
          ),
        );
      },
    );
  }

  static String _statusLine(Book b) => switch (statusOf(b)) {
    ReadStatus.finished => b.finishedAt > 0 ? 'Finished ${_date(b.finishedAt)}' : 'Finished',
    ReadStatus.reading => 'Reading · ${(b.progress * 100).round()}%',
    _ => 'Unread',
  };

  static String _number(double n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  static String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  static String _size(int bytes) =>
      bytes >= 1 << 20 ? '${(bytes / (1 << 20)).toStringAsFixed(1)} MB' : '${(bytes / 1024).ceil()} KB';

  static Future<void> _confirm(BuildContext context, String title, String body, Future<void> Function() action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('confirmReset'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok == true) await action();
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 140, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

// A text field that saves when editing finishes (keyboard done or focus leaves).
class _Field extends StatefulWidget {
  const _Field({required this.label, required this.value, required this.onSave, this.maxLines = 1, this.keyboard});

  final String label;
  final String value;
  final ValueChanged<String> onSave;
  final int maxLines;
  final TextInputType? keyboard;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  @override
  void didUpdateWidget(_Field old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.value != widget.value) _controller.text = widget.value;
  }

  void _save() {
    if (_controller.text != widget.value) widget.onSave(_controller.text.trim());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      key: Key('field:${widget.label}'),
      controller: _controller,
      focusNode: _focus,
      maxLines: widget.maxLines,
      minLines: 1,
      keyboardType: widget.keyboard,
      textInputAction: widget.maxLines > 1 ? TextInputAction.newline : TextInputAction.done,
      onSubmitted: (_) => _save(),
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: const UnderlineInputBorder(),
      ),
    ),
  );
}


// The reading orders this book is in, with a way to add it to one (or a new one).
class _OrderChips extends StatelessWidget {
  const _OrderChips({required this.library, required this.bookId});

  final Library library;
  final String bookId;

  Future<void> _add(BuildContext context) async {
    final controller = TextEditingController();
    final others = library.orders.keys.where((n) => !library.orders[n]!.contains(bookId)).toList()..sort();
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Add to reading order'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final n in others)
            ListTile(dense: true, title: Text(n), onTap: () => Navigator.pop(dialog, n)),
          TextField(
            key: const Key('newOrderName'),
            controller: controller,
            decoration: const InputDecoration(labelText: 'New order'),
            onSubmitted: (v) => Navigator.pop(dialog, v),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialog, controller.text), child: const Text('Add')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final ids = library.orders[name.trim()] ?? const <String>[];
    if (!ids.contains(bookId)) await library.setOrder(name.trim(), [...ids, bookId]);
  }

  @override
  Widget build(BuildContext context) {
    final mine = library.orders.keys.where((n) => library.orders[n]!.contains(bookId)).toList()..sort();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Reading orders', style: Theme.of(context).textTheme.bodySmall),
        for (final n in mine)
          InputChip(
            label: Text('$n · ${library.orders[n]!.indexOf(bookId) + 1}'),
            onDeleted: () => library.setOrder(n, [...library.orders[n]!]..remove(bookId)),
          ),
        ActionChip(key: const Key('addToOrder'), avatar: const Icon(Icons.add, size: 18), label: const Text('Add'), onPressed: () => _add(context)),
      ]),
    );
  }
}
