# Quill (Flutter)

Shared Android + iOS app. Replaces the native Android prototype in `../app`, which stays as a
behaviour reference. Reading engine: `flutter_readium` (Readium Kotlin/Swift toolkits, BSD-3),
patched locally (see `third_party/PATCHES.md`).

Android release application ID `app.quill.reader`; debug builds use `app.quill.reader.dev`
and the launcher name **Quill Dev**. These apps have separate private library data,
preferences and folder permissions. Dev starts empty; choose its Books folder using Android's
picker when ready. It reads originals in place and does not inherit the released app's progress.

## Layout

- `lib/library/` — pure rules (file-name titles, shelf filters, scan merge, progress) and the
  saved library (`library.json`, written atomically in app support storage).
- `lib/shelf/` — cover/compact shelf, shelf picker (series/authors/folders), filters, search,
  Continue.
- `lib/reader/` — reader with overlay controls, status line, contents, search, preferences.
- Folder access is native: `android/.../MainActivity.kt` (folder picker, recursive scan of
  `content://` URIs) and `ios/Runner/AppDelegate.swift` (Files picker, security-scoped bookmark).
- `integration_test/` — on-device checks with synthetic books generated at test time.
  `dart run tool/make_fixtures.dart <dir>` writes the same books to a folder.

## Development toolchain

See [Building](../README.md#building) in the root README; `../tools/dev_setup.py` checks
and configure ignored SDK paths. Tested: Flutter 3.47.9 / Dart 3.13.7, JDK 21, Android SDK 37.0,
build-tools 36.0.0, NDK 28.2.13676358, AGP 9.1.1 and Gradle 9.3.1. Keep `pubspec.lock` and the
patched local reader dependency. Do not override `HOME` or copy old machine caches.

Integration tests run on an emulator only: at teardown Flutter uninstalls the app under test. Integration
runs replace `app-debug.apk` with a test app; rebuild the normal app before phone installation.
Normal `flutter run` and debug tests target Quill Dev. Its activity class keeps the existing
namespace, so direct Android launches use `app.quill.reader.dev/app.quill.reader.MainActivity`.
Updating the released `app.quill.reader` still requires its matching signing certificate.
Never uninstall or clear the released app's data to bypass a key mismatch.

## iOS

Not built yet. With Xcode installed: `flutter build ios --debug --no-codesign` (runs `pod install` with the
Readium pods already in `ios/Podfile`), then fix anything in `AppDelegate.swift`, which has
never been compiled. The iOS plugin expects plain file paths; `publicationLocation` in
`reader_page.dart` converts the picker's `file://` URLs.

## App icon

Open book with a gold pen nib on warm brown (concept A, chosen 2026-11-05). Sources are in
`design/icon/`: `icon.svg` (full icon), `layer-*.svg` (Android adaptive background, foreground
and themed-icon monochrome layers) and `concept-a.svg` (the approved sketch). After editing,
run `zsh design/icon/build_icons.sh` to regenerate every Android mipmap, the adaptive icon XML
and all iOS AppIcon sizes (opaque, as the App Store requires). Needs Google Chrome.
