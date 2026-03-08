# Algorithmic Performance in React Native — Deep-Dive Reference

React Native apps execute JavaScript on the Hermes engine, synchronise with a native UI thread, and often display large, interactive datasets. Poor algorithmic choices compound: an O(n²) operation that runs inside a render function, inside a FlatList item, on a list of 500 rows fires 250,000 iterations on every keystroke. This document catalogues the most impactful algorithmic decisions you can make across data structures, rendering, sorting, string handling, concurrency, and caching.

---

## 1. Data Structure Choices

Choosing the right data structure is the highest-leverage algorithmic decision. The right choice eliminates entire classes of inefficiency before a single profile is taken.

| Structure | Use Case | Time Complexity | RN Example |
|---|---|---|---|
| `Map` vs plain object | Key-value lookups with dynamic keys | `Map.get` O(1) guaranteed; object property access O(1) average but with prototype chain overhead | Normalised state keyed by entity ID |
| `Set` vs `Array` | Membership testing | `Set.has` O(1) vs `Array.includes` O(n) | Selected item IDs, deduplication of seen event IDs |
| `TypedArray` (`Float32Array`, `Uint8Array`) | Homogeneous numeric data | Direct memory buffer, no boxing/unboxing | Audio sample buffers, raw colour channel data, geometry vertices |
| `WeakMap` | Object-keyed cache | O(1) get/set; keys are not prevented from GC | Memoised computations tied to component instance objects |
| `WeakRef` | Weak reference to a large object | O(1) deref, returns `undefined` after GC | Cache entries for decoded images without blocking GC |

### 1.1 Set for Membership Tests

```tsx
// BAD: O(n) membership test runs on every render for every list item
// With 200 items and 200 rendered rows: 40,000 iterations per render
const isSelected = selectedItems.includes(item.id);

// GOOD: O(1) membership test; Set is rebuilt only when selectedIds changes
const selectedSet = useMemo(
  () => new Set(selectedIds),
  [selectedIds]
);
const isSelected = selectedSet.has(item.id);
```

The `useMemo` call is O(n) once when `selectedIds` changes. Every subsequent read is O(1). Total cost for 200 renders with 200 IDs: O(200) build + O(200) lookups = O(400), versus O(40,000) for the naive version.

### 1.2 Map for ID-Keyed Lookups

```tsx
// BAD: O(n) scan on every access
const user = users.find(u => u.id === targetId);

// GOOD: O(1) lookup; index built once when users array changes
const userMap = useMemo(
  () => new Map(users.map(u => [u.id, u])),
  [users]
);
const user = userMap.get(targetId);
```

`new Map(users.map(...))` is O(n) and runs once. `userMap.get` is O(1) every time. When `targetId` changes frequently (e.g. a highlighted row in a list), this matters.

### 1.3 TypedArray for Numeric Buffers

Regular JavaScript arrays store elements as boxed heap objects. `Float32Array` stores 32-bit floats in a contiguous memory buffer with no boxing overhead. For audio processing, signal analysis, or bulk colour operations:

```tsx
// BAD: JS Array — each element is a heap-allocated Number object
const samples: number[] = new Array(44100).fill(0);

// GOOD: Float32Array — contiguous memory, C-compatible, no boxing
const samples = new Float32Array(44100);

// Bulk operations on TypedArray are implemented in native code
// and avoid the JS object allocation overhead entirely
samples.fill(0);
samples.set(incomingBuffer, offset);
```

TypedArrays also transfer directly to native modules via JSI ArrayBuffer bindings without serialisation, making them the correct choice for any data that crosses the JS/native boundary at volume.

### 1.4 WeakMap for Object-Keyed Memoisation

```tsx
const cache = new WeakMap<object, ComputedValue>();

function expensiveCompute(config: Config): ComputedValue {
  if (cache.has(config)) return cache.get(config)!;
  const result = heavyTransform(config);
  cache.set(config, result);
  return result;
}
```

Because `WeakMap` keys are weak references, `config` objects that go out of scope in the caller are garbage-collected automatically — the cache cannot grow unboundedly the way a `Map`-backed cache can.

---

## 2. List and Search Optimisation

### 2.1 Binary Search for Sorted Data

When data is sorted (timestamps, prices, alphabetical), binary search reduces O(n) linear scans to O(log n).

