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

---

## 9. Serialization Formats

Serialisation is the hidden cost in every network response, worker-thread message, and deep-clone. Choosing the wrong format adds O(n) overhead on every data exchange boundary.

### 9.1 SuperJSON — Circular Refs and Non-JSON Types

`JSON.stringify` silently drops `Date`, `Map`, `Set`, `undefined`, and `BigInt`, and throws on circular references. SuperJSON preserves all of them by encoding type metadata alongside the value:

```tsx
import SuperJSON from 'superjson';

const payload = {
  createdAt: new Date(),                // Date
  tags: new Set(['react', 'native']),   // Set
  meta: new Map([['env', 'prod']]),     // Map
  count: BigInt(9007199254740993),      // BigInt
};

// JSON.stringify: silently loses Date, Set, Map, BigInt
const broken = JSON.parse(JSON.stringify(payload));
// broken.createdAt is a string; broken.tags is {}, broken.meta is {}

// SuperJSON: round-trips all types correctly
const serialised = SuperJSON.stringify(payload);
const restored = SuperJSON.parse<typeof payload>(serialised);
// restored.createdAt instanceof Date === true
// restored.tags instanceof Set === true
```

Cost: SuperJSON adds a small `_meta` object alongside the data — O(n) same as JSON but with a constant factor overhead of ~5–15% for metadata. Use it for cross-boundary data that contains non-JSON primitives; use plain JSON for pure string/number payloads where speed matters most.

### 9.2 MessagePack and Protocol Buffers — Binary Encoding

Binary formats eliminate the string parsing step: instead of converting every number to UTF-8 digits, values are stored as fixed-width bytes.

| Format | Encoding | Schema required | Size vs JSON | Parse speed vs JSON |
|---|---|---|---|---|
| JSON | UTF-8 text | No | baseline | baseline |
| MessagePack | Binary | No | ~20–40% smaller | ~2–4x faster |
| Protocol Buffers | Binary | Yes (.proto file) | ~30–60% smaller | ~5–10x faster |

MessagePack integration in React Native using `@msgpack/msgpack`:

```tsx
import { encode, decode } from '@msgpack/msgpack';

// Encode — returns Uint8Array, not a string
const buffer: Uint8Array = encode({
  userId: 'u-123',
  scores: [98.6, 72.1, 55.0],
  active: true,
});
// For 1000-item list: JSON ≈ 42KB string, MessagePack ≈ 28KB Uint8Array

// Transfer over fetch as binary
const response = await fetch('/api/scores', {
  method: 'POST',
  headers: { 'Content-Type': 'application/msgpack' },
  body: buffer, // no JSON.stringify — O(n) encoding into binary directly
});

// Decode — operates on the ArrayBuffer directly without string allocation
const data = await response.arrayBuffer();
const result = decode(new Uint8Array(data)) as ScoresResponse;
// No intermediate UTF-8 string; no JSON tokeniser
```

**When to choose each format:**
- Plain JSON: public APIs, human-readable payloads, small responses (< 10KB)
- MessagePack: internal services, large numeric datasets, mobile bandwidth is constrained
- Protobuf: typed contracts between services, highest performance requirement, team maintains `.proto` files

### 9.3 structuredClone vs JSON.parse(JSON.stringify)

```tsx
interface CloneSubject {
  id: string;
  createdAt: Date;
  tags: Set<string>;
  data: ArrayBuffer;
}

const original: CloneSubject = {
  id: 'abc',
  createdAt: new Date(),
  tags: new Set(['a', 'b']),
  data: new ArrayBuffer(1024),
};

// BAD: JSON round-trip — O(n) stringify to string + O(n) parse
// Loses Date (becomes string), Set (becomes {}), ArrayBuffer (becomes {})
const broken = JSON.parse(JSON.stringify(original));

// GOOD: structuredClone — O(n) single pass, handles all transferable types
// Available in Hermes ≥ 0.12 (React Native ≥ 0.73)
const cloned = structuredClone(original);
// cloned.createdAt instanceof Date === true
// cloned.tags instanceof Set === true

// BEST when transferring large buffers: transfer instead of clone (O(1))
// The original ArrayBuffer becomes detached (zero-copy transfer)
const transferred = structuredClone(original, {
  transfer: [original.data], // O(1) — no memcpy, ownership moves
});
// original.data.byteLength === 0 after transfer
```

### 9.4 Performance Benchmarks

Representative numbers on a mid-range Android device (Hermes, 1000-item list of objects with 5 fields each):

| Operation | Payload Size | Time |
|---|---|---|
| `JSON.stringify` | 42 KB string | ~3.2 ms |
| `JSON.parse` | 42 KB string | ~4.1 ms |
| `MessagePack encode` | 28 KB Uint8Array | ~1.4 ms |
| `MessagePack decode` | 28 KB Uint8Array | ~1.8 ms |
| `structuredClone` | in-memory | ~2.6 ms |
| `JSON.parse(JSON.stringify)` | in-memory | ~7.8 ms |
| Protobuf encode | 18 KB binary | ~0.9 ms |
| Protobuf decode | 18 KB binary | ~1.1 ms |

Key takeaways: MessagePack is roughly 2x faster than JSON for encode/decode. Protobuf is 3–4x faster but requires a schema. `structuredClone` is ~3x faster than the JSON round-trip for in-memory deep clones.

---

## 10. Worker Thread Patterns

### 10.1 react-native-worklets vs react-native-workers

These solve different problems and run on different threads:

| | react-native-reanimated worklets | react-native-workers |
|---|---|---|
| Thread | UI thread (dedicated Hermes runtime) | Background thread (separate Hermes runtime) |
| Purpose | Gesture/animation without JS-thread round-trips | Heavy CPU computation without blocking JS thread |
| Communication | Shared values (zero-copy via Reanimated internals) | `postMessage` / `onmessage` (serialised) |
| When to use | Scroll handlers, gesture callbacks, animated styles | CSV parsing, encryption, image processing, ML inference |
| Frame budget | Must complete in < 16ms per frame | No frame budget constraint |
| Access to React | Cannot call React APIs | Cannot call React APIs |

