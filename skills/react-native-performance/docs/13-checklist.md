# 13. Optimization Checklist by Effort Level

Use this checklist as a structured audit for any React Native app. Work through levels sequentially — Level 1 items should always be completed before investing time in Level 3 or 4 work.

---

## Level 1 — Quick Wins (< 1 day)

These require minimal code changes and deliver measurable improvements immediately.

- [ ] Verify Hermes is enabled — check `!!global.HermesInternal` at runtime; ensure `hermes: true` in `android/app/build.gradle` and `ios/Podfile`
- [ ] Enable `inlineRequires` in `metro.config.js` to defer module evaluation until first use
- [ ] Switch to `react-native-bootsplash` to eliminate the white flash on cold start (avoids the default native splash → white → RN screen transition)
- [ ] Run bundle visualizer (`npx react-native bundle` + `source-map-explorer`) to identify the heaviest dependencies
- [ ] Replace `moment.js` with `dayjs` — identical API, saves ~70KB gzipped from the bundle
- [ ] Replace `import _ from 'lodash'` with individual named imports (`import debounce from 'lodash/debounce'`) or switch to `lodash-es` with tree-shaking
- [ ] Add `keyExtractor` returning a stable, unique string ID to ALL `FlatList` and `SectionList` components
- [ ] Move all static style objects into `StyleSheet.create()` — styles are validated once and sent to the native side as an integer ID
- [ ] Enable `lazy: true` on all `Tab.Navigator` and `Drawer.Navigator` to defer rendering offscreen tabs until first visit
- [ ] Replace `AsyncStorage` with `MMKV` for synchronous, 10–30x faster key-value storage
- [ ] Add `babel-plugin-transform-remove-console` to strip `console.*` calls in production builds
- [ ] Remove Flipper from release builds — Flipper adds significant native overhead; confirm it is inside `debugImplementation` only in `build.gradle`

---

## Level 2 — Standard (1–3 days)

These require more implementation effort but address the most common performance bottlenecks.

- [ ] Replace `FlatList` with `FlashList` (Shopify) for all lists with more than 20 items — uses recycling instead of unmount/remount
- [ ] Wrap list item components in `React.memo` and memoize their callbacks with `useCallback` to prevent re-renders on parent state changes
- [ ] Switch image rendering to `expo-image` or `@d11/react-native-fast-image` — both use native caching (SDWebImage / Glide) and avoid repeated decoding
- [ ] Set up TanStack Query with meaningful `staleTime` values and persist the cache to MMKV so users see data immediately on re-open
- [ ] Lazy load non-critical screens with `React.lazy` and `Suspense` — combine with a loading skeleton for perceived performance
- [ ] Defer analytics initialization, crash reporting SDKs, and non-essential services until after the first interactive frame (use `InteractionManager.runAfterInteractions`)
- [ ] Audit all `useEffect` hooks and add proper cleanup: remove event listeners, clear timers (`clearTimeout`, `clearInterval`), cancel subscriptions
- [ ] Request thumbnail-sized images from your CDN using query parameters (e.g., `?w=200&h=200&fit=crop`) — never load full-resolution images into list cells
- [ ] Replace `Animated` API animations with `Reanimated` for any animation that runs on every frame — Reanimated runs on the UI thread and never drops frames during JS work
- [ ] Add `AbortController` to all `fetch` calls inside `useEffect` to cancel in-flight requests when the component unmounts
- [ ] Split large monolithic React Contexts (e.g., a single `AppContext`) into focused, domain-specific contexts so updates only re-render relevant consumers
- [ ] Use Zustand store selectors (not the entire store object) — `useStore(state => state.user)` instead of `useStore()` to prevent unnecessary re-renders

---

## Level 3 — Advanced (1–2 weeks)

These require architectural decisions and testing across the full app.

- [ ] Migrate to the New Architecture (RN 0.76+) — enables JSI, TurboModules, and Fabric renderer; eliminates the async bridge for native calls
- [ ] Replace all remaining `Animated` API usage with `Reanimated 3` or `Reanimated 4` — audit with a codebase search for `import { Animated } from 'react-native'`
- [ ] Set up Sentry performance monitoring — configure `tracesSampleRate`, `enableNativeFramesTracking`, and `enableStallTracking`; add custom spans to critical paths
- [ ] Add Reassure render benchmarks to CI — establish baselines on `main`, compare on every PR, fail on regressions exceeding thresholds
- [ ] Implement cursor-based pagination (keyset pagination) for all infinite lists — offset pagination causes database full scans at high offsets
- [ ] Set up a WebSocket singleton (not per-component) for real-time features so the connection is shared and not reconnected on re-render
- [ ] Flatten navigation depth to 3 levels or fewer — each nested navigator adds a layout pass; deep stacks increase memory for the navigation state
- [ ] Implement `react-freeze` for offscreen tab content — freezes React trees that are not visible so they do not re-render during background state updates
- [ ] Add memory pressure handlers — listen to `memoryWarning` event on iOS and `onTrimMemory` on Android to release caches and cancel non-essential work
- [ ] Set up bundle size budgets in CI — track bundle size per PR, post a delta comment, and fail the build if the budget is exceeded

---

## Level 4 — Expert (> 2 weeks)

These require deep native knowledge or significant infrastructure investment. Prioritize only after Level 1–3 are complete.

- [ ] Write custom TurboModules for CPU-intensive operations that cannot be offloaded (e.g., image processing, cryptography, audio encoding)
- [ ] Implement CI performance budgets using Flashlight or a custom script — automatically reject PRs that introduce measurable regressions in FPS or startup time
- [ ] Set up Flashlight + Maestro automated performance testing — run full user flow scenarios on real devices or device farms in CI and track score over time
- [ ] Evaluate the React Compiler (available in RN 0.78+) — it eliminates manual `useMemo`/`useCallback` for components where the compiler can prove referential stability
- [ ] Evaluate RAM Bundles or Re.Pack for very large apps (> 5MB JS bundle) — RAM Bundles load modules on demand from the native side; Re.Pack enables Webpack-based code splitting
- [ ] Upgrade to Hermes V1 (available in RN 0.82+) — improved startup performance, better GC, and reduced memory footprint
- [ ] Move CPU-bound computations to a native module — JavaScript is single-threaded; offloading to a native thread unblocks the JS thread for UI work
- [ ] Apply font subsetting — generate font files containing only the Unicode ranges actually used in the app, reducing font asset size by 50–90%
- [ ] Enable ProGuard/R8 optimization for Android release builds — shrinks, obfuscates, and optimizes the Java/Kotlin bytecode, reducing APK size and improving startup

---

## Per-Category Quick Fix Priority

| Category | Highest Impact Fix | Effort |
|---|---|---|
| Startup | `inlineRequires` + defer non-critical SDK initialization | 1 hour |
| Lists | FlashList + `React.memo` on list item components | 2 hours |
| Memory | `useEffect` cleanup audit across the entire codebase | 4 hours |
| Bundle | Replace `moment.js` + tree-shake or remove `lodash` | 1 hour |
| Navigation | `enableScreens` (react-native-screens) + `lazy: true` on tabs | 30 min |
| Animation | Migrate complex animations from `Animated` to Reanimated | 1–2 days |
| Network | TanStack Query with appropriate `staleTime` values | 2 hours |
