# Quill — behavior and design proposal

Status: shelf direction accepted; bounded prototype implementation approved on 2026-11-04.

## Accepted direction — 2026-11-04

The user responded "works" to the interactive shelf proposal, with Cover shelf
selected. Use Cover shelf as the default and keep Compact shelf as an alternate.
The later explicit request to start the prototype authorizes the bounded evaluation.

Confirmed follow-up: a library of a few hundred books; read/unread and series filters are
most important; custom order close to publication order; migrate existing Moon Reader
highlights, notes and progress; English dictionary. The phone's existing Books folder
with subdirectories is the source collection. Engine/migration feasibility remains
open; the earlier optional migration scope is superseded.

## Product character

2026-11-06 reliability follow-up: the footer reserves its full height while page/time metadata
loads; dialogs and their keyboard do not resize the underlying reading page. The slider's
current/total number is tappable and opens a range-checked page input. EPUB uses stable book text
positions (explained in that dialog), while PDF/comics use document pages. Seek requests run in
sequence, keep the thumb preview until the destination arrives, and surface a failed request.
Filtering uses a scrollable sheet bounded by the safe screen height. The curl snapshot spans
the window, including app-painted inset paper; Android's system icons remain system-owned.

Latest direction — 2026-11-06: the user explicitly requested Moon Reader's **bookcase**, superseding
both the plain card grid and the earlier advice against wooden shelves. Covers stand three per
phone row on continuous planks over the side frames; title, author, progress and finished status
remain accessible in each cover's semantics label. Compact shelf remains available. The sampled
shelf back is `#C7B193`; frame 12 dp + inner wall 10 dp; plank lip/front/edge 9/10/1 dp; covers
approximately 100 × 148 dp. Quill keeps its own dark oak header, Continue button and reader bars
(`oak #4E3220`, dark grain `#2E1C10`, light grain `#7A5536`, ivory text).

The day reader uses paper `#EDEAE4`, generated texture and a subtle vignette; Parchment remains a
separate theme. Phone samples: Quill edges/corners `#E1DED8` / `#D9D6D1`, Moon `#DDDAD4` / `#D8D4CE`.
Visual options can disable texture. Portrait is the initial orientation, with the existing toggle
retained, and the Android system status bar stays visible. The footer shows estimated chapter/book
time (using measured reading speed), then battery, clock, chapter/page and whole-book position.
Unavailable chapter screen-page counts are omitted rather than inferred from spine entries.
The 300 ms curl includes the entire app page frame/footer, while the system status bar remains
fixed. Horizontal swipes follow the same single-turn curl path as taps and keys.

Book details offer an image picker and restoration of the embedded cover. Reader options offer
“Use this page as cover”. Custom JPEGs live only in app storage, survive reopen and cover rebuilds,
and never alter source books. Page capture is Android EPUB-only; other formats retain image choice.

Later 2026-11-05: user found the dark palette still too dark and requested a lighter medieval/
literary feel, clearer header/footer shades, and the remaining card/spacing refinements.
The library now defaults to pale parchment with brown ink, deeper vellum chrome and restrained
serif titles. This default is independent of OS dark mode; night reading remains separate.
Reader header, controls footer and status band are shaded consistently, without resizing the
page when controls appear. Cover art is shown in full; card titles occupy two lines, author one
line, and series position is a small number instead of another long metadata row. Generated
covers use a small cloth-binding palette. The latest direction supersedes the dark default below.

2026-11-05 palette refinement: user replaced the blue Midnight ink direction with **Walnut
library**, chosen over Espresso & parchment and Leather & vellum. Dark mode uses deep walnut
surfaces, aged ivory type and muted linen accents; avoid the former blue and generated amber
highlights. The default night-reading theme follows the same palette.

Quiet, bookish and easy to use daily. Use a restrained serif wordmark, clear system
text for controls, generous cover space, and warm paper/ink tones with a dark theme.
Avoid decorative wooden shelves, compulsory dashboards, promotional content or feeds.
Book covers provide most of the visual character. The primary action is always to read.

