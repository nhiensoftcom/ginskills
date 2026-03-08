# Algorithmic Performance in React Native

React Native apps execute JavaScript on the Hermes engine, synchronise with a native UI thread, and often display large, interactive datasets. Poor algorithmic choices compound: an O(n²) operation that runs inside a render function, inside a FlatList item, on a list of 500 rows fires 250,000 iterations on every keystroke. This guide covers the most impactful algorithmic decisions across data structures, search, rendering, sorting, string handling, concurrency, and caching.

---

## 1. Data Structure Choices

Choosing the right data structure is the highest-leverage algorithmic decision. The right choice eliminates entire classes of inefficiency before a single profile is taken.

| Structure | Best Use Case | Complexity | Notes |
|---|---|---|---|
| `Map` | Dynamic key-value lookups | O(1) get/set | Guaranteed hash-based; no prototype chain |
| Plain object | Static, known shape | O(1) get/set | Faster for small, static shapes; JSON-serialisable |
| `Set` | Membership testing, deduplication | O(1) has/add | 100x+ faster than `Array.includes` for n > 1000 |
| `Array` | Ordered sequences, iteration | O(n) includes | Use when order matters and membership tests are rare |
| `TypedArray` | Homogeneous numeric data | O(1) index | 4x less memory than `number[]`; direct buffer transfer via JSI |
| `WeakMap` | Object-keyed memoisation cache | O(1) get/set | Keys are GC-eligible; cache cannot grow unboundedly |
| `WeakRef` | Weak reference to large objects | O(1) deref | Returns `undefined` after GC; no memory leak |

### 1.1 Map vs Object: Dynamic vs Static Shape

```tsx
// Use a plain object for static, known shapes — faster property access via V8/Hermes IC
const config = { timeout: 5000, retries: 3, baseUrl: 'https://api.example.com' };

// Use Map for dynamic keys — O(1) guaranteed, no prototype chain hazard
// BAD: O(n) scan on every access; also slow because find() iterates
const user = users.find(u => u.id === targetId);

// GOOD: O(1) lookup; index built O(n) once when users array changes
const userMap = useMemo(
  () => new Map(users.map(u => [u.id, u])),
  [users]
);
const user = userMap.get(targetId); // O(1) every time
```

`new Map(users.map(...))` is O(n) and runs once on dependency change. `userMap.get` is O(1) per access. When `targetId` changes frequently — a highlighted row in a 500-item list — this is the difference between 500 iterations per render and 1.

### 1.2 Set vs Array: Membership Tests

```tsx
// BAD: O(n) membership test fires on every render for every list item
// 200 items * 200 selected IDs = 40,000 comparisons per render
const isSelected = selectedIds.includes(item.id);

// GOOD: O(1) membership test; Set rebuilt O(n) only when selectedIds changes
const selectedSet = useMemo(
  () => new Set(selectedIds),
  [selectedIds]
);
const isSelected = selectedSet.has(item.id); // O(1)
```

Total cost comparison for 200 rendered items with 200 IDs in the selection:
- `Array.includes` approach: 200 × 200 = **40,000 iterations** per render
- `Set.has` approach: 200 insertions (once) + 200 × O(1) lookups = **400 operations** total

`Set` is 100x+ faster for large sets. The crossover point where `Set` wins over `Array` is roughly n > 50.

### 1.3 TypedArrays for Numeric Data

Regular JavaScript arrays store elements as boxed heap objects — each `number` is a separate allocation. `Float32Array` stores 32-bit floats in a contiguous memory buffer with no boxing overhead.

```tsx
// BAD: JS Array — each element is a heap-allocated Number object
// Memory: ~16 bytes per element = 160KB for 10,000 numbers
const samples: number[] = new Array(10_000).fill(0);

// GOOD: Float32Array — contiguous memory, 4 bytes per element = 40KB for 10,000 numbers
// 4x less memory, no boxing/unboxing, C-compatible
const samples = new Float32Array(10_000);

// Bulk operations run in native code — no JS allocation overhead
samples.fill(0);                         // O(n) native memset
samples.set(incomingBuffer, offset);     // O(n) native memcpy

// TypedArrays transfer directly via JSI ArrayBuffer — zero serialisation cost
nativeModule.processAudioBuffer(samples.buffer);
```

For 10,000 numbers: regular `Array` ≈ 160KB; `Float32Array` ≈ 40KB. For audio (44,100 samples/sec), `Float64Array` avoids precision loss while still being 2x more compact than a boxed array.

TypedArrays also cross the JS/native boundary via JSI `ArrayBuffer` without serialisation, making them the correct choice for any numeric data that is processed by native modules.

### 1.4 WeakMap and WeakRef for GC-Friendly Caches

