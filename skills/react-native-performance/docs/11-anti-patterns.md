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
| R11 | Component definition inside render function | Every render creates a new component class/function reference — React treats it as a completely different component type, unmounts the old tree, and mounts a fresh one; wipes all child state | Hoist component definitions to module scope, never inside another component's render body | ERROR |
| R12 | Inline `require()` inside render (`require('./heavy')`) | Module is synchronously evaluated on the JS thread at render time, blocking the UI; also prevents Metro from doing static bundle splitting | Move `require` / `import` to module scope; use dynamic `import()` with `React.lazy` for code-splitting | WARN |
| R13 | `StyleSheet.create` called inside render | `StyleSheet.create` registers the style with the native registry; calling it on every render floods the registry with duplicate entries and generates a new object reference each time | Call `StyleSheet.create` once at module scope; keep only truly dynamic values in `useMemo` | WARN |
| R14 | Prop drilling through 5+ levels of intermediary components | Any state change at the root propagates through every intermediary — all intermediate components re-render even though they only pass data through, not use it | Lift state into a context, Zustand slice, or Jotai atom scoped to the subtree that actually needs it | WARN |
| R15 | `useEffect` to derive and `setState` for derived values | Sets state → triggers extra render → effect runs again — at minimum one gratuitous re-render per source change; risk of stale values between renders | Replace with `useMemo`: `const derived = useMemo(() => compute(source), [source])` — no extra render, always in sync | WARN |
| R16 | Spreading all props onto a child (`<Child {...props} />`) | Passes every prop including ones the child ignores; any new or changed parent prop creates a new prop bag reference — memo bail-outs fire even if the child's actual props did not change | Destructure and forward only the props the child component consumes | WARN |
| R17 | Rendering SVGs without memoization in lists | Complex SVG components recalculate path data and re-render on every parent update; in a list this multiplies across all visible items | Wrap SVG components in `React.memo`; for static icons, pre-render to PNG/WebP and use `Image` instead | WARN |
| R18 | Deep barrel re-export chains (`index.ts` re-exporting `index.ts`) | Metro and Hermes cannot tree-shake through barrel files — the entire chain is included even when only one export is used; increases bundle size and parse time | Import directly from the source file; use barrel files only at public API boundaries and keep them shallow (one level) | INFO |
| R19 | Circular module dependencies | Module A imports B which imports A — the JS engine initializes one module with partially undefined exports; results in runtime `undefined` errors that are hard to trace and forces double evaluation | Audit with `madge --circular`; break cycles by extracting shared types or utilities into a third module neither imports from the other | WARN |
| R20 | Missing `shouldComponentUpdate` in class components | Class components re-render on every parent render by default — equivalent to never using `React.memo` on functional components | Extend `PureComponent` (shallow comparison) or implement `shouldComponentUpdate` with a custom comparison; prefer converting to functional component with `React.memo` | WARN |

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
| M9 | Decoded image bitmaps held in state without LRU eviction | Each decoded bitmap occupies `width × height × 4 bytes` of JS heap; accumulating them for every feed item exhausts memory within minutes of scrolling | Never store decoded bitmaps in React state or a plain cache; delegate to `expo-image` or `react-native-fast-image` which manage their own bounded native caches | ERROR |
| M10 | Circular references between JS objects | Object A holds a reference to B and B holds a reference back to A — the reference-counting GC used by Hermes cannot collect either object even after both are logically unreachable | Audit data models for back-references; use weak references (`WeakMap`, `WeakRef`) where a back-link is needed; break cycles before storing in global state | WARN |
| M11 | Module-level `Map` used as a cross-screen singleton cache | The cache is allocated at app boot and shared across every screen; it is never reset between navigations, so stale or personally-identifying data from screen A leaks into screen B | Scope caches to the component or feature that owns the data; reset on logout/session change; enforce a max-size with `lru-cache` | WARN |
| M12 | Event listener closure capturing the entire store or Context value | The listener callback closes over the whole context object or Zustand state snapshot at the moment of registration — even after the context is updated, the old snapshot is pinned in memory | Pass only a primitive key into the listener; resolve current state inside the handler via a ref or store's `getState()` | WARN |
| M13 | Not unsubscribing from Reanimated `AnimatedValue` listeners | `animatedValue.addListener(cb)` registers a native-side listener that holds a JS callback reference; without `removeListener` on unmount the callback and its closure are retained indefinitely | Store the listener ID returned by `addListener`; call `animatedValue.removeListener(id)` in `useEffect` cleanup | ERROR |
| M14 | Storing raw API response JSON without normalization | Duplicate entities appear in multiple response payloads (e.g., the same `User` object embedded in 30 posts); each copy occupies separate heap space and must be independently updated on mutation | Normalize responses with a schema (e.g., `normalizr`) or React Query's `select` transformer; store entities once keyed by ID | WARN |
| M15 | Keeping entire navigation history stack objects in memory | React Navigation's state tree stores serialized route params for every screen in the stack; deep link or programmatic navigation can push large param objects that are never popped | Keep route params minimal (IDs only, not full objects); call `navigation.reset()` on logout to clear the stack; use `navigation.replace()` instead of `push` for one-way flows | WARN |

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
| W6 | Retry without exponential backoff | A failed request retried immediately and repeatedly at full rate hammers the server during an outage — amplifies the problem and can constitute a self-inflicted DDoS | Implement exponential backoff with jitter: `delay = Math.min(base * 2^attempt + rand, maxDelay)`; honour `Retry-After` headers | ERROR |
| W7 | Duplicate in-flight requests not deduplicated | Two components mounting simultaneously both fire the same endpoint; the server handles double the load and the second response may overwrite the first with stale data | Use React Query (deduplicates by query key) or a request dedup layer; resolve all callers from a single in-flight promise | WARN |
| W8 | GraphQL without query batching | Each component fires its own GraphQL operation; on a screen with 10 components that is 10 round-trips instead of 1 | Enable Apollo's `BatchHttpLink` or relay's batch fetch; co-locate queries on the screen level and fetch once | WARN |
| W9 | Missing ETag / If-None-Match cache validation | Every request transfers the full payload even when the server-side resource has not changed — wastes bandwidth and battery | Send `If-None-Match: <etag>` on repeat fetches; handle `304 Not Modified` by serving from local cache without parsing a new body | INFO |
| W10 | Large uncompressed request payloads | Sending multi-KB JSON bodies without compression increases upload time and drains battery, especially on slow cellular connections | Enable gzip/brotli compression on the server and set `Accept-Encoding: gzip` on the client; minify JSON before sending; batch small writes | WARN |
| W11 | Ignoring network state transitions (WiFi to cellular) | Requests in-flight when the interface switches drop silently; the app shows stale UI or hangs indefinitely without detecting the change | Listen to `NetInfo.addEventListener`; cancel and retry requests on interface change; show a connectivity banner and pause background sync | WARN |
| W12 | No `AbortController` on long-lived or background fetches | A fetch started on one screen continues consuming bandwidth and processing after the user navigates away or the app backgrounds — no way to cancel without an abort signal | Create an `AbortController` per request context; pass `.signal` to `fetch`; abort in `useEffect` cleanup and on `AppState` background transition | WARN |

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