```tsx
// Finds insertion index in a sorted array — O(log n)
function binarySearchIndex(arr: number[], target: number): number {
  let lo = 0;
  let hi = arr.length - 1;

  while (lo <= hi) {
    const mid = (lo + hi) >>> 1; // unsigned right shift avoids negative overflow
    if (arr[mid] === target) return mid;
    if (arr[mid] < target) lo = mid + 1;
    else hi = mid - 1;
  }
  return lo; // insertion point
}

// Usage: find where to insert a new timestamp
const timestamps: number[] = getSortedTimestamps();
const insertAt = binarySearchIndex(timestamps, newTimestamp); // O(log n) vs O(n)
```

For 10,000 sorted items, binary search takes at most 14 comparisons. Linear search averages 5,000.

### 2.2 Debounce and Throttle for Input Handlers

```tsx
import { useMemo } from 'react';
import debounce from 'lodash/debounce';
import throttle from 'lodash/throttle';

// DEBOUNCE — fires once after the user stops typing for 300ms
// Use for: search inputs, form validation, API calls
const debouncedSearch = useMemo(
  () => debounce((query: string) => triggerSearch(query), 300),
  []
);

// THROTTLE — fires at most once per 16ms (~60fps frame budget)
// Use for: scroll position tracking, drag handlers, sensor data
const throttledScroll = useMemo(
  () => throttle((offset: number) => updateScrollIndicator(offset), 16),
  []
);
```

A keypress firing a 300ms-debounced search instead of an immediate one reduces API calls by 10-20x for a typical typist. A throttled scroll handler at 16ms aligns with the frame budget so you never queue more work than the UI thread can consume.

### 2.3 Trie for Prefix/Autocomplete Search

For large local dictionaries (product names, usernames, tags), a trie gives O(m) prefix lookup where m is the query length, independent of dataset size n.

```tsx
class TrieNode {
  children = new Map<string, TrieNode>();
  isEnd = false;
  value?: string;
}

class Trie {
  root = new TrieNode();

  // O(m) where m = word length
  insert(word: string): void {
    let node = this.root;
    for (const ch of word.toLowerCase()) {
      if (!node.children.has(ch)) node.children.set(ch, new TrieNode());
      node = node.children.get(ch)!;
    }
    node.isEnd = true;
    node.value = word;
  }

  // O(m + k) where k = number of results — independent of n
  search(prefix: string, limit = 10): string[] {
    let node = this.root;
    for (const ch of prefix.toLowerCase()) {
      if (!node.children.has(ch)) return [];
      node = node.children.get(ch)!;
    }
    return this.collect(node, limit);
  }

  private collect(node: TrieNode, limit: number): string[] {
    const results: string[] = [];
    const stack: TrieNode[] = [node];
    while (stack.length && results.length < limit) {
      const curr = stack.pop()!;
      if (curr.isEnd && curr.value) results.push(curr.value);
      for (const child of curr.children.values()) stack.push(child);
    }
    return results;
  }
}

// Build once (O(n*m)), query many times (O(m))
const trie = useMemo(() => {
  const t = new Trie();
  for (const item of catalogue) t.insert(item.name);
  return t;
}, [catalogue]);
```

For datasets over ~5,000 strings, move Trie construction to a native module or Web Worker equivalent; JS Trie construction at 50,000 entries takes ~100ms, which blocks the JS thread.

### 2.4 Fuzzy Search: Levenshtein Distance

Levenshtein edit distance enables typo-tolerant search. The classic dynamic programming implementation is O(m*n) where m and n are the string lengths.

```tsx
function levenshtein(a: string, b: string): number {
  // Only allocate two rows — O(min(m,n)) space instead of O(m*n)
  const [shorter, longer] = a.length <= b.length ? [a, b] : [b, a];
  let prev = Array.from({ length: shorter.length + 1 }, (_, i) => i);

  for (let j = 1; j <= longer.length; j++) {
    const curr = [j];
    for (let i = 1; i <= shorter.length; i++) {
      const cost = shorter[i - 1] === longer[j - 1] ? 0 : 1;
      curr[i] = Math.min(curr[i - 1] + 1, prev[i] + 1, prev[i - 1] + cost);
    }
    prev = curr;
  }
  return prev[shorter.length];
}
```

For real-time fuzzy search over large corpuses, move the computation to:
1. A native module (via JSI TurboModule) for O(1) invocation overhead.
2. `react-native-workers` / `expo-workers` to run on a background thread.
3. A pre-built solution like `fuse.js` (JS, fast enough for <10,000 items) or `minisearch` (optimised index, suitable for 100,000+ items on-device).

