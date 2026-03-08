# 13. Optimization Checklist by Effort Level

Work through levels in order. Complete Level 1 entirely before moving to Level 2 — the compounding effect is significant and later levels are harder to justify without the baseline wins.

---

## Level 1: Quick Wins (< 1 hour each)

| # | Action | Impact | Metric |
|---|--------|--------|--------|
| 1 | **Strip `console.log` via Babel plugin** — add `babel-plugin-transform-remove-console` to `babel.config.js` under `plugins` (production only) | Eliminates string allocations and JS→native bridge calls on every log statement | ~50ms startup saved; console calls removed from bundle |
| 2 | **Enable Metro `inlineRequires`** — set `transformer.inlineRequires: true` in `metro.config.js` | Defers module evaluation until first use; reduces modules executed on startup | ~100ms startup saved; measured with `--profile` flag |
| 3 | **Replace `moment.js` with `dayjs`** — swap import, add only needed plugins | moment.js ships a full locale table even when unused | ~65KB bundle saved (moment ~232KB → dayjs ~6KB + plugins) |
| 4 | **Add `resizeMode` to every `<Image>`** — default behavior forces layout recalculation on load | Without `resizeMode`, the image triggers a second layout pass once dimensions resolve | Eliminates layout thrash; visible jank removed on image-heavy screens |
| 5 | **Enable Hermes engine** — `jsEngine: 'hermes'` in `app.json` (Expo) or `enableHermes: true` in `android/app/build.gradle` | Hermes pre-compiles JS to bytecode at build time; no JIT needed at runtime | 30–50% startup improvement; TTI drops from ~3s to ~1.5s on mid-range Android |
| 6 | **Use `StyleSheet.create` over inline style objects** — audit files with inline `style={{ ... }}` | Inline objects are recreated on every render and pressure the GC; `StyleSheet.create` registers styles natively once | GC pauses reduced; style objects no longer allocated per render cycle |
| 7 | **Add `keyExtractor` to every `FlatList`** — use stable entity IDs, never array index | Without a stable key, RN cannot reconcile list items and re-renders entire visible rows on any state change | Prevents full-list re-renders; measurable with React DevTools Profiler |
| 8 | **Remove Flipper from release builds** — Flipper network plugin and layout inspector ship native code into production APK/IPA | Flipper initializes native plugins at startup even when the debugger is not connected | ~2MB APK/IPA reduction; startup improved by removed plugin init time |
| 9 | **Set `staleTime` in React Query** — configure globally via `QueryClient` defaultOptions and per-query where data changes infrequently | Without `staleTime`, every screen focus triggers a background refetch regardless of data age | Refetch count reduced; measurable in React Query Devtools "fetches" counter |
| 10 | **Replace full `lodash` with `lodash-es` subpath imports** — `import debounce from 'lodash-es/debounce'` instead of `import { debounce } from 'lodash'` | Full lodash barrel import pulls entire library; tree-shaking cannot eliminate unused functions from CJS lodash | ~70KB bundle saved; verify with `react-native-bundle-visualizer` |
| 11 | **Switch to `react-native-bootsplash`** — replace default white flash on launch | Bootsplash keeps the native splash visible until JS is ready; eliminates white-screen flash | Perceived startup instant; no visible blank frame between splash and app |
| 12 | **Run bundle visualizer once** — `npx react-native-bundle-visualizer` | Identifies unexpectedly large transitive dependencies before deeper optimization work | Establishes baseline; typically uncovers 1–3 large deps to replace immediately |

---

## Level 2: Moderate Effort (1–4 hours each)