```tsx
// WeakMap: keys are NOT counted as strong references
// Config objects that go out of scope in the caller are automatically GC'd
const cache = new WeakMap<object, ComputedValue>();

function expensiveCompute(config: Config): ComputedValue {
  if (cache.has(config)) return cache.get(config)!; // O(1)
  const result = heavyTransform(config);             // O(expensive)
  cache.set(config, result);
  return result;
}

// WeakRef: reference a large object without preventing GC
// Useful for decoded image caches, large parsed documents
const imageCache = new Map<string, WeakRef<ImageBitmap>>();

function getCachedImage(url: string): ImageBitmap | undefined {
  const ref = imageCache.get(url);
  if (!ref) return undefined;
  const image = ref.deref(); // returns undefined if GC'd
  if (!image) imageCache.delete(url); // clean up dead entry
  return image;
}
```

A `Map`-backed cache with strong value references will grow without bound unless you implement explicit eviction. `WeakMap` makes GC the eviction policy — correct for caches keyed on object instances that already have their own lifecycle.

### 1.5 Normalised State Shape (Entity Adapter)

Nested arrays require O(n) scans for lookups and O(n) mutations for updates. A normalised "entity adapter" pattern gives O(1) for both:

```tsx
// BAD: nested structure — O(n) lookup, O(n) update, O(n²) cross-reference
interface AppState {
  orders: Order[];       // find order by id: O(n)
  products: Product[];   // find product for order: O(m)
}

// GOOD: normalised — O(1) lookup, O(1) update
interface NormalizedState {
  orders: {
    ids: string[];                // ordered list for rendering
    entities: Record<string, Order>; // O(1) keyed access
  };
  products: {
    ids: string[];
    entities: Record<string, Product>;
  };
}

// With @reduxjs/toolkit createEntityAdapter or a custom equivalent
const ordersAdapter = createEntityAdapter<Order>();
const initialState = ordersAdapter.getInitialState();

// Update a single entity: O(1) — only one object reference changes
const updated = ordersAdapter.updateOne(state, {
  id: 'order-123',
  changes: { status: 'shipped' },
});

// Lookup: O(1)
const order = state.orders.entities['order-123'];
```

---

## 2. Search Optimisation

### 2.1 Binary Search for Sorted Data

When data is sorted (timestamps, prices, alphabetical), binary search reduces O(n) linear scans to O(log n).

```tsx
// O(log n) — finds the insertion index in a sorted array
function binarySearchIndex(arr: number[], target: number): number {
  let lo = 0;
  let hi = arr.length - 1;

  while (lo <= hi) {
    const mid = (lo + hi) >>> 1; // unsigned right shift avoids signed overflow
    if (arr[mid] === target) return mid;
    if (arr[mid] < target) lo = mid + 1;
    else hi = mid - 1;
  }
  return lo; // insertion point when not found
}

// Usage: find where to insert a new event timestamp
const timestamps: number[] = getSortedTimestamps(); // already sorted
const insertAt = binarySearchIndex(timestamps, newTimestamp);
// O(log n) vs O(n) for Array.findIndex
```

For 10,000 sorted items, binary search takes at most 14 comparisons. Linear search averages 5,000.

### 2.2 Debounce and Throttle for Input Handlers

```tsx
import { useMemo } from 'react';
import debounce from 'lodash/debounce';
import throttle from 'lodash/throttle';

// DEBOUNCE: fires once after the user stops typing
// 300ms for API/network search — avoids a request per keystroke
// 150ms for local filter — feels responsive without over-rendering
const debouncedApiSearch = useMemo(
  () => debounce((query: string) => triggerApiSearch(query), 300),
  []
);

const debouncedLocalFilter = useMemo(
  () => debounce((query: string) => setFilterQuery(query), 150),
  []
);

// THROTTLE: fires at most once per interval regardless of call frequency
// 16ms (~60fps) for scroll/drag handlers — aligns with frame budget
const throttledScroll = useMemo(
  () => throttle((offset: number) => updateScrollIndicator(offset), 16),
  []
);
```

A 300ms debounce on a search field reduces API calls by 10–20x for a typical typist (≈5 keystrokes/sec). A 16ms throttle on a scroll listener ensures you never queue more work than the UI thread can consume in one frame.

### 2.3 Trie for Autocomplete — O(m) vs O(n*m)

For local autocomplete over large datasets (product names, usernames, tags), a Trie gives O(m) prefix lookup where m is the query length — independent of dataset size n. `Array.filter` with `startsWith` is O(n*m).

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

  // O(m + k) where k = number of results — does NOT scan all n words
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

// Build once: O(n*m) — query many times: O(m) per query
const trie = useMemo(() => {
  const t = new Trie();
  for (const item of catalogue) t.insert(item.name);
  return t;
}, [catalogue]);