### 2.5 Virtual List Recycling

FlashList (Shopify) uses a recycling pool rather than mounting and unmounting components. Understanding this changes what you put in list items.

- FlashList pre-allocates a pool of `RecyclerListView` cells. When a cell scrolls off-screen it is not unmounted; its props are updated with new data.
- This makes item renders O(1) memory allocation after the pool fills (~viewport height / item height items).
- Side effect: component state inside list items persists across recycled renders. Use `useEffect` with the item's ID as a dependency, not mount/unmount lifecycle, to reset local state.

```tsx
// BAD: relies on mount/unmount to reset state
function ListItem({ item }: { item: Product }) {
  const [expanded, setExpanded] = useState(false); // stale after recycling
  // ...
}

// GOOD: reset when the item identity changes
function ListItem({ item }: { item: Product }) {
  const [expanded, setExpanded] = useState(false);
  useEffect(() => {
    setExpanded(false); // reset when this cell is reused for a different item
  }, [item.id]);
  // ...
}
```

### 2.6 Cursor vs Offset Pagination

| Strategy | Server Cost | Client Cost | Stable? |
|---|---|---|---|
| Offset (`LIMIT 20 OFFSET 400`) | O(n) — DB scans and discards n rows | O(1) append | No — inserts shift items |
| Cursor (`WHERE id > lastId LIMIT 20`) | O(1) — indexed seek | O(1) append | Yes — insert-stable |

Always use cursor pagination for infinite-scroll lists. Offset pagination causes the server to discard O(offset) rows per request and produces duplicate/missing items when new data is inserted between pages.

### 2.7 Bloom Filters

A Bloom filter answers "definitely not in set" in O(k) time (k = number of hash functions, typically 3–7) using O(m) bits of memory. False positives are possible; false negatives are not.

```tsx
// Useful for: "has user seen this notification ID?"
// without storing all 100,000 IDs in memory

class BloomFilter {
  private bits: Uint8Array;
  private k: number;

  constructor(size: number, k = 4) {
    this.bits = new Uint8Array(Math.ceil(size / 8));
    this.k = k;
  }

  private hashes(item: string): number[] {
    // Simplified: real implementation uses MurmurHash3 or xxHash
    const results: number[] = [];
    for (let i = 0; i < this.k; i++) {
      let h = i * 2654435761;
      for (let j = 0; j < item.length; j++) h = Math.imul(h ^ item.charCodeAt(j), 2246822519);
      results.push(Math.abs(h) % (this.bits.length * 8));
    }
    return results;
  }

  add(item: string): void {
    for (const h of this.hashes(item)) this.bits[h >>> 3] |= 1 << (h & 7);
  }

  mightContain(item: string): boolean {
    return this.hashes(item).every(h => (this.bits[h >>> 3] & (1 << (h & 7))) !== 0);
  }
}
```

---

## 3. Rendering Algorithm Optimisations

### 3.1 React Reconciliation and Key Strategy

React's reconciler (in RN: Fabric renderer) diffs virtual DOM trees using a heuristic O(n) algorithm that relies on element `type` and `key`. Wrong key choices break the heuristic.

```tsx
// BAD: index as key — insert at position 0 forces all n items to re-render
// React sees key "0" now maps to a different item → full DOM diff
<FlatList
  data={items}
  keyExtractor={(_, index) => String(index)}
/>

// GOOD: stable unique ID — only the new item re-renders
// React matches key "abc-123" to its previous fiber → no diff needed
<FlatList
  data={items}
  keyExtractor={item => item.id}
/>
```

With index keys, inserting one item at the top of a list of n items triggers n re-renders. With stable ID keys: 1 mount + 0 updates.

### 3.2 React.memo with Custom Comparison

```tsx
// Shallow comparison (default React.memo) fails for objects created inline
const ProductCard = React.memo(
  function ProductCard({ product, onPress }: Props) {
    return (/* ... */);
  },
  (prev, next) =>
    prev.product.id === next.product.id &&
    prev.product.updatedAt === next.product.updatedAt &&
    prev.onPress === next.onPress
);
```

The custom comparison costs O(k) where k is the number of compared fields. Default shallow comparison is also O(k) but compares every prop key, including nested object references. A hand-written comparison that only checks semantically meaningful fields is both faster and more correct.

