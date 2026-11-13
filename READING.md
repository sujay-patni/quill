# Quill — personal reading defaults and chapter navigation

Status: required default profile, recorded at the user's request on 2026-11-04.
Prototype implementation was subsequently approved. Machine-readable source values are in
[reader-defaults.json](reader-defaults.json); only reading preferences were retained.

## Defaults captured from Moon Reader

2026-11-05 color refinement: the user's later lighter parchment/literature request replaces
the initial day background/ink with pale vellum and soft brown ink. Moon-calibrated text size,
spacing, margins and navigation remain the reference. Header/footer bands use a deeper vellum
shade; night reading is still selectable independently from the lighter library.

Inspected current Visual Options and Control Options on-device; compared against
the earlier local backup. No settings were intentionally changed. Resumed books
for inspection without selecting a different page/chapter. Opening books can update
Moon Reader's recent-book order and reading-time statistics. Finished on All Books
and released the phone reservation.

| Setting | Capture / Quill requirement |
|---|---|
| Font | `serif` fallback, with publisher fonts permitted |
| Font size | Moon Reader UI 12.5; visually calibrate Quill, do not equate engine units |
| Font styling | Bold, italic, underline and shadow off; anti-aliasing on |
| Font spacing / scale | 0 / 0 in Moon Reader |
| Paragraph spacing | UI 70%; raw `paragraphSpace2=7` |
| Line spacing | UI/raw 3; exact layout conversion requires comparison |
| Margins | UI left/right 24/24, top/bottom 40/30; raw 84/84/140/105 |
| Theme | Day Theme; text `#000000`, base background `#DCD7D1` |
| Background | Background image enabled (`readbg_13`), giving a subtle paper texture |
| Publisher formatting | Publisher fonts permitted; preserve legitimate book styles |
| Hyphenation | Off |
| Forced first-line indent | Off; publisher CSS may still indent paragraphs |
| Page animation | 2026-11-05 phone: **(Apple) Real Page Turning Effect** (a curl); the 2026-11-04 capture said Flip Vertically (`flip_animation=1`) |
| Horizontal fling | Enabled to turn pages |
| Page sound | Off |
| Left / right tap | Previous page / next page |
| Center tap | Options/reading controls; verified tap-zone preview |
| Volume up / down | Previous page / next page |
| Long press | Text selection |
| Extra swipe actions | None assigned in the four directional action pickers |
| Orientation | Portrait (Sensor) |
| Brightness gesture | Swipe left screen edge to adjust |
| Right-edge font-size gesture | Off |
| Brightness | Raw value `-100`; sentinel semantics not confirmed in UI, never use as a literal percentage |
| Layout | Single-page reading; dual-page off |
| Screen | Keep awake enabled; mini reading-status bar enabled |
| Progress display | Book percentage requested for Quill; chapter/page status and remaining-time display are also present in Moon Reader |

Quill should ship with this profile as its initial and reset-to-default state,
while allowing global changes and per-book overrides. Preserve raw reference values
without forcing them directly into Readium/CSS units. Match apparent text size,
usable text area, line rhythm and page motion on the actual phone. Recreate a subtle
paper treatment rather than assuming Moon Reader's bundled image is reusable.
Publisher CSS means the effective typeface/layout can differ across books; offer
an explicit publisher-formatting toggle and retain a predictable serif fallback.

## Reference books and observations

At the user's correction, use **Reference book A** and **Reference book B**
for chapter acceptance. Reference book C is useful for appearance but its sparse contents
must not be the chapter-navigation baseline.

- Reference book A: Moon Reader shows 41 list entries, chapter start-page labels, current
  entry check mark, Chapters/Bookmarks tabs and chapter search. The inspected EPUB
  has 65 spine items and 40 NCX navigation points. Reader-added entries can explain
  a count difference; do not assume raw file count equals chapter count.
- Reference book B: Moon Reader shows 93 contents entries, named chapters,
  expandable/grouped back matter, chapter start-page labels and the current entry
  selected. Its EPUB contains 92 spine items, 93 NCX navigation points, and 93
  EPUB 3 TOC links. This exercises hierarchy and appendices as well as chapters.
- Completed positions remained at the end during inspection; no chapter jumps
  were performed. Actual jump/return and page-animation fidelity remain tests.

Reference EPUB copies were used locally to inspect container/package/navigation
structure; they are in temporary inspection storage, not included in the project.

## How Quill should build the EPUB index

An EPUB's spine defines document reading order; its navigation document defines
named contents links and hierarchy. EPUB 2 uses NCX; EPUB 3 uses its navigation
document. Targets can be anchors inside a document, so neither a file nor a spine
item necessarily equals a chapter. Keep TOC, reading order, publisher page list and
full-text search index distinct.

Use the reader engine's parsed publication/TOC rather than writing a second EPUB
parser for production. Cache the tree, resolved target links, document order and
available locator/progression information per book fingerprint. Validate targets;
retain unresolvable entries with a clear unavailable state. Rebuild only when the
book changes. Missing publication navigation gets a conservative labelled fallback
from headings/reading order; do not invent authoritative chapter names or numbering.

For reflowable books, screen page counts change with fonts, spacing, orientation
and viewport. Save content locators/anchors independently. Publisher page numbers
are a separate optional mapping and should not be presented as screen counts.

## Navigation behavior to implement

1. Center tap reveals controls; Contents is one clear action away. Tapping the
   chapter label may also open Contents.
2. Contents opens at the current entry, showing its name and nested parents.
   Preserve meaningful hierarchy; allow expanding/collapsing and title search.
3. Tapping a chapter navigates to its exact link/anchor. Show a Return to previous
   position action after intentional TOC, search, footnote or percentage jumps.
4. Previous/next chapter follow TOC targets, not arbitrary internal file boundaries.
   Exclude container-only headings from jump actions. End-of-chapter paging follows
   normal document order without missing/repeating text at resource boundaries.
5. Keep chapter progress distinct from overall book percentage. A progress scrubber
   previews chapter/percentage before committing the jump; small taps must not cause
   accidental large jumps. Show boundary markers where useful.
6. Search in book indexes text lazily, returns chapter-labelled snippets, and links
   to exact matches. Searching the contents only filters chapter titles.
7. Selection, highlights, hyperlinks and brightness gestures take precedence over
   page turns. Long press must not turn a page. Support RTL/fixed layout separately.
8. Preserve reading position when preferences reflow text. Update layout-specific
   page labels independently and avoid marking inspection/jumps as completed reading.

## Verification before daily use

Compare the saved profile on the phone; traverse chapter boundaries in both reference
books; test nested appendix links; verify current-entry detection after reflow;
test chapter-title search vs full-text search; test jump/return without losing resume;
check malformed/sparse TOCs; check volume/tap/fling gestures, text selection, and
completed-book progress. Test app restarts after both normal reading and navigation.

## Primary references

- [W3C EPUB 3.3](https://www.w3.org/TR/epub-33/) — spine and navigation semantics.
- [Readium navigator](https://github.com/readium/kotlin-toolkit/blob/develop/docs/guides/navigator/navigator.md) — navigation using TOC links and saved locators.
- [Readium preferences](https://github.com/readium/kotlin-toolkit/blob/develop/docs/guides/navigator/preferences.md) — preferences and effective renderer settings.
- [Readium locators](https://readium.org/kotlin-toolkit/latest/api/readium/readium-shared/org.readium.r2.shared.publication/-locator/index.html) — content locations independent of screen page numbers.