| # | Action | Impact | Metric |
|---|--------|--------|--------|
| 1 | **Switch `FlatList` → `FlashList`** — install `@shopify/flash-list`, replace component, set `estimatedItemSize` | FlashList recycles native cell views instead of creating new React components per item; JS reconciliation work drops dramatically | 5–10x scroll frame rate improvement on lists > 50 items; JS thread idle during scroll |
| 2 | **Implement Zustand selectors** — replace `useStore()` with `useStore(state => state.specificSlice)` throughout | Without selectors, every Zustand state mutation re-renders all components that called `useStore()` regardless of which slice changed | Store-wide re-renders eliminated; components only re-render when their selected slice changes |
| 3 | **Add `React.memo` to list item components** — wrap with comparison function where props contain objects | List items re-render on every parent state change without memoization, even when item data is unchanged | Re-render count per scroll event drops from N-items to 0 for unchanged items; measurable in Profiler |
| 4 | **Replace `react-native` `Image` with `expo-image`** — swap import, add `contentFit` prop | expo-image ships with blurhash placeholders, memory-aware LRU cache, and native image decoding on background thread | Visible loading flicker eliminated; memory footprint reduced on image-heavy screens |
| 5 | **Use `useFocusEffect` for screen data fetching** — replace `useEffect` fetch calls in screens with `useFocusEffect` + `useCallback` | `useEffect` fetches run on mount and never again; `useFocusEffect` re-fetches when user returns to screen, preventing stale data without over-fetching | Wasted fetches on hidden screens eliminated; stale-data bugs resolved |
| 6 | **Enable `react-native-screens`** — call `enableScreens()` before app renders, ensure `native-stack` is used | Without native screens, navigating away keeps previous screen's entire React tree mounted and rendering | Memory per route reduced; navigation gesture response time improved to native speed |
| 7 | **Add bundle size tracking in CI** — use `bundlesize` or a custom script that fails PR if JS bundle exceeds threshold | Without CI enforcement, bundle size regressions ship silently; a single new dependency can add 50–200KB unnoticed | Bundle size regressions caught at PR time, not post-release |
| 8 | **Implement MMKV for all storage** — replace `AsyncStorage` with `react-native-mmkv`; update all read/write call sites | AsyncStorage is async and goes through the bridge; MMKV is synchronous C++ via JSI | 200x faster read/write; synchronous reads unblock UI code that previously needed `useEffect` to await storage |
| 9 | **Setup Sentry performance monitoring** — add `Sentry.init` with `tracesSampleRate`, wrap navigation with `Sentry.wrap` | Without production tracing, performance regressions are discovered by user complaints, not metrics | Transaction P50/P95 visible in Sentry; regressions detectable before they impact majority of users |
| 10 | **Add lazy loading for tab screens** — set `lazy: true` on `Tab.Navigator`, add skeleton `fallback` per tab | All tab screens mount on app start by default; lazy loading defers mount until tab is first visited | Initial render time reduced by number of tabs × per-screen render cost; measured with Flashlight |
| 11 | **Defer analytics and crash reporter init post-startup** — move `Sentry.init`, `Analytics.init` into a `useEffect` with no deps in root component | These SDKs initialize native modules synchronously during startup, blocking the JS thread | 50–150ms startup improvement depending on SDKs; measured with `--profile` trace |
| 12 | **Add `AbortController` to all `fetch` calls in `useEffect`** — return cleanup that calls `controller.abort()` | Without cleanup, in-flight fetches complete after component unmounts, trigger state updates on unmounted components, and produce memory leaks | Memory leak warnings eliminated; network requests cancelled on unmount confirmed in network tab |

---

## Level 3: Significant Effort (1–2 days each)

