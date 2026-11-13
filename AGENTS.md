# Quill

Offline Android reader (Flutter). Read [README.md](README.md), then PLAN.md, DESIGN.md and
READING.md before changing behavior. Use the reading profile in reader-defaults.json.
If a git-ignored `private/` folder exists, it holds the owner's handover and release logs:
read `private/HANDOFF.md` first and record tested behavior and open limitations there.

- EPUB, PDF, CBR and CBZ are in scope. No TTS, cloud account or server requirement.
- The app is the Flutter project in `mobile/` (Android + iOS, app ID `app.quill.reader`;
  debug and profile builds install separately as Quill Dev, `app.quill.reader.dev`).
- Work on `feature/<name>` (or `hotfix/<name>`) branches from `main`; merge to `main` only
  after unit tests, emulator integration tests and a device check pass.
- Never commit books, Moon Reader backups, note contents, reading data, phone identifiers,
  local paths, credentials or signing keys. The signing keystore is kept outside this
  repository. Use synthetic fixtures in tests.
- Select folders through Android's file picker; read originals in place. Never rewrite or
  delete source books while testing. Label approximate migration explicitly.
- Preserve bookmarks/locators across reflow and process death. Do not confuse spine
  resources with chapter entries or screen pages with stable positions.
- Integration tests run on an emulator only: at teardown Flutter uninstalls the app under
  test, which would erase a phone's library. Before any adb gesture on a real phone, check
  that Quill is the foreground app.
- Local patches to `mobile/third_party/flutter_readium` are listed in
  `mobile/third_party/PATCHES.md`; add an entry for every change there.
- Keep one writer per checkout or worktree.