### 10.2 Thread Pool Management

Running one worker per task wastes thread spawn overhead. Use a bounded pool that queues tasks:

```tsx
// worker-pool.ts — manages N persistent worker threads
import { Worker } from 'react-native-workers';

interface Task<T> {
  payload: unknown;
  resolve: (result: T) => void;
  reject: (err: Error) => void;
}

class WorkerPool<T> {
  private workers: Worker[] = [];
  private idle: Worker[] = [];
  private queue: Task<T>[] = [];

  constructor(workerScript: string, poolSize: number) {
    for (let i = 0; i < poolSize; i++) {
      const worker = new Worker(workerScript);
      worker.onmessage = ({ data }) => this.handleResult(worker, data);
      worker.onerror = (err) => this.handleError(worker, err);
      this.idle.push(worker);
      this.workers.push(worker);
    }
  }

  // O(1): post to idle worker or enqueue
  run(payload: unknown): Promise<T> {
    return new Promise((resolve, reject) => {
      const task: Task<T> = { payload, resolve, reject };
      const worker = this.idle.pop();
      if (worker) {
        this.dispatch(worker, task);
      } else {
        this.queue.push(task); // wait for a free worker
      }
    });
  }

  private dispatch(worker: Worker, task: Task<T>): void {
    (worker as any)._currentTask = task;
    worker.postMessage(task.payload);
  }

  private handleResult(worker: Worker, data: T): void {
    const task = (worker as any)._currentTask as Task<T>;
    task.resolve(data);
    const next = this.queue.shift();
    if (next) {
      this.dispatch(worker, next);
    } else {
      this.idle.push(worker); // return to idle pool
    }
  }

  private handleError(worker: Worker, err: Error): void {
    const task = (worker as any)._currentTask as Task<T>;
    task.reject(err);
    this.idle.push(worker);
  }
}

// Singleton pool: 3 workers for image processing
export const imageWorkerPool = new WorkerPool<ProcessedImage>(
  './image-worker',
  3
);

// Usage — tasks queue automatically when all workers are busy
const processed = await imageWorkerPool.run({ uri: photo.uri, filter: 'blur' });
```

Pool size guideline: match the number of available CPU cores minus one (to leave capacity for the JS and UI threads). For React Native, 2–4 workers is typically optimal on 8-core devices.

### 10.3 Posting Large ArrayBuffers Across Worker Boundary

`postMessage` with a plain object serialises to JSON — O(n) and copies all data. `ArrayBuffer` can be transferred (zero-copy, O(1)):

```tsx
// image-worker.ts — receives and returns ArrayBuffers via transfer
self.onmessage = ({ data }: { data: { buffer: ArrayBuffer; width: number; height: number } }) => {
  const pixels = new Uint8ClampedArray(data.buffer); // O(1) — no copy
  applyGrayscaleInPlace(pixels);                     // O(n) — modifies in place

  // Transfer the buffer back — caller's reference becomes detached
  self.postMessage({ buffer: data.buffer }, [data.buffer]); // O(1) transfer
};

// main thread
async function processImageInWorker(
  imageData: ImageData
): Promise<ImageData> {
  // Transfer to worker — imageData.data.buffer is detached after this call
  worker.postMessage(
    { buffer: imageData.data.buffer, width: imageData.width, height: imageData.height },
    [imageData.data.buffer] // transfer list — zero-copy
  );

  return new Promise(resolve => {
    worker.onmessage = ({ data }) => {
      const pixels = new Uint8ClampedArray(data.buffer); // O(1)
      resolve(new ImageData(pixels, imageData.width, imageData.height));
    };
  });
}
```

For a 4MB image buffer (1000×1000 RGBA): transferring takes O(1) vs O(4MB) copy time (~4ms on a mid-range device). Always use the transfer list when passing `ArrayBuffer`, `SharedArrayBuffer`, or `TypedArray` backing buffers.

### 10.4 Worker Pool for Image Processing — Full Example

```tsx
// image-processor-worker.ts
import { decode, encode } from 'image-processing-lib'; // hypothetical native binding

self.onmessage = async ({ data }: {
  data: { id: string; buffer: ArrayBuffer; ops: ImageOp[] };
}) => {
  try {
    let pixels = new Uint8ClampedArray(data.buffer);

    for (const op of data.ops) {
      switch (op.type) {
        case 'blur':    pixels = applyBoxBlur(pixels, op.radius); break;
        case 'crop':    pixels = applyCrop(pixels, op.rect);      break;
        case 'resize':  pixels = applyResize(pixels, op.size);    break;
      }
    }

    // Return result buffer with transfer for zero-copy
    self.postMessage(
      { id: data.id, buffer: pixels.buffer, success: true },
      [pixels.buffer]
    );
  } catch (err) {
    self.postMessage({ id: data.id, success: false, error: String(err) });
  }
};

// main.ts — pool usage
const pool = new WorkerPool<ProcessResult>('./image-processor-worker', 3);

async function processPhoto(photo: CameraPhoto, ops: ImageOp[]): Promise<string> {
  const buffer = await fetchAsArrayBuffer(photo.uri); // O(n) — read once
  const result = await pool.run({ id: photo.id, buffer, ops }); // O(1) dispatch
  return URL.createObjectURL(new Blob([result.buffer]));
}
// Total complexity: O(n) read + O(n) processing in background + O(1) transfer back
// JS thread is free throughout — no frame drops
```

---

## 11. Advanced Debounce and Throttle

### 11.1 Leading and Trailing Edge Debounce