### 3.3 Selector Memoisation

Zustand and Redux selectors recompute whenever their input slice changes. Without memoisation, a global state update re-runs every selector on every subscribed component.

```tsx
import { create } from 'zustand';

// BAD: new array reference on every store update triggers re-render
const activeProducts = useProductStore(state =>
  state.products.filter(p => p.active)
);

// GOOD: stable reference when products haven't changed
import { useShallow } from 'zustand/react/shallow';

const activeProductIds = useProductStore(
  useShallow(state => state.products.filter(p => p.active).map(p => p.id))
);
```

For complex derived state, use `createSelector` from `reselect`:

```tsx
import { createSelector } from 'reselect';

// Memoised selector — recomputes only when products or selectedCategory changes
const selectFilteredProducts = createSelector(
  (state: RootState) => state.products.list,
  (state: RootState) => state.filters.category,
  (products, category) => products.filter(p => p.category === category)
);
```

`createSelector` uses referential equality checks on inputs. The O(n) filter runs only when inputs change, not on every render.

### 3.4 React 18 Concurrent Features

```tsx
// useDeferredValue — marks a value as non-urgent
// React renders the previous value first (fast), then defers the new value
function SearchResults({ query }: { query: string }) {
  const deferredQuery = useDeferredValue(query);
  // deferredQuery updates after urgent renders complete — no janky typing
  const results = useFilteredResults(deferredQuery);
  return <ResultList items={results} />;
}

// useTransition — marks a state update as non-urgent
function FilterPanel() {
  const [isPending, startTransition] = useTransition();

  const applyFilter = (category: string) => {
    startTransition(() => {
      // This update can be interrupted by urgent updates (e.g. touch input)
      setSelectedCategory(category);
    });
  };

  return (
    <View style={{ opacity: isPending ? 0.6 : 1 }}>
      {/* filter UI */}
    </View>
  );
}
```

`useTransition` does not reduce total rendering work — it re-prioritises it. The list re-render still happens; it just cannot block a touch event response.

### 3.5 Batch State Updates

React 18 automatically batches all state updates inside event handlers, timeouts, Promises, and native callbacks. In React 17 and below, only synthetic event handlers were batched.

```tsx
// React 18: these three updates are batched into a single re-render
async function handleSave() {
  const result = await saveToServer(data);
  setIsSaving(false);      // \
  setLastSaved(new Date()); //  all three batched → one re-render
  setDirty(false);          // /
}

// If you need to opt out of batching (rare):
import { flushSync } from 'react-dom';
flushSync(() => setProgress(50)); // forces immediate synchronous render
setProgress(100);                 // second render
```

---

## 4. Sorting and Filtering

### 4.1 Hermes TimSort

Hermes implements `Array.prototype.sort` as TimSort: O(n log n) worst case, O(n) best case on nearly-sorted data. It is stable (equal elements preserve original order) since ES2019.

Key implications:
- Sorting already-sorted data (e.g. appending to a sorted list and re-sorting) is O(n), not O(n log n).
- Stable sort means secondary sort criteria can be applied sequentially.

### 4.2 Filter Before Sort

Always filter to reduce the dataset before sorting:

```tsx
// BAD: sorts all 10,000 products, then filters to ~50
const result = products
  .sort((a, b) => a.price - b.price)
  .filter(p => p.category === selected);

// GOOD: filters to ~50 first, then sorts only those
const result = products
  .filter(p => p.category === selected)
  .sort((a, b) => a.price - b.price);
```

If filtering reduces n=10,000 to k=50, the bad approach sorts 10,000 elements (log 10,000 ≈ 13 comparisons each = 130,000 ops). The good approach sorts 50 elements (log 50 ≈ 6 = 300 ops) — a 430x improvement.

### 4.3 Memoised Filter and Sort

```tsx
const filteredProducts = useMemo(
  () =>
    products
      .filter(p => p.category === selectedCategory)
      .sort((a, b) => a.price - b.price),
  [products, selectedCategory]
  // Only re-runs when products list or category changes
  // Not on every render of the parent component
);
```

Without `useMemo`, this runs on every render of the containing component. With it, the O(n log n) work runs only when dependencies change.

### 4.4 Multi-Criteria Sort