// In search handler:
const suggestions = trie.search(query, 10); // O(m + k)
```

For datasets over 5,000 strings, move Trie construction to a background thread; building a 50,000-entry Trie in JS takes ~100ms and blocks the JS thread.

### 2.4 Fuzzy Search Fallback Strategy

Layer search strategies from fastest to most permissive:

```tsx
function fuzzySearch(items: Item[], query: string): Item[] {
  const q = query.toLowerCase();

  // Pass 1: exact prefix match — O(n) with early exit possible
  const prefixMatches = items.filter(i => i.name.toLowerCase().startsWith(q));
  if (prefixMatches.length >= 5) return prefixMatches;

  // Pass 2: substring/contains match — O(n*m)
  const containsMatches = items.filter(i =>
    i.name.toLowerCase().includes(q) && !prefixMatches.includes(i)
  );
  if (prefixMatches.length + containsMatches.length >= 5) {
    return [...prefixMatches, ...containsMatches];
  }

  // Pass 3: fuzzy (edit distance) — O(n*m*k) — only reached when needed
  const THRESHOLD = 2;
  const fuzzyMatches = items
    .filter(i => !prefixMatches.includes(i) && !containsMatches.includes(i))
    .map(i => ({ item: i, dist: levenshtein(i.name.toLowerCase(), q) }))
    .filter(({ dist }) => dist <= THRESHOLD)
    .sort((a, b) => a.dist - b.dist)
    .map(({ item }) => item);

  return [...prefixMatches, ...containsMatches, ...fuzzyMatches];
}
```

This avoids running expensive Levenshtein on every item when exact matches exist. For >10,000 items, replace JS fuzzy with `fuse.js` (indexed) or `minisearch`.

### 2.5 Cursor Pagination vs Offset Pagination

| Strategy | Server Cost | Client Cost | Stable with inserts? |
|---|---|---|---|
| Offset (`LIMIT 20 OFFSET 400`) | O(offset + limit) — DB scans and discards rows | O(1) append | No — inserts shift items, causing duplicates/gaps |
| Cursor (`WHERE id > lastId LIMIT 20`) | O(limit) — indexed seek | O(1) append | Yes — position is anchored to a record ID |

```tsx
// BAD: offset pagination — unstable and O(n) on server
const fetchPage = (page: number) =>
  api.get(`/products?limit=20&offset=${page * 20}`);

// GOOD: cursor pagination — O(1) on server, no duplicates on insert
const fetchNextPage = (cursor: string) =>
  api.get(`/products?limit=20&after=${cursor}`);

// TanStack Query infinite query with cursor
const { data, fetchNextPage } = useInfiniteQuery({
  queryKey: ['products'],
  queryFn: ({ pageParam }) => fetchNextPage(pageParam),
  getNextPageParam: lastPage => lastPage.nextCursor,
  initialPageParam: '',
});
```

---

## 3. Rendering Algorithms

### 3.1 React Reconciliation and Key Strategy

React's reconciler (in RN: Fabric) diffs virtual trees using a heuristic O(n) algorithm that relies on element `type` and `key`. Index keys break the heuristic on insertions.

```tsx
// BAD: index as key — inserting at position 0 forces all n items to re-render
// React sees key "0" now maps to a different item → full subtree diff
<FlatList
  data={items}
  keyExtractor={(_, index) => String(index)} // never use index for reorderable lists
/>

// GOOD: stable unique ID — only the new item mounts; existing items skip diff
// React matches key "abc-123" to its previous fiber → no diff needed
<FlatList
  data={items}
  keyExtractor={item => item.id}
/>
```

With index keys, inserting one item at the top of a 500-item list triggers 500 re-renders. With stable ID keys: 1 mount, 0 updates.

### 3.2 Selector Memoisation with reselect and Zustand

Selectors without memoisation recompute on every store update, even when their output has not changed:

```tsx
import { createSelector } from 'reselect';
import { useShallow } from 'zustand/react/shallow';

// BAD: new array reference on every store update → every subscribed component re-renders
const activeProducts = useProductStore(state =>
  state.products.filter(p => p.active)
);

// GOOD with Zustand — useShallow does structural equality, not referential
const activeProductIds = useProductStore(
  useShallow(state => state.products.filter(p => p.active).map(p => p.id))
);

// GOOD with Redux — reselect memoises: re-runs only when inputs change
const selectFilteredProducts = createSelector(
  (state: RootState) => state.products.list,
  (state: RootState) => state.filters.category,
  // This O(n) filter runs once per category change, not once per action
  (products, category) => products.filter(p => p.category === category)
);
```

`createSelector` uses referential equality on its input selectors. The O(n) derivation runs only when `state.products.list` or `state.filters.category` change, not on every render.

### 3.3 React 18 Automatic Batching

React 18 automatically batches all state updates regardless of where they originate — event handlers, `async/await`, `setTimeout`, native callbacks:

```tsx
// React 18: these three updates are batched into a single re-render
async function handleSave() {
  const result = await saveToServer(data);
  setIsSaving(false);       // \
  setLastSaved(new Date()); //  batched → one re-render (was 3 in React 17)
  setDirty(false);          // /
}