Standard debounce fires on the trailing edge (after the last call). Leading-edge fires immediately on the first call and ignores subsequent calls until the wait expires:

```tsx
import debounce from 'lodash/debounce';

// Trailing (default): fires 300ms after the LAST call
// Use for: search queries, form submission, API calls on input
const trailingSearch = debounce((q: string) => fetchResults(q), 300);

// Leading: fires immediately on FIRST call, ignores until 300ms passes
// Use for: button press feedback, preventing double-submit
const leadingSubmit = debounce(
  (form: FormData) => submitOrder(form),
  1000,
  { leading: true, trailing: false }
);

// Both edges: fires immediately, then fires once more after idle
// Use for: analytics events where you want start + end signals
const bothEdges = debounce(
  (value: string) => trackInput(value),
  500,
  { leading: true, trailing: true }
);
```

### 11.2 Debounce with maxWait Constraint

Standard debounce can be starved indefinitely if the user types continuously. `maxWait` guarantees at least one call per interval regardless of activity:

```tsx
import debounce from 'lodash/debounce';

// Fires 300ms after last keystroke, BUT at most every 800ms during continuous typing
// Prevents the search from feeling broken during fast, sustained input
const boundedSearch = useMemo(
  () =>
    debounce(
      (query: string) => triggerSearch(query),
      300,
      { maxWait: 800 } // guaranteed call at 800ms even if typing continues
    ),
  []
);

// Without maxWait: fast typist (10 chars/sec) never triggers search until they stop
// With maxWait 800ms: search fires at 800ms, 1600ms, etc. even during typing
```

`maxWait` is the most important option for live-search UX: it balances reducing API calls (debounce) with keeping results feeling live (maxWait).

### 11.3 Throttle with requestAnimationFrame for Scroll and Resize

Time-based throttle (e.g., `throttle(fn, 16)`) does not align to the actual frame boundary — it can fire in the middle of a frame, wasting a render. An rAF-based throttle always fires at the start of the next frame:

```tsx
// rAF-based throttle — fires at most once per animation frame (~60fps)
// O(1) overhead: one rAF registration per interval, cancelled if superseded
function rafThrottle<T extends unknown[]>(fn: (...args: T) => void) {
  let rafId: number | null = null;
  let lastArgs: T;

  return function throttled(...args: T): void {
    lastArgs = args;
    if (rafId !== null) return; // already scheduled for this frame

    rafId = requestAnimationFrame(() => {
      fn(...lastArgs); // execute with the most recent args
      rafId = null;
    });
  };
}

// Usage: scroll handler aligned to frame boundary
const handleScroll = useMemo(
  () =>
    rafThrottle((event: NativeSyntheticEvent<NativeScrollEvent>) => {
      const y = event.nativeEvent.contentOffset.y;
      updateScrollIndicator(y);
      checkStickyHeader(y);
    }),
  []
);

// Compared to time-based throttle(fn, 16):
// - rafThrottle: always executes at frame start, never wastes a partial frame
// - throttle(fn, 16): can fire at any 16ms interval, may overlap rendering
```

### 11.4 Debounce Pattern for Form Validation

Validate eagerly (immediate feedback for format errors) and validate lazily (debounced for async checks):

```tsx
import { useCallback, useMemo, useState } from 'react';
import debounce from 'lodash/debounce';

function useEmailField() {
  const [value, setValue] = useState('');
  const [syncError, setSyncError] = useState<string | null>(null);
  const [asyncError, setAsyncError] = useState<string | null>(null);
  const [isChecking, setIsChecking] = useState(false);

  // Synchronous: fires on every keystroke — format validation is O(m) regex
  const validateFormat = useCallback((email: string) => {
    setSyncError(
      EMAIL_RE.test(email) || email === '' ? null : 'Invalid email format'
    );
  }, []);

  // Asynchronous: debounced 500ms — avoids an API call per keystroke
  const checkUnique = useMemo(
    () =>
      debounce(async (email: string) => {
        if (!EMAIL_RE.test(email)) return;
        setIsChecking(true);
        try {
          const { available } = await api.checkEmailAvailability(email);
          setAsyncError(available ? null : 'Email already in use');
        } finally {
          setIsChecking(false);
        }
      }, 500),
    []
  );

  const handleChange = useCallback(
    (text: string) => {
      setValue(text);
      validateFormat(text);  // immediate
      checkUnique(text);     // debounced
    },
    [validateFormat, checkUnique]
  );

  return { value, handleChange, error: syncError ?? asyncError, isChecking };
}
```

The split approach gives instant format feedback (no debounce delay) while keeping network traffic minimal (500ms debounce on the async check).

### 11.5 rAF-Based Throttle — Code Reference

```tsx
// Full TypeScript implementation with cleanup support
function createRafThrottle<T extends unknown[]>(
  fn: (...args: T) => void
): { throttled: (...args: T) => void; cancel: () => void } {
  let rafId: number | null = null;
  let pendingArgs: T | null = null;

  function throttled(...args: T): void {
    pendingArgs = args;
    if (rafId !== null) return;

    rafId = requestAnimationFrame(() => {
      if (pendingArgs !== null) {
        fn(...pendingArgs);
        pendingArgs = null;
      }
      rafId = null;
    });
  }

  function cancel(): void {
    if (rafId !== null) {
      cancelAnimationFrame(rafId);
      rafId = null;
      pendingArgs = null;
    }
  }

  return { throttled, cancel };
}

// In a component — cancel on unmount to prevent stale calls
function ScrollTracker() {
  useEffect(() => {
    const { throttled: onScroll, cancel } = createRafThrottle(
      (y: number) => updateParallax(y)
    );
    // ... attach listener
    return cancel; // cleanup on unmount
  }, []);
}
```