| # | Action | Impact | Metric |
|---|--------|--------|--------|
| 1 | **Migrate to `native-stack` navigator** — replace `@react-navigation/stack` with `@react-navigation/native-stack` throughout | JS-stack navigator renders transitions in React; native-stack delegates to `UINavigationController` / `FragmentManager` | Transitions run at 60fps on the UI thread; JS thread is free during navigation gesture |
| 2 | **Implement Reanimated for all animations** — replace `Animated` API with `react-native-reanimated` worklets | `Animated` runs on the JS thread; heavy JS work causes animation jank; Reanimated worklets run on the UI thread via JSI | Animations maintain 60fps even when JS thread is busy; measured with Perfetto/Flashlight |
| 3 | **Setup Reassure regression testing** — add `measurePerformance` tests for critical screens, run in CI on PRs | Without automated benchmarks, render-count regressions ship undetected; manual profiling is not done on every PR | Render count regressions blocked at PR time; baseline render counts documented per screen |
| 4 | **Add code splitting with Re.Pack** — configure webpack chunking, lazy-load feature modules | Entire JS bundle evaluated on startup by default; code splitting defers feature module evaluation | Initial bundle size reduced by size of deferred modules; startup proportionally faster |
| 5 | **Implement optimistic updates** — use React Query's `onMutate` / `context` pattern to update cache before server confirms | User waits for round-trip latency before UI reflects their action; on slow networks this is 300–2000ms of perceived lag | Perceived action latency drops to ~0ms; server errors roll back via `onError` |
| 6 | **Setup offline-first with MMKV persistence** — configure `createSyncStoragePersister` with MMKV adapter; define `gcTime` and `networkMode: 'offlineFirst'` | App is unusable without network; users on flaky connections see empty screens and errors | App renders cached data immediately on launch; reads from cache while revalidating in background |
| 7 | **Configure ProGuard/R8 for Android release** — enable in `android/app/build.gradle`, add rules for reflection-based libs | Debug APK ships with full class names, unused code paths, and debug symbols | APK size reduced 15–30%; startup improved as fewer classes loaded by Dalvik/ART |
| 8 | **Implement image preloading pipeline** — preload next-screen hero images during idle time using `expo-image`'s `prefetch` or `Image.prefetch` | Hero images show a loading placeholder when navigating to a new screen; user sees a blank frame | No visible loading state on navigation; images render immediately on screen mount |
| 9 | **Add memory leak detection to CI** — use `react-native-performance` or Detox + Instruments to measure heap growth across screen navigation cycles | Memory leaks grow unbounded across session; hard to detect until crash reports appear | Heap delta per navigation cycle < threshold enforced; leak source identified before shipping |
| 10 | **Implement cursor-based pagination** — replace offset pagination with cursor tokens from the API | Offset pagination re-fetches earlier pages to maintain position; cursor pagination fetches only new items | Network payload per page load reduced; no duplicate items on fast-scrolling feeds |

---

## Level 4: Major Investment (1+ week each)

| # | Action | Impact | Metric |
|---|--------|--------|--------|
| 1 | **Migrate to New Architecture (JSI, Fabric, TurboModules)** — upgrade to RN 0.76+, enable New Architecture flag, migrate native modules | Old Architecture sends every JS↔native call over an async serialized bridge; New Architecture uses synchronous JSI calls and Fabric's concurrent rendering | Bridge round-trip eliminated; native module calls synchronous; Fabric enables concurrent features |
| 2 | **Build C++ TurboModules for heavy computation** — implement image processing, cryptography, or data transformation in C++ exposed via JSI | JS cannot match native speed for CPU-bound work; large data transformations block the JS thread | Computation moved off JS thread entirely; JS thread idle during heavy processing |
| 3 | **Implement custom native modules for hot paths** — identify bridge-heavy flows via profiling, rewrite in Swift/Kotlin | Frequent bridge calls for gestures, scroll events, or sensor data accumulate latency; each call has serialization overhead | Bridge call count for identified hot path reduced to zero; replaced with JSI or event emitters |
| 4 | **Setup full RUM monitoring pipeline** — integrate Sentry, Datadog, or custom telemetry to capture TTI, frame drops, crash-free sessions, and ANRs by device tier | Without segmented production data, optimizations are applied uniformly rather than targeted at devices where users suffer most | P50/P95/P99 TTI by device tier; frame drop rate by screen; ANR rate by OS version — all tracked continuously |
| 5 | **Implement module federation with Re.Pack** — split app into host + remote feature modules deployable independently | Entire app must be rebuilt and resubmitted to stores for any change; module federation enables OTA updates for individual features | Feature modules updated without app store submission; initial bundle contains only host shell |
| 6 | **Build custom Hermes snapshot for faster startup** — compile a Hermes bytecode snapshot containing the app's JS bundle at build time | Hermes parses and compiles JS at first launch; a pre-compiled snapshot skips this step entirely | First-launch startup time equivalent to subsequent launches; largest startup gain available |

---

## Priority Decision Tree

