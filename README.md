# Quill

An offline Android reader for EPUB, PDF and comics (CBZ/CBR), built with Flutter for people who
keep their own book collection on their phone. No account, no server, no analytics: Quill reads
your books in place from a folder you choose and keeps everything else on the device.

It started as a personal replacement for Moon Reader, so its defaults follow Moon Reader's page
layout and controls, and it can import a Moon Reader backup.

**[Download the latest APK](https://github.com/sujay-patni/quill/releases/latest)** · [Changelog](CHANGELOG.md) · MIT licence

## Features

**Reading**
- Quill's own EPUB engine, written in Dart: books open in well under a second, pages turn
  instantly, and the page uses your layout. A second mode shows the book's own styles.
- Rolled page curl that follows your finger, can be held and reversed.
- Book-wide page numbers, slider with jump-back, go to page, nested contents, in-book search.
- Fonts, size, spacing, margins, alignment, hyphenation, themes (including paper textures),
  two pages in landscape, auto page turn, volume-key turns, brightness swipe, blue-light filter.
- Highlights in five colours, notes, bookmarks, an offline English dictionary (WordNet 3.0),
  links and footnote pop-ups.
- PDFs, including very large scanned ones (opened from the file, not loaded into memory), and
  CBR/CBZ comics.

**Library**
- Bookcase shelf with covers, or a compact list; search, filters and sorting.
- Series with numbering, universes that span several series, and your own reading orders,
  with "next to read" for each.
- Book information: ratings, favourites, tags, custom covers, reading statistics.

**Your data**
- Backup and restore in one `.quill` file (merge or replace), with automatic daily backups.
- Goodreads: open a book's page, export finished books in Goodreads' import format, or read a
  Goodreads export for ratings and dates.
- One-time Moon Reader import (positions, finished state, series, statistics).

## Install

Download `Quill-<version>.apk` from [Releases](https://github.com/sujay-patni/quill/releases) and
install it (Android 8.0 or newer; allow installs from your browser or file manager). Each release
lists the APK's SHA-256. On first launch, choose the folder that holds your books.

Releases are signed with the author's key, so a build you make yourself installs as a separate
app or must replace the released one; it cannot update it in place.

## Building

The app is the Flutter project in [`mobile/`](mobile/). Tested toolchain: Flutter 3.47.9
(Dart 3.13.7), JDK 21, Android SDK platform 37.0, build-tools 36.0.0, NDK 28.2.13676358.

```sh
python3 tools/dev_setup.py --flutter-sdk /path/to/flutter --android-sdk /path/to/android-sdk \
  --java-home /path/to/jdk-21 --configure   # checks the toolchain, writes ignored local paths
source .local/quill-env.sh
cd mobile
flutter pub get
flutter test                                # unit and widget tests
flutter build apk --debug                   # installs as "Quill Dev" (app.quill.reader.dev)
```

Integration tests in `mobile/integration_test/` build their own synthetic books and must run on
an **emulator**: Flutter uninstalls the app under test afterwards, which would erase a phone's
library.

## Project layout

| Path | What it is |
|---|---|
| `mobile/lib/native/` | Quill's EPUB engine: parser, paginator, page view, page curl |
| `mobile/lib/reader/` | Reader screen, options, status line, position log |
| `mobile/lib/library/` | Library model, folder scan, backup, Goodreads, covers, dictionary |
| `mobile/lib/shelf/` | Shelf, book information, reading orders, backup and statistics screens |
| `mobile/lib/import/` | Moon Reader import |
| `mobile/third_party/flutter_readium/` | Patched copy of flutter_readium (PDF, comics, book-styles EPUB); changes in [PATCHES.md](mobile/third_party/PATCHES.md) |
| `tools/` | Toolchain check, dictionary and fixture builders, paper texture generator |
| `PLAN.md`, `DESIGN.md`, `READING.md` | Product plan, design decisions and reading profile |

## Acknowledgements

- [Readium Kotlin toolkit](https://github.com/readium/kotlin-toolkit) and
  [flutter_readium](https://github.com/notalib/flutter_readium) (BSD-3-Clause).
- [WordNet 3.0](https://wordnet.princeton.edu/), Princeton University, for the dictionary
  ([licence](mobile/assets/dictionary/LICENSE.txt)).
- TeX hyph-utf8 English hyphenation patterns (licence in `mobile/assets/hyph-en-us.txt`).
- [junrar](https://github.com/junrar/junrar) for RAR 4 comics (extraction only, under the UnRAR licence).

## Licence

MIT, see [LICENSE](LICENSE). Bundled third-party code and data keep their own licences.