```tsx
// Naive: chained sort calls — O(n log n) per criterion = O(k * n log n)
const sorted = products
  .sort((a, b) => a.name.localeCompare(b.name))
  .sort((a, b) => a.category.localeCompare(b.category))
  .sort((a, b) => a.price - b.price);

// GOOD: single sort with priority — O(n log n) once
const sorted = [...products].sort((a, b) => {
  if (a.price !== b.price) return a.price - b.price;           // primary
  const catCmp = a.category.localeCompare(b.category);
  if (catCmp !== 0) return catCmp;                              // secondary
  return a.name.localeCompare(b.name);                         // tertiary
});
```

The multi-sort approach also produces correct results: chained `.sort()` calls only work because TimSort is stable; a single comparator is both faster and intent-revealing.

### 4.5 Offload Large Sorts to the Server

For datasets > 1,000 items that the user cannot meaningfully paginate through, sort and filter server-side and return only the visible page. The server has indexed columns (O(1) or O(log n) sort cost via B-tree), whereas client-side sort is always O(n log n) against the full payload.

---

## 5. String and Text Processing

### 5.1 Pre-Compile Regex

RegExp object creation involves parsing the pattern into a finite automaton. Doing this inside a render function or a loop pays this O(m) cost (m = pattern length) on every call.

```tsx
// BAD: pattern compiled on every render — 10–100x slower in tight loops
function highlight(text: string, query: string): string {
  return text.replace(new RegExp(query, 'gi'), '<mark>$&</mark>');
}

// GOOD: compile once per query change
const highlightRegex = useMemo(
  () => new RegExp(escapeRegExp(query), 'gi'),
  [query]
);

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
```

For static patterns (not user input), define the `RegExp` at module scope: `const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;`. This pays the compile cost once at module load time.

### 5.2 JSON.parse / JSON.stringify in Hermes

Hermes implements `JSON.parse` and `JSON.stringify` in optimised native C++ code. They are significantly faster than equivalent JS traversal. However, they are still O(n) in the size of the data and block the JS thread.

Guidelines:
- Do not `JSON.parse` large payloads (>100KB) on the main JS thread — move parsing to a native module that returns a parsed object via JSI.
- `JSON.stringify(JSON.parse(x))` for deep clone is O(n) twice plus GC pressure from intermediate allocation. Prefer structural sharing (Immer) or manual spread for partial updates.

```tsx
// BAD: deep clone with JSON round-trip — O(n) parse + O(n) stringify + allocation
const cloned = JSON.parse(JSON.stringify(original));

// GOOD: Immer structural sharing — O(changed nodes) only
import produce from 'immer';
const updated = produce(original, draft => {
  draft.user.name = newName; // only the changed path is copied
});
```

### 5.3 Text Measurement Caching

`TextInput` height measurement and `Text` layout calculation are expensive native operations. `react-native-measure-string` and similar libraries cache results by content hash.

For dynamic text sizes (chat bubbles, adaptive cards), cache the last N measurements:

```tsx
const measureCache = new Map<string, { width: number; height: number }>();

function getCachedMeasure(text: string, style: TextStyle) {
  const key = `${text}|${JSON.stringify(style)}`;
  if (measureCache.has(key)) return measureCache.get(key)!;
  const measured = measureText(text, style); // native call
  if (measureCache.size > 500) {
    // evict oldest entry (Map preserves insertion order)
    measureCache.delete(measureCache.keys().next().value);
  }
  measureCache.set(key, measured);
  return measured;
}
```

---

## 6. Concurrency and Threading

### 6.1 Thread Model

React Native has three primary threads:

| Thread | Runs | Blocked by |
|---|---|---|
| JS thread | React renders, business logic, timers | CPU-intensive JS, synchronous native calls |
| UI thread (Main) | Native view layout, animations, touch | Heavy layout, synchronous JS calls (legacy Bridge) |
| Background threads | Network, image decode, file I/O | — (independent) |

With New Architecture (JSI + Fabric), the UI thread is decoupled from the JS thread. Animations driven by Reanimated worklets execute on the UI thread and never block on JS.

### 6.2 InteractionManager.runAfterInteractions

Defer expensive initialisation until after navigation transitions and animations complete:

```tsx
import { InteractionManager } from 'react-native';
import { useEffect, useState } from 'react';

function HeavyScreen() {
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const task = InteractionManager.runAfterInteractions(() => {
      // Runs after all in-flight animations complete
      // Safe to do expensive work here without janking transitions
      initHeavyData();
      setReady(true);
    });
    return () => task.cancel();
  }, []);

  if (!ready) return <LoadingPlaceholder />;
  return <HeavyContent />;
}
```

