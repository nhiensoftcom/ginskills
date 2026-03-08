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

### React Compiler (RN 0.78+ / Expo SDK 53+)

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
