import 'package:flutter/material.dart';

import '../library/backup_files.dart';
import '../library/goodreads.dart';
import '../library/library.dart';
import '../shelf/rating_stars.dart';

// Shown once per visit when reaching the end of a book. Dismissing it changes nothing.
Future<void> askFinished(BuildContext context, Library library, String bookId) async {
  if (!context.mounted) return;
  final book = library.books.firstWhere((b) => b.id == bookId);
  var stars = book.rating;
  final finish = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Finished ${book.title}?', style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            RatingStars(rating: stars, onChanged: (r) => setSheet(() => stars = r)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Goodreads has no way for an app to mark a book; this opens its page to do it there.
                TextButton(
                  key: const Key('openGoodreads'),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    if (!await const BackupFiles().openUrl(goodreadsUrl(book))) {
                      messenger.showSnackBar(const SnackBar(content: Text('Goodreads could not be opened.')));
                    }
                  },
                  child: const Text('Goodreads'),
                ),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not yet')),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('markFinished'),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Mark finished'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (finish == true) await library.setFinished(bookId, true, rating: stars);
}
