# Rendering Performance

## 1. Understanding Re-renders

### React Reconciliation in React Native

React uses a two-phase reconciliation process: **render** (compute the new element tree) and **commit** (apply changes). In React Native the commit phase does not touch a DOM — it sends a serialized diff over the JS bridge (old architecture) or synchronously via JSI/Fabric (new architecture) to create or update **native views**. Native view creation is significantly more expensive than DOM node mutation, so keeping renders minimal is critical.

Reconciliation rules that apply identically to web and RN:
- Same component type at the same position → update (preserve instance, diff props)
- Different component type → unmount old, mount new (expensive)
- `key` change → unmount + remount even for same type

### What Triggers a Re-render

| Trigger | Notes |
|---|---|
| `setState` / `useState` setter | Even if the new value is the same object reference, React re-renders by default |
| `useReducer` dispatch | Re-renders unless the reducer returns the same state reference |
| Parent re-renders | Children re-render unless wrapped in `React.memo` |
| Context value change | Every consumer re-renders when the context object reference changes |
| `useContext` | Re-renders on any change to the context value, even unrelated fields |
| `forceUpdate` | Always triggers a re-render |

### Identifying Unnecessary Re-renders

**React DevTools Profiler** — record a session and look for components that render with no prop/state change (shown as "rendered by parent"). The flame graph highlights which component took the most time.

**why-did-you-render** — install the library and annotate components to log the exact props/state that changed:

```tsx
// wdyr.ts — import before anything else in index.js
import React from 'react';
import whyDidYouRender from '@welldone-software/why-did-you-render';

if (__DEV__) {
  whyDidYouRender(React, {
    trackAllPureComponents: false, // opt-in per component only
    logOwnerReasons: true,
  });
}

// In the component file:
const ProductCard = ({ id, title }: Props) => <View>...</View>;
ProductCard.whyDidYouRender = true;
export default ProductCard;
```

**Flashlight** — CLI tool that runs on a real device and records FPS, JS thread, UI thread, and CPU in a single session. Better than simulator profiling for Android.

### Cost of Re-renders in React Native vs Web

In the browser a re-render computes a virtual DOM diff and patches real DOM nodes — a mature, well-optimized path. In RN:

1. JS thread executes component functions (same cost as web)
2. A serialized layout/style payload is sent over the bridge or JSI
3. **Native side creates or updates native views** — this involves iOS UIView / Android View allocation, measure/layout passes, and drawing

Native view creation is orders of magnitude more expensive than DOM node creation. A list row that re-renders 10 times unnecessarily will stutter visibly on mid-range Android devices even when the re-render itself is fast on JS.

---

## 2. Memoization Techniques

### React.memo

Wraps a component and skips re-rendering when all props are shallowly equal. Only effective when **every prop** is stable across renders.

```tsx
// Correct — parent passes a stable callback (useCallback) and primitive price
const ProductCard = React.memo(({ id, title, price, onPress }: Props) => {
  return (
    <Pressable onPress={onPress}>
      <Text>{title}</Text>
      <Text>{price}</Text>
    </Pressable>
  );
});

// Anti-pattern — memo is useless because onPress is re-created every render
const Parent = () => {
  const [count, setCount] = useState(0);
  return <ProductCard onPress={() => navigate(id)} ... />; // new ref every time
};
```

**Custom comparator** — use when shallow equality is too strict (e.g., deep object comparison) or too loose (you need referential equality for a specific field):

```tsx
const areEqual = (prev: Props, next: Props) =>
  prev.id === next.id && prev.selected === next.selected;
// Ignores all other prop changes — only re-render on id/selected change
export default React.memo(SelectableRow, areEqual);
```

### useCallback

Stabilizes a function reference across renders so memo'd children don't re-render:

```tsx
const ProductList = () => {
  const navigation = useNavigation();

  // Without useCallback: new function every render → all ProductCard children re-render
  const handlePress = useCallback(
    (id: string) => navigation.navigate('Product', { id }),
    [navigation], // navigation from useNavigation is stable
  );

  return (
    <FlashList
      data={products}
      renderItem={({ item }) => (
        <ProductCard id={item.id} title={item.title} onPress={handlePress} />
      )}
    />
  );
};
```

### useMemo

For **expensive computations** that shouldn't repeat on every render — filtering, sorting, or computing derived data from large arrays:

```tsx
const FilteredList = ({ items, query, sortKey }: Props) => {
  const filtered = useMemo(
    () =>
      items
        .filter((i) => i.name.toLowerCase().includes(query.toLowerCase()))
        .sort((a, b) => a[sortKey].localeCompare(b[sortKey])),
    [items, query, sortKey],
  );

  return <FlashList data={filtered} renderItem={renderItem} estimatedItemSize={72} />;
};
```

Do NOT use `useMemo` for cheap derivations — the overhead of creating the memo and comparing dependencies can exceed the cost of the computation itself.

### React Compiler Deep Dive (RN 0.78+ / Expo SDK 53+)

The React Compiler (formerly React Forget) statically analyses component code and automatically inserts memoization at the correct granularity. When enabled you can remove most manual `React.memo`, `useCallback`, and `useMemo` calls.

```bash
# Enable in babel.config.js (Expo SDK 53+)
# The compiler is enabled by default; opt-out per file with:
# 'use no memo';
```

```tsx
// With React Compiler — no manual memo needed
// The compiler will infer that handlePress only changes when navigation changes
const ProductList = ({ products }: Props) => {
  const navigation = useNavigation();

  const handlePress = (id: string) => navigation.navigate('Product', { id });

  return (
    <FlashList
      data={products}
      renderItem={({ item }) => (
        <ProductCard id={item.id} onPress={handlePress} />
      )}
      estimatedItemSize={80}
    />
  );
};
```

#### Rules for When the Compiler CAN Infer Memoization

The compiler can memoize a value or callback when:

- All values it depends on are **local** to the component or hook (props, state, other local variables)
- The function body follows the **Rules of React**: no mutation of existing values, no reading outside render (side effects)
- Dependencies flow through **pure expressions** — arithmetic, ternary, template literals, object/array literals, function calls that are themselves pure

```tsx
// Compiler CAN memoize — pure derivation from props
const ProductCard = ({ price, discount }: Props) => {
  const finalPrice = price * (1 - discount); // pure, compiler memoizes this
  const label = finalPrice < 10 ? 'Budget' : 'Premium'; // also pure
  return <Text>{label}: ${finalPrice}</Text>;
};
```

#### Rules for When the Compiler CANNOT Infer Memoization

The compiler **bails out** (gives up on the whole component or a subtree) when it encounters:

