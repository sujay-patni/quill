import 'package:flutter/material.dart';

import '../import/moon_import_page.dart';
import '../library/book.dart';
import '../library/library.dart';
import '../library/shelf.dart';
import '../native/native_reader_page.dart';
import '../reader/reader_page.dart';
import '../reader/reading_profile.dart';
import 'backup_page.dart';
import 'book_info_page.dart';
import 'reading_order_page.dart';
import 'bookcase.dart';
import 'stats_page.dart';
import 'shelf_picker.dart';
import '../oak.dart';

class ShelfPage extends StatefulWidget {
  const ShelfPage({super.key, required this.library});

  final Library library;

  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends State<ShelfPage> {
  String _query = '';
  bool _searching = false;

  Library get lib => widget.library;

  Future<void> _open(Book book) async {
    if (book.missing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This file is no longer in your Books folder. Its notes and position are kept.')),
      );
      return;
    }
    // EPUBs open in Quill's own engine unless the book's own design or the web engine is chosen.
    final profile = await ReadingProfile.load();
    final native = profile.nativeEngine && !profile.publisherStyles && book.format == 'EPUB';
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => native ? NativeReaderPage(library: lib, book: book) : ReaderPage(library: lib, book: book),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([lib, lib.covers]),
      builder: (context, _) {
        final shown = shelfBooks(lib.books, lib.view, lib.filters, _query, orders: lib.orders);
        final resume = continueBook(lib.books);
        // On a series, universe or reading-order shelf: the next unread book in its order.
        final ordered = const {ShelfKind.series, ShelfKind.universes, ShelfKind.orders}.contains(lib.view.kind);
        final next = ordered && lib.filters.sort == SortBy.title
            ? nextToRead(shelfBooks(lib.books, lib.view, const ShelfFilters(), '', orders: lib.orders))
            : null;
        return Scaffold(
          appBar: AppBar(
            flexibleSpace: const OakPanel(),
            title: _searching
                ? TextField(
                    autofocus: true,
                    style: TextStyle(color: Theme.of(context).appBarTheme.foregroundColor),
                    cursorColor: Theme.of(context).appBarTheme.foregroundColor,
                    decoration: InputDecoration(
                      hintText: 'Search title, author, series',
                      hintStyle: TextStyle(
                        color: Theme.of(context).appBarTheme.foregroundColor?.withValues(alpha: 0.6),
                      ),
                      border: InputBorder.none,
                    ),
                    onChanged: (q) => setState(() => _query = q),
                  )
                : ShelfPicker(
                    books: lib.books,
                    view: lib.view,
                    orders: lib.orders,
                    saved: lib.saved,
                    onSaved: (s) => lib.setShelf(view: s.view, filters: s.filters),
                    onSelected: (view) => lib.setShelf(view: view),
                  ),
            actions: [
              IconButton(
                tooltip: _searching ? 'Close search' : 'Search',
                icon: Icon(_searching ? Icons.close : Icons.search),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  _query = '';
                }),
              ),
              IconButton(
                tooltip: 'Filter and sort',
                icon: Badge(isLabelVisible: !lib.filters.isDefault, child: const Icon(Icons.filter_list)),
                onPressed: _showFilters,
              ),
              PopupMenuButton<String>(
                onSelected: (v) => switch (v) {
                  'folder' => lib.chooseFolder(),
                  'rescan' => lib.rescan(),
                  'stats' => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => StatsPage(library: lib))),
                  'layout' => lib.setShelf(compact: !lib.compact),
                  'save' => _saveShelf(),
                  'saved' => _manageSaved(),
                  'order' => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => ReadingOrderPage(library: lib, name: lib.view.value)),
                  ),
                  'backup' => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => BackupPage(library: lib))),
                  'moon' => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => MoonImportPage(library: lib))),
                  _ => null,
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'folder', child: Text('Choose Books folder')),
                  const PopupMenuItem(value: 'rescan', child: Text('Rescan folder')),
                  const PopupMenuItem(value: 'stats', child: Text('Reading statistics')),
                  PopupMenuItem(value: 'layout', child: Text(lib.compact ? 'Bookcase' : 'Compact shelf')),
                  const PopupMenuItem(value: 'moon', child: Text('Import from Moon Reader')),
                  const PopupMenuItem(key: Key('backupMenu'), value: 'backup', child: Text('Backup & restore')),
                  const PopupMenuItem(value: 'save', child: Text('Save this shelf…')),
                  if (lib.saved.isNotEmpty) const PopupMenuItem(value: 'saved', child: Text('Saved shelves')),
                  if (lib.view.kind == ShelfKind.orders)
                    const PopupMenuItem(key: Key('editOrder'), value: 'order', child: Text('Edit reading order')),
                ],
              ),
            ],
            bottom: lib.busy || lib.message.isNotEmpty || lib.covers.building
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(24),
                    child: Column(
                      children: [
                        if (lib.busy) const LinearProgressIndicator(minHeight: 2),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            [
                              lib.message,
                              if (lib.covers.building) 'Covers ${lib.covers.done}/${lib.covers.total}',
                            ].where((t) => t.isNotEmpty).join(' · '),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  )
                : null,
          ),
          body: lib.books.isEmpty
              ? _EmptyShelf(onChoose: lib.chooseFolder, busy: lib.busy)
              : RefreshIndicator(onRefresh: lib.rescan, child: lib.compact ? _list(shown) : _bookcase(shown)),
          floatingActionButton: next != null
              ? OakButton(
                  key: const Key('nextToRead'),
                  onPressed: () => _open(next),
                  icon: Icons.skip_next,
                  label: statusOf(next) == ReadStatus.reading ? 'Continue' : 'Next',
                  semanticsLabel: 'Next to read: ${next.title}',
                )
              : resume == null
              ? null
              : OakButton(
                  key: const Key('continue'),
                  onPressed: () => _open(resume),
                  icon: Icons.menu_book,
                  label: 'Continue',
                  semanticsLabel: 'Continue reading ${resume.title}',
                ),
        );
      },
    );
  }

  Future<void> _saveShelf() async {
    final controller = TextEditingController(text: lib.view.kind == ShelfKind.all ? '' : lib.view.title);
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Save this shelf'),
        content: TextField(
          key: const Key('savedShelfName'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name', helperText: 'Keeps the shelf, filters and sort'),
          onSubmitted: (v) => Navigator.pop(dialog, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialog, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) await lib.saveShelf(name.trim());
  }

  void _manageSaved() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => ListenableBuilder(
        listenable: lib,
        builder: (context, _) => ListView(
          shrinkWrap: true,
          children: [
            for (final s in lib.saved)
              ListTile(
                title: Text(s.name),
                subtitle: Text([
                  s.view.title,
                  if (s.filters.status != ReadStatus.all) s.filters.status.name,
                  if (s.filters.type != FileType.all) s.filters.type.label,
                  'by ${s.filters.sort.label.toLowerCase()}',
                ].join(' · ')),
                onTap: () {
                  Navigator.pop(sheet);
                  lib.setShelf(view: s.view, filters: s.filters);
                },
                trailing: IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => lib.removeSaved(s.name),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // The extracted cover when there is one; otherwise the generated title card.
  Widget _cover(Book b, {bool small = false, BoxFit fit = BoxFit.contain}) {
    final placeholder = _PlaceholderCover(book: b, small: small);
    if (!lib.covers.has(b.id)) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.file(
        lib.covers.fileFor(b.id),
        fit: fit,
        width: double.infinity,
        height: fit == BoxFit.cover ? double.infinity : null,
        cacheWidth: small ? 96 : 360,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }

  void _info(Book book) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BookInfoPage(library: lib, bookId: book.id),
    ),
  );

  Widget _bookcase(List<Book> books) => Bookcase(
    books: books,
    cover: (b) => _cover(b, fit: BoxFit.cover),
    onTap: _open,
    onLongPress: _info,
  );

  Widget _list(List<Book> books) => ListView.builder(
    padding: const EdgeInsets.only(bottom: 88),
    itemCount: books.length,
    itemBuilder: (context, i) {
      final b = books[i];
      return ListTile(
        leading: SizedBox(width: 36, height: 52, child: _cover(b, small: true)),
        title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            b.author,
            b.format,
            if (b.progress > 0) '${(b.progress * 100).round()}%',
          ].where((s) => s.isNotEmpty).join(' · '),
        ),
        enabled: !b.missing,
        onTap: () => _open(b),
        onLongPress: () => _info(b),
      );
    },
  );

  void _showFilters() {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      builder: (context) => SafeArea(
        top: false,
        maintainBottomViewPadding: true,
        child: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: lib,
            builder: (context, _) {
              final f = lib.filters;
              Widget chips<T>(
                String label,
                List<T> values,
                T selected,
                String Function(T) name,
                ShelfFilters Function(T) change,
              ) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.labelLarge),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final v in values)
                          ChoiceChip(
                            label: Text(name(v)),
                            selected: v == selected,
                            onSelected: (_) => lib.setShelf(filters: change(v)),
                          ),
                      ],
                    ),
                  ],
                ),
              );
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    chips<ReadStatus>(
                      'Reading',
                      ReadStatus.values,
                      f.status,
                      _statusLabel,
                      (v) => f.copyWith(status: v),
                    ),
                    chips<FileType>('File type', FileType.values, f.type, (v) => v.label, (v) => f.copyWith(type: v)),
                    chips<SortBy>('Sort by', SortBy.values, f.sort, (v) => v.label, (v) => f.copyWith(sort: v)),
                    if (!f.isDefault)
                      TextButton(
                        onPressed: () => lib.setShelf(filters: ShelfFilters(sort: f.sort)),
                        child: const Text('Clear filters'),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static String _statusLabel(ReadStatus s) => switch (s) {
    ReadStatus.all => 'All',
    ReadStatus.unread => 'Unread',
    ReadStatus.reading => 'Reading',
    ReadStatus.finished => 'Finished',
  };
}

