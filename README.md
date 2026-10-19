# remai-mobile

iOS and Android client for **remai**, a Notion-like notes app. One Expo (React Native + TypeScript)
codebase, Expo SDK 58 with `expo-router` stack navigation.

Specs and the API contract live in [`../remai-central-specs`](../remai-central-specs):

- Change: `openspec/changes/archive/2026-10-19-add-notion-core/` (design decisions D9 mobile client, D10 autosave, D11 wire conventions)
- API contract: `docs/api/openapi.yaml`
- Capabilities implemented here: `mobile-client`, plus the client-facing parts of `user-auth`,
  `page-management`, `page-content`, `page-search` and `page-trash`. Return/backspace block rules
  follow the `web-client` "Keyboard block editing" requirement.

## Features

- Sign in / sign up; session token kept in the platform's secure storage (`expo-secure-store`:
  iOS Keychain, Android Keystore-backed) and checked with `GET /auth/me` on launch. Any 401 deletes it and shows sign-in.
- Home: page tree with expand/collapse, “New page”, Search, and a menu with Trash and Sign out.
- Page: emoji icon, title, blocks edited in place (10 types), a “Turn into” bar above the keyboard,
  to-do toggle, numbered lists, “Add subpage”, “Move to trash”. Autosave with a status indicator.
- Search (300 ms debounce) and Trash (Restore, and Delete forever after a confirmation).

## Prerequisites

- Node 20+ (developed on Node 24 / npm 11)
- A running [remai-backend](../remai-backend) (default `http://localhost:8080`)
- To run the app, either:
  - **Expo Go** on a phone (SDK 58 build from the App Store / Play Store), or
  - an **Android emulator** (Android Studio) or **iOS simulator** (Xcode, macOS only).

## Setup

```bash
npm install
```

Create a `.env` file in the repo root with the API base URL (no trailing slash):

```bash
EXPO_PUBLIC_API_URL=http://10.0.2.2:8080
```

| Where the app runs | `EXPO_PUBLIC_API_URL` |
|---|---|
| iOS simulator (same Mac as the backend) | `http://localhost:8080` |
| Android emulator | `http://10.0.2.2:8080` (the emulator's alias for the host machine; `localhost` would be the emulator itself) |
| Physical phone (Expo Go) | `http://<your PC's LAN IP>:8080`, e.g. `http://192.168.1.20:8080`. Phone and PC must be on the same network, and the PC firewall must allow port 8080. |

If unset, the app falls back to `http://localhost:8080`. `EXPO_PUBLIC_*` variables are inlined into
the JavaScript bundle at build time, so they must never hold secrets, and you need to restart
`expo start` (`npx expo start -c` to clear the cache) after changing them.

## Run

```bash
npx expo start          # then press a (Android emulator), i (iOS simulator), or scan the QR code with Expo Go
npm run android         # same as `expo start --android`
npm run ios             # same as `expo start --ios` (macOS only)
```

Everything used here (`expo-secure-store`, `expo-crypto`, `react-native-safe-area-context`,
`react-native-screens`, `@expo/vector-icons`) ships in Expo Go, so no development build is needed.

## Test and verify

```bash
npm test                # jest-expo unit tests (block rules, tree, API client, autosave)
npx tsc --noEmit        # typecheck
npx expo export --platform ios --output-dir dist      # proves the iOS bundle compiles
npx expo export --platform android --output-dir dist  # proves the Android bundle compiles
```

`dist/` is gitignored; delete it after an export check.

## Project layout

```
src/
  app/                 expo-router screens (every file is a route)
    _layout.tsx        providers + Stack with Stack.Protected (signed-in vs signed-out screens)
    sign-in.tsx, sign-up.tsx
    index.tsx          Home: page tree
    page/[id].tsx      Page editor
    search.tsx, trash.tsx
  components/          BlockRow, TurnIntoBar, EmojiPicker, MenuSheet, AuthForm, shared ui
  hooks/               useDebouncedValue, useKeyboardVisible
  lib/                 pure logic: api client, block rules, tree, autosave controller, types, config
    __tests__/         unit tests named after spec scenarios
  state/               session (token + current user) and page-list cache contexts
  theme.ts             colours, spacing, fonts
```

## Notes

- Plain `http://` works in Expo Go and debug builds. A release build should talk to an `https://`
  backend: Android blocks cleartext HTTP and iOS App Transport Security blocks it by default in release builds.
- Concurrent edits from two devices resolve as last write wins (design.md, Risks).
