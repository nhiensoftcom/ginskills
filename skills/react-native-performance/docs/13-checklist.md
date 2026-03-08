# 13. Optimization Checklist by Effort Level

---

## Level 1 — Quick Wins (< 1 day)

- [ ] Verify Hermes enabled (`!!global.HermesInternal`)
- [ ] Enable `inlineRequires` in `metro.config.js`
- [ ] Switch to `react-native-bootsplash`
- [ ] Run bundle visualizer, identify heavy deps
- [ ] Replace `moment.js` → `dayjs` (save ~230 KB)
- [ ] Replace `lodash` full → individual imports
- [ ] Add `keyExtractor` with stable IDs to ALL lists
- [ ] Move static styles to `StyleSheet.create()`
- [ ] Enable `lazy: true` on tab navigators
- [ ] Replace `AsyncStorage` → MMKV
- [ ] Add `babel-plugin-transform-remove-console`
- [ ] Remove Flipper from release builds

---

## Level 2 — Standard (1-3 days)

- [ ] Replace `FlatList` → FlashList for large lists
- [ ] Add `React.memo` + `useCallback` for list items
- [ ] Switch to `expo-image` / FastImage
- [ ] Setup TanStack Query with `staleTime` + MMKV persist
- [ ] Lazy load screens with `React.lazy` + `Suspense`
- [ ] Defer analytics/crash init post-startup
- [ ] Add `useEffect` cleanup for ALL subscriptions
- [ ] Request thumbnail sizes from CDN
- [ ] Replace `Animated` → Reanimated
- [ ] Add `AbortController` to `fetch` in `useEffect`
- [ ] Split monolithic Context
- [ ] Use Zustand selectors

---

## Level 3 — Advanced (1-2 weeks)

- [ ] Migrate to New Architecture (RN 0.76+)
- [ ] Replace all `Animated` with Reanimated 3/4
- [ ] Setup Sentry performance monitoring
- [ ] Add Reassure render benchmarks to CI
- [ ] Implement cursor-based pagination
- [ ] Setup WebSocket for real-time
- [ ] Flatten navigation to 3 levels or fewer
- [ ] Enable `react-freeze` for offscreen tabs
- [ ] Add memory pressure handlers
- [ ] Setup bundle size budget in CI

---

## Level 4 — Expert (> 2 weeks)

- [ ] Custom TurboModules for native operations
- [ ] CI performance budgets
- [ ] Flashlight + Maestro automated testing
- [ ] Evaluate React Compiler (RN 0.78+)
- [ ] Re.Pack for code splitting
- [ ] Hermes V1 (RN 0.82+)
- [ ] Font subsetting
- [ ] ProGuard/R8 optimization

---

## Priority by Category

| Category | Highest Impact Fix | Effort |
|---|---|---|
| Startup | `inlineRequires` + defer init | 1 hour |
| Lists | FlashList + `React.memo` | 2 hours |
| Memory | `useEffect` cleanup audit | 4 hours |
| Bundle | Replace `moment.js` + `lodash` | 1 hour |
| Navigation | `enableScreens` + lazy tabs | 30 min |
| Animation | Reanimated migration | 1-2 days |
| Network | TanStack Query + `staleTime` | 2 hours |