// Generated title/author cover until embedded covers are extracted.
class _PlaceholderCover extends StatelessWidget {
  const _PlaceholderCover({required this.book, this.small = false});

  final Book book;
  final bool small;

  @override
  Widget build(BuildContext context) {
    const cloth = [Color(0xFF755B45), Color(0xFF6D5150), Color(0xFF67604C), Color(0xFF826B4D)];
    final color = cloth[book.id.codeUnits.fold<int>(0, (sum, c) => sum + c) % cloth.length];
    return DecoratedBox(
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Padding(
        padding: EdgeInsets.all(small ? 2 : 8),
        child: small
            ? Center(
                child: Text(book.format, style: const TextStyle(color: Colors.white, fontSize: 9)),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      book.title,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFF2E6CF),
                        fontFamily: 'serif',
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(book.format, style: const TextStyle(color: Colors.white54, fontSize: 9)),
                ],
              ),
      ),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.onChoose, required this.busy});

  final VoidCallback onChoose;
  final bool busy;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_stories, size: 56),
            const SizedBox(height: 16),
            const Text(
              'Choose your Books folder. Quill reads the files where they are and never changes them.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('chooseFolder'),
              onPressed: busy ? null : onChoose,
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose Books folder'),
            ),
          ],
        ),
      ),
    ),
  );
}
