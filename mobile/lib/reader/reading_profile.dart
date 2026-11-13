import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:path_provider/path_provider.dart';

import '../theme.dart';

// A reader colour scheme. The set follows Moon Reader's built-in themes (inspected on the
// user's phone, 2026-11-05); "Walnut library" replaces its textured night theme (user's choice).
class ReaderTheme {
  const ReaderTheme(this.id, this.name, this.background, this.ink, {this.dark = false});

  final String id;
  final String name;
  final Color background;
  final Color ink;
  final bool dark;
}

const readerThemes = [
  // Moon Reader's Day Theme as measured on the phone (page #E7E5E0 under its paper image).
  ReaderTheme('day', 'Day', Color(0xFFEDEAE4), Colors.black),
  ReaderTheme('parchment', 'Parchment', parchmentBackground, parchmentText),
  ReaderTheme('white', 'Pure white', Colors.white, Colors.black),
  ReaderTheme('sepia', 'Sepia', Color(0xFFE2CDA8), Color(0xFF3A2E20)),
  ReaderTheme('grey', 'Light grey', Color(0xFFDDDBD5), Color(0xFF1E1E1E)),
  ReaderTheme('night', 'Walnut library', libraryBackground, libraryText, dark: true),
  ReaderTheme('amoled', 'Black', Colors.black, Color(0xFFBDBDBD), dark: true),
  ReaderTheme('slate', 'Slate', Color(0xFF353B44), Color(0xFFC9CDD2), dark: true),
  ReaderTheme('charcoal', 'Charcoal', Color(0xFF3A3A3A), Color(0xFFD0D0D0), dark: true),
];

ReaderTheme readerTheme(String id) => readerThemes.firstWhere((t) => t.id == id, orElse: () => readerThemes.first);

enum PageTurn { curl, slide, none }

/// What a swipe up/down on the page or a tap on the status bar does (Moon: control options).
enum ReaderAction {
  none('Nothing'),
  nextPage('Next page'),
  previousPage('Previous page'),
  nextChapter('Next chapter'),
  previousChapter('Previous chapter'),
  contents('Contents'),
  search('Search'),
  bookInfo('Book information'),
  dayNight('Day / night'),
  options('Show options'),
  autoTurn('Auto page turn');

  const ReaderAction(this.label);
  final String label;

  static ReaderAction named(Object? name, ReaderAction fallback) =>
      values.firstWhere((a) => a.name == name, orElse: () => fallback);
}

// The personal reading profile. Values are kept in Moon Reader's own units, so the options
// read the same as in Moon Reader, and default to the user's Moon Reader settings
// (reader-defaults.json / READING.md). Each value is converted to Readium through a
// calibration measured against Moon Reader screenshots on the phone (2026-11-10, replacing the
// by-eye 2026-11-05 values): at the defaults that is 0.766x Readium's base size, line height 1.577,
// no paragraph gap, 24 dp side margins.
class ReadingProfile {
  const ReadingProfile({
    this.fontSize = 12.5,
    this.lineSpacing = 3,
    this.paragraphSpacing = 70,
    this.fontSpacing = 0,
    this.sideMargin = 24,
    this.rightMargin = 24,
    this.boldText = false,
    this.hyphenation = false,
    this.fontFamily = 'serif',
    this.dualPage = false,
    this.italicText = false,
    this.underlineText = false,
    this.textShadow = false,
    this.swipeUp = ReaderAction.none,
    this.swipeDown = ReaderAction.none,
    this.statusLeft = ReaderAction.bookInfo,
    this.statusRight = ReaderAction.contents,
    this.turnMillis = 300,
    this.blueLight = 0,
    this.autoTurnSeconds = 30,
    this.topMargin = 40,
    this.bottomMargin = 30,
    this.publisherStyles = false,
    this.nativeEngine = true,
    this.night = false,
    this.dayTheme = 'day',
    this.nightTheme = 'night',
    this.pageTurn = PageTurn.curl,
    this.volumeKeys = true,
    this.brightnessSwipe = true,
    this.keepAwake = true,
    this.paperTexture = true,
    this.brightness,
  });

