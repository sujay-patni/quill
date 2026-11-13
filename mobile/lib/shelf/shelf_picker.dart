import 'package:flutter/material.dart';

import '../library/book.dart';
import '../library/shelf.dart';

// A compact shelf selector, followed by a searchable group list when needed.
class ShelfPicker extends StatelessWidget {
  const ShelfPicker({
    super.key,
    required this.books,
    required this.view,
    required this.onSelected,
    this.orders = const {},
    this.saved = const [],
    this.onSaved,
  });

  final List<Book> books;
  final ShelfView view;
  final ValueChanged<ShelfView> onSelected;

  /// Named reading orders, and saved shelves with a callback that applies one.
  final Map<String, List<String>> orders;
  final List<SavedShelf> saved;
  final ValueChanged<SavedShelf>? onSaved;

  @override
  Widget build(BuildContext context) => PopupMenuButton<Object>(
    key: const Key('shelfPicker'),
    tooltip: 'Choose bookshelf',
    position: PopupMenuPosition.under,
    constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
    onSelected: (choice) async {
      if (choice is SavedShelf) {
        onSaved?.call(choice);
        return;
      }
      final kind = choice as ShelfKind;
      if (kind == ShelfKind.all) {
        onSelected(const ShelfView());
        return;
      }
      final value = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) =>
            _GroupPicker(
              kind: kind,
              groups: shelfGroups(books, kind, orders: orders),
              selected: view.kind == kind ? view.value : null,
            ),
      );
      if (context.mounted && value != null) onSelected(ShelfView(kind, value));
    },
    itemBuilder: (_) => [
      for (final kind in ShelfKind.values) ...[
        if (kind != ShelfKind.all) const PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: kind,
          child: Row(
            children: [
              Icon(_icon(kind), size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(kind.label)),
              Text(
                '${kind == ShelfKind.all ? books.length : shelfGroups(books, kind, orders: orders).length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 12),
              SizedBox(width: 18, child: view.kind == kind ? const Icon(Icons.check, size: 18) : null),
            ],
          ),
        ),
      ],
      for (final s in saved) ...[
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          key: Key('saved-${s.name}'),
          value: s,
          child: Row(
            children: [
              const Icon(Icons.bookmarks_outlined, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(s.name, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ],
    ],
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(view.title, overflow: TextOverflow.ellipsis)),
        const Icon(Icons.arrow_drop_down),
      ],
    ),
  );

  static IconData _icon(ShelfKind kind) => switch (kind) {
    ShelfKind.all => Icons.menu_book_outlined,
    ShelfKind.series => Icons.collections_bookmark_outlined,
    ShelfKind.universes => Icons.public,
    ShelfKind.orders => Icons.format_list_numbered,
    ShelfKind.authors => Icons.person_outline,
    ShelfKind.tags => Icons.local_offer_outlined,
    ShelfKind.folders => Icons.folder_outlined,
  };
}

class _GroupPicker extends StatefulWidget {
  const _GroupPicker({required this.kind, required this.groups, required this.selected});

  final ShelfKind kind;
  final List<MapEntry<String, int>> groups;
  final String? selected;

  @override
  State<_GroupPicker> createState() => _GroupPickerState();
}

class _GroupPickerState extends State<_GroupPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.kind.label;
    final query = _search.text.trim().toLowerCase();
    final groups = widget.groups.where((g) => g.key.toLowerCase().contains(query)).toList();
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
                    IconButton(
                      tooltip: 'Close bookshelf picker',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  key: const Key('shelfGroupSearch'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Find ${label.toLowerCase()}',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear group search',
                            onPressed: () => setState(_search.clear),
                            icon: const Icon(Icons.close),
                          ),
                    border: const UnderlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: groups.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            widget.groups.isEmpty
                                ? 'No ${label.toLowerCase()} yet. Add details in Book information.'
                                : 'No ${label.toLowerCase()} match your search.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      )
                    : ListView.separated(
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: groups.length,
                        separatorBuilder: (_, _) => const Divider(height: 1, indent: 20, endIndent: 20),
                        itemBuilder: (context, i) {
                          final group = groups[i];
                          final selected = widget.selected == group.key;
                          return ListTile(
                            title: Text(group.key),
                            trailing: Text('${group.value}', style: Theme.of(context).textTheme.bodySmall),
                            leading: SizedBox(width: 20, child: selected ? const Icon(Icons.check, size: 20) : null),
                            selected: selected,
                            onTap: () => Navigator.pop(context, group.key),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
