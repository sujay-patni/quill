import 'package:flutter_test/flutter_test.dart';
import 'package:quill/reader/reading_profile.dart';

void main() {
  test("defaults are the user's Moon Reader settings and the calibrated Readium values", () {
    const p = ReadingProfile();
    expect([p.fontSize, p.lineSpacing, p.paragraphSpacing, p.fontSpacing], [12.5, 3, 70, 0]);
    expect([p.sideMargin, p.topMargin, p.bottomMargin], [24, 40, 30]);
    expect(p.publisherStyles, isFalse);
    expect(p.pageTurn, PageTurn.curl);
    expect([p.volumeKeys, p.brightnessSwipe, p.keepAwake], [true, true, true]);
    expect(p.brightness, isNull);
    expect(p.readiumFontSize, closeTo(0.766, 1e-9));
    expect(p.readiumLineHeight, closeTo(1.577, 1e-9));
    expect(p.readiumParagraphSpacing, 0);
    expect(p.readiumLetterSpacing, 0);
    expect(p.readiumPageMargins, closeTo(1.2, 1e-9));
    expect(p.frameBottom, 30);
    expect(p.frameTop(40), 66);
    expect(p.copyWith(topMargin: 0).frameTop(40), 40, reason: 'never above the system inset');
    expect(p.theme.id, 'day');
  });

  test('book design off uses Moon format; on leaves typography to the book', () {
    final moon = const ReadingProfile().epub;
    expect(moon.publisherStyles, isFalse);
    expect(moon.fontFamily, 'serif');
    expect(moon.lineHeight, closeTo(1.577, 1e-9));
    expect(moon.typeScale, 1.0);
    expect(moon.hyphens, isFalse);
    expect(moon.textAlign, isNull, reason: "quillMoonMode.css justifies without overriding centred lines");

    final book = const ReadingProfile(publisherStyles: true).epub;
    expect(book.publisherStyles, isTrue);
    expect([book.fontFamily, book.lineHeight, book.textAlign, book.typeScale, book.hyphens], everyElement(isNull));
    expect([book.paragraphSpacing, book.letterSpacing], everyElement(isNull));
    expect(book.fontSize, moon.fontSize);
    expect(book.pageMargins, moon.pageMargins);
  });

  test('a profile round-trips through JSON', () {
    final p = const ReadingProfile().copyWith(
      fontSize: 14,
      lineSpacing: 5,
      paragraphSpacing: 120,
      sideMargin: 10,
      pageTurn: PageTurn.slide,
      night: true,
      nightTheme: 'amoled',
      brightness: () => 0.4,
    );
    final back = ReadingProfile.fromJson(p.toJson());
    expect(back.toJson(), p.toJson());
    expect(back.theme.id, 'amoled');
  });

  test('older saved profiles carry over', () {
    // v1 stored a scale and the old publisher-styles default; v2 the same scale.
    final v1 = ReadingProfile.fromJson({'fontScale': 1.2, 'publisherStyles': true, 'night': true});
    expect(v1.fontSize, closeTo(15, 1e-9));
    expect(v1.publisherStyles, isFalse);
    expect(v1.night, isTrue);
    final v2 = ReadingProfile.fromJson({'v': 2, 'fontScale': 1.0, 'publisherStyles': true});
    expect(v2.fontSize, 12.5);
    expect(v2.publisherStyles, isTrue);
  });

  test('themes go to their own day or night slot', () {
    final sepia = const ReadingProfile().withTheme(readerTheme('sepia'));
    expect([sepia.night, sepia.dayTheme], [false, 'sepia']);
    final slate = sepia.withTheme(readerTheme('slate'));
    expect([slate.night, slate.nightTheme, slate.dayTheme], [true, 'slate', 'sepia']);
    expect(slate.copyWith(night: false).theme.id, 'sepia');
  });

  test('resets restore only their own group', () {
    final changed = const ReadingProfile().copyWith(fontSize: 20, sideMargin: 50, dayTheme: 'white');
    final text = changed.resetText();
    expect([text.fontSize, text.sideMargin, text.dayTheme], [12.5, 50, 'white']);
    expect(changed.resetMargins().sideMargin, 24);
  });

  test('new options round-trip; an older profile gets a right margin equal to its side margin', () {
    final p = const ReadingProfile().copyWith(
      sideMargin: 30,
      rightMargin: 12,
      boldText: true,
      turnMillis: 450,
      blueLight: 40,
      autoTurnSeconds: 20,
    );
    final back = ReadingProfile.fromJson(p.toJson());
    expect([back.sideMargin, back.rightMargin, back.boldText, back.turnMillis, back.blueLight, back.autoTurnSeconds],
        [30, 12, true, 450, 40, 20]);
    final old = ReadingProfile.fromJson({'v': 3, 'sideMargin': 36});
    expect(old.rightMargin, 36);
    expect([old.boldText, old.turnMillis, old.blueLight], [false, 300, 0]);
    expect(p.resetMargins().rightMargin, 24);
  });

  test('font, text styles and action mapping round-trip; unknown values fall back', () {
    final p = const ReadingProfile().copyWith(
      fontFamily: 'sans-serif',
      italicText: true,
      textShadow: true,
      swipeUp: ReaderAction.contents,
      statusRight: ReaderAction.dayNight,
    );
    final back = ReadingProfile.fromJson(p.toJson());
    expect([back.fontFamily, back.italicText, back.underlineText, back.textShadow], ['sans-serif', true, false, true]);
    expect([back.swipeUp, back.swipeDown, back.statusLeft, back.statusRight],
        [ReaderAction.contents, ReaderAction.none, ReaderAction.bookInfo, ReaderAction.dayNight]);
    final odd = ReadingProfile.fromJson({'v': 3, 'fontFamily': 'Comic', 'swipeUp': 'fly'});
    expect([odd.fontFamily, odd.swipeUp], ['serif', ReaderAction.none]);
    expect(back.epub.fontFamily, 'sans-serif');
  });
}