| Pattern | Why it fails |
|---|---|
| Mutation of a local object or array | `arr.push(x)` violates immutability assumption |
| Reading from a mutable external ref during render | `ref.current` read in the render path |
| Dynamic property access on an unknown type | `obj[dynamicKey]` — compiler cannot track the dependency |
| Calling a non-pure external function | `Math.random()`, `Date.now()`, `console.log` in the render path |
| `try/catch` wrapping render logic | Control flow is too complex to analyse |
| Generators or async component bodies | Not supported in React 19 |

```tsx
// Compiler CANNOT memoize — mutates local array
const BadList = ({ items }: Props) => {
  const sorted = items; // same reference
  sorted.sort((a, b) => a.name.localeCompare(b.name)); // mutation — bail out!
  return <FlashList data={sorted} renderItem={renderItem} estimatedItemSize={60} />;
};

// Fix — create a new array
const GoodList = ({ items }: Props) => {
  const sorted = [...items].sort((a, b) => a.name.localeCompare(b.name));
  return <FlashList data={sorted} renderItem={renderItem} estimatedItemSize={60} />;
};
```

#### `'use no memo'` Directive — When to Use It

The directive tells the compiler to skip a file entirely. Use it when:

- The component intentionally manages its own memoization with custom comparators (`React.memo(C, areEqual)`) that the compiler would override
- A third-party HOC or decorator pattern confuses the compiler's bailout analysis
- You are debugging a regression introduced by compiler-generated memoization and need to bisect quickly
- The component relies on mutating refs or external stores in ways the compiler cannot model

```tsx
'use no memo'; // must be the very first statement in the file

// All components in this file are compiled without React Compiler
export const SpecializedChart = ({ data }: Props) => {
  // ... complex D3-like imperative code with controlled mutation
};
```

Scope it as narrowly as possible — prefer file-level opt-out over disabling the compiler globally.

#### Performance Comparison: Manual Memo vs Compiler-Generated

| Scenario | Manual `useCallback` + `React.memo` | React Compiler |
|---|---|---|
| Correct dependencies | Correct if you don't miss any | Always correct — static analysis |
| Stale closure risk | High (common bug) | None |
| Over-memoization | Common (developers add "just in case") | Minimal — compiler is precise |
| Under-memoization | Common (developers forget) | None — compiler is exhaustive |
| Bundle size overhead | None | Small (~5 KB runtime helper) |
| Dev experience | Verbose, error-prone | Clean, no annotations |

In practice the compiler generates **more granular** memoization than developers do manually — it can memoize individual JSX expressions inside a component rather than the whole return value.

#### Known Limitations in React 19 / RN 0.78

- **Class components** are not supported — the compiler only handles function components and hooks
- **`forwardRef`** wrapping is supported but the compiler cannot memoize the inner render function independently; wrap with `React.memo` manually if needed
- **Custom hooks that call native modules** (e.g., `useAnimatedValue`) are not always correctly identified as pure — the compiler may bail out
- **Reanimated shared values** accessed during render (`sharedValue.value`) cause bailouts because they are mutable external references
- **Dynamic `require()` calls** inside a component body block memoization
- The compiler **does not** optimise across module boundaries — it sees each file in isolation

#### Debugging When the Compiler Fails to Memoize

**Step 1 — Enable compiler annotations in dev builds:**

```bash
# In babel.config.js
const { compiler } = require('@react-compiler/babel-plugin');
module.exports = {
  plugins: [
    [compiler, { logger: { logEvent: (filename, event) => console.log(filename, event) } }],
  ],
};
```

**Step 2 — Use the React DevTools "Compiler" panel** (available in React DevTools 5+). Components that were successfully compiled show a lightning bolt badge. Components that bailed out show a warning with the reason.

**Step 3 — Read the compiler's bailout reason in the console:**

```
ReactCompilerBailout: Mutating a value returned from a hook is not allowed.
  at FilteredList (FilteredList.tsx:14)
```

**Step 4 — Fix the pattern or add `'use no memo'` to the file while you investigate.**

Common fixes:

```tsx
// Bailout: mutation
// Bad
const tags = useTags(); tags.push(newTag);
// Good
const tags = useTags(); const allTags = [...tags, newTag];

// Bailout: dynamic key access
// Bad
const value = config[dynamicKey];
// Good — cast or narrow the type so the compiler knows the shape
const value = (config as Record<string, string>)[dynamicKey];

// Bailout: reading ref.current in render
// Bad
if (scrollRef.current?.scrollY > 100) { ... }
// Good — read in an effect or event handler, store result in state
```

### When NOT to Memoize

- Components that always receive new props (memoization check runs, always misses — pure overhead)
- Cheap components rendering <5 simple elements
- Components that are already rarely re-rendered
- Inside `renderItem` anonymous functions — wrap the component itself instead

### Memoization Anti-patterns

```tsx
// Over-memoization: memoizing a trivial derivation
const label = useMemo(() => `${firstName} ${lastName}`, [firstName, lastName]);
// Just write: const label = `${firstName} ${lastName}`;

// Wrong deps: causes stale closure bugs
const fetchData = useCallback(async () => {
  const result = await api.get(endpoint); // endpoint not in deps
  setData(result);
}, []); // Should include [endpoint, setData]

// Memoizing an inline object in JSX — still a new ref at the call site
<Component style={useMemo(() => ({ flex: 1 }), [])} />
// Use StyleSheet.create instead
```

---

## 3. Lists: FlashList vs FlatList

### Performance Comparison

| Metric | FlatList | FlashList |
|---|---|---|
| JS thread FPS | baseline | ~7.5x better |
| CPU usage | baseline | -32% |
| Blank area during scroll | baseline | -50% (v2) |
| Memory for 1000 items | baseline | significantly lower (recycling) |

FlashList achieves this by **recycling native views** — a fixed pool of views is reused as items scroll off screen, eliminating native view allocation during scroll.

### FlashList Setup

```tsx
import { FlashList } from '@shopify/flash-list';

const Feed = ({ posts }: { posts: Post[] }) => {
  const renderItem = useCallback(
    ({ item }: { item: Post }) => <PostCard post={item} />,
    [],
  );

  return (
    <FlashList
      data={posts}
      renderItem={renderItem}
      estimatedItemSize={120}       // measure a real item and use that value
      keyExtractor={(item) => item.id}
      overrideItemType={(item) => item.type} // enable multi-type recycling
      getItemType={(item) => item.type}
    />
  );
};
```

`estimatedItemSize` is the single most important prop — wrong values cause layout thrashing on initial render. Measure a real rendered item and use that pixel height.

### FlashList v2 Improvements

FlashList v2 introduces **auto-sizing** — it measures items after first render and adjusts the recycling pool accordingly, making `estimatedItemSize` less critical. Recycling is also more aggressive with better handling of variable-height items and horizontal lists.

### FlatList Optimization (When You Must Use It)