## Navigation

Launch into the last shelf, with All Books as the initial default. The shelf selector
opens saved shelves and browse-by-author/series/universe/tag/folder views. Search and
filters live in the top bar. Import and settings live in the overflow menu. A small
optional last-read row supports resume without replacing or pushing down the shelf.

Do not add a separate mandatory home screen or bottom navigation bar in version one.
Book details open from a book's overflow menu or long press; a normal cover tap reads.
Back from reading returns to exactly the same shelf state and position.

## Layout map — follow Moon Reader's placement (2026-11-04)

The user likes where Moon Reader puts things, not necessarily its look. Keep Quill's
quiet paper/ink styling, but put each control where Moon Reader puts it. Observed on the
phone (read-only):

| Place | Moon Reader | Quill prototype today | Proposed Quill |
|---|---|---|---|
| Shelf top bar | ☰ · "All Books ▾" · Search · Filter · ⋮ | "Quill" wordmark · ⋮; "Your shelf" heading below | ☰ · shelf picker ▾ · Search · Filter · ⋮ |
| Shelf picker | All Books, Favourites, Series (with counts), Authors, Tags, Storage folder, Ratings | "All series ▾" under the chips | Picker in the top bar: All, Series, Authors, Folders (later: Universes, saved shelves) |
| Search | Icon that expands | Always-visible text box | Icon that expands into the top bar |
| Filter | Sheet: sort (title, author, import time, folder, recent), read status, layout, file type | Status chips always visible | Filter sheet; show active filters as removable chips only when set |
| ⋮ menu | Import, default cover, rebuild covers, random book, select all | Connect folder, open book, refresh, Moon import, dictionary, about | Refresh, import, rebuild covers, select; settings/about in ☰ |
| Side drawer ☰ | All books, recent, shelves, files, bookmarks, options, night theme | — | Library, Recent, Bookmarks & notes, Dictionary, Settings, Night theme |
| Continue reading | Floating book button, bottom right | — | Floating button, bottom right |
| Reader top bar | ← · book title · ⋮ (visual, control, themes, book info) | ‹ Shelf · title · Aa, plus a second row of four buttons | ← · title · ⋮ (Typography, Layout, Theme, Controls, Book info) |
| Reader bottom | Progress slider with ‹ › and "%" · five customizable icons (orientation, day/night, auto-scroll, chapters, more) | ‹ Chapter · chapter name · % · Chapter › | Slider with ‹ › chapter steps and % · icons: Contents, Bookmarks & notes, Search, Day/Night, Aa |
| Always-on status line | Chapter time left, book time left, battery, clock, chapter (page x/y), page n/total | Title and % | Chapter name · page in chapter · % · clock |
| Contents | Full screen with Chapters/Bookmarks tabs | Dialog | Full-screen sheet with Contents / Bookmarks & notes tabs |

Moon Reader's shelf shows covers only; Quill keeps a title under each cover (decided above).

### Motion

2026-11-05 follow-up: the accepted page curl felt slow at 650 ms. Use 300 ms for the curl;
keep immediate underlying navigation and cancellation when another turn arrives.

Screen recording is blocked on the phone, so Moon Reader's transitions could not be measured
frame by frame. Until they can be, motion is smooth, consistent and fast:
- One set of durations app-wide: 150 ms for controls appearing/disappearing (fade + short
  slide from their edge), 250 ms for sheets and full-screen panels (slide up, decelerating),
  200 ms fade-through between shelf and reader. No bounce or overshoot.
- Everything follows the finger: sheets and the progress slider track drags 1:1 and settle
  with the same curve; a fling completes the motion.
- Page turns keep the captured Flip Vertically preference (READING.md); a tap turns the page
  immediately, without waiting for the animation, so fast tapping never queues up.
