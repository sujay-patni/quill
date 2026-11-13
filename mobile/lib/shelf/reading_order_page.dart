import 'package:flutter/material.dart';

import '../library/library.dart';
import '../library/shelf.dart';

// A reading order: the user's own list of books, dragged into the order to read them.
class ReadingOrderPage extends StatelessWidget {
  const ReadingOrderPage({super.key, required this.library, required this.name});

  final Library library;
  final String name;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) {
      final ids = library.orders[name] ?? const <String>[];
      final byId = {for (final b in library.books) b.id: b};
      final next = nextToRead([for (final id in ids) ?byId[id]]);
      return Scaffold(
        appBar: AppBar(title: Text(name)),
        body: ids.isEmpty
            ? const Center(child: Text('This order is empty. Add books from Book information.'))
            : ReorderableListView.builder(
                key: const Key('orderList'),
                itemCount: ids.length,
                onReorderItem: (from, to) {
                  final list = [...ids];
                  list.insert(to, list.removeAt(from));
                  library.setOrder(name, list);
                },
                itemBuilder: (context, i) {
                  final b = byId[ids[i]];
                  return ListTile(
                    key: ValueKey(ids[i]),
                    leading: Text('${i + 1}', style: Theme.of(context).textTheme.titleMedium),
                    title: Text(b?.title ?? 'Missing book', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text([
                      if (b != null && b.author.isNotEmpty) b.author,
                      if (b != null && statusOf(b) == ReadStatus.finished) 'finished',
                      if (b != null && b.id == next?.id) 'next to read',
                    ].join(' · ')),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Remove from this order',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => library.setOrder(name, [...ids]..removeAt(i)),
                      ),
                      const Icon(Icons.drag_handle),
                    ]),
                  );
                },
              ),
      );
    },
  );
}