  // Moon Reader units.
  final double fontSize; // 12.5
  final int lineSpacing; // 3
  final int paragraphSpacing; // percent, 70
  final int fontSpacing; // 0
  final int sideMargin; // left (and right in the standard reader), 24
  final int rightMargin; // native engine: right margin, 24
  final bool boldText; // Moon: font bold
  final bool hyphenation; // break long words at line ends (Moon: off)
  final String fontFamily; // serif, sans-serif or monospace (system fonts)
  final bool dualPage; // two pages side by side in landscape (Moon: off)
  final bool italicText;
  final bool underlineText;
  final bool textShadow;
  final ReaderAction swipeUp;
  final ReaderAction swipeDown;
  final ReaderAction statusLeft; // tap on the left half of the status bar
  final ReaderAction statusRight;
  final int turnMillis; // page-turn animation length (Moon: flip speed)
  final int blueLight; // warm filter strength, 0–100
  final int autoTurnSeconds; // auto page turn interval
  final int topMargin; // 40
  final int bottomMargin; // 30 (includes the status line)
  final bool publisherStyles;
  // Quill Dev only: open EPUBs (book design off) in the native engine preview.
  final bool nativeEngine;
  final bool night;
  final String dayTheme;
  final String nightTheme;
  final PageTurn pageTurn;
  final bool volumeKeys;
  final bool brightnessSwipe;
  final bool keepAwake;
  // Moon Reader-style paper grain over the page colour (Moon: background image on).
  final bool paperTexture;
  // Screen brightness 0..1 while reading; null follows the system.
  final double? brightness;

  // Bumped when the stored format or defaults change. v2: publisher styles default off.
  // v3: Moon Reader units.
  static const version = 3;

  // Space the status line takes inside the bottom margin, in dp.
  // The footer sits below the bottom margin, as in Moon Reader (its 30 is the gap above it).
  static const statusLineHeight = 0.0;

  ReaderTheme get theme => readerTheme(night ? nightTheme : dayTheme);
  Color get background => theme.background;
  Color get ink => theme.ink;

  // Readium values. Calibrated at Moon Reader's defaults; see the class comment.
  double get readiumFontSize => 0.766 * fontSize / 12.5;
  double get readiumLineHeight => 1.577 + (lineSpacing - 3) * 0.1;
  double get readiumParagraphSpacing => ((paragraphSpacing - 70) / 100).clamp(0.0, 2.0);
  double get readiumLetterSpacing => fontSpacing * 0.02;
  // Readium's page gutter is 20 css px per 1.0; Moon's side margin is in dp.
  double get readiumPageMargins => sideMargin / 20;
  double get frameBottom => (bottomMargin - statusLineHeight).clamp(0.0, 200.0);
  // Moon's top margin starts about 14 dp above Flutter's top inset (measured on the phone
  // 2026-11-10: same text and size, Quill's first line 48 px lower at 3.5 px/dp).
  static const moonTopOffset = -14.0;
  double frameTop(double topInset) => (topMargin + moonTopOffset + topInset).clamp(topInset, topInset + 200.0);

  // Book design on: the book's own CSS (fonts, alignment, spacing, headings); only size,
  // margins and colours remain the reader's. Book design off: Moon Reader's format, with the
  // plugin's quillMoonMode.css dropping what Moon's renderer ignores. Justification comes from
  // that stylesheet, so a book's centred lines stay centred; headings are not scaled up.
  EPUBPreferences get epub => publisherStyles
      ? EPUBPreferences(
          fontSize: readiumFontSize,
          columnCount: EpubColumnCount.one,
          publisherStyles: true,
          scroll: false,
          backgroundColor: background,
          textColor: ink,
          pageMargins: readiumPageMargins,
        )
      : EPUBPreferences(
          fontFamily: fontFamily,
          fontSize: readiumFontSize,
          columnCount: EpubColumnCount.one,
          publisherStyles: false,
          scroll: false,
          hyphens: hyphenation,
          typeScale: 1.0,
          backgroundColor: background,
          textColor: ink,
          lineHeight: readiumLineHeight,
          paragraphSpacing: readiumParagraphSpacing,
          letterSpacing: readiumLetterSpacing,
          pageMargins: readiumPageMargins,
        );