```tsx
<FlatList
  data={items}
  renderItem={renderItem}
  keyExtractor={(item) => item.id}          // Never use index
  // Fixed-height items: skip measurement entirely
  getItemLayout={(_, index) => ({
    length: ITEM_HEIGHT,
    offset: ITEM_HEIGHT * index,
    index,
  })}
  // Rendering window tuning
  initialNumToRender={8}                    // visible items at start
  maxToRenderPerBatch={5}                   // items added per JS frame
  windowSize={5}                            // visible window multiplier (5 = 2 screens above + below)
  updateCellsBatchingPeriod={50}            // ms between batch renders
  removeClippedSubviews                     // unmount offscreen views (use carefully)
/>
```

### VirtualizedList Advanced Tuning

#### `windowSize` Internals

`windowSize` is a **screen-count multiplier** for the rendering window that VirtualizedList maintains around the visible area. A value of `N` means:

- Visible viewport = 1 screen height
- Pre-rendered zone above = `(N - 1) / 2` screen heights
- Pre-rendered zone below = `(N - 1) / 2` screen heights

So `windowSize={5}` keeps 2 screens above + 2 screens below the viewport rendered, for a total rendered window of 5 screens. Items outside this window are unmounted (if `removeClippedSubviews` is enabled) or simply not rendered.

```
windowSize=3 → 1 screen above, 1 below (aggressive — low memory, more blank on fast scroll)
windowSize=5 → 2 screens above, 2 below (default — good balance)
windowSize=11 → 5 screens above, 5 below (conservative — prevents blank areas on slow devices)
```

Increase `windowSize` on content-heavy feeds where users scroll in bursts. Decrease it on long static lists where memory is the constraint.

#### Optimal `maxToRenderPerBatch` by Device Class

`maxToRenderPerBatch` controls how many items are added to the render tree **per JS frame** (16.6 ms at 60 fps, 8.3 ms at 120 fps). Each batch is a synchronous chunk of work on the JS thread.

| Device class | Recommended value | Reasoning |
|---|---|---|
| Flagship (iPhone 15 Pro, Pixel 8 Pro) | 8–12 | JS thread is fast; render more to avoid blank areas |
| Mid-range (iPhone 12, Pixel 6a) | 4–6 | Keep batches short to stay under 16 ms frame budget |
| Low-end Android (<4 GB RAM) | 2–3 | JS thread is slow; large batches cause visible jank |

```tsx
import { Platform } from 'react-native';

// Rough device-class heuristic based on memory
const totalMemory = Platform.OS === 'android'
  ? (global as any).performance?.memory?.jsHeapSizeLimit ?? 512
  : 1024; // iOS doesn't expose this; assume adequate

const maxToRenderPerBatch = totalMemory > 800 ? 8 : totalMemory > 400 ? 5 : 3;
```

#### `updateCellsBatchingPeriod` and Frame Budgets

`updateCellsBatchingPeriod` (default: 50 ms) is the **inter-batch interval** — the minimum time VirtualizedList waits between consecutive batch renders. It interacts with `maxToRenderPerBatch` to form a throughput limit:

```
Items rendered per second ≈ maxToRenderPerBatch × (1000 / updateCellsBatchingPeriod)
Default: 5 × (1000 / 50) = 100 items/sec
```

At 60 fps you have 16.6 ms per frame. If a batch takes 15 ms to render, the remaining 1.6 ms is not enough for the next batch — so the batch period effectively enforces a minimum rest window. Increase `updateCellsBatchingPeriod` to reduce JS thread contention during rapid scroll:

```tsx
// Aggressive scrolling scenario — give more breathing room between batches
<FlatList
  updateCellsBatchingPeriod={100} // 100ms between batches
  maxToRenderPerBatch={6}         // larger batches less frequently
/>
```

#### `removeClippedSubviews` Gotchas

`removeClippedSubviews` unmounts native views for items outside the visible window. It can save significant memory on long lists but has important caveats:

- **Does not work with `overflow: visible` items** — if a cell has content that renders outside its bounds (e.g., a badge or popover), those will be clipped
- **Android only benefit** — on iOS the system is already good at off-screen view compression; the gain is smaller
- **Can cause blank flashes** during very fast scroll on slow devices — views unmount before the next batch renders
- **Breaks sticky items** — do not use with `stickyIndices`
- If a cell's height changes after initial render, `removeClippedSubviews` can cause layout jumps

```tsx
// Safe to use when:
// - All cells have fixed, predictable height
// - No overflow-visible content
// - No sticky indices
// - Targeting Android to reduce memory

// Avoid when:
// - Cells have tooltips, popovers, or overflow badges
// - Using stickyIndices
// - Users are fast-scrollers (causes blank areas)
<FlatList removeClippedSubviews={Platform.OS === 'android' && isFixedHeight} />
```

#### FlashList v2: Advanced Props

**`drawDistance`** — pixels beyond the visible area to pre-render (default: 250 px). Increase for fast-scrolling feeds, decrease for memory-constrained devices:

```tsx
<FlashList
  drawDistance={500}  // render 500px ahead of the visible edge
  ...
/>
```

**`overrideItemType`** — assign a string type to each item so FlashList can maintain **separate recycling pools** per type, preventing layout flicker when cells of different heights are recycled across types:

```tsx
type ItemType = 'image-post' | 'text-post' | 'ad';

<FlashList
  data={feed}
  overrideItemType={(item): ItemType => {
    if (item.kind === 'ad') return 'ad';
    return item.hasImage ? 'image-post' : 'text-post';
  }}
  renderItem={({ item }) => {
    if (item.kind === 'ad') return <AdCard ad={item} />;
    return item.hasImage ? <ImagePost post={item} /> : <TextPost post={item} />;
  }}
  estimatedItemSize={140}
/>
```

**Debugging blank areas in FlashList** — blank areas appear when `estimatedItemSize` is significantly wrong. Diagnose with the built-in warning:

```tsx
// FlashList logs a warning to console when measured sizes deviate significantly:
// "FlashList's rendered item height (320) is more than 30% different
//  from estimatedItemSize (120). Consider changing estimatedItemSize."

// Fix: measure a typical item at runtime and feed it back
const [measuredHeight, setMeasuredHeight] = useState(FALLBACK_HEIGHT);

<FlashList
  estimatedItemSize={measuredHeight}
  renderItem={({ item, index }) => (
    <ItemCell
      item={item}
      onLayout={index === 0 ? (e) => setMeasuredHeight(e.nativeEvent.layout.height) : undefined}
    />
  )}
/>
```

### SectionList Optimization

```tsx
<SectionList
  sections={sections}
  renderItem={renderItem}
  renderSectionHeader={renderSectionHeader}
  keyExtractor={(item) => item.id}
  stickySectionHeadersEnabled={false}       // disable if not needed (cheaper)
  getItemLayout={(data, index) => ({        // include section headers in offset calc
    length: ITEM_HEIGHT,
    offset: ITEM_HEIGHT * index,
    index,
  })}
/>
```

### MasonryFlashList for Grids