// Opt out of batching when you need two sequential renders (rare)
import { flushSync } from 'react-dom';
flushSync(() => setProgress(50)); // immediate synchronous render
setProgress(100);                 // second render
```

Batching reduces re-renders from O(k) to O(1) for k simultaneous state updates in async callbacks — significant in list screens with many coordinated state changes.

### 3.4 useDeferredValue and useTransition

```tsx
// useDeferredValue — marks a value as lower priority
// React renders the stale value first (fast path), defers the new computation
function SearchResults({ query }: { query: string }) {
  const deferredQuery = useDeferredValue(query);
  // deferredQuery updates after urgent updates (touch, input) complete
  const results = useFilteredResults(deferredQuery); // O(n) but deferred
  const isStale = query !== deferredQuery;

  return (
    <View style={{ opacity: isStale ? 0.7 : 1 }}>
      <ResultList items={results} />
    </View>
  );
}

// useTransition — marks a state update as non-urgent; can be interrupted
function FilterPanel() {
  const [isPending, startTransition] = useTransition();

  const applyFilter = (category: string) => {
    startTransition(() => {
      // This update can be interrupted by urgent updates (touch input)
      setSelectedCategory(category);
    });
  };

  return (
    <Pressable onPress={() => applyFilter('shoes')} style={{ opacity: isPending ? 0.6 : 1 }}>
      <Text>Shoes</Text>
    </Pressable>
  );
}
```

`useTransition` does not reduce total rendering work — it re-prioritises it. The O(n) re-render still happens; it just cannot block a touch event response.

### 3.5 React Compiler Auto-Memoisation

React Compiler (stable in React 19, available as a Babel plugin in RN 0.75+) automatically inserts `useMemo`, `useCallback`, and `memo` at the IR level. With the compiler enabled:

```tsx
// You write this — compiler inserts memoisation automatically
function ProductList({ products, category }: Props) {
  const filtered = products.filter(p => p.category === category);
  return filtered.map(p => <ProductCard key={p.id} product={p} />);
}

// Equivalent to what you previously had to write manually:
const filtered = useMemo(
  () => products.filter(p => p.category === category),
  [products, category]
);
const MemoCard = memo(ProductCard);
```

The compiler analyses the Rules of React constraints (no side effects in render, stable input/output) and inserts caching where it can prove correctness. Manual `useMemo` is still needed for:
- Expensive computations the compiler cannot prove are pure
- Cross-component or module-level caches
- Explicit cache control (e.g., `cache()` in React Server Components)

---

## 4. Sorting and Filtering

### 4.1 Filter Before Sort — O(n + k log k) vs O(n log n)

Always reduce the dataset with `filter` before sorting:

```tsx
// BAD: sorts all 10,000 products then filters to ~50
// Cost: O(10,000 * log 10,000) ≈ 130,000 comparisons + O(10,000) filter
const result = products
  .sort((a, b) => a.price - b.price)
  .filter(p => p.category === selected);

// GOOD: filters to ~50 first, sorts only those
// Cost: O(10,000) filter + O(50 * log 50) ≈ 300 comparisons
const result = products
  .filter(p => p.category === selected)
  .sort((a, b) => a.price - b.price);
```

If filtering reduces n=10,000 to k=50, the improvement is (10,000 × 13) / (10,000 + 50 × 6) = 130,000 / 10,300 ≈ **13x fewer operations**.

### 4.2 Hermes TimSort

Hermes implements `Array.prototype.sort` as TimSort:
- **O(n log n)** worst case
- **O(n)** best case on nearly-sorted data (ascending runs detected)
- Stable since ES2019 — equal elements preserve original order

```tsx
// Hermes TimSort is O(n) when the array is already sorted
// Benefit: append to sorted list and re-sort costs only O(n), not O(n log n)
const sortedWithNew = useMemo(() => {
  const copy = [...sortedProducts, newProduct]; // new item at end
  copy.sort((a, b) => a.createdAt - b.createdAt); // O(n) because rest is sorted
  return copy;
}, [sortedProducts, newProduct]);
```

For datasets > 5,000 items, prefer server-side sorting. A database B-tree sort is O(1) (index scan) vs client O(n log n).

### 4.3 Memoised Filter and Sort

```tsx
// Without useMemo: O(n log n) on every parent re-render
// With useMemo: O(n log n) only when products or selectedCategory changes
const filteredSortedProducts = useMemo(
  () =>
    products
      .filter(p => p.category === selectedCategory && p.inStock)
      .sort((a, b) => a.price - b.price),
  [products, selectedCategory]
);
```

### 4.4 Multi-Criteria Sort — One Pass vs Chained Sorts

```tsx
// BAD: O(k * n log n) — one sort pass per criterion
const sorted = products
  .sort((a, b) => a.name.localeCompare(b.name))       // O(n log n)
  .sort((a, b) => a.category.localeCompare(b.category)) // O(n log n)
  .sort((a, b) => a.price - b.price);                  // O(n log n)