  ReadingProfile copyWith({
    double? fontSize,
    int? lineSpacing,
    int? paragraphSpacing,
    int? fontSpacing,
    int? sideMargin,
    int? rightMargin,
    bool? boldText,
    bool? hyphenation,
    String? fontFamily,
    bool? dualPage,
    bool? italicText,
    bool? underlineText,
    bool? textShadow,
    ReaderAction? swipeUp,
    ReaderAction? swipeDown,
    ReaderAction? statusLeft,
    ReaderAction? statusRight,
    int? turnMillis,
    int? blueLight,
    int? autoTurnSeconds,
    int? topMargin,
    int? bottomMargin,
    bool? publisherStyles,
    bool? nativeEngine,
    bool? night,
    String? dayTheme,
    String? nightTheme,
    PageTurn? pageTurn,
    bool? volumeKeys,
    bool? brightnessSwipe,
    bool? keepAwake,
    bool? paperTexture,
    double? Function()? brightness,
  }) => ReadingProfile(
    fontSize: fontSize ?? this.fontSize,
    lineSpacing: lineSpacing ?? this.lineSpacing,
    paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
    fontSpacing: fontSpacing ?? this.fontSpacing,
    sideMargin: sideMargin ?? this.sideMargin,
    rightMargin: rightMargin ?? this.rightMargin,
    boldText: boldText ?? this.boldText,
    hyphenation: hyphenation ?? this.hyphenation,
    fontFamily: fontFamily ?? this.fontFamily,
    dualPage: dualPage ?? this.dualPage,
    italicText: italicText ?? this.italicText,
    underlineText: underlineText ?? this.underlineText,
    textShadow: textShadow ?? this.textShadow,
    swipeUp: swipeUp ?? this.swipeUp,
    swipeDown: swipeDown ?? this.swipeDown,
    statusLeft: statusLeft ?? this.statusLeft,
    statusRight: statusRight ?? this.statusRight,
    turnMillis: turnMillis ?? this.turnMillis,
    blueLight: blueLight ?? this.blueLight,
    autoTurnSeconds: autoTurnSeconds ?? this.autoTurnSeconds,
    topMargin: topMargin ?? this.topMargin,
    bottomMargin: bottomMargin ?? this.bottomMargin,
    publisherStyles: publisherStyles ?? this.publisherStyles,
    nativeEngine: nativeEngine ?? this.nativeEngine,
    night: night ?? this.night,
    dayTheme: dayTheme ?? this.dayTheme,
    nightTheme: nightTheme ?? this.nightTheme,
    pageTurn: pageTurn ?? this.pageTurn,
    volumeKeys: volumeKeys ?? this.volumeKeys,
    brightnessSwipe: brightnessSwipe ?? this.brightnessSwipe,
    keepAwake: keepAwake ?? this.keepAwake,
    paperTexture: paperTexture ?? this.paperTexture,
    brightness: brightness != null ? brightness() : this.brightness,
  );

  // Applies a theme to the day or night slot it belongs to, and switches to it.
  ReadingProfile withTheme(ReaderTheme t) =>
      t.dark ? copyWith(night: true, nightTheme: t.id) : copyWith(night: false, dayTheme: t.id);

