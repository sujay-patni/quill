// Native engine reader (Quill Dev preview, book design off): Moon Reader-style — only the
// chunk around the reader is laid out; the rest of the book is counted in the background for
// screen page numbers.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../library/annotations.dart';
import '../library/book.dart';
import '../library/dictionary.dart';
import '../library/library.dart';
import '../library/stats.dart';
import '../oak.dart';
import '../reader/device_controls.dart';
import '../library/names.dart';
import '../reader/finish_prompt.dart';
import '../reader/perf_log.dart';
import '../reader/position_log.dart';
import '../reader/reader_options.dart';
import '../reader/reader_page.dart';
import '../reader/reading_profile.dart';
import '../reader/status_line.dart';
import '../shelf/book_info_page.dart';
import 'blocks.dart';
import 'book_pages.dart';
import 'hyphenation.dart';
import 'native_book.dart';
import 'page_curl.dart';
import 'page_view.dart';
import 'paginator.dart';

class NativeReaderPage extends StatefulWidget {
  const NativeReaderPage({super.key, required this.library, required this.book, this.profile});

  final Library library;
  final Book book;

  /// Settings to use instead of the saved ones (tests).
  final ReadingProfile? profile;

  @override
  State<NativeReaderPage> createState() => _NativeReaderPageState();
}

/// A page of the book: spine item, chunk of that chapter, page within the chunk.
typedef _Loc = ({int spine, int chunk, int page});