// GOOD: O(n log n) — single comparator with priority fallthrough
const sorted = [...products].sort((a, b) => {
  if (a.price !== b.price) return a.price - b.price;           // primary
  const catCmp = a.category.localeCompare(b.category);
  if (catCmp !== 0) return catCmp;                              // secondary
  return a.name.localeCompare(b.name);                         // tertiary
});
```

The multi-sort approach also produces stable, predictable results without relying on TimSort stability across chained calls.

---

## 5. String Processing

### 5.1 Pre-Compile Regex Outside Render

RegExp construction parses the pattern into a finite automaton — O(m) work where m is the pattern length. Doing this inside a render or a loop pays this cost on every call.

```tsx
// BAD: pattern compiled on every render — 10–20x slower on Hermes in tight loops
function highlight(text: string, query: string): string {
  return text.replace(new RegExp(query, 'gi'), '<mark>$&</mark>');
}

// GOOD: compile once per query change — O(m) once, O(n) per match
function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// In component:
const highlightRegex = useMemo(
  () => new RegExp(escapeRegExp(query), 'gi'),
  [query]
);

// For static patterns, define at module scope (compiled once at load time)
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
```

Benchmarks on Hermes show regex construction inside a tight loop (n=1000 items) is 10–20x slower than pre-compiled alternatives. Always escape user input before constructing a `RegExp` to prevent ReDoS vulnerabilities.

### 5.2 JSON.parse / JSON.stringify — Hermes vs structuredClone

Hermes implements `JSON.parse` and `JSON.stringify` in optimised native C++ — faster than equivalent JS traversal. However, `JSON.parse(JSON.stringify(x))` for deep cloning is O(n) twice plus GC pressure:

```tsx
// BAD: deep clone via JSON round-trip
// O(n) stringify + allocate string + O(n) parse + allocate all objects
const cloned = JSON.parse(JSON.stringify(original));

// GOOD option 1: structuredClone (available in Hermes 0.12+ / RN 0.73+)
// Handles Dates, Maps, Sets, ArrayBuffers — JSON cannot
const cloned = structuredClone(original); // O(n) but single pass

// GOOD option 2: Immer structural sharing — O(changed nodes) only
import produce from 'immer';
const updated = produce(original, draft => {
  draft.user.name = newName; // only the changed path is copied; rest shares refs
});
// For a 1000-node tree with 1 changed field: O(1) vs O(1000) for full clone
```

Prefer Immer `produce` for Redux/Zustand reducers. Prefer `structuredClone` for true deep-copy needs. Avoid `JSON.parse(JSON.stringify(...))` except for JSON-safe data where you need a quick one-liner in non-hot paths.

### 5.3 Text Measurement Caching

Native text measurement (for dynamic row heights, chat bubble sizing) is an expensive UI thread operation. Cache results by content hash:

```tsx
// LRU cache for text measurements — bounded to prevent unbounded growth
const measureCache = new Map<string, { width: number; height: number }>();
const MEASURE_CACHE_MAX = 500;

function getCachedMeasure(
  text: string,
  style: TextStyle
): { width: number; height: number } {
  const key = `${text}::${style.fontSize}::${style.fontWeight}::${style.width}`;
  if (measureCache.has(key)) return measureCache.get(key)!;

  const measured = measureText(text, style); // expensive native call

  if (measureCache.size >= MEASURE_CACHE_MAX) {
    // Evict LRU: Map preserves insertion order; first key = oldest
    measureCache.delete(measureCache.keys().next().value!);
  }
  measureCache.set(key, measured);
  return measured;
}
```

Cache hit cost: O(1) Map lookup. Cache miss cost: O(1) Map lookup + native measurement + O(1) insert (O(1) eviction when full).

### 5.4 String Concatenation in Loops

```tsx
// BAD: O(n²) — each + allocates a new string copying all previous characters
let result = '';
for (const tag of tags) {
  result += '#' + tag + ' '; // allocates a new string of increasing length each time
}

// GOOD: O(n) — push to array, join once at the end
const parts: string[] = [];
for (const tag of tags) {
  parts.push('#' + tag);
}
const result = parts.join(' '); // one allocation, one O(n) pass
```

---

## 6. Concurrency

### 6.1 Thread Model

React Native runs across three primary threads:

| Thread | Responsibility | Blocked by |
|---|---|---|
| JS thread (Hermes) | React renders, business logic, timers, event handlers | CPU-intensive JS, synchronous native calls |
| UI thread (Main) | Native view layout, animations, touch dispatch | Heavy layout recalculation |
| Shadow/Layout thread | Yoga layout calculation (New Architecture: on JS or UI thread) | Complex layout trees |
| Background threads | Network I/O, image decode, file I/O | Independent |

With New Architecture (JSI + Fabric), Reanimated worklets run on the UI thread in a separate JS runtime — animations are decoupled from JS thread load entirely.

### 6.2 InteractionManager.runAfterInteractions

Defer expensive initialisation until after navigation transitions and animations complete:

```tsx
import { InteractionManager } from 'react-native';
import { useEffect, useState } from 'react';

