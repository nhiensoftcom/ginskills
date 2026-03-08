# React Native Performance Anti-Patterns — Quick Reference

A catalog of patterns that degrade React Native performance, organized by category with root cause, fix, and severity.

Severity scale: **ERROR** (causes jank, crashes, or correctness bugs — fix before shipping) / **WARN** (measurable performance impact — fix before scaling) / **INFO** (best-practice violation, minor latent cost).

---

## Rendering Anti-Patterns

| # | Anti-Pattern | Why Bad | Fix | Severity |
|---|---|---|---|---|
| R1 | Inline arrow function in JSX (`onPress={() => fn(item)}`) | New function reference every render bypasses `React.memo` on the child — child re-renders every time the parent does regardless of prop equality | Extract handler with `useCallback`; wrap child in `React.memo` | ERROR |
| R2 | Inline style objects (`style={{ margin: 8 }}`) | New object allocated every render; React native layout diff detects a change even when values are identical | `StyleSheet.create` at module level; `useMemo` for dynamic values | WARN |
| R3 | `key={index}` in dynamic lists | Item insertion, deletion, or reorder maps old components to wrong data — wrong animations, stale state, O(n) reconciliation | Use `key={item.id}` with a stable unique identifier from the data source | ERROR |
| R4 | `<FlatList>` nested inside `<ScrollView>` | Outer `ScrollView` gives `FlatList` infinite height, disabling its virtualizer entirely — all items render at once | Use `ListHeaderComponent` / `ListFooterComponent` on a single `FlatList`, or `SectionList` for heterogeneous content | ERROR |
| R5 | Components over 300 lines with mixed concerns | Many unrelated state slices in one scope — any state update re-renders the entire large tree | Decompose into single-responsibility leaf components; each leaf re-renders only when its own props change | WARN |
| R6 | Missing `React.memo` on list item components | Every parent state change (scroll offset, badge count, selection) re-renders every visible list item | Wrap item component in `React.memo`; ensure all props are stable references | WARN |
| R7 | `import _ from 'lodash'` (default barrel import) | Bundles the entire 72 KB lodash library even when only one utility is used | `import get from 'lodash/get'` (subpath import) or replace with native ES equivalents | WARN |
| R8 | Chained `.map().filter().find()` in render body | O(n²) or worse computation runs synchronously on the JS thread every render, blocking the UI | Pre-compute into `Map` / `Set` during data fetch; wrap in `useMemo` with correct dependencies | ERROR |
| R9 | Dynamic style object computed inline in render | New object each call; if spread into `StyleSheet` it defeats caching; if passed inline it triggers native layout diff every render | Move static parts to `StyleSheet.create`; wrap dynamic parts in `useMemo` | WARN |
| R10 | `console.log` in production code | Serializes arguments, crosses the JS-to-native bridge synchronously (~1ms each); in list renders or loops this sums to tens of ms of UI thread blocking | Strip with `babel-plugin-transform-remove-console` in the production Babel config | WARN |

---

## Memory Anti-Patterns

| # | Anti-Pattern | Why Bad | Fix | Severity |
|---|---|---|---|---|
| M1 | Missing `useEffect` cleanup for subscriptions | Event listener persists after unmount, holds a closure over component state/props, fires on an unmounted component — memory leak and potential state update on dead component | Return a cleanup function: `return () => subscription.remove()` | ERROR |
| M2 | `setInterval` / `setTimeout` not cleared on unmount | Timer retains a reference to the callback closure; fires after the component is gone, may call `setState` on an unmounted component | Store ID in `useRef`; clear in `useEffect` cleanup: `return () => clearInterval(id.current)` | ERROR |
| M3 | No `AbortController` on `fetch` inside `useEffect` | In-flight request completes after navigation away; the `then` callback calls `setState` on an unmounted component — React warning and potential state corruption | Create `AbortController` in effect; pass `signal` to `fetch`; abort in cleanup | WARN |
| M4 | Closures retaining large objects unnecessarily | A callback stored in an event listener closes over the entire component scope; if it outlives the component, the closed-over data cannot be GC'd | Use `useRef` for mutable values callbacks need; pass only primitive identifiers — look up data inside the handler | WARN |
| M5 | Unbounded image cache with no eviction policy | Libraries like `react-native-fast-image` default to unlimited in-memory cache; on image-heavy feeds this exhausts RAM on mid-range devices, causing OOM crashes | Configure max cache size; use `expo-image` (built-in LRU eviction); call `clearMemoryCache()` periodically | ERROR |
| M6 | Storing entire API response object in state | Large objects are held in JS heap and diffed by reference; deep merges or spreads allocate new arrays on every update | Normalize to an ID-keyed map; store slices; select with selectors | WARN |
| M7 | No pagination on large data sets | Loading all records at once blows up heap and causes a long synchronous JS parse after the network response | Implement cursor- or offset-based pagination; render with `FlashList` for recycling | WARN |
| M8 | Global `Map` or cache growing forever | A module-level cache that only adds, never evicts, grows unboundedly for the lifetime of the app process | Use an LRU cache (e.g., `lru-cache`); set a max size appropriate to device RAM | WARN |