```tsx
import { MasonryFlashList } from '@shopify/flash-list';

<MasonryFlashList
  data={images}
  numColumns={2}
  renderItem={({ item }) => <ImageCard image={item} />}
  estimatedItemSize={200}
  optimizeItemArrangement  // reduces blank area by reordering items
/>
```

### Nested Lists — Why It's Bad and Alternatives

Nesting a `FlatList` inside a `ScrollView` disables virtualization on the inner list — all items render at once. On a list with 200 items this means 200 native views created immediately.

```tsx
// Anti-pattern
<ScrollView>
  <Header />
  <FlatList data={items} ... /> {/* Virtualization disabled! */}
</ScrollView>

// Fix option 1: ListHeaderComponent / ListFooterComponent
<FlatList
  data={items}
  ListHeaderComponent={<Header />}
  renderItem={renderItem}
/>

// Fix option 2: SectionList with typed sections
<SectionList
  sections={[{ title: 'header', data: [] }, { title: 'items', data: items }]}
  renderSectionHeader={({ section }) =>
    section.title === 'header' ? <Header /> : null
  }
  renderItem={renderItem}
/>
```

---

## 7. Complex Virtualization Patterns

### Grid Layouts with Variable Row Heights

Standard `FlatList` `numColumns` assumes uniform height across all items in a row — if one item is taller, the entire row height expands but layout can become inconsistent. The reliable approach is to split data into rows manually and render each row as a single item:

```tsx
// Utility: chunk flat array into rows
const chunk = <T,>(arr: T[], size: number): T[][] =>
  Array.from({ length: Math.ceil(arr.length / size) }, (_, i) =>
    arr.slice(i * size, i * size + size),
  );

const NUM_COLUMNS = 2;

const GridFeed = ({ items }: { items: Item[] }) => {
  const rows = useMemo(() => chunk(items, NUM_COLUMNS), [items]);

  return (
    <FlashList
      data={rows}
      estimatedItemSize={220}
      keyExtractor={(_, index) => String(index)}
      renderItem={({ item: row }) => (
        <View style={styles.row}>
          {row.map((item) => (
            <GridCell key={item.id} item={item} style={styles.cell} />
          ))}
          {/* Fill gap if last row is incomplete */}
          {row.length < NUM_COLUMNS && <View style={styles.cell} />}
        </View>
      )}
    />
  );
};

const styles = StyleSheet.create({
  row: { flexDirection: 'row', gap: 8, paddingHorizontal: 16 },
  cell: { flex: 1 },
});
```

### MasonryFlashList: Usage Patterns and Tuning

`MasonryFlashList` renders a Pinterest-style masonry grid where items fill the shortest column. Use it when items have genuinely variable heights (photo galleries, cards with varying text).

```tsx
import { MasonryFlashList } from '@shopify/flash-list';

type Photo = { id: string; uri: string; aspectRatio: number };

const PhotoGrid = ({ photos }: { photos: Photo[] }) => {
  const renderItem = useCallback(
    ({ item }: { item: Photo }) => {
      // Calculate height from aspect ratio so masonry can size the item
      const itemWidth = (Dimensions.get('window').width - 24) / 2; // 2 cols + gap
      const itemHeight = itemWidth / item.aspectRatio;
      return (
        <Image
          source={{ uri: item.uri }}
          style={{ width: itemWidth, height: itemHeight, borderRadius: 8 }}
          contentFit="cover"
        />
      );
    },
    [],
  );

  const overrideItemLayout = useCallback(
    (layout: { span?: number; size?: number }, item: Photo) => {
      const itemWidth = (Dimensions.get('window').width - 24) / 2;
      layout.size = itemWidth / item.aspectRatio; // tell FlashList the exact height upfront
    },
    [],
  );

  return (
    <MasonryFlashList
      data={photos}
      numColumns={2}
      renderItem={renderItem}
      overrideItemLayout={overrideItemLayout}
      estimatedItemSize={200}
      optimizeItemArrangement // shuffles items to minimise column height difference
      contentContainerStyle={{ padding: 8 }}
    />
  );
};
```

Key rule: always provide `overrideItemLayout` when you know the item height ahead of time — it eliminates layout recalculation passes and prevents blank area during initial render.

### Nested Lists: Why They Break Virtualization and Workarounds

A `FlatList`/`FlashList` inside a `ScrollView` loses its scroll context: it cannot measure how far it is from the viewport, so it **renders all its children immediately**. The same applies to a `FlatList` nested inside another `FlatList`.

#### Why Nested FlatList-in-FlatList Fails

```tsx
// Anti-pattern — horizontal carousel rows inside a vertical list
// Inner FlatList renders ALL items in every row on mount
const Feed = () => (
  <FlatList
    data={sections}
    renderItem={({ item }) => (
      <FlatList  // inner list — NO virtualization
        data={item.products}
        horizontal
        renderItem={renderProduct}
      />
    )}
  />
);
```

The outer list virtualises rows (good), but each row's inner list renders every product immediately (bad). 50 rows × 20 products = 1000 native views created on mount.

#### Workaround 1: Flatten into a SectionList

```tsx
// Convert nested structure into SectionList sections
const sections = categoryData.map((cat) => ({
  key: cat.id,
  title: cat.name,
  data: cat.products, // flat — SectionList handles it
}));

<SectionList
  sections={sections}
  keyExtractor={(item) => item.id}
  renderSectionHeader={({ section }) => <CategoryHeader title={section.title} />}
  renderItem={({ item }) => <ProductRow product={item} />}
  stickySectionHeadersEnabled={false}
/>
```

#### Workaround 2: Horizontal Scroll with Fixed Pool

For true horizontal carousels inside a vertical list, cap the horizontal list's item count and avoid `FlatList`. Use a plain `ScrollView` with a small, fixed number of items — carousels rarely exceed 10–15 visible items:

```tsx
const CategoryRow = React.memo(({ products }: { products: Product[] }) => (
  <ScrollView horizontal showsHorizontalScrollIndicator={false}>
    {products.slice(0, 15).map((p) => (
      <ProductCard key={p.id} product={p} />
    ))}
  </ScrollView>
));

// In the outer vertical list:
<FlashList
  data={categories}
  renderItem={({ item }) => <CategoryRow products={item.products} />}
  estimatedItemSize={180}
  overrideItemType={() => 'category-row'} // single pool for all rows
/>
```

### Waterfall/Masonry Grid Performance

Masonry grids are render-intensive because column assignment requires knowing item heights. Tips to keep them performant:

1. **Pre-compute heights server-side** — store `aspectRatio` or `height` on the data model so the client never needs to measure
2. **Use `overrideItemLayout`** on `MasonryFlashList` to skip the measurement cycle
3. **Avoid `optimizeItemArrangement` on paginated feeds** — it reorders items, which breaks stable `keyExtractor` identity when new pages append and causes FlashList to re-render existing items
4. **Limit column count on small screens** — 3+ columns on a 360-dp screen means ~110-dp cells; any content inside needs to be extremely simple or performance suffers