- No transition blocks input or loads content before it starts; open the book first and
  fill in covers, contents and search results as they arrive.

## Shelf cards and gestures

Default grid: three columns when space permits, with configurable two/three/four-column
density. Preserve readable title text rather than forcing four columns on small phones.
Each item has cover, title, optional author and a percentage for books in progress.
Unread is blank or explicitly labelled in list mode; finished has a check mark.
The compact list exposes author, series position and status without opening details.

Tap opens the book; long press starts selection; an accessible overflow action opens
book actions. Selection mode supports assign shelf/tag/series/universe, mark status
and remove from library. Confirm before any source-file deletion; removing a library
entry must not delete the original file. Preserve reading records for reimport unless
the user explicitly chooses to erase them.

## Filters and saved shelves

2026-11-05 picker refinement: tapping the shelf title opens a compact vertical dropdown,
following the recorded Moon Reader shelf selector: All Books, Series, Authors, Tags, Folders.
All Books shows its book count; grouping choices show distinct group counts. A grouping choice
opens a titled, searchable list with per-group book counts and a check on the current group.
Avoid the former large sheet of horizontal tabs and the mostly empty All Books tab.

After slider/chapter/contents/search jumps, offer "Back to reading position" above the slider
for five seconds. Another jump restarts the window and retains its original reading position.
Reserve percentage-label width so neither this notice nor changing digits shorten the track.

Prioritize reading status and series in the toolbar/filter entry points. Expose All,
Unread, Reading and Finished, with an easy series picker. Do not silently equate an
in-progress book with a finished book when interpreting the user's read/unread filter.

Filter dimensions combine with AND. Multiple values within a dimension combine with
OR: (Universe A OR Universe B) AND (Unread OR Reading) AND EPUB.
Search applies to the currently filtered collection. Show active filter chips with
individual removal; preserve sort separately. A zero-result state explains which
filters are active and provides Clear filters without resetting the selected shelf.

Reading status: unread, reading, finished, with explicit manual override. Opening a
cover must not mark it finished. The finished state should require reaching the end
or choosing Mark finished, rather than an arbitrary percentage threshold.

Save view creates a smart shelf containing rules, sort and layout. Manual shelves
contain selected books. Removing a book from a manual shelf does not remove it from
the library. Keep these semantics explicit when creating or editing a shelf.

## Series and universe behavior

Universe detail: title, owned-book counts, continue/next book, series groups and
standalones. Switch between grouping by series and an ordered reading list.
Series detail: ordered books, completed/owned counts, next unread owned book, editable
membership and position. Position is a sortable key plus a display label, allowing
novellas and interludes without treating labels as floating-point database values.

Publication, chronological and custom orders are named lists. Never invent an order
from incomplete metadata. If no reliable order exists, show Unordered and let the
user arrange it. Alternate orders can interleave books from different series.
Custom is the primary order; seed from reliable publication/series metadata and
allow rearrangement while preserving metadata. Unknown publication order stays
explicitly unknown rather than being silently replaced with title sorting.
Universe membership and reading order are independent: a standalone can be in the
universe's order without belonging to a series. A book may be in multiple orders.

Next to read is based on the selected order and read status. If a preceding catalogued
book is missing, indicate that gap and offer the next owned entry; do not silently
claim a universe is complete. Keep books-read counts separate from current-book %.

## Book information and covers

### Compact details and typography — 2026-11-05

The user requested lighter book details after inspecting the Flutter build, using Moon Reader's
book-information layout as the reference. Keep a small cover beside editable title/author;
use underlined fields, a compact rating/favourite row, description, series with its number
alongside, tags, then status and simple reading/file rows. Avoid large outlined form blocks,
filled action buttons and repeating the title in a separate header.

App chrome uses restrained regular-weight headings; reading typography still follows the
personal profile. Statistics uses plain compact totals rather than large shaded tiles.
Week / Month / Year / All time stay on one line; allow horizontal scrolling at larger text
sizes instead of wrapping labels or shrinking the user's accessibility text setting.