class _NativeReaderPageState extends State<NativeReaderPage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _clock = Stopwatch()..start();
  late final _device = DeviceControls(onVolumeKey: (forward) => forward ? _next() : _previous());
  ReadingProfile _profile = const ReadingProfile();
  NativeBook? _book;
  String? _error;
  bool _controls = false;
  bool _firstPainted = false;

  // Where the reader is. Blocks and layouts are kept for this chapter and its neighbours.
  _Loc _loc = (spine: 0, chunk: 0, page: 0);
  NativePosition? _target; // place to show once the chapter is laid out
  final Map<int, List<Block>> _blocks = {};
  final Map<int, ChapterLayout> _layouts = {};
  PageStyle? _style;
  int get _spine => _loc.spine;

  // A page turn in flight: the moving sheet and the page beneath it, as images of whole scenes.
  late final _turn = AnimationController(vsync: this, value: 0);
  ui.Image? _front, _under;
  bool _forward = true;
  bool _commit = true;
  _Loc? _dest;
  double _dragDx = 0;
  bool _dragging = false;
  final _prevKey = GlobalKey(), _currentKey = GlobalKey(), _nextKey = GlobalKey();

  // Decoded images for the visible pages (covers, illustrations).
  late final _images = PageImages((path) async {
    final width = (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round();
    return _book?.decodeImage(path, width);
  });

  // Book-wide screen pages (footer, slider, go to page).
  BookPages? _pages;
  int _countGeneration = 0;
  PageCountCache? _cache;
  DateTime _lastInput = DateTime.now();

  double? _preview; // slider thumb while dragging
  (int, int, int)? _highlight; // spine, start, end of a search match; cleared by the next move

  // Reading time for the statistics, time-left estimates, the finish prompt, brightness swipe.
  final _timer = ReadingTimer();
  double _wordsPerMinute = 226;
  bool _finishAsked = false;
  double? _brightnessShown;
  bool _bookOnly = false; // this book has its own settings

  // Bookmarks, highlights and notes of this book; the text selection (spine, start, end) and the
  // word the long press started on.
  AnnotationStore? _store;
  List<Annotation> _notes = const [];
  (int, int, int)? _selection;
  (int, int)? _anchor;
  final _dictionary = Dictionary();
  Timer? _auto; // auto page turn
  NativePosition? _returnTo; // place before a jump, for "Back to reading position"

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations(_portrait);
    _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auto?.cancel();
    _store?.removeListener(_onNotes);
    SystemChrome.setPreferredOrientations(const []);
    _saveTime();
    _countGeneration++;
    _turn.dispose();
    _images.dispose();
    _front?.dispose();
    _under?.dispose();
    PerfLog.stop();
    unawaited(_device.release());
    super.dispose();
  }

  Future<void> _open() async {
    final b = widget.book;
    try {
      final (profile, own) = widget.profile != null ? (widget.profile!, false) : await ReadingProfile.loadFor(b.id);
      _profile = profile;
      _bookOnly = own;
      if (profile.hyphenation) await _loadHyphenation();
      _wordsPerMinute = _readingSpeed();
      unawaited(_applyDevice(_profile));
      try {
        _cache = PageCountCache(File('${(await getApplicationSupportDirectory()).path}/page-counts.json'));
      } catch (_) {
        // No storage (tests, other platforms): counts are simply not cached.
      }
      final bytes = await NativeBook.readBytes(b.uri);
      final readMs = _clock.elapsedMilliseconds;
      final book = await NativeBook.open(bytes);
      final openMs = _clock.elapsedMilliseconds;
      // The same record of an open as the standard reader keeps: when, and the book's own details.
      final at = DateTime.now().millisecondsSinceEpoch;
      final isbn = book.epub.identifiers.map(isbnFrom).firstWhere((i) => i.isNotEmpty, orElse: () => '');
      unawaited(widget.library
          .update(
            b.id,
            (x) => x.copyWith(
              touched: true,
              opened: at,
              title: metadataTitle(x.title, x.name, book.epub.title),
              author: metadataAuthor(x.author, x.name, book.epub.authors),
              isbn: x.isbn.isEmpty ? isbn : x.isbn,
              addedAt: x.addedAt == 0 ? at : x.addedAt,
            ),
          )
          .catchError((_) {}));
      final spine = b.locator.isEmpty ? 0 : book.spineOf(_hrefOf(b.locator));
      if (spine < 0) {
        // Never guess a place: the saved chapter is not found, so read this book the standard way.
        PositionLog.record(b.id, 'native_fallback', {'reason': 'chapter not found'});
        if (mounted) _openStandard(turnOff: false);
        return;
      }
      final blocks = await book.chapter(spine);
      final target = book.fromLocator(b.locator, (_) => blocks);
      PositionLog.record(b.id, 'native_open', {
        'readMs': readMs,
        'openMs': openMs,
        'parsedMs': _clock.elapsedMilliseconds,
        'spine': target.spine,
        'approximate': target.approximate,
      });
      PerfLog.start(b.id);
      try {
        final store = await widget.library.annotations();
        store.addListener(_onNotes);
        _store = store;
        _notes = store.forBook(b.id);
      } catch (_) {
        // No storage: reading works, annotations are unavailable.
      }
      if (!mounted) return;
      setState(() {
        _book = book;
        _blocks[target.spine] = blocks;
        _loc = (spine: target.spine, chunk: 0, page: 0);
        _target = target;
      });
      _preload();
    } catch (e) {
      PositionLog.record(b.id, 'native_open_failed', {'elapsedMs': _clock.elapsedMilliseconds, 'error': '$e'});
      if (mounted) setState(() => _error = 'This book could not be opened in the native reader. Your place is unchanged.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _saveTime();
  }

  void _saveTime() {
    final spans = _timer.stop(DateTime.now());
    if (spans.isNotEmpty) widget.library.recordReading(widget.book.id, spans, progress: _progress);
  }

  // Words per minute from the imported reading history, as in the standard reader.
  double _readingSpeed() {
    var words = 0, ms = 0;
    for (final days in widget.library.stats.byBook.values) {
      for (final d in days) {
        if ((d.wordsImported ?? 0) > 0 && d.ms > 0) {
          words += d.wordsImported!;
          ms += d.ms;
        }
      }
    }
    final wpm = ms < 3600000 ? 0.0 : words / (ms / 60000);
    return wpm >= 80 && wpm <= 800 ? wpm : 226;
  }

  // About six characters per word, spaces included.
  int _minutes(num characters) => (characters / 6 / _wordsPerMinute).ceil();

  int? _chapterMinutes(_Loc l, int? offset) {
    final book = _book, blocks = _blocks[l.spine];
    if (book == null || blocks == null || offset == null) return null;
    final at = NativePosition(l.spine, offset);
    return _minutes(book.chapterEnd(at, blocks) - offset);
  }

  int? _bookMinutes(_Loc l, int? offset) {
    final book = _book, blocks = _blocks[l.spine];
    if (book == null || blocks == null || blocks.isEmpty || offset == null) return null;
    final sizes = book.epub.spineSizes;
    final bytes = sizes.fold<int>(0, (a, b) => a + b);
    if (bytes == 0 || sizes[l.spine] == 0) return null;
    // Characters per file byte in this chapter, applied to the rest of the book.
    final density = blocks.last.end / sizes[l.spine];
    final left = 1 - book.progressOf(NativePosition(l.spine, offset), blocks.last.end);
    return _minutes(left * bytes * density);
  }

  // Moon Reader: slide up or down along the left edge to change brightness.
  Future<void> _brightnessDrag(DragUpdateDetails d, double height) async {
    final start = _brightnessShown ?? _profile.brightness ?? await _device.systemBrightness();
    final next = (start - (d.primaryDelta ?? 0) / (height * 0.6)).clamp(0.02, 1.0);
    if (!mounted) return;
    setState(() => _brightnessShown = next);
    await _device.brightness(next);
  }

  void _brightnessEnd() {
    final value = _brightnessShown;
    if (value == null) return;
    final profile = _profile.copyWith(brightness: () => value);
    setState(() {
      _brightnessShown = null;
      _profile = profile;
    });
    unawaited(profile.save());
  }

  void _checkFinished() {
    final book = _book;
    final last = _dual ? (_after(_loc) ?? _loc) : _loc; // the last page on screen
    if (book == null || _finishAsked || last.spine != book.length - 1 || _pageAt(_loc) == null || _after(last) != null) return;
    final current = widget.library.books.where((b) => b.id == widget.book.id).firstOrNull;
    if (current == null || current.finished) return;
    _finishAsked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) askFinished(context, widget.library, widget.book.id);
    });
  }

  Future<void> _applyDevice(ReadingProfile p) async {
    await Future.wait([_device.keepAwake(p.keepAwake), _device.volumeKeys(p.volumeKeys), _device.brightness(p.brightness)]);
  }

  /// Leaves the preview for the WebView reader; [turnOff] also switches the preview off.
  Future<void> _openStandard({required bool turnOff}) async {
    if (turnOff) await _profile.copyWith(nativeEngine: false).save();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => ReaderPage(library: widget.library, book: widget.book)),
    );
  }

  static String _hrefOf(String locator) {
    final m = RegExp(r'"href"\s*:\s*"([^"]*)"').firstMatch(locator);
    return m?[1] ?? '';
  }

  // ---- Layout ----

  PageStyle _styleFor(BoxConstraints box) => PageStyle(
    width: _dual ? (box.maxWidth - _gutter) / 2 : box.maxWidth,
    height: box.maxHeight,
    fontFamily: _profile.fontFamily,
    fontSize: 16 * _profile.readiumFontSize,
    lineHeight: _profile.readiumLineHeight,
    ink: _profile.ink,
    link: _profile.theme.dark ? const Color(0xFF8AB4F8) : const Color(0xFF1A5FB4),
    paragraphSpacingEm: _profile.readiumParagraphSpacing / _profile.readiumFontSize,
    bold: _profile.boldText,
    // Only once the patterns are in memory, so the layout signature is truthful.
    hyphenate: _profile.hyphenation && Hyphenator.loaded != null,
    italic: _profile.italicText,
    underline: _profile.underlineText,
    shadow: _profile.textShadow,
  );

  // Called while laying out the page area. A new size or typography re-lays the chapter at the
  // same text and restarts the book count.
  void _setStyle(PageStyle style) {
    final old = _style;
    if (old != null && old.signature == style.signature && old.ink == style.ink && old.link == style.link) return;
    final current = _currentOffset();
    _style = style;
    _layouts.clear();
    if (current != null) _target ??= NativePosition(_spine, current);
    if (old?.signature != style.signature) {
      _pages = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _countBook());
    }
  }

  ChapterLayout? _layoutOf(int spine) {
    final style = _style, blocks = _blocks[spine];
    if (style == null || blocks == null) return null;
    return _layouts[spine] ??= ChapterLayout(blocks, style, imageSizes: _book?.imageSizes(spine) ?? const {});
  }

  LaidOutPage? _pageAt(_Loc l) {
    final layout = _layoutOf(l.spine);
    if (layout == null) return null;
    final pages = layout.pagesOf(l.chunk.clamp(0, layout.chunks.length - 1));
    return pages[l.page.clamp(0, pages.length - 1)];
  }

  /// The page after [l], or null at the book's end or while the next chapter is still loading.
  _Loc? _after(_Loc l) {
    final layout = _layoutOf(l.spine);
    if (layout == null) return null;
    if (l.page + 1 < layout.pagesOf(l.chunk).length) return (spine: l.spine, chunk: l.chunk, page: l.page + 1);
    if (l.chunk + 1 < layout.chunks.length) return (spine: l.spine, chunk: l.chunk + 1, page: 0);
    if (_layoutOf(l.spine + 1) != null) return (spine: l.spine + 1, chunk: 0, page: 0);
    return null;
  }

  _Loc? _before(_Loc l) {
    final layout = _layoutOf(l.spine);
    if (layout == null) return null;
    if (l.page > 0) return (spine: l.spine, chunk: l.chunk, page: l.page - 1);
    if (l.chunk > 0) return (spine: l.spine, chunk: l.chunk - 1, page: layout.pagesOf(l.chunk - 1).length - 1);
    final previous = _layoutOf(l.spine - 1);
    if (previous == null) return null;
    final chunk = previous.chunks.length - 1;
    return (spine: l.spine - 1, chunk: chunk, page: previous.pagesOf(chunk).length - 1);
  }

  // Two pages side by side (landscape, when switched on): a screen is this page and the next,
  // and a turn moves two pages.
  bool _dual = false;
  static const _gutter = 36.0;

  _Loc? _forwardOf(_Loc l) {
    if (!_dual) return _after(l);
    final right = _after(l);
    return right == null ? null : _after(right);
  }

  _Loc? _backOf(_Loc l) {
    final one = _before(l);
    if (!_dual || one == null) return one;
    return _before(one) ?? one;
  }

  int? _currentOffset() => _pageAt(_loc)?.start;

  NativePosition? get _here {
    final o = _currentOffset();
    return o == null ? null : NativePosition(_spine, o);
  }

  void _resolveTarget() {
    final t = _target;
    if (t == null) return;
    final layout = _layoutOf(t.spine);
    if (layout == null) return;
    final (chunk, page) = layout.pageAt(t.offset);
    _loc = (spine: t.spine, chunk: chunk, page: page);
    _target = null;
    // Footer and neighbour pages were built before this layout pass: refresh them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  // Keeps the neighbouring chapters parsed, so turns across a chapter boundary can animate.
  void _preload() {
    final book = _book;
    if (book == null) return;
    _blocks.removeWhere((s, _) => (s - _spine).abs() > 1);
    _layouts.removeWhere((s, _) => (s - _spine).abs() > 1);
    _layouts[_spine]?.keepOnly({_loc.chunk - 1, _loc.chunk, _loc.chunk + 1});
    for (final s in [_spine - 1, _spine + 1]) {
      if (s < 0 || s >= book.length || _blocks.containsKey(s)) continue;
      book.chapter(s).then((blocks) {
        if (mounted && (s - _spine).abs() <= 1) setState(() => _blocks[s] = blocks);
      });
    }
  }

  // ---- Book-wide page count (background) ----

  Future<bool> _idleFrame(int generation) async {
    do {
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted || generation != _countGeneration) return false;
    } while (DateTime.now().difference(_lastInput) < const Duration(milliseconds: 300));
    return true;
  }

  Future<void> _countBook() async {
    final book = _book, style = _style;
    if (book == null || style == null || !mounted) return;
    final generation = ++_countGeneration;
    final key = '${widget.book.id}|${widget.book.size}|${style.signature}';
    final cached = await _cache?.load(key);
    if (!mounted || generation != _countGeneration) return;
    if (cached != null && cached.chunkPages.length == book.length) {
      setState(() => _pages = cached);
      return;
    }
    final pages = BookPages(book.length);
    setState(() => _pages = pages);
    final clock = Stopwatch()..start();
    // The chapter being read first, so its page x/y appears early.
    for (final s in [_spine, for (var i = 0; i < book.length; i++) if (i != _spine) i]) {
      final blocks = await book.chapter(s);
      if (!mounted || generation != _countGeneration) return;
      final layout = ChapterLayout(blocks, style, imageSizes: book.imageSizes(s));
      final counts = <int>[];
      for (var c = 0; c < layout.chunks.length; c++) {
        if (!await _idleFrame(generation)) return;
        counts.add(layout.pagesOf(c).length);
        layout.keepOnly(const {});
      }
      pages.chunkPages[s] = counts;
      if (s == _spine || pages.complete) setState(() {});
    }
    PositionLog.record(widget.book.id, 'native_counted', {'pages': pages.total, 'elapsedMs': clock.elapsedMilliseconds});
    unawaited(_cache?.save(key, pages));
  }

  // ---- Moving ----

  void _touch() => _lastInput = DateTime.now();

  void _moveTo(_Loc to) {
    setState(() {
      _loc = to;
      _highlight = null;
      _selection = _anchor = null;
    });
    _preload();
    _save();
  }

  // A turn into a chapter that is not parsed yet: load it, then show it without animation.
  Future<void> _goToSpine(int spine, {required bool atEnd}) async {
    final book = _book!;
    if (spine < 0 || spine >= book.length) return;
    _blocks[spine] ??= await book.chapter(spine);
    if (!mounted) return;
    final layout = _layoutOf(spine);
    if (layout == null) return;
    final chunk = atEnd ? layout.chunks.length - 1 : 0;
    _moveTo((spine: spine, chunk: chunk, page: atEnd ? layout.pagesOf(chunk).length - 1 : 0));
  }

  void _moveInstant(bool forward) {
    final to = forward ? _forwardOf(_loc) : _backOf(_loc);
    if (to != null) {
      _moveTo(to);
    } else {
      unawaited(_goToSpine(_spine + (forward ? 1 : -1), atEnd: !forward));
    }
  }

  ui.Image? _capture(GlobalKey key) {
    try {
      final boundary = key.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) return null;
      return boundary.toImageSync(pixelRatio: MediaQuery.devicePixelRatioOf(context));
    } catch (_) {
      return null;
    }
  }

  // Starts a turn at progress 0 with both pages captured; false when it cannot animate.
  bool _beginTurn(bool forward) {
    final dest = forward ? _forwardOf(_loc) : _backOf(_loc);
    if (dest == null) return false;
    final current = _capture(_currentKey);
    final other = _capture(forward ? _nextKey : _prevKey);
    if (current == null || other == null) {
      current?.dispose();
      other?.dispose();
      return false;
    }
    _turn.stop();
    _turn.value = 0;
    setState(() {
      _selection = _anchor = null;
      _forward = forward;
      _dest = dest;
      // Forward: this page curls away over the next. Back: the previous page uncurls over this one.
      _front = forward ? current : other;
      _under = forward ? other : current;
    });
    return true;
  }

  void _endTurn(bool commit) {
    final dest = _dest;
    final front = _front, under = _under;
    setState(() {
      _front = null;
      _under = null;
      _dest = null;
      _dragging = false;
      if (commit && dest != null) {
        _loc = dest;
        _highlight = null;
      }
    });
    front?.dispose();
    under?.dispose();
    if (commit && dest != null) {
      _preload();
      _save();
    }
  }

  // A second turn while one is settling finishes the first at once (fast taps never queue).
  void _finishInFlight() {
    if (_front == null) return;
    _turn.stop();
    _endTurn(_commit);
  }

  void _settle(bool commit, {Duration? duration}) {
    _commit = commit;
    final target = commit ? 1.0 : 0.0;
    // Scaled with the chosen page-turn time (default 300 ms → up to 260 ms to settle).
    final full = _profile.turnMillis * 260 / 300;
    final d = duration ?? Duration(milliseconds: (full * (target - _turn.value).abs()).round().clamp(70, 1000));
    _turn.animateTo(target, duration: d, curve: const Cubic(0.25, 0, 0.2, 1)).then((_) {
      if (mounted && _front != null) _endTurn(commit);
    });
  }

  /// A tap or volume-key turn in the chosen style.
  void _turnPage(bool forward) {
    _touch();
    _finishInFlight();
    if (_profile.pageTurn == PageTurn.none || !_beginTurn(forward)) {
      _moveInstant(forward);
      return;
    }
    _settle(true, duration: Duration(milliseconds: _profile.turnMillis));
  }

  void _next() => _turnPage(true);
  void _previous() => _turnPage(false);

  void _onDragUpdate(DragUpdateDetails d, double width) {
    _touch();
    _dragDx += d.delta.dx;
    if (!_dragging) {
      if (_dragDx.abs() < 2 || _profile.pageTurn == PageTurn.none) return;
      _finishInFlight();
      if (!_beginTurn(_dragDx < 0)) return;
      _dragging = true;
    }
    _turn.value = ((_forward ? -_dragDx : _dragDx) / width).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final wasDragging = _dragging;
    final dx = _dragDx;
    _dragDx = 0;
    _dragging = false;
    if (!wasDragging) {
      // No animated turn was possible (style none, or the next chapter is still loading).
      if (v < -200 || dx < -40) _moveInstant(true);
      if (v > 200 || dx > 40) _moveInstant(false);
      return;
    }
    final along = _forward ? -v : v; // speed in the turn's own direction
    _settle(along > 300 || (_turn.value > 0.35 && along > -300));
  }

  /// An intentional jump (slider, contents, typed page): remembers the place for jump-back.
  Future<void> _jumpTo(NativePosition to, {bool remember = true, (int, int, int)? highlight}) async {
    _touch();
    _finishInFlight();
    final book = _book!;
    final from = _here;
    _blocks[to.spine] ??= await book.chapter(to.spine);
    if (!mounted) return;
    setState(() {
      if (remember) _returnTo ??= from;
      _loc = (spine: to.spine, chunk: 0, page: 0);
      _target = to;
      _preview = null;
      _highlight = highlight;
      _selection = _anchor = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preload();
      _save();
    });
  }

  // Only the reader's own moves save a place, so an approximate open never overwrites it.
  void _save() {
    final book = _book, here = _here, blocks = _blocks[_spine];
    if (book == null || here == null || blocks == null) return;
    final saved = widget.library.books.where((b) => b.id == widget.book.id).firstOrNull?.locator ?? '';
    final json = book.toLocator(here, blocks, previous: saved);
    final progress = book.progressOf(here, blocks.isEmpty ? 0 : blocks.last.end);
    PositionLog.record(widget.book.id, 'save', {'spine': here.spine, 'offset': here.offset, 'engine': 'native'});
    _timer.activity(DateTime.now(), pageTurn: true);
    _checkFinished();
    unawaited(widget.library
        .update(widget.book.id, (b) => b.copyWith(locator: json, progress: progress, approximate: false, touched: true))
        .catchError((_) {}));
  }

  // ---- Progress, slider, pages ----

  int? get _bookPage => _pages?.bookPage(_loc.spine, _loc.chunk, _loc.page);
  int? get _total => _pages?.total;

  double get _progress {
    final total = _total, page = _bookPage;
    if (total != null && page != null) return total <= 1 ? 0 : page / (total - 1);
    final book = _book, here = _here, blocks = _blocks[_spine];
    if (book == null || here == null || blocks == null) return 0;
    return book.progressOf(here, blocks.isEmpty ? 0 : blocks.last.end);
  }

  Future<void> _goToBookPage(int page) async {
    final pages = _pages, book = _book, style = _style;
    if (pages == null || !pages.complete || book == null || style == null) return;
    final (spine, chunk, inChunk) = pages.locate(page);
    final blocks = await book.chapter(spine);
    final layout = ChapterLayout(blocks, style, imageSizes: book.imageSizes(spine));
    final list = layout.pagesOf(chunk.clamp(0, layout.chunks.length - 1));
    await _jumpTo(NativePosition(spine, list[inChunk.clamp(0, list.length - 1)].start));
  }

  Future<void> _goToProgress(double v) async {
    final total = _total;
    if (total != null) return _goToBookPage((v * (total - 1)).round());
    // Before the count finishes: by chapter size.
    final book = _book!;
    final sizes = book.epub.spineSizes;
    final all = sizes.fold<int>(0, (a, b) => a + b);
    var left = v * all;
    var spine = 0;
    while (spine < sizes.length - 1 && left > sizes[spine]) {
      left -= sizes[spine++];
    }
    final blocks = await book.chapter(spine);
    final length = blocks.isEmpty ? 0 : blocks.last.end;
    final fraction = sizes[spine] == 0 ? 0.0 : (left / sizes[spine]).clamp(0.0, 1.0);
    await _jumpTo(NativePosition(spine, (fraction * length).floor().clamp(0, length > 0 ? length - 1 : 0)));
  }

  Future<void> _askPage() async {
    final total = _total;
    if (total == null) return;
    final controller = TextEditingController(text: '${(_bookPage ?? 0) + 1}');
    final page = await showDialog<int>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Go to page'),
        content: TextField(
          key: const Key('pageField'),
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'Page (1–$total)', helperText: 'Screen pages at this text size'),
          onSubmitted: (v) => Navigator.pop(dialog, int.tryParse(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialog, int.tryParse(controller.text)), child: const Text('Go')),
        ],
      ),
    );
    if (page != null && page >= 1 && page <= total) await _goToBookPage(page - 1);
  }

  // ---- Contents ----

  int get _tocIndex {
    final book = _book, here = _here;
    return book == null || here == null ? -1 : book.tocIndexAt(here, _blocks[_spine] ?? const []);
  }

  Future<void> _goToToc(int index) async {
    final to = await _book!.positionOfToc(index);
    if (to != null) await _jumpTo(to);
  }

  Future<void> _stepChapter(int step) async {
    final book = _book!, here = _here;
    if (here == null || book.toc.isEmpty) return;
    final i = _tocIndex;
    if (step > 0) {
      if (i + 1 < book.toc.length) await _goToToc(i + 1);
      return;
    }
    // Back: to this chapter's start first, then to the previous chapter.
    final start = i < 0 ? null : await book.positionOfToc(i);
    if (start != null && (start.spine != here.spine || start.offset < here.offset)) {
      await _jumpTo(start);
    } else if (i > 0) {
      await _goToToc(i - 1);
    }
  }

  void _showContents() {
    final book = _book!;
    final current = _tocIndex;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SizedBox(
        height: MediaQuery.sizeOf(sheet).height * 0.75,
        child: DefaultTabController(
          length: 2,
          child: Column(children: [
            const TabBar(tabs: [Tab(text: 'Contents'), Tab(text: 'Bookmarks & notes')]),
            Expanded(
              child: TabBarView(children: [
                ListView.builder(
                  key: const Key('nativeContents'),
                  itemCount: book.toc.length,
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.only(left: 16 + 18.0 * book.toc[i].depth, right: 16),
                    selected: i == current,
                    title: Text(book.toc[i].title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: i == current ? const Icon(Icons.check, size: 18) : null,
                    onTap: () {
                      Navigator.pop(sheet);
                      _goToToc(i);
                    },
                  ),
                ),
                StatefulBuilder(
                  builder: (context, setList) => Column(
                    children: [
                      Expanded(
                        child: _notes.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No bookmarks or highlights yet.\nLong-press a word to select text; use ⋮ to bookmark a page.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          key: const Key('nativeNotes'),
                          itemCount: _notes.length + 1,
                          itemBuilder: (_, n) {
                            if (n == 0) {
                              return Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  key: const Key('copyNotes'),
                                  icon: const Icon(Icons.copy, size: 18),
                                  label: const Text('Copy all as text'),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: annotationsAsText(widget.book.title, _notes)));
                                    ScaffoldMessenger.of(sheet).showSnackBar(const SnackBar(content: Text('Copied')));
                                  },
                                ),
                              );
                            }
                            final i = n - 1;
                            final a = _notes[i];
                            return ListTile(
                              dense: true,
                              leading: a.kind == AnnotationKind.bookmark
                                  ? const Icon(Icons.bookmark, color: Color(0xFFB3261E))
                                  : CircleAvatar(radius: 9, backgroundColor: Color(highlightColors[a.color % highlightColors.length])),
                              title: Text(a.quote.isEmpty ? 'Bookmark' : a.quote, maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                [if (a.chapter.isNotEmpty) a.chapter, if (a.note.isNotEmpty) 'Note: ${a.note}'].join('\n'),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline, size: 20),
                                onPressed: () async {
                                  await _store?.remove(a.id);
                                  setList(() {});
                                },
                              ),
                              onTap: () {
                                Navigator.pop(sheet);
                                _goToNote(a);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  void _showSearch() {
    final book = _book!;
    var results = <(NativePosition, String, String)>[]; // place, chapter title, snippet
    var searching = false;
    var generation = 0;
    var matchLength = 0;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) {
          Future<void> run(String query) async {
            final mine = ++generation;
            matchLength = query.trim().length;
            setSheet(() {
              results = [];
              searching = query.trim().isNotEmpty;
            });
            if (query.trim().isEmpty) return;
            for (var s = 0; s < book.length && results.length < 200; s++) {
              final hits = await book.search(s, query.trim());
              if (!sheet.mounted || mine != generation) return;
              if (hits.isEmpty) continue;
              final blocks = await book.chapter(s);
              if (!sheet.mounted || mine != generation) return;
              setSheet(() => results = [
                ...results,
                for (final (offset, snippet) in hits)
                  (NativePosition(s, offset), book.titleAt(NativePosition(s, offset), blocks), snippet),
              ]);
            }
            if (sheet.mounted && mine == generation) setSheet(() => searching = false);
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
            child: SizedBox(
              height: MediaQuery.sizeOf(sheet).height * 0.7,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    key: const Key('nativeSearchField'),
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(hintText: 'Search in book', prefixIcon: Icon(Icons.search)),
                    onSubmitted: run,
                  ),
                ),
                if (searching) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: results.isEmpty
                      ? Center(child: Text(searching ? 'Searching…' : 'Type a word or phrase and press search'))
                      : ListView.builder(
                          key: const Key('nativeSearchResults'),
                          itemCount: results.length,
                          itemBuilder: (_, i) {
                            final (place, title, snippet) = results[i];
                            return ListTile(
                              dense: true,
                              title: Text(snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: title.isEmpty ? null : Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                              onTap: () {
                                Navigator.pop(sheet);
                                _jumpTo(place, highlight: (place.spine, place.offset, place.offset + matchLength));
                              },
                            );
                          },
                        ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ---- Bookmarks, highlights, notes, selection ----

  void _onNotes() {
    if (mounted) setState(() => _notes = _store?.forBook(widget.book.id) ?? const []);
  }

  static const _selectionColor = Color(0x553F8CFF);

  /// Tints for a chapter's pages: its highlights and the current selection.
  List<(int, int, Color)> _marksFor(int spine) => [
    for (final a in _notes)
      if (a.kind == AnnotationKind.highlight && a.spine == spine)
        (a.start, a.end, Color(highlightColors[a.color % highlightColors.length]).withValues(alpha: 0.42)),
    if (_selection != null && _selection!.$1 == spine) (_selection!.$2, _selection!.$3, _selectionColor),
  ];

  String _textOf(int spine, int start, int end) {
    final out = StringBuffer();
    for (final b in _blocks[spine] ?? const <Block>[]) {
      if (b.kind != BlockKind.text || b.end <= start || b.start >= end) continue;
      if (out.isNotEmpty) out.write(' ');
      out.write(b.text.substring((start - b.start).clamp(0, b.text.length), (end - b.start).clamp(0, b.text.length)));
    }
    return out.toString().replaceAll('\n', ' ').trim();
  }

  /// The page under a point of the gesture area, and the point in that page's coordinates.
  (_Loc, LaidOutPage, Offset)? _pageUnder(Offset local) {
    final p = _profile;
    var at = local - Offset(p.sideMargin.toDouble(), p.frameTop(MediaQuery.viewPaddingOf(context).top));
    var loc = _loc;
    if (_dual) {
      final column = (MediaQuery.sizeOf(context).width - p.sideMargin - p.rightMargin - _gutter) / 2;
      if (at.dx > column + _gutter / 2) {
        final right = _after(_loc);
        if (right == null) return null;
        loc = right;
        at = at.translate(-(column + _gutter), 0);
      }
    }
    final page = _pageAt(loc);
    return page == null ? null : (loc, page, at);
  }

  void _selectAt(Offset local, {required bool start}) {
    final under = _pageUnder(local);
    final hit = under?.$2.hitTest(under.$3);
    if (under == null || hit == null) return;
    final word = hit.$2;
    setState(() {
      if (start || _anchor == null || _selection?.$1 != under.$1.spine) {
        _anchor = word;
        _selection = (under.$1.spine, word.$1, word.$2);
      } else {
        final a = _anchor!;
        _selection = (under.$1.spine, word.$1 < a.$1 ? word.$1 : a.$1, word.$2 > a.$2 ? word.$2 : a.$2);
      }
    });
  }

  // ---- Selection handles: drag either end of the selection to change it ----

  // Where a shown page's text area starts on the screen (the inverse of [_pageUnder]).
  Offset _originOf(_Loc loc) {
    final p = _profile;
    var origin = Offset(p.sideMargin.toDouble(), p.frameTop(MediaQuery.viewPaddingOf(context).top));
    if (_dual && loc != _loc) {
      final column = (MediaQuery.sizeOf(context).width - p.sideMargin - p.rightMargin - _gutter) / 2;
      origin = origin.translate(column + _gutter, 0);
    }
    return origin;
  }

  // The end being dragged takes the character under the finger (a little above it, so the
  // finger does not cover the line); if it crosses the other end, the ends swap.
  void _dragHandle(bool isStart, Offset at) {
    final sel = _selection;
    final under = _pageUnder(at.translate(0, -18));
    final hit = under?.$2.hitTest(under.$3);
    if (sel == null || under == null || hit == null || under.$1.spine != sel.$1) return;
    final fixed = isStart ? sel.$3 : sel.$2;
    final moved = hit.$1;
    if (moved == fixed) return;
    final a = moved < fixed ? moved : fixed, b = moved < fixed ? fixed : moved + 1;
    _draggingStart = moved < fixed;
    setState(() {
      _selection = (sel.$1, a, b);
      _anchor = (a, b);
    });
  }

  bool? _draggingStart;

  List<Widget> _selectionHandles() {
    final sel = _selection;
    if (sel == null) return const [];
    final out = <Widget>[];
    Widget handle(Offset at, bool isStart) => Positioned(
      left: at.dx - 22,
      top: at.dy - 4,
      width: 44,
      height: 44,
      child: GestureDetector(
        key: Key(isStart ? 'selectionStart' : 'selectionEnd'),
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => _draggingStart = isStart,
        onPanUpdate: (d) => _dragHandle(_draggingStart ?? isStart, d.globalPosition),
        onPanEnd: (_) => _draggingStart = null,
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1A73E8),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isStart ? 8 : 0),
                topRight: Radius.circular(isStart ? 0 : 8),
                bottomLeft: const Radius.circular(8),
                bottomRight: const Radius.circular(8),
              ),
            ),
          ),
        ),
      ),
    );
    for (final loc in [_loc, if (_dual) ?_after(_loc)]) {
      final page = _pageAt(loc);
      if (page == null || loc.spine != sel.$1) continue;
      final (first, last) = page.rangeEnds(sel.$2, sel.$3);
      final origin = _originOf(loc);
      if (first != null) out.add(handle(first + origin, true));
      if (last != null) out.add(handle(last + origin, false));
    }
    return out;
  }

  void _clearSelection() {
    if (_selection != null) setState(() => _selection = _anchor = null);
  }

  // A tap on a link: footnotes open as a pop-up, other links jump (with jump-back).
  bool _followLinkAt(Offset local) {
    final under = _pageUnder(local);
    final hit = under?.$2.hitTest(under.$3);
    if (under == null || hit == null) return false;
    final spine = under.$1.spine;
    final block = (_blocks[spine] ?? const <Block>[]).where((b) => b.start <= hit.$1 && hit.$1 < b.end).firstOrNull;
    final run = block?.runAt(hit.$1 - block.start);
    final href = run?.href;
    if (run == null || href == null) return false;
    // Only when the finger is really on the link's glyphs, not merely on its line.
    final onText = under.$2.rangeContains(hit.$2.$1, hit.$2.$2, under.$3);
    if (!onText) return false;
    _openLink(spine, run);
    return true;
  }

  Future<void> _openLink(int spine, Run run) async {
    final book = _book!;
    final to = await book.resolveLink(spine, run.href!);
    if (to == null || !mounted) return;
    final blocks = await book.chapter(to.spine);
    if (!mounted) return;
    // A note: marked as one by the book, or a short reference (number, asterisk) to a short passage.
    final at = blocks.indexWhere((b) => b.start <= to.offset && to.offset < b.end);
    final target = at < 0 ? null : blocks[at];
    final marker = RegExp(r'^[\[\(]?[\d*†‡§a-z]{1,3}[\]\)]?$').hasMatch(run.text.trim());
    if (target != null && target.kind == BlockKind.text && (run.noteRef || (marker && target.text.length < 1200))) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheet) => ConstrainedBox(
          key: const Key('footnoteSheet'),
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.5),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(target.text, style: Theme.of(sheet).textTheme.bodyLarge),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(sheet);
                    _jumpTo(to);
                  },
                  child: const Text('Go to note'),
                ),
              ),
            ]),
          ),
        ),
      );
      return;
    }
    await _jumpTo(to);
  }

  Annotation? _highlightAt(Offset local) {
    final under = _pageUnder(local);
    final hit = under?.$2.hitTest(under.$3);
    if (under == null || hit == null) return null;
    return _notes
        .where((a) => a.kind == AnnotationKind.highlight && a.spine == under.$1.spine && a.start <= hit.$1 && hit.$1 < a.end)
        .firstOrNull;
  }

  String _chapterTitle(int spine, int offset) =>
      _book?.titleAt(NativePosition(spine, offset), _blocks[spine] ?? const []) ?? '';

  Future<Annotation?> _highlightSelection(int color) async {
    final sel = _selection, store = _store, book = _book;
    if (sel == null || store == null || book == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final a = Annotation(
      id: store.newId(),
      bookId: widget.book.id,
      kind: AnnotationKind.highlight,
      spine: sel.$1,
      start: sel.$2,
      end: sel.$3,
      href: book.epub.spine[sel.$1].href,
      quote: _textOf(sel.$1, sel.$2, sel.$3),
      color: color,
      chapter: _chapterTitle(sel.$1, sel.$2),
      created: now,
      updated: now,
      locator: book.toLocator(NativePosition(sel.$1, sel.$2), await book.chapter(sel.$1)),
    );
    _clearSelection();
    await store.put(a);
    return a;
  }

  // A note made here has an exact place; a bookmark from the standard reader has a locator,
  // which converts approximately.
  Future<void> _goToNote(Annotation a) async {
    final book = _book;
    if (book == null) return;
    if (a.spine >= 0) return _jumpTo(NativePosition(a.spine, a.start));
    try {
      final spine = book.spineOf(_hrefOf(a.locator));
      if (spine < 0) return;
      final blocks = await book.chapter(spine);
      await _jumpTo(book.fromLocator(a.locator, (_) => blocks));
    } catch (_) {}
  }

  Annotation? get _bookmarkHere {
    final page = _pageAt(_loc);
    if (page == null) return null;
    return _notes
        .where((a) => a.kind == AnnotationKind.bookmark && a.spine == _spine && a.start >= page.start && a.start < page.end)
        .firstOrNull;
  }

  Future<void> _toggleBookmark() async {
    final store = _store, book = _book, page = _pageAt(_loc);
    if (store == null || book == null || page == null) return;
    final existing = _bookmarkHere;
    if (existing != null) return store.remove(existing.id);
    final now = DateTime.now().millisecondsSinceEpoch;
    await store.put(Annotation(
      id: store.newId(),
      bookId: widget.book.id,
      kind: AnnotationKind.bookmark,
      spine: _spine,
      start: page.start,
      end: page.start,
      href: book.epub.spine[_spine].href,
      quote: _textOf(_spine, page.start, page.start + 90),
      chapter: _chapterTitle(_spine, page.start),
      created: now,
      updated: now,
      locator: book.toLocator(NativePosition(_spine, page.start), await book.chapter(_spine)),
    ));
  }

  Future<void> _editHighlight(Annotation a) async {
    final store = _store;
    if (store == null) return;
    var color = a.color;
    final note = TextEditingController(text: a.note);
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('“${a.quote}”', maxLines: 3, overflow: TextOverflow.ellipsis, style: Theme.of(sheet).textTheme.bodyMedium),
            const SizedBox(height: 12),
            Row(children: [
              for (var c = 0; c < highlightColors.length; c++)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: InkWell(
                    key: Key('editColor$c'),
                    customBorder: const CircleBorder(),
                    onTap: () => setSheet(() => color = c),
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(highlightColors[c]),
                      child: c == color ? const Icon(Icons.check, size: 16, color: Colors.black87) : null,
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 8),
            TextField(
              key: const Key('noteField'),
              controller: note,
              minLines: 1,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Note'),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(key: const Key('deleteHighlight'), onPressed: () => Navigator.pop(sheet, 'delete'), child: const Text('Delete')),
              const SizedBox(width: 8),
              FilledButton(key: const Key('saveHighlight'), onPressed: () => Navigator.pop(sheet, 'save'), child: const Text('Save')),
            ]),
          ]),
        ),
      ),
    );
    if (result == 'delete') {
      await store.remove(a.id);
    } else if (result == 'save') {
      await store.put(a.copyWith(note: note.text.trim(), color: color, updated: DateTime.now().millisecondsSinceEpoch));
    }
  }

  Future<void> _define() async {
    final sel = _selection;
    if (sel == null) return;
    final text = _textOf(sel.$1, sel.$2, sel.$3);
    DictionaryEntry? entry;
    try {
      entry = await _dictionary.lookup(text);
    } catch (_) {
      entry = null;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => ConstrainedBox(
        key: const Key('dictionarySheet'),
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.6),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(entry?.word ?? text, style: Theme.of(sheet).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (entry == null)
              const Text('No definition found in the offline dictionary.')
            else
              for (final (i, (pos, definition)) in entry.senses.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${i + 1}. $pos  ', style: const TextStyle(fontStyle: FontStyle.italic)),
                    TextSpan(text: definition),
                  ])),
                ),
            const SizedBox(height: 4),
            Text(Dictionary.credit, style: Theme.of(sheet).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  // The actions for the selected text, floating above the footer.
  Widget _selectionBar() {
    final sel = _selection!;
    return Positioned(
      left: 12,
      right: 12,
      bottom: 64,
      child: Center(
        child: Material(
          key: const Key('selectionBar'),
          elevation: 6,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var c = 0; c < highlightColors.length; c++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: InkWell(
                    key: Key('highlightColor$c'),
                    customBorder: const CircleBorder(),
                    onTap: () => _highlightSelection(c),
                    child: CircleAvatar(radius: 13, backgroundColor: Color(highlightColors[c])),
                  ),
                ),
              IconButton(
                key: const Key('selectionNote'),
                tooltip: 'Note',
                icon: const Icon(Icons.edit_note),
                onPressed: () async {
                  final a = await _highlightSelection(0);
                  if (a != null && mounted) await _editHighlight(a);
                },
              ),
              IconButton(
                key: const Key('selectionDictionary'),
                tooltip: 'Dictionary',
                icon: const Icon(Icons.menu_book_outlined, size: 20),
                onPressed: _define,
              ),
              IconButton(
                key: const Key('selectionCopy'),
                tooltip: 'Copy',
                icon: const Icon(Icons.copy, size: 20),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _textOf(sel.$1, sel.$2, sel.$3)));
                  _clearSelection();
                },
              ),
              IconButton(tooltip: 'Cancel', icon: const Icon(Icons.close, size: 20), onPressed: _clearSelection),
            ]),
          ),
        ),
      ),
    );
  }

  // ---- Options ----

  Future<void> _loadHyphenation() async {
    try {
      await Hyphenator.english();
    } catch (_) {
      // Patterns unavailable: text simply stays unhyphenated.
    }
  }

  void _setProfile(ReadingProfile profile) {
    setState(() => _profile = profile);
    if (profile.hyphenation && Hyphenator.loaded == null) {
      _loadHyphenation().then((_) {
        if (mounted) setState(() {});
      });
    }
    unawaited(_bookOnly ? profile.saveFor(widget.book.id) : profile.save());
    unawaited(_applyDevice(profile));
    // Book design on, or the preview switched off: this book continues in the standard reader.
    if (profile.publisherStyles || !profile.nativeEngine) _openStandard(turnOff: false);
  }

  // Switches between this book's own settings and the usual ones.
  Future<void> _setBookOnly(bool own) async {
    if (own) {
      await _profile.saveFor(widget.book.id);
      if (mounted) setState(() => _bookOnly = true);
    } else {
      await ReadingProfile.clearFor(widget.book.id);
      final usual = await ReadingProfile.load();
      if (!mounted) return;
      setState(() {
        _bookOnly = false;
        _profile = usual;
      });
      unawaited(_applyDevice(usual));
    }
  }

  void _toggleAuto() {
    if (_auto != null) return _stopAuto();
    setState(() {
      _controls = false;
      _auto = Timer.periodic(Duration(seconds: _profile.autoTurnSeconds), (_) {
        if (_forwardOf(_loc) == null && _spine == (_book?.length ?? 1) - 1) return _stopAuto();
        _turnPage(true);
      });
    });
  }

  void _stopAuto() {
    if (_auto == null) return;
    _auto!.cancel();
    if (mounted) setState(() => _auto = null);
  }

  void _run(ReaderAction action) {
    final hasContents = _book?.toc.isNotEmpty ?? false;
    switch (action) {
      case ReaderAction.none:
        break;
      case ReaderAction.nextPage:
        _next();
      case ReaderAction.previousPage:
        _previous();
      case ReaderAction.nextChapter:
        if (hasContents) _stepChapter(1);
      case ReaderAction.previousChapter:
        if (hasContents) _stepChapter(-1);
      case ReaderAction.contents:
        if (hasContents) _showContents();
      case ReaderAction.search:
        _showSearch();
      case ReaderAction.bookInfo:
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => BookInfoPage(library: widget.library, bookId: widget.book.id)),
        );
      case ReaderAction.dayNight:
        _setProfile(_profile.copyWith(night: !_profile.night));
      case ReaderAction.options:
        setState(() => _controls = true);
      case ReaderAction.autoTurn:
        _toggleAuto();
    }
  }

  void _onStatusTap(TapUpDetails d, double width) {
    _touch();
    _run(d.localPosition.dx < width / 2 ? _profile.statusLeft : _profile.statusRight);
  }

  // Reading is portrait unless the orientation button is used, as in the standard reader.
  static const _portrait = [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown];
  bool _landscape = false;

  void _toggleOrientation() {
    setState(() => _landscape = !_landscape);
    SystemChrome.setPreferredOrientations(
      _landscape ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight] : _portrait,
    );
  }

  void _onTap(TapUpDetails d, double width) {
    _touch();
    if (_auto != null) return _stopAuto();
    if (_selection != null) return _clearSelection();
    final x = d.localPosition.dx;
    final tapped = _controls ? null : _highlightAt(d.localPosition);
    if (tapped != null) {
      _editHighlight(tapped);
      return;
    }
    if (!_controls && _followLinkAt(d.localPosition)) return;
    if (_controls) {
      setState(() => _controls = false);
    } else if (x < width / 3) {
      _previous();
    } else if (x > width * 2 / 3) {
      _next();
    } else {
      setState(() => _controls = true);
    }
  }

  // Taps and swipes work across the whole page, margins included (the current scene only).
  Widget _gestures(bool current, Widget child) {
    if (!current) return child;
    final width = MediaQuery.sizeOf(context).width;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => _onTap(d, width),
      onHorizontalDragStart: (_) {
        _stopAuto();
        _dragDx = 0;
      },
      onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
      onHorizontalDragEnd: _onDragEnd,
      // Long press selects a word; keep holding and move to extend. It never turns the page.
      onLongPressStart: (d) {
        _stopAuto();
        _selectAt(d.localPosition, start: true);
      },
      onLongPressMoveUpdate: (d) => _selectAt(d.localPosition, start: false),
      onVerticalDragEnd: _profile.swipeUp == ReaderAction.none && _profile.swipeDown == ReaderAction.none
          ? null
          : (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -300) _run(_profile.swipeUp);
              if (v > 300) _run(_profile.swipeDown);
            },
      child: child,
    );
  }

  // In two-page mode, [left] with the following page beside it.
  Widget _spread(Widget left, _Loc? at) {
    if (!_dual) return left;
    final next = at == null ? null : _after(at);
    final right = next == null ? null : _pageAt(next);
    return Row(children: [
      Expanded(child: left),
      const SizedBox(width: _gutter),
      Expanded(
        child: right == null ? const SizedBox.expand() : NativePage(page: right, paper: const Color(0x00000000), images: _images, marks: _marksFor(next!.spine)),
      ),
    ]);
  }

  // One whole page as the reader sees it: paper, text area and footer. The current scene also
  // measures the text area and takes the gestures; neighbours exist to be captured for turns.
  Widget _scene(NativeBook book, _Loc? at, GlobalKey key, {required bool current}) {
    final p = _profile;
    final page = at == null || (!current && _style == null) ? null : (current ? null : _pageAt(at));
    final offset = current ? _currentOffset() : page?.start;
    final l = at ?? _loc;
    final bookPage = _pages?.bookPage(l.spine, l.chunk, l.page), total = _total;
    final chapterPage = _pages?.chapterPage(l.spine, l.chunk, l.page);
    final shownPage = at == null || _style == null ? null : _pageAt(at);
    final bookmarked = shownPage != null &&
        _notes.any((a) => a.kind == AnnotationKind.bookmark && a.spine == l.spine && a.start >= shownPage.start && a.start < shownPage.end);
    return RepaintBoundary(
      key: key,
      child: ColoredBox(
        color: p.background,
        child: Stack(children: [
          Positioned.fill(
            child: DecoratedBox(
          decoration: BoxDecoration(
            image: p.paperTexture
                ? const DecorationImage(image: AssetImage('assets/paper.png'), repeat: ImageRepeat.repeat, scale: 1)
                : null,
          ),
          child: Column(children: [
            Expanded(
              child: _gestures(
                current,
                Padding(
                padding: EdgeInsets.fromLTRB(
                  p.sideMargin.toDouble(),
                  p.frameTop(MediaQuery.viewPaddingOf(context).top),
                  p.rightMargin.toDouble(),
                  p.frameBottom,
                ),
                child: !current
                    ? (page == null ? const SizedBox.expand() : _spread(NativePage(page: page, paper: const Color(0x00000000), images: _images, marks: _marksFor(at!.spine)), at))
                    : LayoutBuilder(builder: (context, box) {
                        _dual = _profile.dualPage && box.maxWidth > box.maxHeight * 1.15;
                        _setStyle(_styleFor(box));
                        _resolveTarget();
                        final shown = _pageAt(_loc);
                        if (shown == null) return const SizedBox.expand();
                        if (!_firstPainted) {
                          _firstPainted = true;
                          _timer.activity(DateTime.now());
                          WidgetsBinding.instance.addPostFrameCallback((_) => PositionLog.record(
                              widget.book.id, 'first_page', {'elapsedMs': _clock.elapsedMilliseconds, 'engine': 'native'}));
                        }
                        return _spread(
                          NativePage(
                          key: const Key('nativePage'),
                          page: shown,
                          paper: const Color(0x00000000),
                          images: _images,
                          highlight: _highlight != null && _highlight!.$1 == _spine ? (_highlight!.$2, _highlight!.$3) : null,
                          marks: _marksFor(_spine),
                        ),
                          _loc,
                        );
                      }),
              ),
              ),
            ),
            Builder(builder: (context) {
              final status = StatusLine(
              key: current ? const Key('currentStatus') : null,
              chapter: at == null ? '' : book.titleAt(NativePosition(l.spine, offset ?? 0), _blocks[l.spine] ?? const []),
              ink: p.ink,
              page: p.background,
              chapterPage: chapterPage == null ? null : chapterPage + 1,
              chapterPages: _pages?.pagesIn(l.spine),
              chapterMinutes: at == null ? null : _chapterMinutes(l, offset),
              bookMinutes: at == null ? null : _bookMinutes(l, offset),
              position: bookPage == null || total == null ? null : bookPage + 1,
              positions: total,
            );
              if (!current) return status;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _onStatusTap(d, MediaQuery.sizeOf(context).width),
                child: status,
              );
            }),
          ]),
            ),
          ),
          // A ribbon on pages that hold a bookmark.
          if (bookmarked)
            Positioned(
              top: MediaQuery.viewPaddingOf(context).top - 4,
              right: 14,
              child: Icon(Icons.bookmark, key: current ? const Key('bookmarkRibbon') : null, size: 30, color: const Color(0xFFB3261E)),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final book = _book;
    final front = _front, under = _under;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: p.theme.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: p.background,
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: () => _openStandard(turnOff: false), child: const Text('Open in the web reader')),
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back to shelf')),
                  ]),
                ),
              )
            : book == null
            ? const Center(child: CircularProgressIndicator())
            : Stack(fit: StackFit.expand, children: [
                // Neighbours sit under the current page, painted and ready to be captured.
                _scene(book, _style == null ? null : _backOf(_loc), _prevKey, current: false),
                _scene(book, _style == null ? null : _forwardOf(_loc), _nextKey, current: false),
                _scene(book, _loc, _currentKey, current: true),
                if (front != null && under != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _turn,
                        builder: (context, _) => CustomPaint(
                          key: const Key('pageTurn'),
                          painter: PageTurnPainter(
                            front: front,
                            under: under,
                            progress: _forward ? _turn.value : 1 - _turn.value,
                            paper: p.background,
                            pixelRatio: MediaQuery.devicePixelRatioOf(context),
                            style: p.pageTurn == PageTurn.slide ? TurnStyle.slide : TurnStyle.curl,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (p.blueLight > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(color: const Color(0xFFFF8F00).withValues(alpha: p.blueLight / 100 * 0.35)),
                    ),
                  ),
                if (p.brightnessSwipe)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 44,
                    child: LayoutBuilder(
                      builder: (context, box) => GestureDetector(
                        key: const Key('brightnessEdge'),
                        behavior: HitTestBehavior.translucent,
                        onVerticalDragUpdate: (d) => _brightnessDrag(d, box.maxHeight),
                        onVerticalDragEnd: (_) => _brightnessEnd(),
                        onVerticalDragCancel: _brightnessEnd,
                      ),
                    ),
                  ),
                if (_brightnessShown != null)
                  Center(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.brightness_6, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text('${(_brightnessShown! * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 16)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ..._selectionHandles(),
                if (_selection != null) _selectionBar(),
                // Bars fade in over the page (150 ms); the page keeps its bounds.
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_controls,
                    child: AnimatedOpacity(
                      opacity: _controls ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: _bars(context, book),
                    ),
                  ),
                ),
              ]),
      ),
    );
  }

  Widget _bars(BuildContext context, NativeBook book) {
    final total = _total;
    final shown = (_preview ?? _progress).clamp(0.0, 1.0);
    final label = total == null ? '${(shown * 100).round()}%' : '${(shown * (total - 1)).round() + 1}/$total';
    return Stack(children: [
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: OakBar(
          child: SafeArea(
            bottom: false,
            child: Row(children: [
              IconButton(tooltip: 'Back to shelf', icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
              Expanded(child: Text(widget.book.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
              PopupMenuButton<String>(
                key: const Key('readerMenu'),
                tooltip: 'Options',
                onSelected: (v) => switch (v) {
                  'visual' => showVisualOptions(context, _profile, _setProfile, bookOnly: _bookOnly, onBookOnly: _setBookOnly),
                  'control' => showControlOptions(context, _profile, _setProfile),
                  'themes' => showThemes(context, _profile, _setProfile),
                  'bookmark' => _toggleBookmark(),
                  _ => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => BookInfoPage(library: widget.library, bookId: widget.book.id)),
                  ),
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    key: const Key('bookmarkItem'),
                    value: 'bookmark',
                    child: Text(_bookmarkHere == null ? 'Bookmark this page' : 'Remove bookmark'),
                  ),
                  const PopupMenuItem(value: 'visual', child: Text('Visual options')),
                  const PopupMenuItem(value: 'control', child: Text('Control options')),
                  const PopupMenuItem(value: 'themes', child: Text('Themes')),
                  const PopupMenuItem(value: 'info', child: Text('Book information')),
                ],
              ),
            ]),
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: OakBar(
          seed: 9,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_returnTo != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('returnToReadingPosition'),
                      onPressed: () {
                        final to = _returnTo!;
                        setState(() => _returnTo = null);
                        _jumpTo(to, remember: false);
                      },
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('Back to reading position'),
                    ),
                  ),
                Row(children: [
                  IconButton(
                    tooltip: 'Previous chapter',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: book.toc.isEmpty ? null : () => _stepChapter(-1),
                  ),
                  Expanded(
                    child: Slider(
                      key: const Key('progress'),
                      value: shown,
                      onChanged: (v) {
                        _touch();
                        setState(() => _preview = v);
                      },
                      onChangeEnd: _goToProgress,
                    ),
                  ),
                  SizedBox(
                    width: MediaQuery.textScalerOf(context).scale(total == null ? 64 : 24 + 14.0 * '$total'.length),
                    child: TextButton(
                      key: const Key('pageNumber'),
                      onPressed: total == null ? null : _askPage,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      child: Text(label, maxLines: 1),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next chapter',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: book.toc.isEmpty ? null : () => _stepChapter(1),
                  ),
                ]),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  IconButton(
                    tooltip: _landscape ? 'Portrait' : 'Landscape',
                    icon: Icon(_landscape ? Icons.stay_current_portrait : Icons.stay_current_landscape),
                    onPressed: _toggleOrientation,
                  ),
                  IconButton(
                    tooltip: _profile.night ? 'Day' : 'Night',
                    icon: Icon(_profile.night ? Icons.light_mode : Icons.dark_mode),
                    onPressed: () => _setProfile(_profile.copyWith(night: !_profile.night)),
                  ),
                  IconButton(
                    tooltip: 'Contents',
                    icon: const Icon(Icons.toc),
                    onPressed: book.toc.isEmpty ? null : _showContents,
                  ),
                  IconButton(
                    key: const Key('autoTurn'),
                    tooltip: 'Auto page turn',
                    icon: const Icon(Icons.play_circle_outline),
                    onPressed: _toggleAuto,
                  ),
                  IconButton(tooltip: 'Search in book', icon: const Icon(Icons.search), onPressed: _showSearch),
                ]),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}