Big-O: O(1) per call — one conditional check, optionally one `requestAnimationFrame` registration. The `fn` itself is called at most once per 16ms frame regardless of call frequency.

---

## 12. Virtualization Internals

### 12.1 How FlatList Windowing Works

FlatList wraps `VirtualizedList`, which renders only the items within a "window" around the current scroll position. Items outside the window are unmounted and replaced by blank spacer views.

Key parameters:

| Prop | Default | Effect |
|---|---|---|
| `windowSize` | 21 | Renders `windowSize × viewportHeight` pixels of content (10 viewports above + 10 below) |
| `initialNumToRender` | 10 | Items rendered synchronously before first paint |
| `maxToRenderPerBatch` | 10 | Items added per `requestAnimationFrame` batch during scroll |
| `updateCellsBatchingPeriod` | 50 | Milliseconds between render batches |
| `removeClippedSubviews` | false | Detaches (but keeps in memory) off-screen native views |

```
Viewport (600px)

┌───────────────────────┐  ─ top of rendered window
│  overscan buffer      │  windowSize=5 → 2 viewports above = 1200px
│  (not visible)        │
├───────────────────────┤  ─ scroll position start
│                       │
│   VISIBLE CONTENT     │  600px viewport
│                       │
├───────────────────────┤  ─ scroll position end
│  overscan buffer      │  2 viewports below = 1200px
│  (not visible)        │
└───────────────────────┘  ─ bottom of rendered window
     blank spacers          ← unmounted items above/below window
```

`windowSize` is measured in viewport multiples. `windowSize=21` means 10 viewports above + 1 visible + 10 below = 21 total. Reduce to `windowSize=5` on low-memory devices; increase to `windowSize=31` for fast-scrolling carousels where blank flashes are unacceptable.

### 12.2 FlashList Cell Reuse and Predictive Rendering

FlashList (Shopify) replaces RN's VirtualizedList internals with a RecyclerListView-based engine that reuses native view instances rather than unmounting and remounting them:

```
VirtualizedList (FlatList): unmount → mount cycle on scroll
  item scrolls off top → unmounted (React tree destruction)
  new item scrolls in  → mounted (React tree creation)
  Cost: O(component tree depth) per item × scroll speed

FlashList: view recycling
  item scrolls off top → view detached from tree, placed in recycle pool
  new item scrolls in  → view taken from pool, props updated in-place
  Cost: O(1) prop update — no mount/unmount lifecycle
```

```tsx
import { FlashList } from '@shopify/flash-list';

<FlashList
  data={products}
  renderItem={({ item }) => <ProductCard product={item} />}
  estimatedItemSize={80}          // critical: enables predictive layout
  keyExtractor={item => item.id}
  // FlashList uses estimatedItemSize to pre-calculate scroll positions
  // without needing to measure every item — O(1) per layout position
/>
```

`estimatedItemSize` is required. FlashList uses it to calculate spacer heights without rendering items — a critical optimisation for lists of 10,000+ items. If actual sizes vary widely from the estimate, FlashList corrects via measurement but accumulates positional drift.

### 12.3 Dynamic Height Virtualization Algorithms

Variable-height items break the O(1) position calculation (`index × fixedHeight`). Two approaches:

**Approach 1: Measured cache** — measure each item once, cache heights. Scroll position requires summing all heights above the viewport: O(n) worst case, reducible to O(log n) with a Fenwick tree (prefix-sum tree).

**Approach 2: Estimation + correction** — estimate uniform height, correct as items are measured. FlashList and most modern virtualizers use this.

```tsx
// Fenwick tree (Binary Indexed Tree) for O(log n) prefix-sum updates
// Useful when you need to compute "total height above item at index i"
class FenwickTree {
  private tree: number[];

  constructor(size: number) {
    this.tree = new Array(size + 1).fill(0);
  }

  // O(log n) — update height at index
  update(index: number, delta: number): void {
    for (let i = index + 1; i < this.tree.length; i += i & -i) {
      this.tree[i] += delta;
    }
  }

  // O(log n) — prefix sum: total height of items 0..index
  query(index: number): number {
    let sum = 0;
    for (let i = index + 1; i > 0; i -= i & -i) {
      sum += this.tree[i];
    }
    return sum;
  }
}

// Usage: O(log n) scroll position calculation instead of O(n) linear sum
const heights = new FenwickTree(items.length);
items.forEach((_, i) => heights.update(i, estimatedHeight));

// When item i is measured: update the delta
function onItemMeasured(index: number, actualHeight: number): void {
  const delta = actualHeight - estimatedHeight;
  heights.update(index, delta); // O(log n)
}

// Scroll to item at index: O(log n)
const yOffset = heights.query(targetIndex - 1);
```

For n=10,000 items: linear sum is O(n) = 10,000 operations per scroll calculation; Fenwick tree is O(log n) = 14 operations.

### 12.4 Masonry and Grid Virtualization Complexity

Grid layouts add a second dimension. For an m-column grid, the virtual window spans multiple columns simultaneously:

```
Items rendered = ceil(windowHeight / itemHeight) × columns
For 3-col grid, 600px viewport, 150px items, windowSize=5:
  Visible rows: 600/150 = 4 rows
  Visible items: 4 × 3 = 12
  With windowSize=5: (4 × 5) × 3 = 60 items rendered total
```

Masonry layout (Pinterest-style varying heights per column) cannot precompute row positions because column heights diverge. The algorithm must track the current height of each column and assign items to the shortest column — a greedy O(n log m) algorithm using a min-heap of column heights:

```tsx
// O(n log m) masonry column assignment
// n = items, m = columns
function assignMasonryColumns<T>(
  items: T[],
  getHeight: (item: T) => number,
  columnCount: number
): T[][] {
  const columns: T[][] = Array.from({ length: columnCount }, () => []);
  const columnHeights = new Array(columnCount).fill(0);

  for (const item of items) {
    // Find shortest column — O(m), acceptable for m ≤ 4
    // For large m use a min-heap: O(log m) per item
    const shortestCol = columnHeights.indexOf(Math.min(...columnHeights));
    columns[shortestCol].push(item);
    columnHeights[shortestCol] += getHeight(item);
  }

  return columns; // each column is its own virtualised list
}
```

Render each column as a separate `FlashList` with `horizontal={false}`. This gives O(n/m) items per virtualised list — each list is m times shorter.

### 12.5 windowSize Multiplier — Practical Guide

```tsx
// Low-memory device (< 3GB RAM) — minimise rendered items
<FlatList windowSize={3} maxToRenderPerBatch={5} removeClippedSubviews />

// Default — balanced for mid-range devices
<FlatList windowSize={21} maxToRenderPerBatch={10} />

// Fast-scrolling carousels — pre-render more to prevent blank frames
<FlatList windowSize={41} maxToRenderPerBatch={20} initialNumToRender={20} />

// Rule of thumb:
// windowSize=N renders (N-1)/2 viewports above AND below the current position
// windowSize=5  → 2 above, 2 below (good for most cases)
// windowSize=21 → 10 above, 10 below (default, allows fast fling)
// windowSize=41 → 20 above, 20 below (maximises pre-render; costs memory)
```

Memory cost scales linearly with `windowSize`. For 100 items × 80px each, `windowSize=21` renders roughly 21 × (600/80) ≈ 157 items at most — a 43% saving over rendering all 100 visible-height items would imply for a tall list.

---

## 13. Fuzzy Search and Text Algorithms

### 13.1 Levenshtein Distance with Bounds Optimisation

Naive Levenshtein is O(n×m) where n and m are string lengths. Two optimisations dramatically cut practical cost:

1. **Early termination**: if the running minimum exceeds a threshold, abandon the computation
2. **Only compute the diagonal band**: if max distance is k, only the 2k+1 diagonal cells matter

```tsx
// Bounded Levenshtein — O(n × min(m, 2k+1)) where k is the max allowed distance
// Returns Infinity if distance exceeds maxDist (avoids full O(n×m) when clearly too far)
function levenshteinBounded(a: string, b: string, maxDist: number): number {
  if (Math.abs(a.length - b.length) > maxDist) return Infinity; // O(1) early exit

  const n = a.length;
  const m = b.length;

  // Allocate single row — O(m) space instead of O(n×m)
  let prev = new Uint16Array(m + 1);
  let curr = new Uint16Array(m + 1);

  for (let j = 0; j <= m; j++) prev[j] = j;

  for (let i = 1; i <= n; i++) {
    curr[0] = i;
    let rowMin = i;

    // Only compute the band [i-maxDist, i+maxDist]
    const jStart = Math.max(1, i - maxDist);
    const jEnd = Math.min(m, i + maxDist);

    if (jStart > 1) curr[jStart - 1] = Infinity; // guard the left edge

    for (let j = jStart; j <= jEnd; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      curr[j] = Math.min(
        curr[j - 1] + 1,          // insertion
        prev[j] + 1,              // deletion
        prev[j - 1] + cost        // substitution
      );
      if (curr[j] < rowMin) rowMin = curr[j];
    }

    if (rowMin > maxDist) return Infinity; // prune entire remaining computation

    [prev, curr] = [curr, prev]; // swap buffers without allocation
  }

  return prev[m] <= maxDist ? prev[m] : Infinity;
}

// Big-O comparison:
// Naive Levenshtein:   O(n × m)               — always full matrix
// Bounded Levenshtein: O(n × min(m, 2k+1))    — prunes rows early
// For n=m=20, k=2: naive = 400 ops; bounded = 20 × 5 = 100 ops (4x faster)
```

### 13.2 Jaro-Winkler Similarity

Jaro-Winkler is O(n+m) — faster than Levenshtein — and optimised for short strings (names, usernames). It gives higher scores to strings that share a common prefix, which matches user typing behaviour:

```tsx
// O(n + m) — suitable for real-time scoring of short strings (names, tags)
function jaroWinkler(s1: string, t: string, prefixScale = 0.1): number {
  const s = s1.toLowerCase();
  const tt = t.toLowerCase();

  if (s === tt) return 1;
  if (s.length === 0 || tt.length === 0) return 0;

  const matchDist = Math.max(Math.floor(Math.max(s.length, tt.length) / 2) - 1, 0);
  const sMatches = new Uint8Array(s.length);
  const tMatches = new Uint8Array(tt.length);
  let matches = 0;
  let transpositions = 0;

  // Find matching characters within matchDist window — O(n×m) worst case but bounded
  for (let i = 0; i < s.length; i++) {
    const start = Math.max(0, i - matchDist);
    const end = Math.min(i + matchDist + 1, tt.length);
    for (let j = start; j < end; j++) {
      if (tMatches[j] || s[i] !== tt[j]) continue;
      sMatches[i] = 1;
      tMatches[j] = 1;
      matches++;
      break;
    }
  }

  if (matches === 0) return 0;

  let k = 0;
  for (let i = 0; i < s.length; i++) {
    if (!sMatches[i]) continue;
    while (!tMatches[k]) k++;
    if (s[i] !== tt[k]) transpositions++;
    k++;
  }

  const jaro =
    (matches / s.length +
      matches / tt.length +
      (matches - transpositions / 2) / matches) /
    3;

  // Winkler prefix bonus — up to 4 characters
  let prefix = 0;
  for (let i = 0; i < Math.min(4, Math.min(s.length, tt.length)); i++) {
    if (s[i] === tt[i]) prefix++;
    else break;
  }

  return jaro + prefix * prefixScale * (1 - jaro);
}

// Usage: score all items and sort by similarity
function rankByJaroWinkler(items: string[], query: string): string[] {
  return items
    .map(item => ({ item, score: jaroWinkler(query, item) }))
    .filter(({ score }) => score > 0.75)        // threshold: tune per domain
    .sort((a, b) => b.score - a.score)
    .map(({ item }) => item);
}
// O(n × (s+m)) total — n items, s=query length, m=item length
```

