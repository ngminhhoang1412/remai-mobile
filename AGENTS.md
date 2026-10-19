# AGENTS.md: remai-mobile

Expo SDK 58 / React Native 0.88 / React 19.3 / TypeScript 6 app. iOS and Android come from one codebase.

## Source of truth

Behaviour is specified in `../remai-central-specs` and this repo holds no spec copies:

- `openspec/changes/archive/2026-10-19-add-notion-core/design.md`: D9 (mobile), D10 (autosave), D11 (wire conventions)
- `openspec/specs/mobile-client/spec.md`, plus `user-auth`, `page-management`,
  `page-content`, `page-search` and `page-trash` for the client-facing scenarios, and `web-client`
  "Keyboard block editing" for return/backspace rules
- `docs/api/openapi.yaml`: the exact wire contract. `src/lib/types.ts` and `src/lib/api.ts` mirror it.

If behaviour and these docs disagree, the specs win. Propose spec changes in remai-central-specs instead of drifting here.

## Commands

```bash
npm install
npx expo install <pkg>     # ALWAYS use for Expo/RN packages so versions match SDK 58
npx expo start             # dev server (Expo Go / emulator)
npm test                   # jest-expo unit tests
npx tsc --noEmit           # typecheck (must pass)
npx expo export --platform ios --output-dir dist && npx expo export --platform android --output-dir dist
```

Before declaring work done, run `npm test`, `npx tsc --noEmit` and both exports, then delete `dist/`.
There is no Android SDK or Xcode on the Windows dev machines. Bundling both platforms is the compile check.

Expo changes between SDKs. Check the versioned docs (`https://docs.expo.dev/versions/v58.0.0/`)
before using an Expo/RN API from memory. RN 0.88 ships its own generated types: use
`TextInputInstance`, `ScrollViewInstance` and `TextInputKeyPressEvent` from `react-native`, not
`TextInput` as a ref type. TS 6 no longer auto-includes `@types/*`, so `tsconfig.json` lists `"types": ["jest"]`.

## Architecture

- `src/app/`: expo-router routes only. `_layout.tsx` wraps `SafeAreaProvider` → `SessionProvider` → `PagesProvider`
  and renders a `Stack` with two `Stack.Protected` groups. A session change (sign-in, sign-out, any 401)
  swaps the available screens, so there is no manual redirect code.
- `src/lib/`: **pure logic with no React or native imports** (except `tokenStorage.ts`, `uuid.ts` and `config.ts`).
  Keep it that way so it stays unit-testable.
  - `api.ts`: `createApiClient({ baseUrl, getToken, onUnauthorized, fetchImpl })`. Bearer header,
    error-envelope parsing into `ApiError{status, code, message}`, network failure → `status 0 / network_error`.
    A 401 on an authenticated call invokes `onUnauthorized(tokenUsed)`. Login/register 401s don't.
    With no token, authenticated calls fail locally (no request).
  - `blocks.ts`: return/backspace/turn-into/toggle/numbering rules. Ids are injected (`makeId`).
  - `tree.ts`: `buildTree` (createdAt ascending, orphans at the top level), `flattenVisible(roots, expanded)`, `subtreeIds`.
  - `autosave.ts`: `AutosaveController<T>`: 800 ms debounce, single in flight, re-save if dirty,
    retry backoff 2 s → 30 s, `flush()`, `dispose()`. One for blocks (PUT), one for title+icon (PATCH).
- `src/state/session.tsx`: the token lives in a ref plus `expo-secure-store` (never AsyncStorage). Launch check is
  `GET /auth/me`. A network failure on launch shows a "Can't reach remai" overlay (retry / sign out) instead
  of discarding a possibly valid token.
- `src/state/pages.tsx`: page-list cache shared by Home and Page. Live title/icon edits are patched in locally.

## Editor implementation notes (read before touching `page/[id].tsx` / `BlockRow.tsx`)

- **Return creates the next block** by detecting the newline in `onChangeText`
  (`isReturnAtEnd(prev, next)`: longer text that ends in `\n`). Multiline `TextInput`s insert `\n` on
  return and always report it through `onChangeText` on both iOS and Android, while `onKeyPress`
  `Enter` isn't reliable on Android soft keyboards. The check tolerates autocorrect committing a word
  together with the return. A newline typed **mid-text** stays a line break inside the block (the
  mobile stand-in for the web's Shift+Enter). `submitBehavior="submit"` was rejected for blocks
  because it would make multi-line code/quote blocks impossible. The title uses it (return → first block).
- **Backspace on empty** uses `onKeyPress` with `key === 'Backspace'`. It fires before `onChangeText`,
  so the check reads the pre-edit text from `blocksRef` and only removes a block that was already empty.
  Known caveat: a few third-party Android keyboards don't emit key events for backspace on an empty field.
  The removal then doesn't happen, but nothing breaks.
- `BlockRow` always renders `[prefix slot, TextInput]` in fixed positions, so "Turn into" re-styles the
  same input instead of remounting it, which would drop focus and the keyboard.
- `TurnIntoBar` uses `keyboardShouldPersistTaps="always"` so tapping a type keeps the block focused.
- Keyboard safety: `KeyboardAvoidingView behavior="padding"` on both platforms. Android is edge-to-edge
  on RN 0.88, so the window doesn't resize and padding is needed. If the window does resize, KAV computes zero
  overlap, so there's no double offset. The focused block is kept visible by measuring block layouts and
  scrolling (`ensureVisible`) on focus, on keyboard show, on viewport change and when the block grows.
  **Not yet verified on a physical device or emulator.**
- Dividers aren't editable. Long-press a divider to delete it. Turning a block that has text into a
  divider inserts the divider above it, so no text is lost.
- Empty pages get one local empty paragraph, which isn't saved until edited.
- Tapping below the last block focuses a trailing empty paragraph if there is one, rather than stacking another.

## Conventions

- Strict TypeScript and the `@/` alias → `src/` (mapped for Jest in `package.json`).
- Name tests after spec scenarios (e.g. "Numbered list restarts: …").
- Never log or display tokens. Use synthetic credentials in tests. The repo commits no `.env`.
- Light theme only (`userInterfaceStyle: "light"`). Colours and spacing come from `src/theme.ts`.
- `typedRoutes` and the React Compiler experiment are off to keep `tsc` deterministic without
  generated `.expo/types` and to keep the editor's ref-heavy code predictable.
