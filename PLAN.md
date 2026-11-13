# Quill — personal Android ebook reader

Status: prototype implementation approved and started on 2026-11-04.
Date: 2026-11-04

Detailed proposed behavior and review scenarios: [DESIGN.md](DESIGN.md).
Personal reading defaults and EPUB navigation: [READING.md](READING.md).
Open-source integration/reference assessment: [REFERENCES.md](REFERENCES.md).

Design checkpoint (2026-11-04): user accepted the shelf proposal ("works").
Cover shelf is the default; Compact shelf remains an alternate. User preferences
below are confirmed; engine and migration feasibility remain open. Prototype implementation was subsequently approved and is now in progress.

## Goal and agreed requirements

An independently owned Android reader, primarily for EPUB and occasionally PDF.
The shelf is the main workspace. Fonts, spacing, brightness, themes, bookmarks,
highlights, notes, dictionary lookup, reading position and percentage are required.
No text-to-speech. Covers should be extracted automatically, with manual and optional
online replacements. Series and universes need stronger organization than Moon Reader.

Confirmed library/workflow:
- A few hundred books in an existing phone Books folder with subdirectories.
- Most-used filters: read/unread and series.
- Custom reading order, generally close to publication order.
- Existing Moon Reader highlights, notes and reading progress must carry over.
- English dictionary only for the first version.
- Use the existing Moon Reader typography, paper-style theme, gestures and
  Flip Vertically page animation as Quill's personal default profile.
- Chapter-navigation acceptance books: Reference book A and Empire of
  Silence; Reference book C's sparse chapter list is not an adequate navigation baseline.

## Reference study

Inspected Moon Reader on the user's connected, unlocked phone after checking the
shared device registry and obtaining a phone lease. No active lease or queued request
was present. Returned to the shelf and released the lease after inspection. Did not
open a book, save book edits, download covers, or intentionally alter reader settings.

Observed:
- Cover grid; shelf selector, search, reading filter and overflow menu in the toolbar.
- Shelf selector: All Books, My Favorites, Series, Authors, Tags, Storage Folder, My Ratings.
- Filter panel: title/author/import time/storage folder/recent sorting; unread/reading/
  finished; layout and file type controls.
- Shelf menu: import, default cover, rebuild covers, random book, select all.
- Book menu: pin, information, download cover, send file, remove from shelf.
- Book information: title, author, custom cover text, local/online cover selection,
  description, favorite/category, series, tags, reading status and reading history.

Moon Reader already has series organization. Our differentiators are universes,
flexible book membership, alternate reading orders, and reusable combined filters.
No public source release/license was located on its official site; do not assume
Moon Reader code is available to reuse.

## Proposed product

### Shelf as home

- Default launch screen; configurable cover grid and compact list.
- Optional title/author, series number, percentage and status on cards.
- Search and combined filters: status, author, tags, series, universe, folder, format,
  favorites and rating. Sorting independent of filtering.
- Remember filters, sort, layout and scroll when returning from a book.
- Manual shelves: explicit memberships; one book may be on multiple shelves.
- Smart shelves: saved rules, e.g. unread EPUBs in a universe.
- Multi-select for tags, shelving, series/universe assignment and status edits.
- Remove from library and delete source file are separate, explicit actions.

### Series, universes and reading orders

- A universe can contain several series and standalone books.
- Books may have multiple series/universe memberships; avoid a rigid folder hierarchy.
- Series membership stores a sortable position plus a display label (supports novellas).
- Publication, chronological and custom reading orders are separate ordered lists.
- User chooses the active order; show the next owned unread book.
- Custom order is primary; seed from reliable publication/series metadata when
  available, then allow rearrangement without changing the original metadata.
- Derive progress from owned books; show missing entries only when explicitly catalogued.
- Read embedded EPUB/Calibre metadata where available. Treat filename/folder/online
  inference as suggestions. Manual corrections take precedence.

### Reader

- EPUB: pagination and continuous scroll; TOC; in-book search; font family/size,
  line/paragraph spacing, margins, alignment and themes; per-book overrides.
- Brightness gesture with app-window brightness control.
- Save a stable content locator and percentage, not just a screen page number.
  Font/orientation changes must retain the same text position.
- Bookmarks, colored highlights and attached notes, with jump-back navigation.
- Dictionary lookup from text selection. Prefer an integrated offline dictionary
  using redistributable data; downloadable packs may be installed once. Optional
  online lookup is supplementary. English only initially.
- PDF: page/offset resume and percentage; zoom, pan, fit-width, bookmarks and themes.
  Text selection, dictionary and annotation support require a dedicated engine check.
  Scanned PDFs need OCR for word lookup; OCR is not in the initial proposal.
  PDF typography does not behave like reflowable EPUB typography.

### Import, metadata and covers

- Single-file and folder import using Android's file picker; background indexing.
- Proposed default: link the existing Books folder, recursively index its EPUB/PDF
  files and read in place. Preserve subdirectories; do not rename, rewrite or
  duplicate the collection. Store Quill data and cover overrides separately.