```tsx
const numColumns = Dimensions.get('window').width >= 600 ? 3 : 2;

<MasonryFlashList
  numColumns={numColumns}
  // Disable reordering on paginated data to keep item identity stable
  optimizeItemArrangement={false}
  overrideItemLayout={(layout, item) => {
    layout.size = COLUMN_WIDTH / item.aspectRatio;
  }}
  ...
/>
```

---

## 4. Image Optimization

### Library Comparison

| Feature | `expo-image` | `@d11/react-native-fast-image` | RN `Image` |
|---|---|---|---|
| Disk cache | Yes | Yes | No |
| Memory cache | Yes | Yes | Limited |
| Blurhash | Built-in | No | No |
| AVIF/WebP | Yes | Partial | No |
| Priority loading | Yes | Yes | No |
| Expo Go support | Yes | No | Yes |

Use `expo-image` in Expo projects — it covers all use cases and avoids a native module dependency.

### Format Priority

Serve images in order of preference: **AVIF > WebP > JPEG**. AVIF is ~50% smaller than JPEG at equivalent quality. Use CDN auto-format when possible.

```tsx
import { Image } from 'expo-image';

<Image
  source={{ uri: 'https://cdn.example.com/photo.jpg?f=auto&q=80&w=400' }}
  style={{ width: 200, height: 200 }}
  contentFit="cover"
  placeholder={{ blurhash: 'LGF5]+Yk^6#M@-5c,1Ex@@o#W.S2' }}
  transition={200}
  cachePolicy="memory-disk"
/>
```

### CDN Parameters

Always pass explicit dimensions and format to the CDN:

```tsx
const buildImageUrl = (baseUrl: string, width: number) =>
  `${baseUrl}?f=auto&q=auto&w=${width}&dpr=${PixelRatio.get()}`;

// Cloudinary example
const cloudinaryUrl = (publicId: string, w: number, h: number) =>
  `https://res.cloudinary.com/demo/image/upload/f_auto,q_auto,w_${w},h_${h},c_fill/${publicId}`;
```

### Android Memory Budget

A 1080×1920 JPEG decoded into memory occupies ~8 MB (1080 × 1920 × 4 bytes ARGB). A feed of 10 full-resolution images = 80 MB just for images. Always request thumbnail dimensions from the CDN:

```tsx
const THUMBNAIL_WIDTH = Math.round(Dimensions.get('window').width / 2);
// Request exactly what the view needs, not the original
const uri = `https://cdn.example.com/${id}?w=${THUMBNAIL_WIDTH}&f=auto`;
```

### Cache Strategies

```tsx
// expo-image cache policies
cachePolicy="none"          // never cache
cachePolicy="disk"          // disk only (survives app restarts)
cachePolicy="memory"        // memory only (fast, lost on restart)
cachePolicy="memory-disk"   // both (recommended for feeds)

// Prefetch images before they appear on screen
import { Image } from 'expo-image';
await Image.prefetch(['https://cdn.example.com/next-page-image.jpg']);

// Lazy load in lists — only load when close to viewport
<FlashList
  renderItem={({ item, index }) => (
    <Image
      source={{ uri: item.thumbnailUrl }}
      // expo-image handles lazy loading via its internal queue
      priority={index < 5 ? 'high' : 'normal'}
    />
  )}
/>
```

---

## 5. Component Architecture for Performance

### Decompose Large Components

Components over ~300 lines are a performance red flag — they re-render as a monolith when any internal state changes. Extract leaf components that only receive the props they need:

```tsx
// Before: monolithic card re-renders on any state change
const OrderCard = ({ order }: { order: Order }) => {
  const [expanded, setExpanded] = useState(false);
  // 350 lines of JSX mixing layout, logic, and formatting
};

// After: decomposed — only OrderActions re-renders when expanded changes
const OrderCard = ({ order }: { order: Order }) => {
  const [expanded, setExpanded] = useState(false);
  return (
    <View>
      <OrderHeader order={order} />
      <OrderSummary items={order.items} />
      <OrderActions expanded={expanded} onToggle={() => setExpanded((e) => !e)} />
    </View>
  );
};
```

### Container/Presentational Pattern

Separate data-fetching (container) from rendering (presentational). The presentational component can be `React.memo`'d without concern for query logic:

```tsx
// Container — handles data fetching and state
const ProductScreenContainer = ({ id }: { id: string }) => {
  const { data, isLoading } = useProduct(id);
  const { mutate: addToCart } = useAddToCart();

  if (isLoading) return <ProductSkeleton />;
  return <ProductScreen product={data} onAddToCart={addToCart} />;
};

// Presentational — pure, memoizable
const ProductScreen = React.memo(({ product, onAddToCart }: Props) => (
  <ScrollView>
    <ProductGallery images={product.images} />
    <ProductInfo product={product} />
    <AddToCartButton price={product.price} onPress={() => onAddToCart(product.id)} />
  </ScrollView>
));
```

### react-freeze for Offscreen Tabs

Tab navigators render all tab screens immediately and keep them mounted. Use `react-freeze` to suspend rendering of non-focused tabs without unmounting them (preserving scroll position and state):

```tsx
import { Freeze } from 'react-freeze';

const TabScreen = ({ isFocused, children }: { isFocused: boolean; children: React.ReactNode }) => (
  <Freeze freeze={!isFocused}>{children}</Freeze>
);
```

React Navigation 6+ integrates `react-freeze` automatically via `freezeOnBlur` prop on navigators.

### Error Boundaries

An error in one component can cascade re-renders across the tree during recovery. Use error boundaries to isolate failures:

```tsx
import { ErrorBoundary } from 'react-error-boundary';

const FeedSection = () => (
  <ErrorBoundary fallback={<SectionError />}>
    <ExpensiveList />
  </ErrorBoundary>
);
```

---

## 6. Style Performance

### StyleSheet.create vs Inline Styles

`StyleSheet.create` registers styles on the native side at module load time and passes integer IDs across the bridge instead of serialized objects. Inline styles serialize a new object on every render.

```tsx
// Benchmark (1000 renders of a View with one style prop):
// StyleSheet.create: ~2ms total
// Inline object: ~18ms total (9x slower at scale)

// Correct
const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#fff' },
  title: { fontSize: 18, fontWeight: '600' },
});
const Card = () => <View style={styles.container}><Text style={styles.title} /></View>;

// Anti-pattern — new object every render
const Card = () => <View style={{ flex: 1, backgroundColor: '#fff' }} />;
```

### useMemo for Dynamic Style Parts

When a style depends on runtime values (theme, props), compute it once:

```tsx
const Tag = ({ color, selected }: { color: string; selected: boolean }) => {
  const tagStyle = useMemo(
    () => ({
      ...styles.base,
      backgroundColor: selected ? color : 'transparent',
      borderColor: color,
    }),
    [color, selected],
  );

  return <View style={tagStyle} />;
};

