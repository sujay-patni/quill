# Local patches

## flutter_readium 0.9.0 (BSD-3-Clause, https://github.com/notalib/flutter_readium)

Copied from pub.dev without `example/` and `test/`. First change, in
`android/src/main/kotlin/dk/nota/flutterreadium/ReadiumReader.kt` (`resolvePubUrl`):

- Upstream checks `absoluteSchemeRegex.matches(url)`, which needs the whole string to match
  `^scheme://`, so it never matches. Every URL then gets `file://` prefixed again:
  `content://` URIs from Android's folder picker and paths with spaces fail with `notFound`.
- Patched to `containsMatchIn`, and plain paths become encoded `file:///` URLs.

Drop this copy (and the `dependency_overrides` entry in pubspec.yaml) once upstream fixes it.

Second change (2026-11-05), PDF taps — `fragments/PdfReaderFragment.kt`, `navigators/PdfNavigator.kt`:

- Upstream adds no input listener to the PDF navigator, so tapping the page edges did not turn
  pages on Android (only swipes did). Added the stock `DirectionalNavigationAdapter` (edge taps,
  volume keys), as the EPUB fragment already does, and forward other taps so the centre toggles
  the reader controls.

Third change (2026-11-05), whole-book EPUB seeking — `ReadiumReader.kt`,
`PublicationChannel.kt`, `lib/flutter_readium.dart`:

- Added `goToBookProgression` as a separate Android method. The upstream `goToProgression`
  scrolls inside the current resource and keeps its original semantics. The new method asks
  Readium's `locateProgression` service for a weighted whole-book locator, then navigates there.
  This makes the slider agree with totalProgression even when resources have very different
  lengths. Returns false on other platforms or when no position service is available; Quill
  then uses a documented approximate reading-order fallback. iOS is still unbuilt.

Fourth change (2026-11-05), page-curl turn — `fragments/PageFlip.kt`, `fragments/PageCurlView.kt`
(new), `fragments/EpubReaderFragment.kt`:

- Upstream paged EPUB turns only slide horizontally. For tapped and volume-key turns of
  reflowable paged text, Quill snapshots the old page and turns instantly underneath
  (`animated = false`), then draws a 2D page curl over it (300 ms; reduced from 650 ms after
  the user's speed feedback): the bottom-right corner is
  pulled across, the crease is the bisector, the turned part shows as the page's back (paper with
  the print faintly mirrored), shaded along the crease and casting a shadow on the page below.
  Backward: the previous page is snapshotted ~90 ms later once rendered and uncurls onto the old
  one. Position, locator and page counters come from the instant turn, so the animation cannot
  move the saved position. A new turn finishes a running one; pausing cancels it. Fixed layout,
  and scroll mode are unchanged; swipe curl support is described in patch six.

Fifth change (2026-11-05), page-turn style — `ReadiumReader.kt`, `PublicationChannel.kt`,
`fragments/EpubReaderFragment.kt`, `lib/flutter_readium.dart`:

- `setPageTurnStyle('curl' | 'slide' | 'none')` on the main channel picks how paged
  reflowable turns animate. Programmatic `goForward` / `goBackward` (Quill's volume keys) now
  take the same path as taps, so they curl too.

Sixth change (2026-11-06), swipe turns — `fragments/SwipeTurnLayout.kt`,
`fragments/EpubReaderFragment.kt`, `res/layout/fragment_reader.xml`:

- A deliberate horizontal swipe in paged reflowable EPUB text invokes the same turn path as
  edge taps. Left advances once; right goes back once. Vertical gestures, long presses and
  fixed-layout/scroll modes retain the content's native handling.

Seventh change (2026-11-06), paper and page covers — `ReadiumReader.kt`,
`PublicationChannel.kt`, `navigators/EpubNavigator.kt`, `fragments/EpubReaderFragment.kt`,
`lib/flutter_readium.dart`:

- `setPaperTexture` supplies a base64 PNG behind EPUB text. Quill also paints the generated
  paper asset behind its outer page frame. Turning texture off removes both layers.
- Android `snapshotPage` draws the current reader page to a scaled JPEG for Quill's custom
  cover store. It captures the reading view without Flutter's controls. PixelCopy of Flutter's
  separate surface produced a black image and is not used. Other platforms return unsupported.
  Phone validation produced a readable page JPEG; the synthetic reader test checks paper and
  printed pixels so a black capture fails.

Eighth change (2026-11-06), full reader-page curl — `fragments/EpubReaderFragment.kt`,
`fragments/PageFlip.kt`:

- Use the full window decor root for the curl snapshot and overlay, including Flutter's paper
  frame and status footer. If the activity root is unavailable, use the reading view as before.
  Hide the held overlay while taking the backward snapshot to avoid capturing the old curl.
  Android status/navigation icons remain system-owned; the paper snapshot spans the window inset areas. Phone mid-turn captures
  verified the frame/footer in both directions and no blank Flutter surface; forward/back and
  swipe round trips returned to the same content locator. Duration remains 300 ms.

Ninth change (2026-11-06), reliable manual seeking and book position numbers —
`ReadiumReader.kt`, `PublicationChannel.kt`, `navigators/EpubNavigator.kt`,
`fragments/EpubReaderFragment.kt`, `lib/flutter_readium.dart`:

- Whole-book EPUB seeking now returns the navigator's real acceptance result, uses an instant
  locator jump, and clears any held curl before navigation. A rejected Android jump no longer
  masquerades as success or trigger Quill's approximate chapter fallback.
- `bookPositionCount` and `goToBookPosition` expose Readium's one-based stable text positions.
  They are independent of screen pagination. Quill uses the exact count and locator for the
  tappable number beside the slider, validates typed targets, serializes seeks and waits for
  a matching destination event before releasing its preview. Other platforms retain the
  explicitly approximate fallback; PDF/comic navigation uses their existing page progression.
- Flutter reserves the complete footer before metadata arrives and keeps the page size fixed
  under keyboard overlays, avoiding unwanted re-pagination. This is an app layout change.

### 2026-11-10 — curl capture, rolled curl, Moon mode

`fragments/PageFlip.kt`, `fragments/PageCurlView.kt`, `ReadiumExtensions.kt`,
`assets/helpers/quillMoonMode.css`, `assets/helpers/quillMoonMode.js`:

- Curl pages are captured with `PixelCopy` from Flutter's SurfaceView (the reader is a
  texture-layer platform view that software `View.draw` renders blank); software drawing is the
  fallback. The origin capture is asynchronous and completes before the page is covered.
- The curl is a page rolled around a cylinder (Apple Books / Moon Reader "Real page turning"
  style), drawn with `Canvas.drawBitmapMesh`: flat behind the axis, curving up over the roll,
  then lying back with the plain back and faint print. Own implementation of the standard
  cylinder mapping; geometry covered by `PageCurlRollTest`.
- While publisher styles are off (`readium-advanced-on`), the injected Moon-mode stylesheet and
  script drop generated content, small caps, publisher fonts and `min-height`, keep empty
  paragraphs as blank lines and justify only start-aligned blocks. Publisher styles on: untouched.

### 2026-11-13 — PDFs opened from a file descriptor (Q02-08)

`pdf/StreamingPdfium.kt`, `ReadiumReader.kt`, `navigators/PdfNavigator.kt`,
`fragments/PdfReaderFragment.kt`, `android/build.gradle`:

- Readium 3.4.0's `PdfiumDocumentFactory` opens a PDF from disk only for `file://` resources.
  Quill's books are `content://`, so every PDF was read whole into one `ByteArray`: large PDFs ran
  out of memory, and one over 2 GiB could never open ("The resource is too large to be read on
  this device"). `StreamingPdfiumDocumentFactory` opens `content://` and `file://` PDFs in PDFium
  from a `ParcelFileDescriptor`; anything else, or any failure, falls back to Readium's factory.
  It does not hash the whole file for the (unused) publication identifier.
- Readium's `PdfiumDocumentFragment` builds its own factory and has an internal constructor, so
  `StreamingPdfiumDocumentFragment` is a copy of it using the new factory, and
  `StreamingPdfiumEngineProvider` delegates everything else to `PdfiumEngineProvider`.
  `AndroidPdfViewer` 3.2.8 (the version Readium already uses at runtime) is declared so these
  compile. Drop all three when Readium opens content:// PDFs by descriptor itself.