Keep the reader's whole-book progress slider (explicitly requested again). EPUB jumps resolve
to a reading-order resource plus its local progression; the engine's local resource slider
alone is insufficient. Preserve the Return action and never mark finished just because a
jump reaches the end: show the optional finish prompt.

### Existing Books folder

Select the existing Books folder and recursively index supported files while
preserving its hierarchy. Read in place by default; do not duplicate or reorganize
the collection. Store Quill metadata, progress, annotations and cover overrides
separately. Keep folder browsing alongside series/universe views. Folder names can
suggest organization but require confirmation before assigning series/universes.

Provide Refresh library and refresh checks on returning to the app. Scan changes
incrementally. Match renamed/moved identical files to existing records when
unambiguous; otherwise offer relinking. Missing files retain their records and show
an unavailable state. Revoked access offers Reconnect Books folder. Neither case
deletes annotations or progress. One-off external imports can explicitly copy files.

Editable title, authors, description, tags, series/memberships, universe/memberships,
rating and reading status. Present embedded values as initial metadata and retain
manual overrides. Editing metadata does not rewrite the EPUB in version one.

Cover actions: choose local image, search online, use embedded cover, regenerate
placeholder. Online lookup is explicit, shows candidates for confirmation, and never
changes the cover automatically. Provider and dataset choices remain unresolved.
Rebuilding thumbnails must preserve overrides. Batch imports report corrupt files
individually and keep successfully imported books available.

## Reading and annotations

Use [READING.md](READING.md) and [reader-defaults.json](reader-defaults.json) as the
required initial/reset profile, captured from the user's Moon Reader preferences.
They supersede generic reader-default suggestions. Calibrate appearance and page
motion on the actual phone rather than copying numeric units between engines.
Chapter navigation includes searchable hierarchical contents, current-entry
highlighting, previous/next chapter, jump-return history and stable text anchors.
Use two large novels with deep, nested contents as acceptance examples.

Center tap toggles reading controls. Settings are grouped into Typography, Layout,
Theme and Brightness; changes preview immediately. Global defaults apply unless a
book explicitly has overrides; offer Reset this book to defaults.

Selection menu: Highlight, Note, Dictionary, Copy. Highlights and notes appear in a
book's annotation list and link back to their passages. Export readable notes.
Resume keeps a stable text anchor plus surrounding quote/context, not a screen index.
Moving or renaming a file does not discard progress. A revised EPUB is not assumed
to share identical anchors; flag it for relinking rather than guessing silently.

Reader footer defaults to book percentage and chapter information. Page counts, if
shown, must distinguish layout-dependent screens from publisher page numbers.
PDF uses page/offset and book percentage; reflowable typography settings apply to
EPUB. OCR and PDF reflow are outside the first version.

## First version and gates

Core: shelf/grid/list, local EPUB/PDF import, combined filters and saved shelves,
metadata and covers, manual series/universe organization and custom reading orders,
EPUB reading controls/annotations/dictionary, resume/percentage, basic PDF reading,
and verified export/restore.

Requested but capability-dependent: online cover candidates, built-in offline
dictionary data, and PDF selection/highlighting. Evaluate and explicitly settle
these before calling the scope final. They are not silently dropped.

Migration is required for highlights, notes and reading progress. Inspect available
exports before substantial implementation; do not assume native backup compatibility.
Match books, convert supported annotations and validate passage anchors. Percent-only
progress is approximate, not exact resume. Preserve quoted text/notes that cannot
be anchored, and prevent duplicates on repeated imports. Report exact, approximate
and unmatched results for review before switching daily reading to Quill.

Dictionary scope is English only. Prefer offline lookup inside Quill; evaluate the
dataset/format, licensing, inflected words and multiple definitions before selection.