const styles = StyleSheet.create({
  base: { paddingHorizontal: 8, paddingVertical: 4, borderRadius: 12, borderWidth: 1 },
});
```

### Avoid Creating Style Objects in render

```tsx
// Anti-pattern — new array reference every render, defeats React.memo
const Row = ({ height }: { height: number }) => (
  <View style={[styles.row, { height }]} />
);

// Fix — extract the dynamic part as a separate useMemo
const Row = ({ height }: { height: number }) => {
  const dynamicStyle = useMemo(() => ({ height }), [height]);
  return <View style={[styles.row, dynamicStyle]} />;
};
```

### Platform-Specific Styles Outside render

Evaluate `Platform.OS` at module level, not inside render:

```tsx
import { Platform, StyleSheet } from 'react-native';

const styles = StyleSheet.create({
  shadow: Platform.select({
    ios: {
      shadowColor: '#000',
      shadowOffset: { width: 0, height: 2 },
      shadowOpacity: 0.12,
      shadowRadius: 8,
    },
    android: {
      elevation: 4,
    },
    default: {},
  }),
});
```

---

## 8. Context Splitting to Prevent Re-renders

Every consumer of a React context re-renders whenever the context **value reference** changes. A single large context that mixes fast-changing state (form input, search query) with slow-changing state (user profile, theme) causes all consumers — including expensive ones — to re-render on every keystroke.

### The Problem: Single Monolithic Context

```tsx
// Bad — one context for everything
type AppContextValue = {
  user: User;           // changes on login/logout
  theme: Theme;         // changes rarely
  searchQuery: string;  // changes on every keystroke
  cartCount: number;    // changes on add/remove
};

const AppContext = createContext<AppContextValue>({} as AppContextValue);

const AppProvider = ({ children }: { children: React.ReactNode }) => {
  const [user, setUser] = useState<User>(initialUser);
  const [theme, setTheme] = useState<Theme>(defaultTheme);
  const [searchQuery, setSearchQuery] = useState('');
  const [cartCount, setCartCount] = useState(0);

  // New object reference on every state change — ALL consumers re-render
  const value = { user, theme, searchQuery, cartCount, setSearchQuery };

  return <AppContext.Provider value={value}>{children}</AppContext.Provider>;
};

// ProductCard subscribes to AppContext to read theme — but re-renders on searchQuery changes too!
const ProductCard = () => {
  const { theme } = useContext(AppContext); // re-renders on every keystroke
  return <View style={{ backgroundColor: theme.surface }} />;
};
```

### The Fix: Split Contexts by Update Frequency

```tsx
// Good — separate contexts by how frequently they change

// "Slow" contexts — change rarely
const UserContext = createContext<User>({} as User);
const ThemeContext = createContext<Theme>(defaultTheme);

// "Fast" contexts — change frequently
const SearchContext = createContext<{
  query: string;
  setQuery: (q: string) => void;
}>({ query: '', setQuery: () => {} });

const CartContext = createContext<{ count: number }>({ count: 0 });

// Providers composed at the top level
const AppProvider = ({ children }: { children: React.ReactNode }) => {
  const [user] = useState<User>(initialUser);
  const [theme] = useState<Theme>(defaultTheme);
  const [query, setQuery] = useState('');
  const [cartCount] = useState(0);

  // Each provider only re-renders its consumers when its own value changes
  return (
    <ThemeContext.Provider value={theme}>
      <UserContext.Provider value={user}>
        <CartContext.Provider value={{ count: cartCount }}>
          <SearchContext.Provider value={{ query, setQuery }}>
            {children}
          </SearchContext.Provider>
        </CartContext.Provider>
      </UserContext.Provider>
    </ThemeContext.Provider>
  );
};

// ProductCard now only re-renders when theme actually changes
const ProductCard = () => {
  const theme = useContext(ThemeContext);
  return <View style={{ backgroundColor: theme.surface }} />;
};

// SearchBar re-renders on every keystroke — that's fine, it's the only subscriber
const SearchBar = () => {
  const { query, setQuery } = useContext(SearchContext);
  return <TextInput value={query} onChangeText={setQuery} />;
};
```

### Stabilise Context Values with `useMemo`

Even in a split context, forgetting to stabilise the value object creates a new reference on every render of the provider:

```tsx
// Bad — new object on every parent render
const SearchContext.Provider value={{ query, setQuery }}>

// Good — stable reference; only changes when query or setQuery change
const searchValue = useMemo(
  () => ({ query, setQuery }),
  [query, setQuery],
);
<SearchContext.Provider value={searchValue}>
```

`setQuery` from `useState` is already stable (same reference across renders), so this memo only re-creates when `query` changes — correct behaviour.

### Context + useReducer for Isolated Updates

When a context manages several related fields, `useReducer` allows consumers to dispatch targeted actions without exposing setter functions for every field:

```tsx
type FilterState = { query: string; category: string; minPrice: number };
type FilterAction =
  | { type: 'SET_QUERY'; query: string }
  | { type: 'SET_CATEGORY'; category: string }
  | { type: 'SET_MIN_PRICE'; minPrice: number }
  | { type: 'RESET' };

const initialFilter: FilterState = { query: '', category: 'all', minPrice: 0 };

const filterReducer = (state: FilterState, action: FilterAction): FilterState => {
  switch (action.type) {
    case 'SET_QUERY': return { ...state, query: action.query };
    case 'SET_CATEGORY': return { ...state, category: action.category };
    case 'SET_MIN_PRICE': return { ...state, minPrice: action.minPrice };
    case 'RESET': return initialFilter;
  }
};

// Split state and dispatch into separate contexts so dispatch consumers
// (action buttons) don't re-render when filter state changes
const FilterStateContext = createContext<FilterState>(initialFilter);
const FilterDispatchContext = createContext<React.Dispatch<FilterAction>>(() => {});

const FilterProvider = ({ children }: { children: React.ReactNode }) => {
  const [state, dispatch] = useReducer(filterReducer, initialFilter);
  return (
    <FilterStateContext.Provider value={state}>
      <FilterDispatchContext.Provider value={dispatch}>
        {children}
      </FilterDispatchContext.Provider>
    </FilterStateContext.Provider>
  );
};

// Custom hooks for ergonomic consumption
const useFilterState = () => useContext(FilterStateContext);
const useFilterDispatch = () => useContext(FilterDispatchContext);