## Image Anti-Patterns

| # | Anti-Pattern | Why Bad | Fix | Severity |
|---|---|---|---|---|
| IMG1 | PNG format for photographic images | PNG is lossless — photos encoded as PNG are 5–20x larger than equivalent JPEG/WebP; larger files mean slower loads, more bandwidth, and higher memory usage | Use JPEG (or WebP) for photos; reserve PNG only for graphics that require hard edges or transparency | WARN |
| IMG2 | Not using WebP/AVIF with a legacy fallback | Skipping modern formats wastes 25–50% bandwidth that WebP saves over JPEG/PNG; AVIF saves a further 20% over WebP on supported devices | Serve WebP by default via `<Image source={{ uri: webpUrl }}`; configure the CDN to negotiate AVIF for capable clients; keep a JPEG fallback for older Android | WARN |
| IMG3 | Shipping unoptimized SVGs with bloated path data | SVGs exported from design tools contain editor metadata, redundant transforms, and high-precision decimals that add KB of overhead and slow the SVG parser | Run SVGs through `svgo` with a strict preset before committing; aim for under 2 KB per icon; convert complex illustrations to raster | INFO |
| IMG4 | Transparent PNG when an opaque image suffices | The alpha channel doubles memory consumption in some renderers (RGBA vs RGB) and prevents certain GPU optimizations like texture compression | Use opaque JPEG or WebP when the image background is always a known solid color; add `shouldRasterizeIOS` / `renderToHardwareTextureAndroid` only when truly needed | WARN |
| IMG5 | Serving high-resolution images scaled down by the layout | A 2000×2000 image displayed in a 100×100 `Image` component still decodes the full bitmap into memory — 16x more pixels than needed | Use a CDN image transform (`?w=200&dpr=2`) to serve the exact dimensions needed; compute `width * PixelRatio.get()` for the request size | ERROR |
| IMG6 | Prefetching images without a priority queue | Prefetching every visible or likely-next image concurrently saturates the network connection during a critical path (e.g., initial feed load) and may evict more important assets from the cache | Use a priority queue: prefetch above-the-fold images first at high priority; schedule below-the-fold and speculative prefetches as idle tasks via `InteractionManager.runAfterInteractions` | WARN |

