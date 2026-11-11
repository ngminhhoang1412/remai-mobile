# AGENTS.md: remai-mobile

Flutter 3.44 / Dart 3.12 app for iOS and Android (one codebase). It replaces the earlier Expo client.

## Source of truth

The specs live in the sibling repo [`../remai-central-specs`](../remai-central-specs). This repo holds no copies of them.

- `openspec/changes/archive/2026-10-19-adopt-flutter-and-serverless/design.md`: **D8** (Flutter stack, packages, structure,
  block editing, the backspace requirement) and **D9** (429 bodies aren't the error envelope). Its
  `tasks.md` group 5 lists the mobile tasks. Spec owners tick tasks, not agents.
- `openspec/changes/archive/2026-10-19-add-notion-core/design.md`: D10 (autosave protocol), D11 (wire conventions)
- `openspec/specs/mobile-client/spec.md`, plus `user-auth`, `page-management`, `page-content`,
  `page-search` and `page-trash` for the client-facing scenarios. The return/backspace rules come from
  the `web-client` "Keyboard block editing" requirement.
- `docs/api/openapi.yaml` is the exact wire contract, and `lib/models/models.dart` and `lib/api/api_client.dart` mirror it.
  `designs/design-tokens.md` is mirrored by `lib/theme.dart`.

If the code and these docs disagree, the specs win. Propose spec changes in remai-central-specs instead of letting the code drift.

## Commands

Flutter isn't installed on the Windows dev machines, so run every check in the pinned container.
Run it from Git Bash, and note that `MSYS_NO_PATHCONV=1` stops Git Bash from rewriting `/app`:

```bash
MSYS_NO_PATHCONV=1 docker run --rm \
  -v "C:/Users/<you>/.../remai-mobile:/app" -w /app \
  -v remai-pub-cache:/root/.pub-cache -v remai-gradle:/root/.gradle \
  ghcr.io/cirruslabs/flutter:3.44.0 \
  sh -c "flutter pub get && flutter analyze && flutter test && flutter build apk --debug"
```

- The first `flutter build apk` in a fresh container takes about 15 minutes. Gradle downloads go to the
  `remai-gradle` volume, but the Android SDK Platform 35 and CMake 3.22.1 that the build installs land
  in the container's `/opt/android-sdk-linux`, and the container is thrown away afterwards. To keep them between runs you can
  add `-v remai-android-sdk:/opt/android-sdk-linux`, which Docker seeds from the image on first use.
  This tip is untested.
- Before declaring work done, run `flutter analyze` (zero issues, including infos), `flutter test`
  (all green) and `flutter build apk --debug`.
- iOS can't be built on this machine. Keep native iOS changes to a minimum, and flag in your report anything that needs `flutter build ios` on a Mac.
- Add or upgrade a dependency with `flutter pub add <pkg>` in the container, then commit `pubspec.lock`.
  **Allowed runtime packages are fixed by D8:** `go_router`, `provider`, `http`, `flutter_secure_storage`
  and `uuid`. Don't add code generation, Riverpod/Bloc or rich-text packages. A new package needs a
  design change in remai-central-specs first. Dev-only: `flutter_lints` and `fake_async`.
- `go_router` is pinned to **17.x** on purpose. 18.x moved to the standalone `material_ui` package,
  whose `MaterialApp` is a different class from `package:flutter/material.dart`'s. go_router 18 then
  wouldn't detect this app as a MaterialApp, so pages would lose Material transitions and the error
  screen. Move both together when the app migrates to `material_ui`.
- `flutter_secure_storage` 11.x needs Android minSdk 24 (Flutter 3.44's default minimum).

## Architecture

- `lib/main.dart` builds `SessionState(SecureTokenStorage, http.Client, REMAI_API_URL)` and runs
  `RemaiApp`. `REMAI_API_URL` is `String.fromEnvironment` (set with `--dart-define`) and defaults to `http://localhost:8080`.
- `lib/app.dart` provides `SessionState` and `PagesState` (provider `ChangeNotifier`s) above `MaterialApp.router`.
- `lib/router.dart`: go_router with `refreshListenable: session`. The redirect is the only auth gate.
  `loading`/`unreachable` → `/launch`, `signedOut` → `/sign-in` (or `/sign-up`), and `signedIn`
  leaves the auth routes for `/`. A sign-in, sign-out or 401 swaps the whole stack, so screens contain no redirect code.
  Screens are pushed (`context.push`) so the platform back gesture works.
- `lib/api/api_client.dart`: `ApiClient({baseUrl, httpClient, getToken, onUnauthorized, timeout})`.
  - It sends the bearer header and parses the error envelope into `ApiException{status, code, message}`.
  - Network failures and timeouts become `status 0 / network_error`.
  - **Any 429 is `rate_limited` ("slow down") whatever the body**, because API Gateway's body isn't the envelope (D9).
  - A 401 on an authenticated call invokes `onUnauthorized(tokenUsed)`. Login/register 401s don't.
  - With no token, authenticated calls fail locally without sending a request.
  - `isRetryableSaveError`: 400/401/404/413 aren't retried. Everything else, including 429, 5xx and the network, is.
- `lib/state/session.dart`: the token is held in memory plus `TokenStorage` (secure storage, never
  shared preferences). The launch check is `GET /auth/me`. A 401 signs out, and a network failure leads to `unreachable`
  ("Can't reach remai", with Retry and Sign out) and keeps the token. A late 401 for a replaced token is ignored.
- `lib/state/pages.dart`: the page-list cache shared by Home and the Page screen. Live title/icon edits are
  patched in, and it's cleared on sign-out.
- `lib/logic/` holds **pure Dart with no Flutter imports**. Keep it that way so it stays unit-testable.
  - `blocks.dart`: return/backspace/turn-into/toggle/numbering rules, plus the sentinel helpers.
  - `tree.dart`: `buildTree` (createdAt ascending, stable, orphans at top level), `flattenVisible`, `subtreeIds`.
  - `autosave.dart`: `AutosaveController<T>`. 800 ms debounce, one save in flight, re-save if dirty,
    retry backoff 2 s → 30 s (`error`), non-retryable failure → `failed` ("Couldn't save") until the
    next edit, plus `flush()` and `dispose()`. The page uses one controller for blocks (PUT, whole list, client UUIDs)
    and one for title+icon (PATCH).

## Editor implementation notes (read before touching `page_screen.dart` / `block_row.dart`)

- **One multiline `TextField` per block**, each with its own `BlockTextController` and `FocusNode`.
  Both are owned by the page state, keyed by block id, created lazily, and disposed one frame after
  their block is removed.
- **Return at the end creates the next block.** A multiline field with `TextInputAction.newline`
  inserts `\n`, and `onChanged` sees it. `isReturnAtEnd(prev, next)` checks for longer text that ends
  in `\n`, and tolerates autocorrect committing a word along with the return. A newline typed
  **mid-text** stays a line break inside the block (the mobile stand-in for Shift+Enter). The title
  uses `TextInputAction.next` instead: return moves to the first block.
- **Backspace on an empty block uses a zero-width sentinel.** Soft keyboards don't send key events
  to Flutter, and deleting in an empty field changes nothing, so `onChanged` would never fire. So:
  - Every block field holds `U+200B` + the block text (`withSentinel`).
  - `BlockTextController.value` clamps every selection to offset ≥ 1, so the caret can never sit
    before the sentinel. That's true for taps, IME updates and programmatic changes.
  - The only way to remove the sentinel is a delete at the very start of the field. In
    `onChanged`, `readSentinel(raw)` reports `deletedSentinel`:
    - If the block was empty, this is "backspace in an empty block". `applyBackspaceOnEmpty`
      removes the block and moves the caret to the end of the previous editable block.
    - If it's the first block, nothing is removed and the sentinel is put back.
    - If the block had text, it's a backspace at the start. The text is kept and the sentinel is
      restored (no merge with the previous block, which the spec doesn't require).
  - The text sent to the API never contains `U+200B`. `readSentinel` strips every occurrence, so
    pasted zero-width spaces are dropped too.
  - The field's own `hintText` can't show because the text is never empty. `BlockRow` draws the
    placeholder itself, behind the field.
  - Hardware keyboards go through the same path, so there's no key-event handling.
  - Covered by widget tests in `test/widgets/page_editor_test.dart`: "Remove empty block: …"
    (soft keyboard and hardware), the first-block and non-empty cases, and caret clamping.
  - **Unverified on devices:** some IMEs may treat the leading `U+200B` as "mid-word" and skip
    auto-capitalising the first letter. Check Gboard, Samsung Keyboard and the iOS keyboard.
- `_syncFieldState` only rewrites a controller when its text differs from the block, for example
  after a return, a restored sentinel or a programmatic edit. Normal typing never rewrites the controller, so IME composing
  isn't disturbed.
- **Focus moves**: `_focusAfterFrame` focuses an already-mounted field immediately, so focus passes
  straight from field to field (a removed field never holds focus when it unmounts, which would close
  and reopen the keyboard). A newly created field is focused after the frame that mounts it.
- `BlockRow` keeps the **same widget shape for every editable type**: Padding > DecoratedBox > Padding >
  Row[prefix SizedBox, Expanded[Stack[placeholder, TextField]]]. That way "Turn into" re-styles the existing
  field instead of remounting it, which would drop focus. Don't swap in `Container` here, because it
  inserts or removes wrappers depending on its arguments.
- The Turn-into bar sits in a `TextFieldTapRegion` with non-focusable chips, so tapping it keeps the
  block focused. It shows while any block is focused.
- **Keyboard-safe layout**: `Scaffold` resizes for the keyboard (`adjustResize` on Android). The
  blocks are in a non-lazy `SliverToBoxAdapter` column, so every field stays mounted and focusable.
  `EditableText` scrolls the caret into view on focus and when the insets change, with extra
  `scrollPadding` at the bottom. The test "Typing near the bottom" covers this with a phone-sized
  view and fake insets. **It hasn't been verified on a physical device or emulator yet.**
- Dividers aren't editable. Long-press one to delete it (after a confirmation). Turning a block that
  has text into a divider inserts the divider above it, so no text is lost.
- An empty page gets one local empty paragraph, which isn't saved until it's edited. Tapping below the
  last block focuses a trailing empty paragraph if there is one, instead of stacking another.
- **Autosave flushes** happen when you leave the page (`dispose`), when the app is inactive, hidden or paused
  (`AppLifecycleListener`), before "Add subpage", and before "Move to trash", which then disposes the savers.

## Conventions

- Lints: `flutter_lints` plus the stricter rules in `analysis_options.yaml` (`strict-casts`,
  `strict-raw-types`, `unawaited_futures`, …). Wrap fire-and-forget futures in `unawaited(...)`.
- No code generation. The JSON mapping is hand-written in `lib/models/models.dart`. The page model
  is `PageInfo`, so it doesn't clash with Flutter's `Page`. Import go_router with `show GoRouterHelper` where
  `Block` is used, because go_router also exports a `Block` type.
- Name tests after spec scenarios, for example "Numbered list restarts: …" or "Token rejected: …".
  Widget tests use `test/support/fake_backend.dart` (`MockClient` + in-memory storage) and pass
  `requestTimeout: null` so no timer outlives a test.
- Never log or display tokens. Tests use synthetic credentials only, and the repo commits no `.env`,
  keystores or `key.properties`.
- Light theme only. Colours, spacing and type sizes come from `lib/theme.dart` (design tokens).