### 6.3 requestAnimationFrame

`requestAnimationFrame` schedules a callback before the next frame paint on the JS thread. Use it to spread work across frames:

```tsx
// Process 500 items without blocking — yield between frames
function processInChunks(items: Item[], chunkSize = 50) {
  let index = 0;

  function processChunk() {
    const end = Math.min(index + chunkSize, items.length);
    for (; index < end; index++) {
      expensiveProcess(items[index]);
    }
    if (index < items.length) {
      requestAnimationFrame(processChunk); // yield to frame, continue next frame
    }
  }

  requestAnimationFrame(processChunk);
}
```

Each chunk runs within one 16ms frame budget. This keeps the app interactive during bulk processing.

### 6.4 Reanimated Worklets

Worklets are JavaScript functions marked with `'worklet'` that Reanimated serialises and runs on the UI thread via its own JS runtime (separate from the main Hermes instance):

```tsx
import Animated, {
  useSharedValue,
  useAnimatedScrollHandler,
  useAnimatedStyle,
  interpolate,
} from 'react-native-reanimated';

function ParallaxHeader() {
  const scrollY = useSharedValue(0);

  const onScroll = useAnimatedScrollHandler({
    onScroll: event => {
      'worklet';
      scrollY.value = event.contentOffset.y; // runs on UI thread at 60/120fps
    },
  });

  const headerStyle = useAnimatedStyle(() => {
    'worklet';
    return {
      transform: [{ translateY: interpolate(scrollY.value, [0, 200], [0, -100]) }],
    };
  });

  return (
    <Animated.ScrollView onScroll={onScroll}>
      <Animated.View style={headerStyle} />
    </Animated.ScrollView>
  );
}
```

Worklets never schedule work on the JS thread during animation. There is no serialisation, no JS thread round-trip, and no frame drops from JS-side re-renders.

### 6.5 JSI Synchronous Calls

JSI host functions call directly into C++ without thread hops. The cost is the C++ function execution time plus a small JSI binding overhead (~0.04µs for a simple call). This makes JSI appropriate for high-frequency operations (per-frame, per-scroll-event) that were previously impossible over the Bridge.

However, synchronous JSI calls block the JS thread for their duration. An expensive synchronous native call (database query, image decode) will drop frames. Rule: synchronous JSI for fast operations (<100µs); async for anything longer.

### 6.6 Background Threads for CPU-Intensive Work

For tasks that take >5ms (image processing, CSV parsing, cryptography), move work off the JS thread:

- **`react-native-workers`**: Exposes Web Worker-compatible API. Runs a separate Hermes instance on a background thread. Communicate via `postMessage` (serialised, like the old Bridge).
- **Native TurboModule**: Write the algorithm in C++/Swift/Kotlin and expose it via JSI. Results return synchronously or via Promise. Best for very hot paths (>1000 calls/sec) or when existing native libraries exist.
- **Offload to server**: For one-time or infrequent heavy operations, send the data to an API and return results. Most maintainable option.

```tsx
// react-native-workers example
// worker.ts (runs on background thread)
self.onmessage = ({ data }) => {
  const result = heavyCsvParse(data.csv); // O(n), doesn't block JS thread
  self.postMessage(result);
};

// main thread
const worker = new Worker('./worker');
worker.postMessage({ csv: rawData });
worker.onmessage = ({ data }) => setRows(data);
```

### 6.7 Hermes Microtask Queue

Hermes processes microtasks (Promise `.then`, `async/await` continuations, `queueMicrotask`) in the same JS thread event loop, draining the microtask queue between each macrotask. Implications:

- A chain of 10,000 `Promise.then` callbacks blocks the JS thread for their combined duration before yielding to timers or native events.
- `await` at each step yields to the microtask queue, not to the macrotask/timer queue. To truly yield a frame, use `await new Promise(r => setTimeout(r, 0))` or `requestAnimationFrame`.

```tsx
// Truly yield to next frame between chunks
async function processWithFrameYield(items: Item[]) {
  for (let i = 0; i < items.length; i += 50) {
    const chunk = items.slice(i, i + 50);
    chunk.forEach(expensiveProcess);
    // await Promise.resolve() only yields microtask queue, NOT a frame
    await new Promise(r => requestAnimationFrame(r)); // actually yields a frame
  }
}
```

---

