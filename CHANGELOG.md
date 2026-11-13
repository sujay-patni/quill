# Changelog

APKs and checksums are on the [Releases](https://github.com/sujay-patni/quill/releases) page. Full
release notes: [0.2.1](docs/releases/0.2.1.md), [0.2.0](docs/releases/0.2.0.md),
[0.1.0](docs/releases/0.1.0.md).

## 0.2.1 — 2026-11-13

- **Very large PDFs open.** PDFs are opened from the file instead of being read whole into
  memory, so very large scanned PDFs open (a 2.65 GB graphic novel opens in about 2 s; anything
  over 2 GB used to fail with "This book could not be opened"). Positions, page numbers and
  bookmarks are unchanged.

## 0.2.0 — 2026-11-12

- **Quill's own EPUB engine.** Books open in well under a second, pages turn instantly, and the
  page follows your layout: book-wide page numbers, slider, go to page, nested contents, search
  with the match marked, rolled page curl with held turns. "Use the book's own styles" shows the
  page as the book was designed.
- **Reader options:** separate left/right margins, bold, italic, underline, shadow, font family,
  hyphenation, two pages in landscape, auto page turn, swipe and status-bar tap actions,
  blue-light filter, flip speed, saved themes, settings for one book only.
- **Notes:** text selection with handles, highlights in five colours, notes, bookmarks, copy all
  as text, offline dictionary (WordNet 3.0), tappable links and footnote pop-ups.
- **Library:** universes, reading orders, saved shelves, "Next" in a series or order.
- **Backup & restore** in one `.quill` file; automatic daily backups and one before every import,
  restore and reset; restore with a preview, merged or replacing everything; book list as a
  spreadsheet; reset all progress or statistics.
- **Goodreads:** open a book's page, save finished books in Goodreads' import format, read a
  Goodreads export for ratings and dates.
- **CBR comics** (RAR 4) open, converted once into Quill's cache.

## 0.1.0 — 2026-11-07

- Offline EPUB, PDF and CBZ reading from a folder chosen with Android's picker; extracted covers.
- Bookcase shelf with a compact-list option; series, author, tag and folder selection, filters
  and sorting.
- Paper textures, day/night themes, typography and layout controls, page curl for taps, swipes
  and volume keys.
- Slider seeking, typed page entry and a five-second jump undo.
- Book information, favourites, ratings, finished status, reading statistics, finish prompt.
- Custom covers, including a page of the book.
- Moon Reader import with a preview and explicitly approximate imported positions.

## Known gaps

- PDFs turn pages without the curl, and show page/total without a percent.
- RAR 5 and password-protected CBR files are refused.
- A book's embedded fonts are used only in "the book's own styles".
- Backups do not include book files; iOS is not built yet.