- Retain source references and content fingerprints. Refresh on demand and check
  for changes when returning to the app; do not promise instant background watching.
- Missing files and revoked folder access preserve annotations/progress and offer
  relinking/reconnection. Folder names provide suggestions, not authoritative metadata.
- Copy-on-import is an explicit option for external files. Backups distinguish
  metadata-only exports from exports that also contain book files.
- Detect exact duplicates without losing annotations; book identity independent of path.
- Cover order: user override, declared embedded EPUB cover, safe image fallback;
  PDF first-page thumbnail; generated title/author placeholder if unavailable.
- Local image replacement, optional online candidate selection, reset and rebuild.
- Downloaded covers remain usable offline. Provider failure never blocks reading.
- Retain metadata provenance; never silently overwrite user edits.

### Ownership and recovery

- Core library and reading work offline, with no account or hosted backend required.
- Local database, local books and covers; no analytics requirement.
- Versioned export/restore of library metadata, shelves, series/universes, annotations,
  positions and preferences; optional included book files.
- Human-readable metadata/notes export as well as full restore backup.
- Keep release signing credentials under the owner's control for future APK updates.
- Moon Reader migration is required for the user's switch: investigate available
  exports for highlights, notes and progress before committing to an importer.
  Preserve originals; do not assume position formats are compatible.
- Report exact, approximate and unmatched transfers. Preserve note/quote text even
  when its passage cannot be anchored. Repeated imports must not create duplicates.

## Technical direction — provisional

Native Kotlin + Jetpack Compose; Room database; DataStore preferences; Android Storage
Access Framework; WorkManager for indexing and optional downloads. Readium Kotlin is
the leading EPUB engine candidate, subject to a small integration evaluation.

Keep library, reader, annotation, dictionary, cover lookup and backup interfaces
separate so providers/engines can be replaced. Keep annotations and organization in
our own database, with stable content anchors. Store PDF page geometry separately
from EPUB text locators. No custom server is needed for version one.

References:
- Moon Reader official features: https://www.moondownload.com/
- Moon Reader FAQ: https://www.moondownload.com/faq.html
- Readium Kotlin, EPUB/PDF support and feature matrix: https://github.com/readium/kotlin-toolkit
- Readium BSD-3-Clause license: https://github.com/readium/kotlin-toolkit/blob/develop/LICENSE
- Readest, cross-platform UX/reference candidate, AGPL-3.0: https://github.com/readest/readest
- Librera, Android reference candidate, GPL-3.0: https://github.com/foobnix/LibreraReader
- KOReader, reading/dictionary/PDF reference candidate, AGPL-3.0: https://github.com/koreader/koreader

Only Moon Reader was inspected on-device. Other applications were researched through
their published repositories. Reference selection is not a commitment to copy code.
Check the licenses of any reused components and dictionary datasets before adoption.
Readium's feature matrix does not currently list PDF highlighting or text search as
implemented; PDF annotation capability is an explicit unresolved engine decision.

## Delivery sequence after plan approval

1. Approve shelf/series/universe interactions using static mockups and real workflows.
2. Inspect migration inputs and recursive folder access; evaluate EPUB locators,
   English dictionary integration and PDF engines on representative books. Establish
   migration feasibility before substantial implementation, then finalize the stack.
3. Build shelf, import/indexing, covers, filters, bulk editing, series and universes.
4. Complete reading customization, reliable resume, annotations and dictionary.
5. Complete PDF scope, optional cover lookup, backup/restore and verified migration.
6. Daily-use trial on the phone with an independently signed installable APK.

Acceptance includes airplane-mode reading, filter persistence, mixed-format import,
missing/malformed covers, duplicate/relinked files, resume after force-close and
font/orientation changes, correct annotation anchors, custom reading orders and a
verified backup restore. Validate a few-hundred-book collection, cached
shelf rendering and incremental scans, including moved/missing files and lost access.

## Remaining planning checks

1. Export inspected: metadata/annotation/position data is readable; exact locator
   conversion remains unproven.
2. Folder verified on the phone: mostly EPUB, some PDF and CBR. Actual
   app-level recursive folder access still needs evaluation.
3. Settle PDF annotation capabilities and English offline dictionary data/engine.
4. Review the finalized implementation plan before starting app implementation.
5. Decide whether the existing CBR comics belong in first-version scope.

Next deliverable is the approved behavior/design plan, not app implementation.

## Prototype approval — 2026-11-04

User explicitly included comics and requested Git/GitHub setup followed by the prototype.
Scope: EPUB, PDF, CBR/CBZ; personal reading-profile evaluation; folder access; chapter
navigation/resume; offline English dictionary; Moon Reader migration preview.
Implementation branch: `prototype/reader`; isolated package: `app.quill.prototype`.
The full production feature set remains the target, not a claim of prototype completeness.