---

## Navigation Anti-Patterns

| # | Anti-Pattern | Why Bad | Fix | Severity |
|---|---|---|---|---|
| N1 | JS stack navigator instead of native-stack | JS-driven stack animates in JavaScript, consuming the JS thread and dropping frames during transitions | Use `@react-navigation/native-stack` (backed by `UINavigationController` / `Fragment` transitions) | ERROR |
| N2 | Missing `lazy: true` on tab screens | All tab screens initialize, fetch data, and render at startup even though only one tab is visible — multiplies startup time and memory usage | Set `lazy={true}` (React Navigation tab default); add `freezeOnBlur={true}` to suspend inactive renders | WARN |
| N3 | More than 3 navigator nesting levels | Navigation state object grows with each level; `useNavigation` traverses the ancestor chain; `goBack()` on deeply nested screens is slow | Flatten the hierarchy; use shared modals at the root navigator level instead of pushing modals inside nested stacks | WARN |
| N4 | `useEffect` instead of `useFocusEffect` for screen focus work | `useEffect` runs once on mount, not on subsequent back-navigations; misses refresh needs — or if used with navigation listener, is harder to clean up correctly | Use `useFocusEffect(React.useCallback(..., [deps]))` for work that must run each time a screen gains focus | WARN |
| N5 | Missing `enableScreens()` from `react-native-screens` | Without native screen containers, all navigator screens are rendered in a single native view layer — loses OS-level memory and lifecycle management | Call `enableScreens()` once in app entry before any navigator renders | ERROR |
| N6 | Heavy synchronous work in screen component body | Module-level or top-of-render computations run during navigation transition, janking the transition animation | Defer with `useFocusEffect`, `InteractionManager.runAfterInteractions`, or `useEffect` | WARN |

---

## State Anti-Patterns

| # | Anti-Pattern | Why Bad | Fix | Severity |
|---|---|---|---|---|
| S1 | Monolithic Context holding all app state | Any state change anywhere re-renders all consumers — auth change re-renders cart UI, theme change re-renders user profile | Split context by domain and update frequency; use Zustand or Jotai for high-frequency slices | ERROR |
| S2 | Missing Zustand selectors (subscribing to entire store) | `useStore(state => state)` re-renders the component on every store mutation regardless of which slice changed | Select the minimum needed: `useStore(state => state.feed.items)` | WARN |
| S3 | Storing derived data in state | When source data updates, derived state must be separately updated — creates stale/inconsistent values and double state updates | Store only source data; derive with `useMemo` or reselect selectors | WARN |
| S4 | Subscribing to entire Redux/Zustand store | Same as S2 — the entire component tree connected to a monolithic selector re-renders on any action | Use `useSelector` with narrow selectors; split reducers by domain | WARN |
| S5 | `setState` in `useEffect` without a staleness guard | Effect runs, triggers state update, triggers re-render, effect runs again — potential infinite loop or redundant re-renders | Guard with a condition (`if (newValue !== currentRef.current)`) or include a proper dependency array | ERROR |
| S6 | Storing large objects or arrays in React state | React's reconciler diffs state by reference; large objects increase diff cost and GC pressure | Keep state normalized and flat; store IDs, not full objects | WARN |

---

## Network Anti-Patterns