## 7. Caching Strategies

### 7.1 LRU Cache

A Least Recently Used cache evicts the least recently accessed entry when capacity is reached. Using `Map` (insertion-order preserved) gives O(1) get and set:

```tsx
class LRUCache<K, V> {
  private map = new Map<K, V>();

  constructor(private readonly maxSize: number) {}

  get(key: K): V | undefined {
    if (!this.map.has(key)) return undefined;
    // Move to end (most recently used)
    const value = this.map.get(key)!;
    this.map.delete(key);
    this.map.set(key, value);
    return value;
  }

  set(key: K, value: V): void {
    if (this.map.has(key)) this.map.delete(key);
    else if (this.map.size >= this.maxSize) {
      // Evict LRU: first entry in Map (oldest insertion)
      this.map.delete(this.map.keys().next().value);
    }
    this.map.set(key, value);
  }

  has(key: K): boolean {
    return this.map.has(key);
  }

  get size(): number {
    return this.map.size;
  }
}

// Usage: cache last 100 processed thumbnails
const thumbnailCache = new LRUCache<string, ImageData>(100);
```

`Map` preserves insertion order, so the first key returned by `.keys().next()` is always the least recently inserted (and after any `get` call moves entries, the least recently used). Both `get` and `set` are O(1) amortised.

### 7.2 TTL Cache

Time-based invalidation prevents stale data accumulation:

```tsx
interface TTLEntry<V> {
  value: V;
  expiresAt: number;
}

class TTLCache<K, V> {
  private store = new Map<K, TTLEntry<V>>();

  constructor(private readonly ttlMs: number) {}

  get(key: K): V | undefined {
    const entry = this.store.get(key);
    if (!entry) return undefined;
    if (Date.now() > entry.expiresAt) {
      this.store.delete(key);
      return undefined;
    }
    return entry.value;
  }

  set(key: K, value: V): void {
    this.store.set(key, { value, expiresAt: Date.now() + this.ttlMs });
  }
}

// Cache geocoding results for 10 minutes
const geocodeCache = new TTLCache<string, LatLng>(10 * 60 * 1000);
```

### 7.3 Stale-While-Revalidate

TanStack Query implements stale-while-revalidate natively: it returns cached (stale) data immediately, then fetches fresh data in the background. Configure with `staleTime` and `gcTime`:

```tsx
const { data: products } = useQuery({
  queryKey: ['products', categoryId],
  queryFn: () => fetchProducts(categoryId),
  staleTime: 5 * 60 * 1000,  // serve cached data for up to 5 minutes
  gcTime: 30 * 60 * 1000,    // keep in memory for 30 minutes after last use
});
```

- `staleTime: 5 min` means the user sees data instantly (O(1) cache read) and the network is only hit if data is older than 5 minutes.
- Setting `staleTime: Infinity` turns the query into a one-time fetch — useful for static reference data (countries, categories).

### 7.4 Image Cache

React Native's `Image` component has a built-in memory and disk cache managed by the native layer (SDWebImage on iOS, Glide on Android). For predictable cache control:

```tsx
// Prefetch images during idle time before they're needed
import { Image } from 'react-native';

async function prefetchNextPage(items: FeedItem[]) {
  await Promise.all(
    items.slice(0, 10).map(item => Image.prefetch(item.thumbnailUrl))
  );
}

// For advanced cache policies, use expo-image (disk+memory LRU, BlurHash placeholders)
import { Image } from 'expo-image';

<Image
  source={{ uri: product.imageUrl }}
  cachePolicy="memory-disk"       // LRU in memory, then disk fallback
  placeholder={product.blurhash}  // shown while loading, no layout shift
  contentFit="cover"
/>
```

### 7.5 API Cache: HTTP Cache Headers

Leverage HTTP cache headers to reduce requests at the network layer — zero JS cost:

```tsx
// On the server (NestJS example)
@Get('products')
@Header('Cache-Control', 'public, max-age=300, stale-while-revalidate=60')
@Header('ETag', computeETag(products))
async getProducts() { /* ... */ }

// The native HTTP layer (NSURLSession / OkHttp) handles ETag and 304 responses
// automatically — no application code required
```

A `304 Not Modified` response transfers zero body bytes and requires no JSON parsing — effectively O(1) versus O(n) for a full response.

---

## 8. Common Algorithmic Mistakes