---

## Data Structure Anti-Patterns

| # | Anti-Pattern | Why Bad | Fix | Severity |
|---|---|---|---|---|
| DS1 | `Array.find()` / `Array.includes()` in hot render paths or loops | O(n) linear scan on every call; inside a render or a loop over m items this becomes O(n×m) — e.g., resolving 100 items against a 100-element allow-list performs 10 000 comparisons | Pre-build a `Set` or `Map` keyed by the lookup value once (O(n)); subsequent lookups are O(1) | WARN |
| DS2 | Plain object used as a `Set` (`obj[key] = true`) | Prototype-chain keys (`constructor`, `toString`, etc.) pollute the key space and cause false membership results; no built-in size tracking; `for...in` requires `hasOwnProperty` guards | Use `new Set()`; it has O(1) `has()`, proper iteration, and no prototype collision | INFO |
| DS3 | Deeply nested response objects stored verbatim in state | Selectors must traverse nested paths (`state.data.users[0].profile.avatar`); any mutation requires deep clone to maintain immutability — expensive and error-prone | Normalize to a flat entity map (`{ byId: { [id]: entity }, allIds: [] }`); use RTK's `createEntityAdapter` or a custom normalizer | WARN |
| DS4 | String concatenation inside loops (`str += chunk`) | In V8/Hermes, repeated `+=` on strings can trigger O(n²) copies depending on the engine's rope optimization heuristics; long loops produce significant GC pressure | Accumulate parts in an array and call `.join('')` once outside the loop | INFO |
| DS5 | Inline `.filter()`, `.map()`, or `.reduce()` in JSX without `useMemo` | A new array is allocated on every render, even when the source data has not changed; the new reference invalidates `React.memo` on any child that receives it as a prop | Wrap in `useMemo` with the source array as a dependency: `const filtered = useMemo(() => items.filter(pred), [items])` | WARN |

---

## Summary by Severity

### ERROR — Fix Before Shipping

- R1: Inline arrow in JSX bypassing memo
- R3: `key={index}` in dynamic lists
- R4: `FlatList` inside `ScrollView`
- R8: Chained `.map/.find` O(n²) in render
- R11: Component definition inside render function
- M1: Missing `useEffect` cleanup
- M2: Timers not cleared on unmount
- M5: Unbounded image cache
- M9: Decoded image bitmaps in state without LRU eviction
- M13: Not unsubscribing from Reanimated animated value listeners
- N1: JS stack instead of native-stack
- N5: Missing `enableScreens()`
- S1: Monolithic Context
- S5: `setState` in `useEffect` without guard
- W1: Sequential awaits for independent requests
- W3: No caching layer
- W6: Retry without exponential backoff
- IMG5: High-res images scaled down in layout
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
- R12: Inline `require()` inside render
- R13: `StyleSheet.create` inside render
- R14: Prop drilling through deep trees
- R15: `useEffect` for derived state
- R16: Spreading all props onto child
- R17: SVGs without memoization in lists
- R19: Circular module dependencies
- R20: Missing `shouldComponentUpdate` in class components
- M3: No `AbortController` on fetch
- M4: Closures retaining large objects
- M6: Storing entire API response in state
- M7: No pagination on large data sets
- M8: Global `Map` growing unboundedly
- M10: Circular references between JS objects
- M11: Module-level singleton cache across screens
- M12: Event listener closure capturing entire store
- M14: Raw API response stored without normalization
- M15: Entire navigation history objects in memory
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
- W7: Duplicate in-flight requests not deduplicated
- W8: GraphQL without query batching
- W10: Large uncompressed request payloads
- W11: Ignoring network state transitions
- W12: No `AbortController` on long-lived fetches
- IMG1: PNG format for photographic images
- IMG2: Not using WebP/AVIF
- IMG4: Transparent PNG when opaque suffices
- IMG6: Image prefetching without priority queue
- DS1: `Array.find()` in hot loops
- DS3: Deeply nested objects instead of normalized entity map
- DS5: Inline `.filter/.map` in JSX without `useMemo`
- A3: Always-mounted Lottie
- A4: Heavy iOS shadows on animated views

### INFO — Best-Practice Violations

- R18: Deep barrel re-export chains blocking tree shaking
- W9: Missing ETag / If-None-Match cache validation
- IMG3: Unoptimized SVG path data
- DS2: Plain object used as `Set`
- DS4: String concatenation in loops