Jaro-Winkler is better than Levenshtein for name matching ("Jon" → "John", score 0.93) and worse for substring matching ("react" in "react-native"). Choose based on your dataset.

### 13.3 Trie-Based Autocomplete with Ranked Results

Extending the Trie from Section 2.3 with frequency-ranked results and Unicode normalisation:

```tsx
interface TrieEntry {
  value: string;
  frequency: number; // higher = more common; surfaces popular results first
}

class RankedTrie {
  private root: TrieNode<TrieEntry> = new TrieNode();

  // O(m) — normalise to NFC before insert for Unicode consistency
  insert(word: string, frequency = 1): void {
    const normalised = word.normalize('NFC').toLowerCase();
    let node = this.root;
    for (const ch of normalised) {
      if (!node.children.has(ch)) node.children.set(ch, new TrieNode());
      node = node.children.get(ch)!;
    }
    node.isEnd = true;
    // Accumulate frequency (e.g., from usage analytics)
    node.entry = { value: word, frequency: (node.entry?.frequency ?? 0) + frequency };
  }

  // O(m + k log k) — traverse to prefix, collect top-k by frequency
  search(prefix: string, limit = 10): TrieEntry[] {
    const normalised = prefix.normalize('NFC').toLowerCase();
    let node = this.root;
    for (const ch of normalised) {
      if (!node.children.has(ch)) return [];
      node = node.children.get(ch)!;
    }

    const results: TrieEntry[] = [];
    this.collectRanked(node, results, limit);
    return results.sort((a, b) => b.frequency - a.frequency).slice(0, limit);
  }

  private collectRanked(node: TrieNode<TrieEntry>, results: TrieEntry[], limit: number): void {
    if (results.length >= limit * 3) return; // collect 3x then sort-slice
    if (node.isEnd && node.entry) results.push(node.entry);
    for (const child of node.children.values()) {
      this.collectRanked(child, results, limit);
    }
  }
}
```

### 13.4 Locale-Aware Sorting and localeCompare Pitfalls

`Array.sort` with a plain `<`/`>` comparison uses Unicode code points — incorrect for any non-ASCII text:

```tsx
// BAD: code-point sort — wrong for accented characters and many locales
const names = ['Ångström', 'Zebra', 'apple', 'Banana'];
names.sort(); // ['Banana', 'Zebra', 'apple', 'Ångström'] — 'Å' sorts after 'Z'

// BAD: localeCompare without options — browser/OS dependent, slow, inconsistent
names.sort((a, b) => a.localeCompare(b)); // varies by device locale

// GOOD: explicit locale + options — deterministic, correct
const collator = new Intl.Collator('en', {
  sensitivity: 'base',    // 'a' === 'A' === 'á' for sorting purposes
  numeric: true,          // '10' > '9' (not '1' < '9' lexicographically)
  ignorePunctuation: true,
});
names.sort((a, b) => collator.compare(a, b));
// Result: ['apple', 'Ångström', 'Banana', 'Zebra'] — alphabetically correct

// Performance: create Intl.Collator ONCE outside the sort — not per comparison
// BAD: new Intl.Collator per comparison = O(n log n) × constructor cost
names.sort((a, b) => new Intl.Collator('en').compare(a, b)); // avoid

// For case-insensitive sort: sensitivity: 'base' treats a/A/á as equal
// For case-sensitive sort: sensitivity: 'variant' distinguishes all
```

Intl.Collator construction is O(locale data load) — create it once at module or hook level, not inside the comparator.

### 13.5 Optimised Fuzzy Search for Large Lists

Combining Trie (exact prefix), layered strategy (Section 2.4), and Jaro-Winkler (fuzzy) for production-quality search over large datasets:

```tsx
// Full optimised search pipeline for lists up to ~50,000 items
// Total complexity: O(m) Trie prefix + O(n) fallback (rarely reached) + O(k log k) rank

interface SearchResult<T> {
  item: T;
  score: number;
  matchType: 'prefix' | 'contains' | 'fuzzy';
}

function createSearchEngine<T>(
  items: T[],
  getText: (item: T) => string
) {
  // Build Trie once — O(n × avg_length)
  const trie = new RankedTrie();
  const textMap = new Map<string, T>();

  for (const item of items) {
    const text = getText(item).normalize('NFC').toLowerCase();
    trie.insert(text);
    textMap.set(text, item);
  }

  // Collator created once for the entire search session
  const collator = new Intl.Collator('en', { sensitivity: 'base', numeric: true });

  return function search(query: string, limit = 20): SearchResult<T>[] {
    const q = query.normalize('NFC').toLowerCase().trim();
    if (q.length === 0) return [];

    const results: SearchResult<T>[] = [];
    const seen = new Set<T>();

    // Pass 1: Trie prefix — O(m + k)
    const prefixHits = trie.search(q, limit);
    for (const hit of prefixHits) {
      const item = textMap.get(hit.value.toLowerCase());
      if (item && !seen.has(item)) {
        results.push({ item, score: hit.frequency + 1000, matchType: 'prefix' });
        seen.add(item);
      }
    }

    if (results.length >= limit) {
      return results.sort((a, b) => b.score - a.score).slice(0, limit);
    }

    // Pass 2: substring contains — O(n × m)
    for (const item of items) {
      if (seen.has(item)) continue;
      const text = getText(item).toLowerCase();
      if (text.includes(q)) {
        results.push({ item, score: 500, matchType: 'contains' });
        seen.add(item);
      }
    }

    if (results.length >= limit) {
      return results.sort((a, b) => b.score - a.score).slice(0, limit);
    }

    // Pass 3: Jaro-Winkler fuzzy — O(n × (m + avg_item_len))
    const THRESHOLD = 0.78;
    for (const item of items) {
      if (seen.has(item)) continue;
      const text = getText(item).toLowerCase();
      const score = jaroWinkler(q, text);
      if (score >= THRESHOLD) {
        results.push({ item, score: score * 100, matchType: 'fuzzy' });
        seen.add(item);
      }
    }

    return results
      .sort((a, b) =>
        b.score !== a.score
          ? b.score - a.score
          : collator.compare(getText(a.item), getText(b.item))
      )
      .slice(0, limit);
  };
}

// Usage — build once, query on every keystroke with debounce
const search = useMemo(
  () => createSearchEngine(catalogue, item => item.name),
  [catalogue]
);

const debouncedSearch = useMemo(
  () => debounce((q: string) => setResults(search(q)), 150, { maxWait: 400 }),
  [search]
);
```