  // The groups the options sheet resets individually.
  ReadingProfile resetText() {
    const d = ReadingProfile();
    return copyWith(
      fontSize: d.fontSize,
      lineSpacing: d.lineSpacing,
      paragraphSpacing: d.paragraphSpacing,
      fontSpacing: d.fontSpacing,
      publisherStyles: d.publisherStyles,
      paperTexture: d.paperTexture,
      boldText: d.boldText,
      hyphenation: d.hyphenation,
      fontFamily: d.fontFamily,
      italicText: d.italicText,
      underlineText: d.underlineText,
      textShadow: d.textShadow,
    );
  }

  ReadingProfile resetMargins() {
    const d = ReadingProfile();
    return copyWith(
      sideMargin: d.sideMargin,
      rightMargin: d.rightMargin,
      topMargin: d.topMargin,
      bottomMargin: d.bottomMargin,
    );
  }

  Map<String, Object?> toJson() => {
    'v': version,
    'fontSize': fontSize,
    'lineSpacing': lineSpacing,
    'paragraphSpacing': paragraphSpacing,
    'fontSpacing': fontSpacing,
    'sideMargin': sideMargin,
    'rightMargin': rightMargin,
    'boldText': boldText,
    'hyphenation': hyphenation,
    'fontFamily': fontFamily,
    'dualPage': dualPage,
    'italicText': italicText,
    'underlineText': underlineText,
    'textShadow': textShadow,
    'swipeUp': swipeUp.name,
    'swipeDown': swipeDown.name,
    'statusLeft': statusLeft.name,
    'statusRight': statusRight.name,
    'turnMillis': turnMillis,
    'blueLight': blueLight,
    'autoTurnSeconds': autoTurnSeconds,
    'topMargin': topMargin,
    'bottomMargin': bottomMargin,
    'publisherStyles': publisherStyles,
    'night': night,
    'dayTheme': dayTheme,
    'nightTheme': nightTheme,
    'pageTurn': pageTurn.name,
    'volumeKeys': volumeKeys,
    'brightnessSwipe': brightnessSwipe,
    'keepAwake': keepAwake,
    'paperTexture': paperTexture,
    'brightness': brightness,
  };

  static ReadingProfile fromJson(Map<String, dynamic> j) {
    const d = ReadingProfile();
    final v = (j['v'] as num?)?.toInt() ?? 1;
    double? num_(String k) => (j[k] as num?)?.toDouble();
    int int_(String k, int fallback) => (j[k] as num?)?.toInt() ?? fallback;
    bool bool_(String k, bool fallback) => j[k] is bool ? j[k] as bool : fallback;
    return ReadingProfile(
      // Before v3 text size was a scale of the old base; 1.0 then matched Moon Reader's 12.5.
      fontSize: v >= 3 ? (num_('fontSize') ?? d.fontSize) : ((num_('fontScale') ?? 1.0) * 12.5),
      lineSpacing: int_('lineSpacing', d.lineSpacing),
      paragraphSpacing: int_('paragraphSpacing', d.paragraphSpacing),
      fontSpacing: int_('fontSpacing', d.fontSpacing),
      sideMargin: int_('sideMargin', d.sideMargin),
      // Before the right margin was separate it equalled the side margin.
      rightMargin: int_('rightMargin', int_('sideMargin', d.sideMargin)),
      boldText: bool_('boldText', d.boldText),
      hyphenation: bool_('hyphenation', d.hyphenation),
      fontFamily: const ['serif', 'sans-serif', 'monospace'].contains(j['fontFamily']) ? j['fontFamily'] as String : d.fontFamily,
      dualPage: bool_('dualPage', d.dualPage),
      italicText: bool_('italicText', d.italicText),
      underlineText: bool_('underlineText', d.underlineText),
      textShadow: bool_('textShadow', d.textShadow),
      swipeUp: ReaderAction.named(j['swipeUp'], d.swipeUp),
      swipeDown: ReaderAction.named(j['swipeDown'], d.swipeDown),
      statusLeft: ReaderAction.named(j['statusLeft'], d.statusLeft),
      statusRight: ReaderAction.named(j['statusRight'], d.statusRight),
      turnMillis: int_('turnMillis', d.turnMillis).clamp(100, 1000),
      blueLight: int_('blueLight', d.blueLight).clamp(0, 100),
      autoTurnSeconds: int_('autoTurnSeconds', d.autoTurnSeconds).clamp(3, 600),
      topMargin: int_('topMargin', d.topMargin),
      bottomMargin: int_('bottomMargin', d.bottomMargin),
      // Profiles saved before v2 stored the old "on" default, not a choice.
      publisherStyles: v >= 2 && bool_('publisherStyles', false),
      // EPUBs always open in Quill's own engine unless the book's own styles are chosen; the
      // earlier switches (preview, web engine) are ignored.
      nativeEngine: true,
      night: bool_('night', false),
      dayTheme: j['dayTheme'] as String? ?? d.dayTheme,
      nightTheme: j['nightTheme'] as String? ?? d.nightTheme,
      pageTurn: PageTurn.values.firstWhere((p) => p.name == j['pageTurn'], orElse: () => d.pageTurn),
      volumeKeys: bool_('volumeKeys', d.volumeKeys),
      brightnessSwipe: bool_('brightnessSwipe', d.brightnessSwipe),
      keepAwake: bool_('keepAwake', d.keepAwake),
      paperTexture: bool_('paperTexture', d.paperTexture),
      brightness: num_('brightness')?.clamp(0.02, 1.0),
    );
  }