Later unless requested: cloud sync, desktop app, bookstore/catalog downloads,
automatic online universe discovery, OCR, social features and reading goals.
Text-to-speech is explicitly excluded.

Before implementation, finalize main flows, inspect migration feasibility and settle
reading engines and dictionary data. Library size, key filters, reading-order
preference, migration need and dictionary language are now answered.

## Review scenarios

1. Import mixed EPUB/PDF files; see usable covers and individual error reports.
2. Combine universe + unread + EPUB, save the view, read, and return to its exact state.
3. Add a novella between series entries and switch reading orders without renumbering files.
4. Select a word offline, look it up, highlight it and attach a note.
5. Force-close, reopen, change font/orientation and resume the same passage.
6. Replace a cover, rebuild thumbnails and confirm the override remains.
7. Export a full backup and restore into a clean app instance; compare books,
   memberships, ordering, locators, annotations and preferences.
8. Scan a folder of a few hundred books; add/move/remove files and refresh without
   losing notes/progress. Reconnect folder access and relink unavailable files.
9. Import Moon Reader data twice without duplicates; verify representative passages
   and clearly flag approximate/unmatched positions and annotations.

### Reader page frame and page turn — 2026-11-05

The user found the reader "flowy", not page-like, and asked for Moon Reader's feel. EPUB pages
now get the captured frame: top 40 dp (or the display cutout, if larger) and a gap above the
status line; side margins stay Readium's `pageMargins`. PDF and comic pages keep the full screen.
Page turns by tap or volume key curl like a paper page, as in Moon Reader: forward, the
bottom-right corner is pulled over to the left, folding along a crease with the page's back and
shadows showing; back, the previous page uncurls from the left. 650 ms (420 ms felt too fast).
Rejected: a vertical fold (unnatural) and a rigid hinge turn (mechanical). Swipes still slide. The turn is
instant underneath, so the animation never changes the resume position. Font size and
spacing calibration against Moon Reader still needs a side-by-side check on the phone.

### Reader options — 2026-11-05

Inspected read-only on the phone (Reference book C): Moon Reader's reading menu has ← · title · ⋮ at
the top (⋮: Visual Options, Control Options, Miscellaneous, Themes, More Operations, Share,
Book information) and, at the bottom, ‹ slider % › then orientation, day/night, auto-scroll,
contents and "more". Visual Options: paragraph spacing 70%, line spacing 3, font spacing 0,
font scale 0 (reset), margins L/R/T/B 24/24/40/30 (reset), save/load theme, page-flip animation
and speed. Control Options: DPad centre, four swipe actions (none), fling to turn (on), mini
status bar taps (left: book info, right: bookmarks, long-tap left: brightness), key mapping.
Themes: Day, Night (AMOLED), Night, Day 1 (pure white), Day 2 (sepia), Day 3 (light grey),
Night 2 (slate), Night 3 (charcoal).

The user asked for only what is clear and easy. Quill now has:
- Top bar ← · title · ⋮ (Visual options, Control options, Themes, Book information); bottom
  ‹ previous chapter · slider · % · next chapter › and orientation, day/night, contents, search.
- Visual options in Moon Reader's units with its defaults: font size 12.5, paragraph spacing
  70%, line spacing 3, font spacing 0, publisher styles; margins left/right 24 (Readium supports
  only equal side margins), top 40, bottom 30; each group resets; page turn Curl / Slide / None.
- Control options: volume keys turn pages, left-edge slide for brightness, keep screen on
  (all on, as in Moon Reader), reading brightness back to system.
- Themes: Day (paper), Pure white, Sepia, Light grey; Midnight ink, Black, Slate, Charcoal.
  Day and night remember their own theme; the day/night button switches between them.

Left out for now: auto-scroll, font scale (no Readium equivalent), swipe action mapping,
status-bar tap actions, save/load custom themes, flip speed, blue-light filter, dual page,
focused reading, cloud sync, paper texture.
