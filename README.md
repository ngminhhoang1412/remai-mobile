# remai-mobile

iOS and Android client for **remai**, a Notion-like notes app. One Flutter 3.44 / Dart 3.12 codebase.

Specs and the API contract live in [`../remai-central-specs`](../remai-central-specs):

- Change: `openspec/changes/archive/2026-10-19-adopt-flutter-and-serverless/` (design D8 for the Flutter client, D9 for 429 handling)
- Autosave protocol: `openspec/changes/archive/2026-10-19-add-notion-core/design.md` D10
- API contract: `docs/api/openapi.yaml`. Design tokens: `designs/design-tokens.md`
- Capabilities implemented here: `mobile-client`, plus the client-facing parts of `user-auth`,
  `page-management`, `page-content`, `page-search` and `page-trash`. Return/backspace block rules
  follow the `web-client` "Keyboard block editing" requirement.

## Features

- Sign in / sign up. The session token is kept in the platform's secure storage
  (`flutter_secure_storage`: iOS Keychain, Android Keystore-backed) and checked with `GET /auth/me` on
  launch. Any 401 deletes it and shows sign-in. If the server can't be reached at launch, the app
  shows "Can't reach remai" with Retry and Sign out instead of discarding the token.
- Home: the page tree with expand/collapse, "New page", Search, and a menu with Trash and Sign out.
- Page: emoji icon, title, and blocks edited in place (10 types). A "Turn into" bar shows above the
  keyboard. There's a to-do toggle, numbered lists, "Add subpage" and "Move to trash". Autosave
  shows a status indicator: Saving…, Saved, Couldn't save – retrying, or Couldn't save.
- Search (300 ms debounce) and Trash (Restore, and Delete forever after a confirmation).

## Prerequisites

- Flutter 3.44.x (Dart 3.12). Any machine without Flutter can use the Docker image instead (see
  [Checks via Docker](#checks-via-docker)).
- A running [remai-backend](../remai-backend). Locally, that's `http://localhost:8080`.
- To run the app you need one of:
  - an **Android emulator** or device (Android Studio / Android SDK)
  - an **iOS simulator** or device (Xcode, **macOS only**)

## Run on an emulator or device

The API base URL is a build-time setting:

```bash
flutter pub get
flutter run --dart-define=REMAI_API_URL=http://10.0.2.2:8080
```

| Where the app runs | `REMAI_API_URL` |
|---|---|
| Android emulator | `http://10.0.2.2:8080`. This is the emulator's alias for the host machine; `localhost` would be the emulator itself. |
| iOS simulator (on the Mac that runs the backend) | `http://localhost:8080` |
| Physical phone | `http://<your PC's LAN IP>:8080`, for example `http://192.168.1.20:8080`. The phone and the PC must be on the same network, and the PC firewall must allow port 8080. |
| Hosted API | `https://<apiId>.execute-api.<region>.amazonaws.com` |

If unset, the app uses `http://localhost:8080`. Values passed with `--dart-define` are compiled
into the app, so they must never hold secrets.

**Plain http is for development only.** Android debug and profile builds allow cleartext traffic
(`android/app/src/debug|profile/AndroidManifest.xml`), and release builds don't. On iOS,
`NSAllowsLocalNetworking` lets the app reach a local or LAN backend over http. **Release builds
must use an `https` API URL.**

## Build

```bash
flutter build apk --debug --dart-define=REMAI_API_URL=http://10.0.2.2:8080
flutter build apk --release --dart-define=REMAI_API_URL=https://<apiId>.execute-api.<region>.amazonaws.com
flutter build ios --dart-define=REMAI_API_URL=https://...    # macOS + Xcode only
```

- **iOS builds need macOS and Xcode.** The iOS target is generated and contains no custom native
  code, but it hasn't been built in this repo's CI/dev environment (Windows + Docker). Run
  `flutter build ios` on a Mac before any release.
- Release signing isn't set up yet: the Android `release` build type still signs with the debug key
  (Flutter template default). Keystores and `key.properties` are gitignored. Don't commit them.

## Test and verify

```bash
flutter analyze          # must report no issues
flutter test             # unit tests (block rules, tree, autosave, API client) + widget tests
flutter build apk --debug
```

### Checks via Docker

On machines without Flutter (e.g. the Windows dev boxes), run the same checks in the
`ghcr.io/cirruslabs/flutter:3.44.0` image, which includes the Android SDK. Named volumes keep the pub and Gradle caches
between runs:

```bash
docker run --rm -v "$PWD:/app" -w /app \
  -v remai-pub-cache:/root/.pub-cache -v remai-gradle:/root/.gradle \
  ghcr.io/cirruslabs/flutter:3.44.0 \
  sh -c "flutter pub get && flutter analyze && flutter test && flutter build apk --debug"
```

In Git Bash on Windows, prefix the command with `MSYS_NO_PATHCONV=1` and use a Windows-style path for
the mount (e.g. `-v "C:/path/to/remai-mobile:/app"`). Files the container creates (`build/`,
`.dart_tool/`) are root-owned on Linux hosts.

## Project layout

```
lib/
  main.dart            entry point: secure token storage + http client → RemaiApp
  app.dart             providers (SessionState, PagesState) + MaterialApp.router
  router.dart          go_router routes; the session drives the sign-in / launch redirect
  theme.dart           design tokens (colours, spacing, type scale) and ThemeData
  api/                 ApiClient (bearer, error envelope, 401, 429), TokenStorage
  models/              wire types mirroring openapi.yaml (hand-written fromJson/toJson)
  logic/               pure Dart: block rules, tree, autosave controller, ids, formatting
  state/               ChangeNotifiers: session, page-tree cache
  screens/             launch, sign in/up, home, page editor, search, trash
  widgets/             block row, Turn-into bar, emoji picker, shared states
test/
  logic/ api/          unit tests named after spec scenarios
  widgets/             widget tests against an in-memory fake backend (test/support/)
```

See [AGENTS.md](AGENTS.md) for conventions and editor implementation notes.