Big-O summary: prefix path is O(m + k), avoids O(n) entirely for the common case. The O(n) passes are reached only when fewer than `limit` prefix matches exist — typically rare in well-indexed data.

---

## 14. Batch Processing Patterns

### 14.1 Chunking Large Datasets with requestAnimationFrame

Processing 10,000 items synchronously blocks the JS thread for the entire duration. Chunking with `requestAnimationFrame` yields between chunks, keeping the app responsive:

```tsx
// Generic rAF-chunked processor — keeps each chunk within a ~16ms frame budget
// O(n) total work, spread across ceil(n / chunkSize) frames
interface ChunkOptions<T, R> {
  items: T[];
  process: (item: T, index: number) => R;
  chunkSize?: number;
  onProgress?: (processed: number, total: number) => void;
  onComplete?: (results: R[]) => void;
}

function processInFrames<T, R>({
  items,
  process,
  chunkSize = 100,
  onProgress,
  onComplete,
}: ChunkOptions<T, R>): () => void {
  const results: R[] = new Array(items.length);
  let index = 0;
  let rafId: number;

  function tick(): void {
    const end = Math.min(index + chunkSize, items.length);
    const t0 = performance.now();

    // Process up to chunkSize items, but bail if over 12ms (leave headroom)
    while (index < end && performance.now() - t0 < 12) {
      results[index] = process(items[index], index);
      index++;
    }

    onProgress?.(index, items.length);

    if (index < items.length) {
      rafId = requestAnimationFrame(tick); // yield frame, continue next tick
    } else {
      onComplete?.(results);
    }
  }

  rafId = requestAnimationFrame(tick);

  // Return cancel function
  return () => cancelAnimationFrame(rafId);
}

// Usage: transform 10,000 feed items without blocking UI
const [progress, setProgress] = useState(0);
const [items, setItems] = useState<ProcessedItem[]>([]);

useEffect(() => {
  const cancel = processInFrames({
    items: rawFeedData,
    process: item => ({ ...item, formattedDate: formatDate(item.createdAt) }),
    chunkSize: 200,
    onProgress: (done, total) => setProgress(done / total),
    onComplete: setItems,
  });
  return cancel; // cancel if component unmounts during processing
}, [rawFeedData]);
```

Chunk size tuning: 100–200 items at ~0.05ms each = 5–10ms per frame, leaving 6–11ms for React rendering and native layout. Measure with `performance.now()` and adapt dynamically (as shown above) rather than hardcoding.

### 14.2 Sliding Window Algorithms for Moving Averages

A naive moving average recalculates the sum over the entire window on every new data point — O(k) per update. A sliding window approach adds the new value and subtracts the evicted value — O(1) per update:

```tsx
// O(k) initialisation, O(1) per subsequent update
class SlidingWindowAverage {
  private buffer: Float64Array;
  private head = 0;
  private sum = 0;
  private count = 0;

  constructor(private readonly windowSize: number) {
    this.buffer = new Float64Array(windowSize); // circular buffer
  }

  // O(1) — add new value, evict oldest
  push(value: number): number {
    const evicted = this.buffer[this.head];
    this.buffer[this.head] = value;
    this.head = (this.head + 1) % this.windowSize;
    this.sum += value - evicted;
    if (this.count < this.windowSize) this.count++;
    return this.sum / this.count; // current average
  }

  get average(): number {
    return this.count === 0 ? 0 : this.sum / this.count;
  }
}

// Usage: real-time frame rate monitoring
const fpsTracker = new SlidingWindowAverage(60); // 60-frame rolling average

useEffect(() => {
  let lastTime = performance.now();
  let rafId: number;

  function frame(): void {
    const now = performance.now();
    const fps = 1000 / (now - lastTime);
    const avgFps = fpsTracker.push(fps); // O(1)
    lastTime = now;

    if (avgFps < 50) reportFrameDrop(avgFps); // alert on sustained jank
    rafId = requestAnimationFrame(frame);
  }

  rafId = requestAnimationFrame(frame);
  return () => cancelAnimationFrame(rafId);
}, []);
```

For a window of k=60 and n=10,000 data points: naive approach is O(k×n) = 600,000 operations; sliding window is O(k) init + O(n) updates = 10,060 operations.

### 14.3 Partition and GroupBy for Categorisation Before Processing

Partition once into buckets, then process each bucket independently. This avoids rescanning the full dataset for each category:

```tsx
// O(n) single pass — partition into all categories simultaneously
function groupBy<T, K extends string | number>(
  items: T[],
  getKey: (item: T) => K
): Map<K, T[]> {
  const groups = new Map<K, T[]>();
  for (const item of items) {
    const key = getKey(item);
    let group = groups.get(key);
    if (!group) {
      group = [];
      groups.set(key, group);
    }
    group.push(item);
  }
  return groups; // O(n) total — one pass, all groups
}

// O(n) — partition into exactly two buckets (generalised filter)
function partition<T>(
  items: T[],
  predicate: (item: T) => boolean
): [T[], T[]] {
  const pass: T[] = [];
  const fail: T[] = [];
  for (const item of items) {
    (predicate(item) ? pass : fail).push(item);
  }
  return [pass, fail]; // O(n), single pass
}

// Usage: categorise 10,000 orders for parallel display
const ordersByStatus = useMemo(
  () => groupBy(orders, order => order.status),
  [orders]
);
// O(n) once — then O(1) per category access

const [inStock, outOfStock] = useMemo(
  () => partition(products, p => p.stock > 0),
  [products]
);

// BAD alternative — O(k × n) for k categories:
const pending  = orders.filter(o => o.status === 'pending');   // O(n)
const shipped  = orders.filter(o => o.status === 'shipped');   // O(n) again
const returned = orders.filter(o => o.status === 'returned');  // O(n) again
// 3 categories = 3 full passes; groupBy does all 3 in 1 pass
```

### 14.4 Lazy Evaluation Patterns

Avoid computing values that may never be consumed. In JavaScript, lazy evaluation is achieved with functions, generators, and `useMemo` with careful dependency scoping:

```tsx
// Generator-based lazy sequence — items computed only when consumed
function* lazyTransform<T, R>(
  source: Iterable<T>,
  transform: (item: T) => R,
  filter?: (item: T) => boolean
): Generator<R> {
  for (const item of source) {
    if (!filter || filter(item)) {
      yield transform(item); // O(1) per consumed item — never computes all at once
    }
  }
}

// Usage: only transform items that end up in the visible window
const visibleItemGen = lazyTransform(
  allItems,                                    // 50,000 items
  item => expensiveTransform(item),            // only called for items passed to FlatList
  item => item.category === selectedCategory   // filter in the generator
);

// Consume only the first 100 (FlatList initial render)
const initialItems: TransformedItem[] = [];
for (const item of visibleItemGen) {
  initialItems.push(item);
  if (initialItems.length >= 100) break; // stop consuming — rest never computed
}
// O(filter_cost × 100) rather than O(transform_cost × 50,000)

// Lazy object property — computed only on first access
function createLazyReport(data: RawData) {
  let _summary: Summary | undefined;
  let _chart: ChartData | undefined;

  return {
    get summary() {
      if (!_summary) _summary = computeExpensiveSummary(data); // O(n) once
      return _summary;
    },
    get chart() {
      if (!_chart) _chart = buildChartData(data); // O(n log n) once
      return _chart;
    },
    raw: data,
  };
}
// If the user never opens the chart tab, buildChartData is never called
```

### 14.5 Batch Processing 10,000 Items Without Blocking UI — Full Example

A complete pipeline combining chunking, progress tracking, cancellation, and result streaming into a FlatList:

```tsx
// hooks/useBatchProcessor.ts
interface BatchState<R> {
  results: R[];
  progress: number; // 0–1
  isProcessing: boolean;
}

function useBatchProcessor<T, R>(
  items: T[],
  process: (item: T) => R,
  chunkSize = 150
): BatchState<R> {
  const [state, setState] = useState<BatchState<R>>({
    results: [],
    progress: 0,
    isProcessing: false,
  });

  useEffect(() => {
    if (items.length === 0) return;

    // Pre-allocate result array — avoids repeated reallocation during processing
    const results: R[] = new Array(items.length);
    let index = 0;
    let rafId: number;

    setState(s => ({ ...s, isProcessing: true, progress: 0, results: [] }));

    function tick(): void {
      const t0 = performance.now();

      // Time-budget chunk: process items until 12ms budget consumed
      while (index < items.length && performance.now() - t0 < 12) {
        results[index] = process(items[index]);
        index++;
      }

      const progress = index / items.length;

      if (index < items.length) {
        // Stream partial results every 10% to unblock FlatList rendering
        if (Math.floor(progress * 10) > Math.floor((index - chunkSize) / items.length * 10)) {
          setState({ results: results.slice(0, index), progress, isProcessing: true });
        } else {
          setState(s => ({ ...s, progress }));
        }
        rafId = requestAnimationFrame(tick);
      } else {
        // Final: deliver all results
        setState({ results: results.slice(), progress: 1, isProcessing: false });
      }
    }

    rafId = requestAnimationFrame(tick);

    return () => {
      cancelAnimationFrame(rafId);
      setState(s => ({ ...s, isProcessing: false }));
    };
  }, [items, process, chunkSize]);

  return state;
}

// Screen usage
function CatalogueScreen({ rawItems }: { rawItems: RawItem[] }) {
  const { results, progress, isProcessing } = useBatchProcessor(
    rawItems,
    item => ({
      ...item,
      formattedPrice: formatCurrency(item.priceCents),
      imageUri: buildImageUri(item.imageKey, 'thumbnail'),
      searchKey: item.name.normalize('NFC').toLowerCase(),
    })
  );

  return (
    <View style={{ flex: 1 }}>
      {isProcessing && (
        <ProgressBar value={progress} style={styles.progress} />
      )}
      <FlashList
        data={results}                    // grows as chunks complete
        renderItem={({ item }) => <CatalogueCard item={item} />}
        estimatedItemSize={96}
        keyExtractor={item => item.id}
      />
    </View>
  );
}

// Big-O summary:
// Total work: O(n × transform_cost) — unchanged from synchronous approach
// JS-thread block per frame: O(chunk) ≈ O(150) — bounded, never O(n)
// Frames dropped: 0 — each chunk fits within 16ms budget
// Time to first render: O(150 × transform_cost) — first chunk, not O(n)
```