// ResetButton only subscribes to dispatch — never re-renders on filter state changes
const ResetButton = () => {
  const dispatch = useFilterDispatch();
  return <Button onPress={() => dispatch({ type: 'RESET' })} title="Reset" />;
};
```

---

## 9. useTransition and useDeferredValue in React Native

Concurrent features landed in React 18 and are available in React Native with the **New Architecture** (Fabric renderer). On the old bridge-based architecture, `useTransition` and `useDeferredValue` are no-ops — they exist but do not actually defer work because the JS thread is not truly concurrent.

**Requirement: New Architecture must be enabled** (`newArchEnabled: true` in `app.json` / `gradle.properties`).

### What `useTransition` Does

`useTransition` marks a state update as **non-urgent**. React renders the urgent update immediately, then schedules the transitioned update in a lower-priority lane. This keeps the UI responsive during expensive re-renders (e.g., filtering a large list).

```tsx
// Without useTransition — typing in the search box causes the list to lag
const SearchScreen = ({ items }: { items: Item[] }) => {
  const [query, setQuery] = useState('');

  const filtered = items.filter((i) =>
    i.name.toLowerCase().includes(query.toLowerCase()),
  );

  return (
    <>
      {/* Every keystroke triggers expensive list re-render synchronously */}
      <TextInput value={query} onChangeText={setQuery} />
      <FlashList data={filtered} renderItem={renderItem} estimatedItemSize={60} />
    </>
  );
};
```

```tsx
// With useTransition — input stays snappy, list updates are deferred
import { useTransition, useState } from 'react';

const SearchScreen = ({ items }: { items: Item[] }) => {
  const [query, setQuery] = useState('');
  const [deferredQuery, setDeferredQuery] = useState('');
  const [isPending, startTransition] = useTransition();

  const handleSearch = (text: string) => {
    setQuery(text); // urgent — updates TextInput immediately
    startTransition(() => {
      setDeferredQuery(text); // non-urgent — React can defer this
    });
  };

  const filtered = useMemo(
    () => items.filter((i) => i.name.toLowerCase().includes(deferredQuery.toLowerCase())),
    [items, deferredQuery],
  );

  return (
    <>
      <TextInput value={query} onChangeText={handleSearch} />
      {/* Show loading indicator while transition is pending */}
      {isPending && <ActivityIndicator style={styles.spinner} />}
      <FlashList
        data={filtered}
        renderItem={renderItem}
        estimatedItemSize={60}
        // Optionally dim the list during the transition
        style={isPending ? styles.dimmed : undefined}
      />
    </>
  );
};

const styles = StyleSheet.create({
  spinner: { position: 'absolute', top: 60, right: 16 },
  dimmed: { opacity: 0.6 },
});
```

### `useDeferredValue` — Alternative for Derived Values

`useDeferredValue` is a lower-level primitive. Instead of wrapping a setter, it returns a **stale copy** of a value that lags behind the real value during rendering. Use it when you don't own the setter (e.g., the value comes from a prop or context):

```tsx
import { useDeferredValue, useMemo } from 'react';

const FilteredResults = ({ query, items }: { query: string; items: Item[] }) => {
  // deferredQuery trails query — the component re-renders twice on change:
  // 1. with old deferredQuery (fast, shows stale results)
  // 2. with new deferredQuery (slower, shows correct results)
  const deferredQuery = useDeferredValue(query);

  const filtered = useMemo(
    () => items.filter((i) => i.name.toLowerCase().includes(deferredQuery.toLowerCase())),
    [items, deferredQuery],
  );

  const isStale = deferredQuery !== query; // true while deferred render is pending

  return (
    <FlashList
      data={filtered}
      renderItem={renderItem}
      estimatedItemSize={60}
      style={isStale ? { opacity: 0.7 } : undefined}
    />
  );
};
```

### Trade-offs: Does It Help on React Native?

| Scenario | Benefit |
|---|---|
| New Architecture + expensive JS computation (filtering 5000 items) | Yes — UI thread stays responsive, list update is interruptible |
| New Architecture + cheap computation (<100 items) | Minimal — the overhead of scheduling outweighs the benefit |
| Old Architecture (bridge-based) | None — JS thread is not concurrent; updates run to completion |
| Reanimated worklets running on UI thread | Not applicable — concurrent features only affect the JS thread |

The JS thread in React Native is **single-threaded** — concurrent rendering does not mean true parallelism. What it means is that React can **interrupt** a low-priority render mid-way if a high-priority update arrives (e.g., a new keystroke). This is meaningful when the list re-render takes multiple frames; React slices the work and yields to the input handler between slices.

On a 60 fps budget (16.6 ms per frame), filtering 2000 items typically takes 30–80 ms. Without `useTransition` this blocks input for 2–5 frames. With `useTransition` + New Architecture, input is processed immediately and the list catches up asynchronously.

### `isPending` for Loading Indicators

`isPending` becomes `true` immediately when `startTransition` is called and goes `false` when the deferred render completes. Use it for subtle affordances — a spinner, opacity change, or skeleton — that communicate the list is updating without blocking the user:

```tsx
{isPending ? (
  <View style={styles.pendingOverlay}>
    <ActivityIndicator size="small" color={colors.brand} />
    <Text style={styles.pendingText}>Updating results…</Text>
  </View>
) : null}
```

---

## 10. Large Form Rendering Optimization

Forms with many fields are a common source of React Native performance issues. Every `onChangeText` on a controlled input triggers a state update, which re-renders the form component, which re-renders every field — even fields the user is not touching.

### The Problem: Controlled Inputs at the Form Level

```tsx
// Bad — entire form re-renders on every keystroke
const CheckoutForm = () => {
  const [values, setValues] = useState({
    firstName: '',
    lastName: '',
    address: '',
    city: '',
    postcode: '',
    cardNumber: '',
    expiry: '',
    cvv: '',
  });

  const handleChange = (field: string) => (value: string) =>
    setValues((v) => ({ ...v, [field]: value }));

  // 8 controlled inputs — every keystroke re-renders all 8
  return (
    <ScrollView>
      <TextInput value={values.firstName} onChangeText={handleChange('firstName')} />
      <TextInput value={values.lastName} onChangeText={handleChange('lastName')} />
      {/* ... 6 more fields */}
    </ScrollView>
  );
};
```

### Pattern 1: Decompose Fields into Isolated Components

Each field manages its own state. The parent only receives the final value via `onBlur` or `onSubmit`:

```tsx
// Isolated field — only re-renders itself
const FormField = React.memo(({
  label,
  onCommit,
  ...inputProps
}: {
  label: string;
  onCommit: (value: string) => void;
} & TextInputProps) => {
  const [value, setValue] = useState('');

  return (
    <View style={styles.fieldContainer}>
      <Text style={styles.label}>{label}</Text>
      <TextInput
        {...inputProps}
        value={value}
        onChangeText={setValue}
        onBlur={() => onCommit(value)} // commit to parent only on blur
      />
    </View>
  );
});