Use this tree when you do not know where to start. Answer each question based on profiling data, not assumptions.

```
START
  │
  ├─ Is startup slow? (TTI > 3s on mid-range Android)
  │    │
  │    ├─ YES ──► Run Level 1 items 1, 2, 5, 8, 11 first
  │    │          Then: Level 2 items 7, 10, 11
  │    │          Then: Level 3 item 7 (ProGuard) + item 4 (code splitting)
  │    │          Finally: Level 4 item 6 (Hermes snapshot)
  │    │
  │    └─ NO
  │         │
  │         ├─ Are lists janky? (scroll < 60fps, frame drops visible)
  │         │    │
  │         │    ├─ YES ──► Level 2 item 1 (FlashList) first
  │         │    │          Then: Level 2 items 2, 3 (selectors + memo)
  │         │    │          Then: Level 3 item 2 (Reanimated)
  │         │    │
  │         │    └─ NO
  │         │         │
  │         │         ├─ Is bundle large? (> 3MB JS bundle)
  │         │         │    │
  │         │         │    ├─ YES ──► Level 1 items 3, 10, 8 (dayjs, lodash-es, Flipper)
  │         │         │    │          Then: Level 2 item 7 (CI bundle tracking)
  │         │         │    │          Then: Level 3 item 4 (Re.Pack splitting)
  │         │         │    │
  │         │         │    └─ NO
  │         │         │         │
  │         │         │         ├─ Are animations janky?
  │         │         │         │    │
  │         │         │         │    ├─ YES ──► Level 2 item 10 (lazy tabs)
  │         │         │         │    │          Then: Level 3 item 1 (native-stack)
  │         │         │         │    │          Then: Level 3 item 2 (Reanimated)
  │         │         │         │    │
  │         │         │         │    └─ NO
  │         │         │         │         │
  │         │         │         │         ├─ Is memory growing unbounded?
  │         │         │         │         │    │
  │         │         │         │         │    ├─ YES ──► Level 2 item 12 (AbortController)
  │         │         │         │         │    │          Then: Level 3 item 9 (leak detection CI)
  │         │         │         │         │    │          Then: Level 4 item 4 (RUM monitoring)
  │         │         │         │         │    │
  │         │         │         │         │    └─ NO
  │         │         │         │         │         │
  │         │         │         │         │         └─ Instrument with Flashlight + Sentry
  │         │         │         │         │            then revisit tree with data
  │         │         │         │         │
  │         │         │         │         └─ Is perceived latency high on user actions?
  │         │         │         │              │
  │         │         │         │              ├─ YES ──► Level 3 item 5 (optimistic updates)
  │         │         │         │              │          Then: Level 3 item 6 (offline-first)
  │         │         │         │              │          Then: Level 2 item 9 (Sentry tracing)
  │         │         │         │              │
  │         │         │         │              └─ NO ──► App is performing well.
  │         │         │         │                        Set up Level 3 item 3 (Reassure CI)
  │         │         │         │                        to protect current performance.
  │         │         └─────────┘
  │         └─────────┘
  └─────────┘
```

---

## Priority by Category

| Category | Highest-Impact Fix | Level | Effort |
|---|---|---|---|
| Startup | Hermes + `inlineRequires` + defer SDK init | L1 + L2 | < 2 hours total |
| Lists | FlashList + `React.memo` + Zustand selectors | L2 | 2–4 hours |
| Memory | `useEffect` cleanup audit + AbortController | L2 | 2–3 hours |
| Bundle | Remove Flipper + replace moment + lodash-es | L1 | < 1 hour |
| Navigation | `native-stack` + `enableScreens` + lazy tabs | L2 + L3 | 2–6 hours |
| Animation | Reanimated migration | L3 | 1–2 days |
| Network | React Query `staleTime` + MMKV persist + cursor pagination | L1 + L3 | 3–5 hours |
| Storage | MMKV everywhere | L2 | 2–3 hours |
| Observability | Sentry perf + Reassure CI + RUM pipeline | L2 + L4 | 1 day + ongoing |
| Architecture | New Architecture migration | L4 | 1+ week |
