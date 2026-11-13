# Quill — open-source reuse and feature references

Research checkpoint: 2026-11-04. Sources reviewed through published repositories,
documentation and selected source modules. These apps were not all installed or
tested on-device. Recommendations below are engineering judgments, not completed
integrations or a complete dependency/license audit. The user explicitly requested
existing open-source readers as both feature references and reuse candidates.

| Project | Relevant evidence | Proposed use in Quill |
|---|---|---|
| [Readium Kotlin](https://github.com/readium/kotlin-toolkit) | EPUB parsing/rendering, preferences, TOC-link navigation, saved locators and highlight decorations | Leading direct integration candidate for the native Android EPUB engine |
| [Readest](https://github.com/readest/readest) / [reader guide](https://readest.com/docs/reading) | Contents/bookmarks/notes/search navigation, chapter and book progress, chapter-boundary progress marks | Reference for a compact navigation panel, progress and annotation flows; do not import its entire cross-platform app into Kotlin |
| [KOReader](https://github.com/koreader/koreader) | Dedicated [TOC module](https://github.com/koreader/koreader/blob/master/frontend/apps/reader/modules/readertoc.lua), [dictionary module](https://github.com/koreader/koreader/blob/master/frontend/apps/reader/modules/readerdictionary.lua), mature document navigation | Reference for hierarchical contents, dictionary result handling and navigation edge cases; its Lua/native stack is not a drop-in Compose module |
| [Librera](https://github.com/foobnix/LibreraReader) | Broad Android document-format support; MuPDF integration and documented native dependencies | Reference for local-file/mixed-format reading and PDF behavior; assess components individually rather than embedding the app |
| [foliate-js](https://github.com/johnfactotum/foliate-js) | Modular browser ebook rendering, CFI handling, dictionary-format support; MIT license | Alternative engine/component candidate if Readium fails important requirements; would require a deliberate WebView/JavaScript integration path |

## Integration decisions to evaluate

Use one EPUB engine for layout, selection and locators. Mixing Readium rendering
with another engine's offsets can break resume/highlights. Build Quill's shelf,
series/universe relationships, custom reading orders, folder identity mapping,
Moon Reader migration and backup model in our own application layer.

Readium's documented preferences and decorations are reusable primitives, but do
not promise that its available animation matches Moon Reader's Flip Vertically.
Compare motion and gesture behavior in a bounded evaluation. Add a presentation
adapter only if necessary; do not replace reliable location/selection logic merely
to obtain an animation.

For dictionaries, KOReader's source shows StarDict/sdcv-based handling. Its module
is a behavior/data-format reference; engine code and English dictionary content
must be selected separately. Prefer a licensed offline dataset plus a locally
queryable index. No mandatory external dictionary app or online account.

For PDF and optional CBR, assess engine annotation/selection and archive support
against actual files. A renderer does not automatically supply text-selection UI,
search, annotation persistence or correct position migration. Readium's published
feature matrix leaves PDF highlighting/search as open capabilities, and CBR is not
a promised supported format. Keep the eight existing CBRs as an explicit scope item.

## License and maintenance notes

Readium Kotlin publishes BSD-3-Clause; foliate-js publishes MIT, with vendored
dependencies carrying their own notices. Readest and KOReader publish AGPL-3.0;
Librera publishes GPL-3.0 and lists dependencies including AGPL MuPDF. These are
evidence for component selection; any actual code reuse requires checking the
specific files/version and retaining applicable notices. Private use is not a
reason to assume arbitrary assets or dependencies are interchangeable.

A whole-app fork is viable to evaluate, but customization would inherit its UI,
architecture, update path and dependency surface. My provisional recommendation
remains a small native Quill app over a maintained reading toolkit, using the other
projects for proven interaction patterns and targeted reusable components.

Next gate: demonstrate personal-profile rendering, chapter navigation and stable
anchors in the reference books; compare exact Moon Reader migration; settle
the English dictionary and PDF engine. Only then finalize implementation choices.