const CheckoutForm = () => {
  const valuesRef = useRef({ firstName: '', lastName: '', address: '' });

  const handleCommit = useCallback((field: string) => (value: string) => {
    valuesRef.current = { ...valuesRef.current, [field]: value };
  }, []);

  const handleSubmit = () => {
    // valuesRef.current has all final values
    submitOrder(valuesRef.current);
  };

  return (
    <ScrollView>
      <FormField label="First name" onCommit={handleCommit('firstName')} />
      <FormField label="Last name" onCommit={handleCommit('lastName')} />
      <FormField label="Address" onCommit={handleCommit('address')} />
      <Button title="Submit" onPress={handleSubmit} />
    </ScrollView>
  );
};
```

### Pattern 2: react-hook-form (Recommended for Complex Forms)

`react-hook-form` is **uncontrolled by default** — it registers inputs with `ref` and reads values only on submit, or on demand with `watch()`. This eliminates all intermediate re-renders:

```tsx
import { useForm, Controller } from 'react-hook-form';

type FormValues = {
  firstName: string;
  lastName: string;
  email: string;
  address: string;
};

const CheckoutForm = () => {
  const { control, handleSubmit, formState: { errors } } = useForm<FormValues>({
    defaultValues: { firstName: '', lastName: '', email: '', address: '' },
  });

  const onSubmit = (values: FormValues) => {
    submitOrder(values);
  };

  // Controller renders its own isolated controlled input
  // The parent CheckoutForm does NOT re-render on field changes
  return (
    <ScrollView>
      <Controller
        control={control}
        name="firstName"
        rules={{ required: 'First name is required' }}
        render={({ field: { value, onChange, onBlur } }) => (
          <TextInput value={value} onChangeText={onChange} onBlur={onBlur} />
        )}
      />
      {errors.firstName && <Text style={styles.error}>{errors.firstName.message}</Text>}

      <Controller
        control={control}
        name="lastName"
        render={({ field: { value, onChange, onBlur } }) => (
          <TextInput value={value} onChangeText={onChange} onBlur={onBlur} />
        )}
      />

      <Button title="Submit" onPress={handleSubmit(onSubmit)} />
    </ScrollView>
  );
};
```

`react-hook-form` advantages over manual controlled forms:
- Zero re-renders on field change (uncontrolled mode)
- Built-in validation with `rules` or schema validators (Zod, Yup)
- `formState.isDirty` / `isSubmitting` without extra state
- `watch()` can subscribe to individual fields without re-rendering others

### Pattern 3: Debouncing Fast-Changing Fields

For fields with live validation or search-as-you-type behaviour, debounce the expensive side effect rather than the input itself — the input should always feel instant:

```tsx
import { useDebouncedCallback } from 'use-debounce';

const PostcodeField = ({ onPostcodeLookup }: { onPostcodeLookup: (pc: string) => void }) => {
  const [value, setValue] = useState('');

  // Debounce the expensive lookup, not the text state
  const debouncedLookup = useDebouncedCallback(onPostcodeLookup, 400);

  const handleChange = (text: string) => {
    setValue(text);           // immediate — keeps input responsive
    debouncedLookup(text);   // deferred — triggers API call after typing stops
  };

  return <TextInput value={value} onChangeText={handleChange} autoCapitalize="characters" />;
};
```

### Controlled vs Uncontrolled: When to Use Each

| Scenario | Recommendation |
|---|---|
| Simple form, <5 fields, no live validation | Controlled state at field level (`useState` per field) |
| Complex form, 5+ fields, schema validation | `react-hook-form` (uncontrolled) |
| Live search / filter input | Controlled + `useTransition` or debounce |
| OTP / PIN inputs requiring tight synchronisation | Controlled — you need to react to each character |
| Long multi-step forms | `react-hook-form` with `persist` mode to preserve between steps |

### Virtualizing Long Forms

If a form has dynamic, potentially long field lists (e.g., configurable product attributes), render it in a `FlashList` rather than a `ScrollView`:

```tsx
type FieldConfig = { key: string; label: string; type: 'text' | 'number' | 'select' };

const DynamicForm = ({ fields }: { fields: FieldConfig[] }) => {
  const { control } = useForm();

  const renderField = useCallback(
    ({ item }: { item: FieldConfig }) => (
      <Controller
        key={item.key}
        control={control}
        name={item.key}
        render={({ field }) => <FormFieldRenderer config={item} field={field} />}
      />
    ),
    [control],
  );

  return (
    <FlashList
      data={fields}
      renderItem={renderField}
      estimatedItemSize={72}
      keyExtractor={(item) => item.key}
      // Prevent keyboard from dismissing on scroll
      keyboardShouldPersistTaps="handled"
    />
  );
};
```

---

## Quick Reference

| Technique | When to Use | When to Skip |
|---|---|---|
| `React.memo` | Component receives stable props, re-renders from parent | Props always change, cheap renders |
| `useCallback` | Passing callbacks to memo'd children | Internal handlers not passed down |
| `useMemo` | Sorting/filtering 100+ items | String concat, simple arithmetic |
| `FlashList` | Any list with 20+ items | Static lists, <20 items |
| `getItemLayout` | Fixed-height FlatList rows | Variable heights |
| `StyleSheet.create` | All static styles | Never skip this |
| `expo-image` | All image rendering | N/A — always prefer it |
| `react-freeze` | Tab navigators | Stack navigators (screens unmount) |
| React Compiler | RN 0.78+ / Expo SDK 53+ | Older RN versions |
| `'use no memo'` | Files with custom memo comparators or compiler-incompatible patterns | General use — too broad |
| Split contexts | App with mixed fast/slow state; >3 consumers of a shared context | Single-consumer context — splitting adds boilerplate for no gain |
| `useMemo` on context value | Any context provider that re-renders due to parent state | Context providers that never re-render themselves |
| `useReducer` + split dispatch context | Complex context with multiple related fields | Simple boolean or string context values |
| `useTransition` | New Architecture + expensive JS derivation (filtering 500+ items) | Old Architecture; cheap derivations; Reanimated worklets |
| `useDeferredValue` | You don't own the setter; value comes from props/context | You own the setter — prefer `useTransition` |
| `react-hook-form` | Forms with 5+ fields, validation, or multi-step flows | Simple 1–2 field inline forms |
| Debounce effect (not input) | Live search, postcode lookup, async validation | OTP/PIN inputs needing per-character reactions |
| `overrideItemLayout` (FlashList/Masonry) | Known item heights (aspect ratios stored on data) | Truly unknown heights — let FlashList measure |
| `MasonryFlashList` | Variable-height grid (photo galleries, cards) | Uniform-height grids — use `numColumns` on `FlashList` |
| `removeClippedSubviews` | Long Android lists with fixed-height cells | iOS (minimal gain); variable-height cells; sticky indices |
| `windowSize` increase | Users scroll in bursts; content-heavy cells | Memory-constrained devices |
| `maxToRenderPerBatch` tuning | Slow Android devices showing blank areas | Flagship devices — default is fine |