| # | Anti-Pattern | Why Bad | Fix | Severity |
|---|---|---|---|---|
| W1 | Sequential `await` chains for independent requests | `await requestA(); await requestB()` takes `time(A) + time(B)` — the second request waits even though there is no dependency | `const [a, b] = await Promise.all([requestA(), requestB()])` | ERROR |
| W2 | Polling with `setInterval` | Fires at fixed intervals regardless of app state (backgrounded, screen off, no network) — wastes battery and floods the server | Use WebSockets or SSE for real-time data; for polling, use exponential backoff and pause when app is backgrounded via `AppState` listener | WARN |
| W3 | No caching layer (fetching on every mount) | Every navigation to a screen triggers a full network round-trip — user sees a spinner for data that has not changed | Use React Query or SWR with `staleTime` and `gcTime` configured; use `initialData` from navigation params for instant display | ERROR |
| W4 | Over-fetching (requesting entire objects) | Fetching 50 fields when only 3 are displayed wastes bandwidth, parse time, and memory — especially costly on mobile connections | Use GraphQL field selection or REST projection endpoints; cache normalized by entity ID | WARN |
| W5 | Hardcoded base URLs per environment | Production URL checked into source or baked into builds without environment distinction — wrong endpoint shipped to prod or staging | Use environment variables (`APP_API_URL`) resolved at build time via Expo config or `.env` + `react-native-config` | WARN |

---

## Animation Anti-Patterns

| # | Anti-Pattern | Why Bad | Fix | Severity |
|---|---|---|---|---|
| A1 | Animated without `useNativeDriver: true` | Animation values are updated on the JS thread each frame and posted across the bridge — any JS jank drops animation frames | Always set `useNativeDriver: true`; only `transform` and `opacity` support it — redesign if you need to animate layout properties | ERROR |
| A2 | Using Animated API for layout property changes | Layout property animation (`width`, `height`, `top`) requires the layout engine to recompute the full subtree every frame on the main thread — cannot use native driver | Replace with `transform: [{ scaleX }]` / `transform: [{ translateY }]` to achieve the same visual result GPU-side | ERROR |
| A3 | Always-mounted Lottie animations | `lottie-react-native` holds animation JSON and rendering state in memory even when the animation is not visible; multiplies per tab in tab-based apps | Unmount Lottie when its parent screen is not focused; use `useFocusEffect` to mount/unmount; use `.lottie` binary format to reduce file size | WARN |
| A4 | Heavy iOS shadow on animated or list views | `shadowColor` / `shadowOffset` / `shadowRadius` force an offscreen render pass — 50 cards = 50 offscreen passes per frame | On iOS, use pre-rendered shadow images or a border approach; on Android use `elevation` (GPU-accelerated) | WARN |
| A5 | JS-driven gesture handlers (`PanResponder` for 60 fps tracking) | `PanResponder` runs on the JS thread — any JS work during a fast gesture causes lag or dropped touch events | Use `react-native-gesture-handler` (worklets run on the UI thread) + `react-native-reanimated` for gesture-driven animations | ERROR |

---

## Summary by Severity

### ERROR — Fix Before Shipping

- R1: Inline arrow in JSX bypassing memo
- R3: `key={index}` in dynamic lists
- R4: `FlatList` inside `ScrollView`
- R8: Chained `.map/.find` O(n²) in render
- M1: Missing `useEffect` cleanup
- M2: Timers not cleared on unmount
- M5: Unbounded image cache
- N1: JS stack instead of native-stack
- N5: Missing `enableScreens()`
- S1: Monolithic Context
- S5: `setState` in `useEffect` without guard
- W1: Sequential awaits for independent requests
- W3: No caching layer
- A1: Animated without `useNativeDriver`
- A2: Animated layout properties
- A5: JS-driven gesture handlers

### WARN — Fix Before Scaling

- R2: Inline style objects
- R5: Components over 300 lines
- R6: Missing `React.memo` on list items
- R7: Full lodash barrel import
- R9: Dynamic style computed in render body
- R10: `console.log` in production
- M3: No `AbortController` on fetch
- M4: Closures retaining large objects
- M6: Storing entire API response in state
- M7: No pagination on large data sets
- M8: Global `Map` growing unboundedly
- N2: Missing `lazy: true` on tab screens
- N3: More than 3 navigator nesting levels
- N4: `useEffect` instead of `useFocusEffect`
- N6: Heavy work in screen body during transition
- S2: Missing Zustand selectors
- S3: Storing derived data in state
- S4: Entire store subscription
- S6: Large objects in React state
- W2: Polling with `setInterval`
- W4: Over-fetching API responses
- W5: Hardcoded base URLs
- A3: Always-mounted Lottie
- A4: Heavy iOS shadows on animated views