| Mistake | Complexity | Fix | Complexity |
|---|---|---|---|
| Nested `.map`/`.filter`/`.find` in render | O(n²) or worse | Pre-build `Map`/`Set` from data once | O(n) build, O(1) per lookup |
| New object/array literal every render | O(1) but forces all memoised children to re-render | `useMemo`/`useCallback` for stable references | Stable ref, child skips re-render |
| Deep clone with `JSON.parse(JSON.stringify(x))` | O(n) + full allocation | Immer `produce` or targeted spread | O(changed nodes) |
| `Array.sort` in render without `useMemo` | O(n log n) per render | `useMemo` with correct dependencies | O(n log n) once per change |
| Multiple array passes (filter, map, reduce separately) | O(k*n) | Single `reduce` pass | O(n) |
| `Array.includes` inside a loop | O(n²) | Convert to `Set`, use `Set.has` | O(n) |
| Inline `new RegExp(pattern)` in render loop | O(n*m) per render | Pre-compile with `useMemo` | O(m) once, O(n) matching |
| `Array.find` repeated with same id across items | O(n) per item = O(n²) total | Build `Map` once, call `get` per item | O(n) build + O(1) per item |
| `Object.keys(obj).forEach` to iterate Map-like data | O(n) + prototype check overhead | Use `Map.forEach` or `for...of Map` | O(n), no prototype overhead |
| `string + string` concatenation in a loop | O(n²) — each `+` allocates a new string | `Array.push` then `.join('')` | O(n) |

### 8.1 Nested Loop Example — Full Fix

```tsx
// BAD: O(n²) — for each of n orders, scan m products to find name
function OrderList({ orders, products }: Props) {
  return orders.map(order => {
    const product = products.find(p => p.id === order.productId); // O(m) per order
    return <OrderRow key={order.id} order={order} productName={product?.name} />;
  });
}

// GOOD: O(n + m) — build index once, lookup is O(1)
function OrderList({ orders, products }: Props) {
  const productMap = useMemo(
    () => new Map(products.map(p => [p.id, p])),
    [products]
  );

  return orders.map(order => {
    const product = productMap.get(order.productId); // O(1)
    return <OrderRow key={order.id} order={order} productName={product?.name} />;
  });
}
```

For n=500 orders and m=1,000 products: bad = 500,000 comparisons; good = 1,000 Map inserts + 500 O(1) lookups = 1,500 operations.

### 8.2 String Concatenation in Loops

```tsx
// BAD: O(n²) — each + creates a new string copying all previous characters
let result = '';
for (const item of items) {
  result += item.label + ', '; // allocates new string of length i on each iteration
}

// GOOD: O(n) — push to array, join once
const parts: string[] = [];
for (const item of items) {
  parts.push(item.label);
}
const result = parts.join(', '); // one allocation, one pass
```

### 8.3 Multiple Array Passes Collapsed to One

```tsx
// BAD: 3 passes over the same array = O(3n)
const result = data
  .filter(item => item.active)         // pass 1
  .map(item => transform(item))        // pass 2
  .reduce((acc, item) => acc + item.value, 0); // pass 3

// GOOD: single pass = O(n)
const result = data.reduce((acc, item) => {
  if (!item.active) return acc;
  return acc + transform(item).value;
}, 0);
```

Note: the three-pass version is often more readable. Prefer collapsing to one pass only when profiling shows the extra iterations are a bottleneck (typically n > 10,000 or running inside a FlatList renderItem).

---

## Quick Reference — Big-O Cheat Sheet for RN

| Operation | Structure | Best | Average | Worst |
|---|---|---|---|---|
| Lookup by key | `Map` | O(1) | O(1) | O(n) hash collision |
| Lookup by key | Plain object | O(1) | O(1) | O(n) prototype chain |
| Membership test | `Set` | O(1) | O(1) | O(n) hash collision |
| Membership test | `Array.includes` | O(1) | O(n) | O(n) |
| Prefix search | Trie | O(m) | O(m) | O(m) |
| Sort | `Array.sort` (TimSort) | O(n) | O(n log n) | O(n log n) |
| Binary search | Sorted array | O(1) | O(log n) | O(log n) |
| LRU get/set | `Map`-based | O(1) | O(1) | O(1) |
| JSON.parse | Any | O(n) | O(n) | O(n) |
| Immer produce | Partial update | O(changed) | O(changed) | O(n) |
| Regex match | Compiled pattern | O(n) | O(n*m) | O(n*m) |
