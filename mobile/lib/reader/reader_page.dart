import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_readium/flutter_readium.dart';

import '../library/annotations.dart';
import '../library/cbr.dart';
import '../library/book.dart';
import '../library/library.dart';
import '../library/names.dart';
import '../library/shelf.dart';
import '../library/stats.dart';
import '../shelf/book_info_page.dart';
import '../shelf/custom_cover.dart';
import '../theme.dart';
import '../oak.dart';
import 'device_controls.dart';
import 'finish_prompt.dart';
import 'perf_log.dart';
import 'position_log.dart';
import 'reader_options.dart';
import 'reading_profile.dart';
import 'status_line.dart';

// Android takes content:// URIs and paths as they are. The iOS plugin expects a plain path.
String publicationLocation(String uri) =>
    Platform.isIOS && uri.startsWith('file://') ? Uri.parse(uri).toFilePath() : uri;

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.library, required this.book});

  final Library library;
  final Book book;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> with WidgetsBindingObserver {
  // Active reading time; saved when the reader closes or the app goes to the background.
  final _timer = ReadingTimer();
  bool _finishAsked = false;
  final _readium = FlutterReadium();
  final _controls = ValueNotifier<bool>(false);
  StreamSubscription<Locator>? _locatorSub;
  StreamSubscription<ReadiumError>? _errorSub;
  Timer? _loadDeadline;
  final _openClock = Stopwatch();
  static Future<void>? _closing;
  int _openGeneration = 0;
  bool Function(Locator)? _seekDestination;
  Publication? _publication;
  Locator? _initial;
  Locator? _current;
  // Where a slider or contents jump started, so it can be undone.
  Locator? _returnTo;
  Timer? _returnTimer;
  // An approximate imported position (e.g. from Moon Reader) to go to once the book is shown.
  double? _resumeApproximate;
  bool _restoringApproximate = false;
  double? _preview;
  int? _positionCount;
  // A CBR is being rewritten as a CBZ (first open only).
  bool _preparing = false;
  bool _loadingPositionCount = false;
  Future<void> _seekTail = Future<void>.value();
  int _seekGeneration = 0;
  String? _error;
  ReadingProfile _profile = const ReadingProfile();
  late final _device = DeviceControls(onVolumeKey: _onVolumeKey);
  // Shown while the left-edge brightness slide is in progress.
  double? _brightnessShown;
  bool _landscape = false;
  static const _portrait = [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown];
  int? _battery;
  Timer? _clock;
  // The reader's own speed in words per minute, from reading statistics (Moon Reader recorded
  // words); 226 is the user's measured average when nothing is known yet.
  double _wordsPerMinute = 226;

  bool get _isEpub => widget.book.format == 'EPUB';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // As in the user's Moon Reader ("full screen with status bar"): the phone's status bar
    // stays at the top, navigation is hidden.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: const [SystemUiOverlay.top]);
    // Moon Reader's "Portrait (Sensor)": upright either way up, never sideways unless asked.
    SystemChrome.setPreferredOrientations(_portrait);
    _open();
  }

  Future<void> _open() async {
    final generation = ++_openGeneration;
    _clock?.cancel();
    ++_seekGeneration;
    _seekDestination = null;
    _seekTail = Future<void>.value();
    final book = _book;
    _loadDeadline?.cancel();
    _openClock
      ..reset()
      ..start();
    _loadDeadline = Timer(const Duration(seconds: 25), () {
      if (mounted && generation == _openGeneration && _current == null) {
        _openingFailed('This book is taking too long to load. Retry keeps your saved position.');
      }
    });
    setState(() {
      _error = null;
      _preparing = false;
      _publication = null;
      _current = null;
      _positionCount = null;
    });
    try {
      await _closing;
      if (!mounted || generation != _openGeneration) return;
      await _errorSub?.cancel();
      _errorSub = _readium.onErrorEvent.listen((error) {
        if (!mounted || generation != _openGeneration || error.isInformational) return;
        if (_current == null || error.isFatal) {
          _openingFailed('The reader could not load this book. Your saved position is kept.');
        }
      });
      _profile = await ReadingProfile.load();
      await _notes();
      if (!mounted || generation != _openGeneration) return;
      _readium.setDefaultPreferences(_profile.epub);
      await _applyDevice(_profile);
      if (!mounted || generation != _openGeneration) return;
      _wordsPerMinute = _readingSpeed();
      _tick();
      _clock = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
      // A CBR is first rewritten as a CBZ in Quill's cache (once; large comics take a while).
      var location = book.uri;
      if (book.format == 'CBR') {
        _loadDeadline?.cancel();
        try {
          location = (await cbzFor(book, onConverting: () {
            if (mounted && generation == _openGeneration) setState(() => _preparing = true);
          })).path;
          if (mounted) setState(() => _preparing = false);
        } on PlatformException catch (e) {
          if (mounted && generation == _openGeneration) _openingFailed(e.message ?? 'This comic could not be read.');
          return;
        } on MissingPluginException {
          if (mounted && generation == _openGeneration) _openingFailed('CBR comics open on Android only.');
          return;
        }
        if (!mounted || generation != _openGeneration) return;
      }
      final publication = await _readium
          .openPublication(publicationLocation(location))
          .timeout(const Duration(seconds: 20));
      if (!mounted || generation != _openGeneration) return;
      PositionLog.record(book.id, 'open_ready', {'elapsedMs': _openClock.elapsedMilliseconds});
      PerfLog.start(book.id);
      _initial = book.locator.isEmpty ? null : Locator.fromJsonString(book.locator);
      if (_initial == null && book.approximate && book.progress > 0 && book.progress < 1) {
        _resumeApproximate = book.progress;
      }
      final start = (_initial?.toJson()['locations'] as Map?) ?? const {};
      PositionLog.record(book.id, 'open', {
        'href': _initial?.href,
        'page': start['currentPage'],
        'pages': start['totalPages'],
        'progression': start['progression'],
      });
      _locatorSub = _readium.onTextLocatorChanged.listen(_onLocator);
      // A metadata disk write must not gate first content.
      setState(() => _publication = publication);
      unawaited(
        widget.library
            .update(
              book.id,
              (b) => b.copyWith(
                touched: true,
                opened: DateTime.now().millisecondsSinceEpoch,
                title: metadataTitle(b.title, b.name, publication.metadata.title),
                author: metadataAuthor(b.author, b.name, [for (final c in publication.metadata.authors) c.name ?? '']),
                isbn: b.isbn.isEmpty ? isbnFrom(publication.metadata.identifier) : b.isbn,
                addedAt: b.addedAt == 0 ? DateTime.now().millisecondsSinceEpoch : b.addedAt,
              ),
            )
            .catchError((_) {
              if (mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Library changes could not be saved.')));
              }
            }),
      );
    } catch (_) {
      if (mounted && generation == _openGeneration) {
        _openingFailed('This book could not be opened. Your file and saved position are unchanged.');
      }
    }
  }

  void _openingFailed(String message) {
    ++_openGeneration;
    ++_seekGeneration;
    _loadDeadline?.cancel();
    _locatorSub?.cancel();
    _locatorSub = null;
    _errorSub?.cancel();
    _errorSub = null;
    PositionLog.record(widget.book.id, 'open_failed', {'elapsedMs': _openClock.elapsedMilliseconds});
    setState(() => _error = message);
    _closeReader();
  }

  void _closeReader() {
    final pending = _readium.closePublication().timeout(const Duration(seconds: 5)).catchError((_) {});
    _closing = pending;
    unawaited(
      pending.then((_) {
        if (identical(_closing, pending)) _closing = null;
      }),
    );
  }

  // Save a stable content locator (not a screen page) on every page change.
  void _onLocator(Locator locator) {
    if (!mounted || _error != null) return;
    // Resource-start events during a seek are provisional. Never persist them as resume.
    if (_seekDestination != null && !_seekDestination!(locator)) return;
    if (_current == null) {
      _loadDeadline?.cancel();
      PositionLog.record(widget.book.id, 'first_content', {'elapsedMs': _openClock.elapsedMilliseconds});
    }
    // The first page shown is the book's start; go to the imported position before saving any.
    final approximate = _resumeApproximate;
    if (approximate != null) {
      if (!_restoringApproximate) {
        _restoringApproximate = true;
        PositionLog.record(widget.book.id, 'approximate', {'progress': approximate});
        _queueSeek(
          () => _goToProgress(approximate),
          (l) => (_progressOf(l) - approximate).abs() < 0.03,
        ).whenComplete(() => _resumeApproximate = null);
      }
      if ((_progressOf(locator) - approximate).abs() > 0.03) return;
      _resumeApproximate = null;
    }
    if (_isEpub && !_loadingPositionCount && _positionCount == null) _loadPositionCount();
    final progress = _progressOf(locator);
    final moved = _current != null && jsonEncode(_current!.toJson()) != jsonEncode(locator.toJson());
    _timer.activity(DateTime.now(), pageTurn: moved);
    setState(() => _current = locator);
    if (moved && _atEnd(locator, progress) && !_finishAsked && !_book.finished) {
      _finishAsked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _askFinished());
    }
    final locations = (locator.toJson()['locations'] as Map?) ?? const {};
    PositionLog.record(widget.book.id, 'save', {
      'href': locator.href,
      'page': locations['currentPage'],
      'pages': locations['totalPages'],
      'progression': locations['progression'],
    });
    widget.library.update(
      widget.book.id,
      (b) => b.copyWith(locator: jsonEncode(locator.toJson()), progress: progress, approximate: false),
    );
  }

  @override
  void dispose() {
    ++_openGeneration;
    ++_seekGeneration;
    _loadDeadline?.cancel();
    _returnTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _saveTime();
    _locatorSub?.cancel();
    _errorSub?.cancel();
    _closeReader();
    _controls.dispose();
    _clock?.cancel();
    _device.release();
    SystemChrome.setPreferredOrientations(const []);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    PerfLog.stop();
    super.dispose();
  }

  double _progressOf(Locator locator) => bookProgress(
    [for (final l in _publication?.readingOrder ?? const <Link>[]) l.href],
    locator.href,
    progression: locator.locations?.progression,
    totalProgression: locator.locations?.totalProgression,
  );

  bool _atEnd(Locator locator, double progress) {
    final locations = (locator.toJson()['locations'] as Map?) ?? const {};
    int? asInt(Object? v) => v is num ? v.toInt() : null;
    return isAtEnd(
      readingOrder: [for (final l in _publication?.readingOrder ?? const <Link>[]) l.href],
      href: locator.href,
      currentPage: asInt(locations['currentPage']),
      totalPages: asInt(locations['totalPages']),
      progression: locator.locations?.progression,
      position: widget.book.format == 'PDF' ? locator.locations?.position : null,
      numberOfPages: widget.book.format == 'PDF' ? _publication?.metadata.numberOfPages : null,
      progress: progress,
    );
  }

  Book get _book => widget.library.books.firstWhere((b) => b.id == widget.book.id, orElse: () => widget.book);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _saveTime();
  }

  void _saveTime() {
    final spans = _timer.stop(DateTime.now());
    if (spans.isNotEmpty) widget.library.recordReading(widget.book.id, spans, progress: _percentage);
  }

  Future<void> _askFinished() => askFinished(context, widget.library, widget.book.id);

  double get _percentage => _current == null ? widget.book.progress : _progressOf(_current!);

  Future<void> _setProfile(ReadingProfile profile) async {
    final old = _profile;
    setState(() => _profile = profile);
    await _applyDevice(profile, old: old);
    await _readium.setEPUBPreferences(profile.epub);
    await profile.save();
  }

  // Native settings that live outside Readium's preferences.
  Future<void> _applyDevice(ReadingProfile p, {ReadingProfile? old}) async {
    if (old?.keepAwake != p.keepAwake) await _device.keepAwake(p.keepAwake);
    if (old?.volumeKeys != p.volumeKeys) await _device.volumeKeys(p.volumeKeys);
    if (old?.brightness != p.brightness) await _device.brightness(p.brightness);
    if (old?.pageTurn != p.pageTurn) await _readium.setPageTurnStyle(p.pageTurn.name);
    if (old?.paperTexture != p.paperTexture) await _readium.setPaperTexture(p.paperTexture ? await _paper() : null);
  }

  static String? _paperBase64;
  static Future<String> _paper() async =>
      _paperBase64 ??= base64Encode((await rootBundle.load('assets/paper.png')).buffer.asUint8List());

  Future<void> _tick() async {
    final level = await _device.battery();
    if (mounted) setState(() => _battery = level);
  }

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

  Map<String, Object?> get _locations => (_current?.toJson()['locations'] as Map?)?.cast<String, Object?>() ?? const {};
  int? get _chapterPages => (_locations['totalPages'] as num?)?.toInt();
  int? get _chapterPage {
    final p = (_locations['currentPage'] as num?)?.toInt();
    return p == null ? null : p + 1;
  }

  Future<void> _loadPositionCount() async {
    _loadingPositionCount = true;
    try {
      final count = await _readium.bookPositionCount();
      if (mounted && count > 0) setState(() => _positionCount = count);
    } finally {
      _loadingPositionCount = false;
    }
  }

  // EPUB text positions are stable across reflow; PDF/comic counts are physical pages.
  int? get _positions =>
      _isEpub ? _positionCount : (_publication?.metadata.numberOfPages ?? _publication?.readingOrder.length);

  int _positionAt(double progress) {
    final count = _positions;
    if (count == null || count < 1) return 1;
    if (_preview == null && _current?.locations?.position != null) {
      return _current!.locations!.position!.clamp(1, count);
    }
    return (1 + progress * (count - 1)).round().clamp(1, count);
  }

  // Estimates as Moon Reader shows them: a screen page is ~240 words, a position ~170.
  int? get _chapterMinutes {
    final pages = _chapterPages, page = _chapterPage;
    if (!_isEpub || pages == null || page == null) return null;
    return ((pages - page) * 240 / _wordsPerMinute).ceil();
  }

  int? get _bookMinutes {
    final total = _positions, position = _current?.locations?.position;
    if (!_isEpub || total == null || position == null) return null;
    return ((total - position) * 170 / _wordsPerMinute).ceil();
  }

  // Moon Reader's "use a page as cover": hide the controls, then capture the page as shown.
  Future<void> _pageAsCover() async {
    final messenger = ScaffoldMessenger.of(context);
    _controls.value = false;
    try {
      final ok = await capturePageAsCover(widget.library, widget.book.id, _readium);
      messenger.showSnackBar(
        SnackBar(content: Text(ok ? 'This page is now the cover' : 'The page could not be saved')),
      );
    } on PlatformException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('The page could not be captured: ${e.message}')));
    }
  }

  void _onVolumeKey(bool forward) {
    if (_publication == null || !mounted) return;
    forward ? _readium.goForward() : _readium.goBackward();
  }

  // Moon Reader: slide up or down along the left edge to change brightness.
  Future<void> _brightnessDrag(DragUpdateDetails d, double height) async {
    final start = _brightnessShown ?? _profile.brightness ?? await _device.systemBrightness();
    final next = (start - (d.primaryDelta ?? 0) / (height * 0.6)).clamp(0.02, 1.0);
    setState(() => _brightnessShown = next);
    await _device.brightness(next);
  }

  void _brightnessEnd() {
    final value = _brightnessShown;
    setState(() => _brightnessShown = null);
    if (value != null) _setProfile(_profile.copyWith(brightness: () => value));
  }

  void _toggleOrientation() {
    setState(() => _landscape = !_landscape);
    SystemChrome.setPreferredOrientations(
      _landscape ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight] : _portrait,
    );
  }

  // Moon Reader's ‹ › beside the slider: previous / next contents entry.
  Future<void> _stepChapter(Publication pub, int delta) async {
    final toc = pub.tocFlattened;
    final at = _current;
    if (toc.isEmpty) return;
    final i = at == null
        ? -1
        : contentsIndex(
            [for (final l in toc) ContentsTarget(l.href, l.title ?? '')],
            at.href,
            fragments: at.locations?.fragments ?? const [],
            title: at.title,
          );
    final target = (i + delta).clamp(0, toc.length - 1);
    if (target == i) return;
    await _jumpWithReturn(() => _readium.goByLink(toc[target], pub));
  }

  Future<void> _jumpToProgression(double value) => _queueSeek(
    () => _goToProgress(value),
    // Readium lands on the screen containing the target, so allow one screen of text (about
    // 2.5 stable positions of ~1024 characters). In a short book a screen exceeds 2% of it,
    // and a stricter check undid a successful jump.
    (locator) => (_progressOf(locator) - value).abs() <= max(0.02, 2.5 / (_positions ?? 50)),
  );

  // Serialize seeks, discard superseded queued targets, and retain the thumb preview until
  // Readium reports the destination. A method-channel acknowledgement alone is not a page load.
  Future<void> _queueSeek(Future<bool> Function() seek, bool Function(Locator) matches) {
    final generation = ++_seekGeneration;
    final operation = _seekTail.then((_) async {
      if (!mounted || generation != _seekGeneration) return;
      final origin = _current;
      _seekDestination = matches;
      try {
        await _jumpWithReturn(() async {
          final arrived = Completer<void>();
          final sub = _readium.onTextLocatorChanged.listen((locator) {
            if (matches(locator) && !arrived.isCompleted) arrived.complete();
          });
          try {
            var accepted = false;
            for (var attempt = 0; attempt < 3 && mounted; attempt++) {
              if (await seek().timeout(const Duration(seconds: 5))) {
                accepted = true;
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            if (!accepted) throw StateError('The reader is still loading');
            if (_current != null && matches(_current!)) return true;
            await arrived.future.timeout(const Duration(seconds: 5));
            return true;
          } finally {
            await sub.cancel();
          }
        });
      } catch (_) {
        if (mounted && generation == _seekGeneration) {
          if (origin != null) {
            _seekDestination = (locator) =>
                locator.href == origin.href &&
                ((locator.locations?.progression ?? 0) - (origin.locations?.progression ?? 0)).abs() < .02;
            try {
              await _readium.goToLocator(origin).timeout(const Duration(seconds: 5));
            } catch (_) {
              // Keep the last confirmed durable position if rendering cannot recover.
            }
          }
          if (!mounted || generation != _seekGeneration) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Could not reach that page. Please try again.')));
        }
      } finally {
        if (generation == _seekGeneration) _seekDestination = null;
        if (mounted && generation == _seekGeneration) setState(() => _preview = null);
      }
    });
    _seekTail = operation;
    return operation;
  }

  Future<void> _askPage() async {
    final total = _positions;
    if (total == null || total < 1) return;
    final controller = TextEditingController(text: '${_positionAt(_percentage)}');
    final form = GlobalKey<FormState>();
    final target = await showDialog<int>(
      context: context,
      builder: (dialog) {
        void submit() {
          if (form.currentState!.validate()) Navigator.pop(dialog, int.parse(controller.text));
        }

        return AlertDialog(
          title: const Text('Go to page'),
          content: Form(
            key: form,
            child: TextFormField(
              key: const Key('pageNumberInput'),
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.go,
              decoration: InputDecoration(
                labelText: 'Page (1–$total)',
                helperText: _isEpub ? 'Book positions stay fixed when text size changes.' : null,
                helperMaxLines: 2,
              ),
              validator: (text) {
                final number = int.tryParse(text ?? '');
                return number == null || number < 1 || number > total ? 'Enter a number from 1 to $total' : null;
              },
              onFieldSubmitted: (_) => submit(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
            TextButton(key: const Key('goToPage'), onPressed: submit, child: const Text('Go')),
          ],
        );
      },
    );
    // The exiting dialog still owns its field during its route animation.
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    if (!mounted || target == null) return;
    setState(() => _preview = total == 1 ? 0 : (target - 1) / (total - 1));
    await _queueSeek(
      () => _isEpub && Platform.isAndroid
          ? _readium.goToBookPosition(target)
          : _goToProgress(total == 1 ? 0 : (target - 1) / (total - 1)),
      (locator) => locator.locations?.position != null
          ? (locator.locations!.position! - target).abs() <= 2
          : (_progressOf(locator) - (total == 1 ? 0 : (target - 1) / (total - 1))).abs() < 0.03,
    );
  }

  // Every intentional jump offers the same brief undo. Repeated exploration
  // keeps its original reading position and restarts the five-second window.
  Future<void> _jumpWithReturn<T>(Future<T> Function() jump) async {
    final from = _returnTo ?? _current;
    final result = await jump();
    if (result == false || !mounted || from == null) return;
    _returnTimer?.cancel();
    setState(() => _returnTo = from);
    _returnTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _returnTo = null);
    });
  }

  // Whole-book position 0..1: Readium's weighted EPUB positions, else the reading-order estimate.
  Future<bool> _goToProgress(double value) async {
    final order = _publication?.readingOrder ?? const <Link>[];
    if (_isEpub && Platform.isAndroid) return _readium.goToBookProgression(value);
    final target = _isEpub ? readingOrderPosition(order.length, value) : null;
    if (target != null) {
      final link = order[target.index];
      return _readium.goToLocator(
        Locator(
          href: link.href,
          type: link.type ?? 'application/xhtml+xml',
          locations: Locations(progression: target.progression),
        ),
      );
    }
    return _readium.goToProgression(value);
  }

  Future<void> _jumpBack() async {
    final target = _returnTo;
    if (target == null) return;
    ++_seekGeneration;
    await _seekTail;
    if (!mounted) return;
    _returnTimer?.cancel();
    setState(() {
      _returnTo = null;
      _preview = null;
    });
    await _readium.goToLocator(target);
  }

  String get _chapter {
    final pub = _publication;
    final at = _current;
    if (pub == null || at == null) return '';
    final toc = pub.tocFlattened;
    final i = contentsIndex(
      [for (final l in toc) ContentsTarget(l.href, l.title ?? '')],
      at.href,
      fragments: at.locations?.fragments ?? const [],
      title: at.title,
    );
    return i >= 0 ? (toc[i].title ?? '') : (at.title ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final pub = _publication;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _profile.theme.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: _profile.background,
        body: DecoratedBox(
          // The same paper as the text area, so the page frame and text read as one sheet.
          decoration: BoxDecoration(
            image: _isEpub && _profile.paperTexture
                ? const DecorationImage(image: AssetImage('assets/paper.png'), repeat: ImageRepeat.repeat, scale: 1)
                : null,
          ),
          child: _error != null
              ? _Message(
                  text: _error!,
                  onBack: () => Navigator.pop(context),
                  onRetry: _open,
                )
              : pub == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      if (_preparing)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Preparing this comic. This happens once and can take a minute for a large file.',
                            key: Key('preparingComic'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                )
              : Stack(
                  children: [
                    // The page keeps the same bounds whether or not controls are showing.
                    Column(
                      children: [
                        Expanded(
                          // Reflowable text gets Moon Reader's page frame (READING.md: top 40, bottom 30
                          // including the status line) so it reads as a page, not a scroll. PDF and comic
                          // pages carry their own margins and keep the full screen.
                          child: Padding(
                            padding: _isEpub
                                ? EdgeInsets.only(
                                    top: _profile.frameTop(MediaQuery.viewPaddingOf(context).top),
                                    bottom: _profile.frameBottom,
                                  )
                                : EdgeInsets.zero,
                            child: ReadiumReaderWidget(
                              key: const Key('reader'),
                              publication: pub,
                              initialLocator: _initial,
                              shouldShowControls: _controls,
                            ),
                          ),
                        ),
                        StatusLine(
                          chapter: _chapter,
                          ink: _profile.ink,
                          page: _profile.background,
                          chapterPage: _chapterPage,
                          chapterPages: _chapterPages,
                          position: _current?.locations?.position,
                          positions: _positions,
                          chapterMinutes: _chapterMinutes,
                          bookMinutes: _bookMinutes,
                          battery: _battery,
                        ),
                      ],
                    ),
                    // Moon Reader's paper darkens softly toward the edges and corners (measured:
                    // centre #E7E5E0, corners #D8D4CE). Drawn over the page; touches pass through.
                    if (_isEpub && _profile.paperTexture)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                radius: 1.05,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: _profile.theme.dark ? 0.12 : 0.055),
                                ],
                                stops: const [0.55, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Only vertical drags are claimed here, so taps on the left edge still turn back.
                    if (_profile.brightnessSwipe)
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
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.brightness_6, color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${(_brightnessShown! * 100).round()}%',
                                    style: const TextStyle(color: Colors.white, fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ValueListenableBuilder<bool>(
                      valueListenable: _controls,
                      builder: (context, show, _) {
                        if (!show) return const SizedBox.shrink();
                        final theme = quillTheme(_profile.night ? Brightness.dark : Brightness.light);
                        return Theme(
                          data: theme,
                          child: Builder(builder: (context) => _overlay(context, pub, theme.colorScheme)),
                        );
                      },
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _overlay(BuildContext context, Publication pub, ColorScheme scheme) {
    final shown = _preview ?? _percentage;
    // Only the two bars take touches; the page between them stays tappable.
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: OakBar(
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back to shelf',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(child: Text(widget.book.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  // Moon Reader keeps the option screens behind ⋮ in the top bar.
                  PopupMenuButton<String>(
                    key: const Key('readerMenu'),
                    tooltip: 'Options',
                    onSelected: (v) => switch (v) {
                      'visual' => showVisualOptions(context, _profile, _setProfile),
                      'control' => showControlOptions(context, _profile, _setProfile),
                      'themes' => showThemes(context, _profile, _setProfile),
                      'cover' => _pageAsCover(),
                      'bookmark' => _toggleBookmark(),
                      'bookmarks' => _showBookmarks(),
                      _ => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => BookInfoPage(library: widget.library, bookId: widget.book.id),
                        ),
                      ),
                    },
                    itemBuilder: (_) => [
                      if (_isEpub) const PopupMenuItem(value: 'visual', child: Text('Visual options')),
                      const PopupMenuItem(value: 'control', child: Text('Control options')),
                      const PopupMenuItem(value: 'themes', child: Text('Themes')),
                      PopupMenuItem(
                        key: const Key('bookmarkItem'),
                        value: 'bookmark',
                        child: Text(_bookmarkHere == null ? 'Bookmark this page' : 'Remove bookmark'),
                      ),
                      const PopupMenuItem(key: Key('bookmarksItem'), value: 'bookmarks', child: Text('Bookmarks & notes')),
                      const PopupMenuItem(value: 'cover', child: Text('Use this page as cover')),
                      const PopupMenuItem(value: 'info', child: Text('Book information')),
                    ],
                  ),
                ],
              ),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_returnTo != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const Key('returnToReadingPosition'),
                          onPressed: _jumpBack,
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('Back to reading position'),
                        ),
                      ),
                    // As in Moon Reader: ‹ previous chapter · slider · % · next chapter ›.
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous chapter',
                          icon: const Icon(Icons.chevron_left),
                          onPressed: pub.tocFlattened.isEmpty ? null : () => _stepChapter(pub, -1),
                        ),
                        Expanded(
                          child: Slider(
                            key: const Key('progress'),
                            value: shown.clamp(0.0, 1.0),
                            onChanged: (v) => setState(() => _preview = v),
                            onChangeEnd: _jumpToProgression,
                          ),
                        ),
                        SizedBox(
                          width: MediaQuery.textScalerOf(context)
                              .scale(_positions == null ? 64 : 24 + 14.0 * _positions.toString().length),
                          child: TextButton(
                            key: const Key('pageNumber'),
                            onPressed: _positions == null ? null : _askPage,
                            style: TextButton.styleFrom(padding: EdgeInsets.zero),
                            child: Text(
                              _positions == null ? '${(shown * 100).round()}%' : '${_positionAt(shown)}/$_positions',
                              maxLines: 1,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next chapter',
                          icon: const Icon(Icons.chevron_right),
                          onPressed: pub.tocFlattened.isEmpty ? null : () => _stepChapter(pub, 1),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
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
                          onPressed: pub.tocFlattened.isEmpty ? null : () => _showContents(pub),
                        ),
                        IconButton(tooltip: 'Search in book', icon: const Icon(Icons.search), onPressed: _showSearch),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---- Bookmarks (kept with the native reader's notes in annotations.json) ----

  AnnotationStore? _store;

  Future<AnnotationStore?> _notes() async {
    try {
      return _store ??= await widget.library.annotations();
    } catch (_) {
      return null;
    }
  }

  static bool _samePlace(Locator a, Locator b) =>
      a.href == b.href && ((a.locations?.progression ?? 0) - (b.locations?.progression ?? 0)).abs() < 0.002;

  // The bookmark on the page being shown, if any.
  Annotation? get _bookmarkHere {
    final at = _current, store = _store;
    if (at == null || store == null) return null;
    for (final a in store.forBook(widget.book.id)) {
      if (a.kind != AnnotationKind.bookmark || a.locator.isEmpty) continue;
      final l = Locator.fromJsonString(a.locator);
      if (l != null && _samePlace(l, at)) return a;
    }
    return null;
  }

  Future<void> _toggleBookmark() async {
    final at = _current, store = await _notes();
    if (at == null || store == null || !mounted) return;
    final existing = _bookmarkHere;
    final messenger = ScaffoldMessenger.of(context);
    if (existing != null) {
      await store.remove(existing.id);
      messenger.showSnackBar(const SnackBar(content: Text('Bookmark removed'), duration: Duration(seconds: 1)));
    } else {
      final now = DateTime.now().millisecondsSinceEpoch;
      final page = _positions == null ? '${(_percentage * 100).toStringAsFixed(1)}%' : 'Page ${_positionAt(_percentage)}';
      await store.put(Annotation(
        id: store.newId(),
        bookId: widget.book.id,
        kind: AnnotationKind.bookmark,
        spine: -1,
        start: 0,
        end: 0,
        href: at.href,
        quote: page,
        chapter: _chapter,
        created: now,
        updated: now,
        locator: jsonEncode(at.toJson()),
      ));
      messenger.showSnackBar(const SnackBar(content: Text('Bookmarked'), duration: Duration(seconds: 1)));
    }
    if (mounted) setState(() {});
  }

  Future<void> _showBookmarks() async {
    final store = await _notes();
    if (store == null || !mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scroll) => StatefulBuilder(
          builder: (context, setList) {
            final notes = store.forBook(widget.book.id);
            if (notes.isEmpty) {
              return const Center(
                child: Padding(padding: EdgeInsets.all(24), child: Text('No bookmarks yet. Use ⋮ to bookmark a page.', textAlign: TextAlign.center)),
              );
            }
            return ListView.builder(
              key: const Key('bookmarksList'),
              controller: scroll,
              itemCount: notes.length,
              itemBuilder: (_, i) {
                final a = notes[i];
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
                      await store.remove(a.id);
                      setList(() {});
                      if (mounted) setState(() {});
                    },
                  ),
                  onTap: () async {
                    // Older notes have no locator: go to the start of their chapter.
                    final target = a.locator.isNotEmpty
                        ? Locator.fromJsonString(a.locator)
                        : (a.href.isEmpty ? null : Locator(href: a.href, type: 'application/xhtml+xml', locations: Locations(progression: 0)));
                    if (target == null) return;
                    Navigator.pop(sheet);
                    await _jumpWithReturn(() => _readium.goToLocator(target));
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _showContents(Publication pub) {
    final toc = pub.tocFlattened;
    final at = _current;
    final current = at == null
        ? -1
        : contentsIndex(
            [for (final l in toc) ContentsTarget(l.href, l.title ?? '')],
            at.href,
            fragments: at.locations?.fragments ?? const [],
            title: at.title,
          );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scroll) => ListView.builder(
          controller: scroll,
          itemCount: toc.length,
          itemBuilder: (context, i) => ListTile(
            title: Text(toc[i].title ?? 'Section'),
            selected: i == current,
            leading: i == current ? const Icon(Icons.chevron_right) : null,
            onTap: () async {
              Navigator.pop(context);
              await _jumpWithReturn(() => _readium.goByLink(toc[i], pub));
            },
          ),
        ),
      ),
    );
  }

  void _showSearch() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _SearchSheet(
        readium: _readium,
        onPick: (locator) async {
          Navigator.pop(context);
          await _jumpWithReturn(() => _readium.goToLocator(locator));
        },
      ),
    );
  }
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.readium, required this.onPick});

  final FlutterReadium readium;
  final ValueChanged<Locator> onPick;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  List<TextSearchResult> _results = const [];
  bool _searching = false;

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _searching = true);
    try {
      final results = await widget.readium.searchInPublication(query.trim());
      if (mounted) setState(() => _results = results);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(hintText: 'Search in book', prefixIcon: Icon(Icons.search)),
                onSubmitted: _search,
              ),
            ),
            if (_searching) const LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, i) {
                  final r = _results[i];
                  final text = r.locator.text;
                  return ListTile(
                    title: Text(r.chapterTitle ?? r.locator.title ?? ''),
                    subtitle: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: _tail(text?.before ?? '', 45)),
                          TextSpan(
                            text: text?.highlight ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(text: _head(text?.after ?? '', 90)),
                        ],
                      ),
                    ),
                    onTap: () => widget.onPick(r.locator),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _tail(String s, int n) => s.length <= n ? s : s.substring(s.length - n);
  static String _head(String s, int n) => s.length <= n ? s : s.substring(0, n);
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onBack, this.onRetry});

  final String text;
  final VoidCallback onBack;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          if (onRetry != null)
            FilledButton(key: const Key('retryReader'), onPressed: onRetry, child: const Text('Retry')),
          TextButton(onPressed: onBack, child: const Text('Back to shelf')),
        ],
      ),
    ),
  );
}