function HeavyAnalyticsScreen() {
  const [isReady, setIsReady] = useState(false);

  useEffect(() => {
    // Runs AFTER all registered interactions (e.g., navigation transition) finish
    const task = InteractionManager.runAfterInteractions(() => {
      initHeavyCharts();   // safe to do O(n) work here
      fetchAnalytics();    // network requests won't jank the transition
      setIsReady(true);
    });
    return () => task.cancel(); // cancel if screen unmounts mid-transition
  }, []);

  if (!isReady) return <SkeletonScreen />;
  return <AnalyticsContent />;
}
```

Without `runAfterInteractions`, heavy screen initialisation runs concurrently with the navigation animation, causing frame drops on the UI thread.

### 6.3 requestAnimationFrame for Frame-Yielding Chunks

`await Promise.resolve()` yields to the microtask queue but NOT to the macrotask/timer queue — the JS thread still blocks between frames. Use `requestAnimationFrame` to actually yield a frame:

```tsx
// Process 500 items without blocking the JS thread
function processInChunks<T>(items: T[], process: (item: T) => void, chunkSize = 50) {
  let index = 0;

  function processChunk() {
    const end = Math.min(index + chunkSize, items.length);
    for (; index < end; index++) {
      process(items[index]);
    }
    if (index < items.length) {
      requestAnimationFrame(processChunk); // yield to next frame, then continue
    }
  }

  requestAnimationFrame(processChunk);
}

// True frame yield in async/await:
async function processWithFrameYield(items: Item[]) {
  for (let i = 0; i < items.length; i += 50) {
    items.slice(i, i + 50).forEach(expensiveProcess);
    // await Promise.resolve() — yields microtask queue only, NOT a frame
    await new Promise(r => requestAnimationFrame(r)); // actually yields a frame
  }
}
```

Each 50-item chunk runs within one 16ms frame budget. The app remains interactive (touch events are handled between chunks) during bulk processing.

### 6.4 Reanimated Worklets — UI Thread Computation

Worklets are JS functions serialised to Reanimated's UI-thread Hermes instance. They run at 60/120fps without any JS thread involvement:

```tsx
import Animated, {
  useSharedValue,
  useAnimatedScrollHandler,
  useAnimatedStyle,
  interpolate,
  Extrapolation,
} from 'react-native-reanimated';

function ParallaxHeader() {
  const scrollY = useSharedValue(0);

  const onScroll = useAnimatedScrollHandler({
    onScroll: event => {
      'worklet'; // serialised to UI thread runtime
      scrollY.value = event.contentOffset.y; // never touches JS thread
    },
  });

  const headerStyle = useAnimatedStyle(() => {
    'worklet';
    return {
      opacity: interpolate(scrollY.value, [0, 100], [1, 0], Extrapolation.CLAMP),
      transform: [
        { translateY: interpolate(scrollY.value, [0, 200], [0, -100]) },
      ],
    };
  });

  return (
    <Animated.ScrollView onScroll={onScroll} scrollEventThrottle={16}>
      <Animated.View style={headerStyle} />
    </Animated.ScrollView>
  );
}
```

Worklets: no JS thread round-trip, no serialisation, no frame drops from JS-side re-renders. For gesture-driven or scroll-driven animations, this is the only approach that guarantees 60fps on a busy JS thread.

### 6.5 react-native-workers for Heavy JS Computation

For tasks > 5ms (image processing, CSV parsing, cryptography, ML inference), move off the JS thread:

```tsx
// worker.ts — runs in a separate Hermes instance on a background thread
self.onmessage = ({ data }: { data: { csv: string } }) => {
  const rows = heavyCsvParse(data.csv); // O(n) — does not block JS thread
  self.postMessage({ rows });
};

// main thread
import { Worker } from 'react-native-workers';

const worker = new Worker('./worker');

function parseUpload(csv: string): Promise<Row[]> {
  return new Promise(resolve => {
    worker.onmessage = ({ data }) => resolve(data.rows);
    worker.postMessage({ csv });
  });
}
```

When to use which approach:
| Work Duration | Approach |
|---|---|
| < 1ms | Run inline — no overhead |
| 1–5ms | `requestAnimationFrame` chunking or `InteractionManager` |
| 5–50ms | `react-native-workers` (background Hermes) |
| > 50ms or needs native libs | Native TurboModule (C++/Swift/Kotlin via JSI) |
| Infrequent / one-time | Offload to server API |

---

## 7. Caching Strategies

### 7.1 LRU Cache — Map-Based O(1)

A Least Recently Used cache evicts the least recently accessed entry when capacity is full. `Map` preserves insertion order, enabling O(1) get and set:

```tsx
class LRUCache<K, V> {
  private map = new Map<K, V>();