  static Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/reader.json');

  static Future<ReadingProfile> load() async {
    try {
      return fromJson(jsonDecode(await (await _file()).readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return const ReadingProfile();
    }
  }

  Future<void> save() async => (await _file()).writeAsString(jsonEncode(toJson()));

  // ---- Settings kept for one book only, and named saved settings ("themes" in Moon Reader) ----

  static Future<File> _extras() async => File('${(await getApplicationSupportDirectory()).path}/reader-extras.json');

  static Future<Map<String, dynamic>> _readExtras() async {
    try {
      return jsonDecode(await (await _extras()).readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeExtras(Map<String, dynamic> all) async =>
      (await _extras()).writeAsString(jsonEncode(all));

  /// The book's own settings when it has them, else the global ones; and whether they are its own.
  static Future<(ReadingProfile, bool)> loadFor(String bookId) async {
    final usual = await load();
    final own = ((await _readExtras())['books'] as Map?)?[bookId];
    if (own is! Map<String, dynamic>) return (usual, false);
    // Which reader opens a book is decided by the usual settings, never per book.
    return (fromJson(own).copyWith(nativeEngine: usual.nativeEngine, publisherStyles: usual.publisherStyles), true);
  }

  /// Saves these as [bookId]'s own settings.
  Future<void> saveFor(String bookId) async {
    final all = await _readExtras();
    all['books'] = {...?(all['books'] as Map?)?.cast<String, dynamic>(), bookId: toJson()};
    await _writeExtras(all);
  }

  /// The book goes back to the global settings.
  static Future<void> clearFor(String bookId) async {
    final all = await _readExtras();
    all['books'] = {...?(all['books'] as Map?)?.cast<String, dynamic>()}..remove(bookId);
    await _writeExtras(all);
  }

  static Future<Map<String, ReadingProfile>> savedThemes() async {
    final saved = ((await _readExtras())['themes'] as Map?)?.cast<String, dynamic>() ?? const {};
    return {for (final e in saved.entries) e.key: fromJson((e.value as Map).cast<String, dynamic>())};
  }

  Future<void> saveTheme(String name) async {
    final all = await _readExtras();
    all['themes'] = {...?(all['themes'] as Map?)?.cast<String, dynamic>(), name: toJson()};
    await _writeExtras(all);
  }

  static Future<void> deleteTheme(String name) async {
    final all = await _readExtras();
    all['themes'] = {...?(all['themes'] as Map?)?.cast<String, dynamic>()}..remove(name);
    await _writeExtras(all);
  }
}
