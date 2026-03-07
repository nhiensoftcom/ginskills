---
name: react-native-expo
description: |
  **React Native Expo (Sty AI Mobile)**: Production patterns for the Sty AI React Native app — Expo SDK 54, Expo Router v5, React Query v5, Zustand v5, Reanimated v4, FlashList v2, MMKV, BottomSheet v5, react-hook-form + zod, and the full Sty AI design system.
  - MANDATORY TRIGGERS: react native, expo, mobile app, screen, component, navigation, route, tab, stack, modal, animation, reanimated, gesture, flash list, flatlist, list performance, bottom sheet, form, validation, zod, state management, zustand, store, query, mutation, api call, fetch data, image, expo-image, styling, theme, color, typography, spacing, font, button, card, skeleton, shimmer, toast, dialog, upload, camera, photo, push notification, deep link, branch, auth, login, onboarding, keyboard, MMKV, storage, cache, i18n, localization, live activity, adapty, subscription, in-app purchase, analytics, airbridge, facebook sdk
  - Use this skill whenever working on ANY file in the styai-mobile directory, creating new screens/components, debugging mobile issues, optimizing performance, or reviewing mobile code. Also trigger when discussing React Native architecture, Expo configuration, or mobile-specific patterns — even casual mentions like 'fix this screen' or 'add a button'.
---

# React Native Expo — Sty AI Mobile

Production-grade skill for the Sty AI React Native mobile app (Expo SDK 54, New Architecture, Hermes).

## Quick Start — Load Only What You Need

Before writing code, read the correct reference file based on the task:

| Task | Reference File |
|------|---------------|
| Screens, routes, navigation, tabs, modals | `references/navigation.md` |
| React Query hooks, API calls, mutations | `references/data-layer.md` |
| Zustand stores, MMKV, global state | `references/state-management.md` |
| Animations, gestures, Reanimated, lists | `references/performance.md` |
| Theme, colors, typography, spacing, scaling | `references/design-system.md` |
| Forms, validation, zod, bottom sheets | `references/ui-patterns.md` |
| Auth, notifications, deep links, i18n, analytics | `references/platform-services.md` |

Read ONLY the relevant reference file(s) for the current task. This keeps token usage minimal.

## Project Identity

- **App**: Sty AI — AI-powered wardrobe management
- **Bundle**: `app.styai.android` (Android) / `dev.jerrypham.easycloset` (iOS)
- **Stack**: Expo SDK 54, React Native 0.81, React 19, TypeScript 5.9
- **Package Manager**: pnpm
- **Font**: Poppins (300-900 weights, platform-specific families)
- **Design**: Sophisticated minimal with rose/blush brand accent (#EC4899)

## Architecture at a Glance

```
styai-mobile/src/
  app/           # Route files (thin delegators to screens)
  screens/       # Actual screen logic (mirrors app/ structure)
  models/        # Domain models: _services/, _types/, _ui/, _store/
  features/      # Cross-cutting features (auth, credit, stylist, etc.)
  shared/        # Shared infrastructure
    components/  # Typography, Button, BottomSheet, shimmer, toast
    hooks/       # use-auth-init, use-push-notifications, use-infinite-scroll
    libs/        # api-client (Axios + auto-refresh), token-storage (Keychain)
    stores/      # Zustand stores with slices pattern
    theme/       # Design tokens: color, typography, spacing, scaling
    services/    # Singletons: logger, airbridge, facebook, push
    types/       # PaginatedResponse<T>, IdRes, TimeStampRes, ApiError
    constant/    # ROUTES object, enums
    utils/       # Helpers: compress-image, date, logger, share-app
  components/    # (deprecated — use shared/components/)
```

## Critical Rules

1. **Route files are thin delegators** — actual logic lives in `src/screens/`
2. **Always use `Typography`** instead of raw `<Text>`
3. **Always use `Theme.color.*`** semantic tokens, never raw hex values
4. **Always use `useShallow`** when selecting multiple fields from Zustand
5. **Query keys = API URL path strings** (e.g., `"/api/v1/item"`)
6. **All API calls through `client`** from `@/shared/libs/api-client`
7. **Use `expo-image`** (`Image` from `expo-image`), not React Native's `Image`
8. **Use `FlashList`** for lists, never `FlatList`
9. **Use `Spacing.*`** semantic tokens for all spacing values
10. **Platform fonts differ**: iOS uses `Poppins-Medium`, Android uses `Poppins_500Medium` — always use `typefaceBase` or `withFontWeight()`, never hardcode font names

## Path Aliases

```
@/*            → ./src/*
@auth/*        → ./src/features/auth/*
@testimonials/* → ./src/assets/images/testimonials/*
assets/*       → ./assets/*
```

## Commands

```bash
pnpm start              # Dev server (Metro)
pnpm ios                # iOS device
pnpm android            # Android emulator
pnpm type-check         # TypeScript check
pnpm lint:fix           # ESLint + auto-fix
pnpm test               # Jest
pnpm prebuild           # Regenerate native code
pnpm cng:development    # Full dev env setup
```

## Key Dependencies

| Package | Version | Use |
|---------|---------|-----|
| `expo` | 54 | Framework (New Arch, Hermes) |
| `expo-router` | 6 | File-based routing (v5 API) |
| `@tanstack/react-query` | 5 | Server state |
| `zustand` | 5 | Client state |
| `react-native-mmkv` | 3.1 | Fast sync storage |
| `react-native-reanimated` | 4.1 | UI-thread animations |
| `@shopify/flash-list` | 2.0 | High-perf lists (New Arch only) |
| `@gorhom/bottom-sheet` | 5 | Bottom sheets |
| `react-hook-form` + `zod` | 7 + 3 | Forms + validation |
| `expo-image` | 3.0 | Cached images |
| `react-native-gesture-handler` | 2.28 | Native gestures |
| `@shopify/react-native-skia` | 2.2 | Canvas drawing |
| `react-native-keychain` | 10 | Secure JWT storage |
| `i18next` + `react-i18next` | 25 + 16 | i18n (9 languages) |
| `react-native-adapty` | 3.15 | Subscriptions |
| `airbridge-expo-sdk` | 4.8 | Analytics |
| `lottie-react-native` | 7.3 | Lottie animations |
| `date-fns` / `dayjs` | 4 / 1.11 | Date utils |
| `axios` | 1.11 | HTTP client (wrapped) |
| `react-native-svg` | 15.12 | SVG rendering |
| `ai` + `@ai-sdk/react` | 4 + 1 | AI SDK streaming |

## New Code Placement

- **New model** → `src/models/<model-name>/` with `_services/`, `_types/`
- **New screen** → `src/screens/` + thin delegator in `src/app/`
- **New shared component** → `src/shared/components/`
- **New hook** → `src/shared/hooks/` or model's `_hooks/`
- **New store** → `src/shared/stores/` (Zustand) or feature's `_stores/`
- **New feature** → `src/features/<feature-name>/`
- **DO NOT** add to `src/components/` (deprecated)