  constructor(private readonly maxSize: number) {}

  // O(1) — deletes and re-inserts to move to "most recently used" position
  get(key: K): V | undefined {
    if (!this.map.has(key)) return undefined;
    const value = this.map.get(key)!;
    this.map.delete(key);
    this.map.set(key, value); // re-insert at end = most recent
    return value;
  }

  // O(1) — evicts LRU (first entry) if at capacity
  set(key: K, value: V): void {
    if (this.map.has(key)) this.map.delete(key);
    else if (this.map.size >= this.maxSize) {
      // Map.keys() iterator is insertion-ordered; first = least recently used
      this.map.delete(this.map.keys().next().value!);
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

// Usage: cache up to 200 processed thumbnails
const thumbnailCache = new LRUCache<string, ProcessedImage>(200);
```

Both `get` and `set` are O(1) amortised. The `Map` delete + re-insert costs O(1) (hash table operation), not O(n).

### 7.2 TTL Cache with Periodic Purge

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
      return undefined; // expired
    }
    return entry.value;
  }

  set(key: K, value: V): void {
    this.store.set(key, { value, expiresAt: Date.now() + this.ttlMs });
  }

  // Purge all expired entries — call periodically in a low-priority timer
  purgeExpired(): void {
    const now = Date.now();
    for (const [key, entry] of this.store) {
      if (now > entry.expiresAt) this.store.delete(key);
    }
  }
}

// Cache geocoding results for 10 minutes
const geocodeCache = new TTLCache<string, LatLng>(10 * 60 * 1000);
```

### 7.3 Stale-While-Revalidate with TanStack Query

TanStack Query implements stale-while-revalidate natively: it returns cached (stale) data immediately at O(1) cost, then fetches fresh data in the background:

```tsx
const { data: products } = useQuery({
  queryKey: ['products', categoryId],
  queryFn: () => fetchProducts(categoryId),
  staleTime: 5 * 60 * 1000,  // serve cached data for up to 5 minutes
  gcTime: 30 * 60 * 1000,    // keep in memory for 30 minutes after last use
});

// For ETag-based caching: pass headers through and let the native HTTP layer handle 304s
queryFn: async () => {
  const response = await fetch(`/api/products?category=${categoryId}`, {
    headers: etag ? { 'If-None-Match': etag } : {},
  });
  if (response.status === 304) return cachedData; // O(1) — zero body transfer
  setEtag(response.headers.get('ETag') ?? '');
  return response.json();
},

// Static reference data that never changes during a session
const { data: countries } = useQuery({
  queryKey: ['countries'],
  queryFn: fetchCountries,
  staleTime: Infinity, // never re-fetch; persists for session lifetime
});
```

`staleTime: Infinity` turns a query into a one-time fetch — correct for country lists, category trees, configuration data.

### 7.4 Image Cache Strategies

```tsx
// React Native Image: native-layer LRU cache (SDWebImage iOS, Glide Android)
// No application code needed — handled automatically

// Prefetch images during idle time before they scroll into view
import { Image } from 'react-native';

async function prefetchNextPageImages(items: FeedItem[]): Promise<void> {
  await Promise.all(
    items.slice(0, 10).map(item => Image.prefetch(item.thumbnailUrl))
  );
}

// expo-image: explicit cache policy + BlurHash placeholder (no layout shift)
import { Image } from 'expo-image';

<Image
  source={{ uri: product.imageUrl }}
  cachePolicy="memory-disk"        // memory LRU → disk LRU → network
  placeholder={product.blurhash}   // shown immediately from in-memory string
  contentFit="cover"
  transition={200}
/>
```

`cachePolicy="memory-disk"` means: serve from memory cache (O(1)), fall back to disk (O(disk read)), fall back to network. The BlurHash placeholder is decoded from a ~30-character string — no placeholder image download.

### 7.5 HTTP Cache Headers — Zero JS Cost

Leverage HTTP cache headers to eliminate network requests at the infrastructure layer:

```tsx
// Server (NestJS): set cache headers on stable responses
@Get('products')
@Header('Cache-Control', 'public, max-age=300, stale-while-revalidate=60')
@Header('Vary', 'Accept-Encoding')
async getProducts(@Headers('if-none-match') ifNoneMatch: string) {
  const products = await this.productsService.findAll();
  const etag = computeETag(products);

  if (ifNoneMatch === etag) {
    throw new HttpException('', HttpStatus.NOT_MODIFIED); // 304 — zero body
  }

  return products;
}
```

A `304 Not Modified` response transfers zero body bytes and requires no JSON parsing — effectively O(1) data cost versus O(n) for a full JSON response. The native HTTP layer (NSURLSession / OkHttp) handles ETag round-trips automatically when `Cache-Control` headers are present.

---

## 8. Common Algorithmic Mistakes

| Mistake | Complexity | Fix | Fixed Complexity |
|---|---|---|---|
| Nested `.map`/`.find` in render | O(n²) | Pre-build `Map`/`Set` index with `useMemo` | O(n) build, O(1) per lookup |
| New object/array literal in render | O(1) but forces memo children to re-render | `useMemo`/`useCallback` for stable refs | Child skips re-render |
| `JSON.parse(JSON.stringify(x))` deep clone | O(n) + full allocation + GC | Immer `produce` or `structuredClone` | O(changed nodes) |
| `Array.sort` in render without `useMemo` | O(n log n) per render | `useMemo` with correct deps | O(n log n) once per change |
| Multiple array passes (filter → map → reduce) | O(k × n) | Single `reduce` pass | O(n) |
| `Array.includes` inside a loop | O(n²) | Convert to `Set`, use `Set.has` | O(n) |
| `new RegExp(pattern)` inside render or loop | O(n × m) compile overhead | Pre-compile with `useMemo` or module scope | O(m) once, O(n) matching |
| `Array.find(id)` repeated across items | O(n) per item = O(n²) total | Build `Map` once, call `get` per item | O(n) build + O(1) per item |
| `string +=` in a loop | O(n²) — new allocation per iteration | `Array.push` then `.join('')` | O(n) |
| Sort without filter first | O(n log n) then O(n) | Filter first, then sort smaller set | O(n + k log k) |

### 8.1 Nested Loop — Full Fix

```tsx
// BAD: O(n × m) — for each of n orders, scan m products
function OrderList({ orders, products }: Props) {
  return orders.map(order => {
    const product = products.find(p => p.id === order.productId); // O(m) per order
    return <OrderRow key={order.id} order={order} productName={product?.name} />;
  });
}
// For n=500 orders, m=1000 products: 500 × 1000 = 500,000 comparisons per render

// GOOD: O(n + m) — build index O(m) once, lookup O(1) per order
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
// Cost: 1000 Map inserts + 500 O(1) lookups = 1,500 operations — 333x improvement
```

### 8.2 Multiple Array Passes Collapsed to One

```tsx
// BAD: 3 separate passes over the array = O(3n)
const total = data
  .filter(item => item.active)          // pass 1: O(n)
  .map(item => transform(item))         // pass 2: O(filtered)
  .reduce((acc, item) => acc + item.value, 0); // pass 3: O(filtered)

// GOOD: single pass = O(n)
const total = data.reduce((acc, item) => {
  if (!item.active) return acc;
  return acc + transform(item).value;
}, 0);
```

Note: the three-pass version is often more readable. Prefer collapsing to a single `reduce` only when profiling confirms the extra allocations are a bottleneck — typically n > 10,000 or inside a FlatList `renderItem`.

### 8.3 Stable Callback References

```tsx
// BAD: new function reference on every render → every memoised child re-renders
function ProductList({ products }: Props) {
  return products.map(p => (
    <ProductCard
      key={p.id}
      product={p}
      onPress={() => navigate('Product', { id: p.id })} // new ref each render
    />
  ));
}

// GOOD: stable reference per product; only the specific item's handler changes if id changes
function ProductList({ products }: Props) {
  const handlePress = useCallback(
    (id: string) => navigate('Product', { id }),
    [navigate]
  );

  return products.map(p => (
    <ProductCard
      key={p.id}
      product={p}
      onPress={handlePress} // same reference across renders
      productId={p.id}      // pass data separately
    />
  ));
}
```

---

## Quick Reference — Big-O Cheat Sheet for React Native

| Operation | Structure | Best | Average | Worst |
|---|---|---|---|---|
| Key lookup | `Map` | O(1) | O(1) | O(n) hash collision |
| Key lookup | Plain object | O(1) | O(1) | O(n) prototype chain |
| Membership test | `Set.has` | O(1) | O(1) | O(n) hash collision |
| Membership test | `Array.includes` | O(1) | O(n) | O(n) |
| Prefix search | Trie | O(m) | O(m) | O(m) |
| Sort (Hermes TimSort) | `Array.sort` | O(n) nearly sorted | O(n log n) | O(n log n) |
| Binary search | Sorted array | O(1) | O(log n) | O(log n) |
| LRU get/set | `Map`-based | O(1) | O(1) | O(1) |
| Deep clone | `JSON.parse(JSON.stringify)` | O(n) | O(n) | O(n) |
| Partial update | Immer `produce` | O(changed) | O(changed) | O(n) |
| Regex match | Pre-compiled | O(n) | O(n*m) | O(n*m) |
| Text measure | Native + cache | O(1) cache hit | O(native) | O(native) |
| HTTP response | 304 Not Modified | O(1) | O(1) | O(1) |
| HTTP response | Full JSON | O(n) | O(n) | O(n) |
