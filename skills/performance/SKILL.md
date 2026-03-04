# React Native Performance Optimization Skill

> Hướng dẫn toàn diện tối ưu hiệu suất React Native app (2025-2026)

## Khi nào kích hoạt skill này

- User hỏi về tối ưu hiệu suất React Native
- Code review phát hiện anti-patterns ảnh hưởng performance
- User muốn cải thiện startup time, FPS, memory, bundle size
- User cần chọn thư viện (state management, list, image, animation, navigation, storage)

---

## 1. Architecture Foundation (New Architecture)

### JSI (JavaScript Interface)
- Thay thế Bridge cũ bằng C++ direct calls, không serialization JSON
- **Benchmark**: ~55% faster startup vs JSC, 92-99.98% faster native method calls
- Cold TTI: 3.6s → 2.1s trên mid-range Android (Hermes + JSI + inlineRequires)

### Fabric Renderer
- Synchronous rendering via JSI, hỗ trợ React Concurrent Mode
- Yoga 2 layout engine nhanh hơn
- 5,000 `<Text>` elements render nhanh hơn 20%

### TurboModules
- Lazy loading: module chỉ init khi được gọi lần đầu
- `TurboModuleRegistry.get<Spec>('ModuleName')` — lazy by design
- Defer analytics, crash reporting, push notification init sau startup

### Hermes Engine (V1 — RN 0.82+/0.84 default)
- AOT bytecode precompilation: skip parse + compile at runtime
- TTI improvement: iOS +2.5%, Android +7.6% (vs Hermes legacy)
- Bundle load: iOS +9%, Android +3.1% faster
- Bytecode ~33% smaller than minified JS
- Memory: ~136MB vs JSC ~185MB (-26%)

### Bridgeless Mode (RN 0.76+ default)
- ~50% TTI reduction by removing legacy Bridge runtime init
- Timers, error handling, event emitters chuyển sang JSI

### Enable New Architecture
```js
// android/gradle.properties
newArchEnabled=true

// ios/Podfile
ENV['RCT_NEW_ARCH_ENABLED'] = '1'
```

### Metro Config tối ưu
```js
// metro.config.js
module.exports = {
  transformer: {
    getTransformOptions: async () => ({
      transform: {
        inlineRequires: true, // defer module evaluation — major startup win
      },
    }),
  },
};
```

---

## 2. Rendering Optimization

### Giảm Re-render

**React.memo** — chỉ hiệu quả khi MỌI prop stable:
```tsx
const ProductCard = React.memo(({ product, onPress }: Props) => {
  return (
    <Pressable onPress={onPress}>
      <Text>{product.name}</Text>
    </Pressable>
  );
});
```

**useCallback** — stabilize callback trước khi truyền vào memo child:
```tsx
const handlePress = useCallback((id: string) => {
  dispatch(addToCart(id));
}, [dispatch]);
```

**useMemo** — chỉ dùng cho expensive computation:
```tsx
const sorted = useMemo(
  () => products.filter(p => p.inStock).sort((a, b) => a.price - b.price),
  [products],
);
```

**React Compiler (RN 0.78+ / Expo SDK 53+)**: Tự động memoize, giảm nhu cầu manual useMemo/useCallback.

### Lists: FlashList > FlatList

| Metric | FlatList | FlashList |
|---|---|---|
| JS thread FPS | baseline | ~7.5x better |
| CPU usage | baseline | -32% |
| Blank area | baseline | -50% (v2) |

```tsx
import { FlashList } from '@shopify/flash-list';

<FlashList
  data={products}
  renderItem={({ item }) => <ProductCard product={item} />}
  keyExtractor={item => item.id}
  estimatedItemSize={88} // v1 required; v2 optional
/>
```

**FlatList optimization khi cần dùng:**
```tsx
<FlatList
  data={products}
  renderItem={renderItem} // useCallback, defined outside JSX
  keyExtractor={item => item.id} // NEVER use index
  getItemLayout={(_, index) => ({ length: 88, offset: 88 * index, index })}
  maxToRenderPerBatch={8}
  windowSize={11}
  updateCellsBatchingPeriod={40}
  initialNumToRender={6}
  removeClippedSubviews={Platform.OS === 'android'}
/>
```

### Image Optimization

**Recommended libraries:**
- **expo-image**: Best cho Expo (WebP, AVIF, Blurhash built-in)
- **@d11/react-native-fast-image**: Best cho bare RN

```tsx
import { Image } from 'expo-image';

<Image
  source={{ uri: `${baseUrl}?w=400&h=400&fm=webp&q=75` }}
  placeholder={{ blurhash: 'LEHV6nWB2yk8...' }}
  contentFit="cover"
  transition={200}
  cachePolicy="memory-disk"
  style={{ width: 200, height: 200 }}
/>
```

**Format priority**: AVIF > WebP > JPEG. Dùng CDN với `f_auto,q_auto`.

**CRITICAL**: Android decode 1080x1920 JPEG → ~8MB RAM. LUÔN request thumbnail size từ CDN.

### Animation: Reanimated 3/4

```tsx
import Animated, { useSharedValue, useAnimatedStyle, withSpring } from 'react-native-reanimated';

const scale = useSharedValue(1);

const animatedStyle = useAnimatedStyle(() => ({
  transform: [{ scale: scale.value }],
}));

// Worklets run on UI thread — 60fps guaranteed
const onPressIn = () => { scale.value = withSpring(0.95); };
```

| | Animated (no native) | Animated (useNativeDriver) | Reanimated 3/4 |
|---|---|---|---|
| FPS under JS load | ~45fps | ~60fps | 60-120fps |
| Layout properties | ~30fps | Not supported | ~60fps |
| Gesture tracking | Laggy | Partial | 60-120fps |

**Lottie**: Dùng `.lottie` format (70-80% smaller than JSON). Unmount khi không visible.

---

## 3. Startup Optimization

### Cold Start Targets

| Device | Target TTI |
|---|---|
| iOS flagship | ≤ 1.5s |
| Mid-tier Android | ≤ 2.0s |
| Low-end Android | ≤ 2.5s |

### Quick Wins
1. **Enable Hermes** (default RN 0.70+, verify active)
2. **Enable inlineRequires** trong metro.config.js
3. **react-native-bootsplash** thay react-native-splash-screen
4. **Bundle visualizer**: `npx react-native-bundle-visualizer`
5. **Replace heavy libs**: moment.js → dayjs, lodash → lodash/method

### Lazy Loading
```tsx
// Screens
const HeavyScreen = React.lazy(() => import('./screens/HeavyScreen'));

// Navigation
<Stack.Navigator screenOptions={{ lazy: true }}>
```

### Defer Non-Critical Modules
- Analytics, crash reporting → init sau startup
- Push notification setup → setTimeout hoặc InteractionManager
- Social SDK → lazy TurboModule

### Splash Screen → Skeleton → Content
```tsx
import BootSplash from 'react-native-bootsplash';

useEffect(() => {
  Promise.all([loadFonts(), checkAuth(), prefetchData()])
    .finally(() => BootSplash.hide({ fade: true }));
}, []);
```

---

## 4. Memory Management

### Top Memory Leak Causes & Fixes

**1. Event Listeners** — phải cleanup:
```tsx
useEffect(() => {
  const sub = Keyboard.addListener('keyboardDidShow', handler);
  return () => sub.remove();
}, []);
```

**2. Timers** — phải clearInterval/clearTimeout:
```tsx
useEffect(() => {
  const id = setInterval(fetchPrice, 2000);
  return () => clearInterval(id);
}, []);
```

**3. Async Operations** — dùng AbortController:
```tsx
useEffect(() => {
  const controller = new AbortController();
  fetch(url, { signal: controller.signal }).then(/*...*/);
  return () => controller.abort();
}, []);
```

**4. Closures** — capture primitive, không capture entire object.

### Image Memory
- Android: 1080x1920 JPEG → ~8MB RAM per image
- LUÔN request thumbnail size từ CDN/server
- Clear memory cache khi unmount heavy gallery screens

### Memory Budgets

| Device RAM | JS Heap Budget | Image Cache Budget |
|---|---|---|
| 1-2 GB | < 50 MB | < 30 MB |
| 3-4 GB | < 100 MB | < 80 MB |
| 6+ GB | < 200 MB | < 200 MB |

### Large Data → Pagination, không giữ trong memory
```tsx
const { data, fetchNextPage, hasNextPage } = useInfiniteQuery({
  queryKey: ['products'],
  queryFn: ({ pageParam = 0 }) => fetchProducts(pageParam),
  getNextPageParam: (lastPage, pages) =>
    lastPage.length === PAGE_SIZE ? pages.length * PAGE_SIZE : undefined,
});
```

### Storage: MMKV >> AsyncStorage
- MMKV: ~20-30x faster reads, ~500% faster writes
- Synchronous (JSI), encryption support

```tsx
import { MMKV } from 'react-native-mmkv';
const storage = new MMKV({ id: 'app-storage' });
storage.set('token', value);
storage.getString('token');
```

---

## 5. Navigation Optimization

### Library Choice

| Need | Recommendation |
|---|---|
| Standard app | `@react-navigation/native-stack` + `react-native-screens` |
| File-based routing + web | Expo Router |
| Max native performance | react-native-navigation (Wix) |

### Key Optimizations

```tsx
// Entry point
import { enableScreens } from 'react-native-screens';
enableScreens(true); // native screen containers — saves 30-40% memory

// Tab Navigator
<Tab.Navigator screenOptions={{ lazy: true, lazyPreloadDistance: 0 }}>

// ALWAYS use native-stack, NOT JS stack
import { createNativeStackNavigator } from '@react-navigation/native-stack';
```

### useFocusEffect vs useEffect

| | useEffect | useFocusEffect |
|---|---|---|
| Trigger | Mount/unmount | Screen focus/blur |
| Runs khi quay lại screen | No | Yes |
| Use case | One-time setup | Data refresh, analytics |

```tsx
useFocusEffect(
  useCallback(() => {
    fetchFreshData();
    return () => cleanup();
  }, [])
);
```

### Tránh heavy work khi navigate
```tsx
useFocusEffect(
  useCallback(() => {
    const task = InteractionManager.runAfterInteractions(async () => {
      // Heavy work SAU KHI animation complete
    });
    return () => task.cancel();
  }, [])
);
```

### Navigation depth: MAX 3 levels. Flatten bằng root-level screens cho modals/details.

---

## 6. Network & State Management

### State Management Choice

| Library | Bundle | Update Speed | Best For |
|---|---|---|---|
| **Zustand** | ~8 KB | 0.8ms | Most apps, simple API, MMKV persist |
| **Jotai** | ~4 KB | 0.9ms | Complex derived/interdependent state |
| **Redux Toolkit** | ~43 KB | 1.2ms | Large teams, complex async, RTK Query |
| Context API | 0 KB | 2.5ms+ | Theme, locale, auth (low-frequency only) |

**Zustand selector pattern:**
```tsx
// Only re-renders when `total` changes
const total = useCartStore((state) => state.total);
```

### Data Fetching: TanStack Query

```tsx
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5 * 60 * 1000,    // 5 min fresh
      gcTime: 24 * 60 * 60 * 1000, // 24h cache
      retry: 2,
      refetchOnWindowFocus: false,   // mobile: use AppState instead
      refetchOnReconnect: true,
    },
  },
});
```

**Offline persistence với MMKV:**
```tsx
import { createSyncStoragePersister } from '@tanstack/query-sync-storage-persister';
import { PersistQueryClientProvider } from '@tanstack/react-query-persist-client';

const persister = createSyncStoragePersister({
  storage: {
    getItem: (key) => storage.getString(key) ?? null,
    setItem: (key, value) => storage.set(key, value),
    removeItem: (key) => storage.delete(key),
  },
});
```

### Network Best Practices
- `Promise.all()` cho parallel requests (tránh waterfall)
- Field projection hoặc GraphQL (tránh over-fetching)
- WebSocket cho real-time (tránh polling)
- Exponential backoff cho reconnection

---

## 7. Anti-Patterns Quick Reference

| Anti-Pattern | Fix |
|---|---|
| Inline `() => {}` trong JSX props | `useCallback` + `React.memo` |
| Inline `{}` style objects | `StyleSheet.create` + `useMemo` dynamic parts |
| `key={index}` trong lists | `key={item.id}` (stable unique ID) |
| Monolithic Context cho mọi state | Split context; Zustand cho high-frequency |
| FlatList inside ScrollView | `ListHeaderComponent` / FlashList |
| Component 300+ lines | Decompose thành focused leaf components |
| `import _ from 'lodash'` | `import get from 'lodash/get'` |
| All screens imported eagerly | `React.lazy()` + `Suspense` |
| All tabs rendered on mount | `screenOptions={{ lazy: true }}` |
| Heavy work trong useFocusEffect | `InteractionManager.runAfterInteractions` |
| Navigator nesting >3 levels | Flatten, root-level stack cho modals |
| No API caching | TanStack Query với staleTime |
| Sequential await chains | `Promise.all()` hoặc BFF endpoint |
| `setInterval` polling | WebSocket singleton |
| Missing useEffect cleanup | Return cleanup; AbortController |
| Full-res images cho thumbnails | CDN resize; request đúng size |
| Entire dataset trong state | Cursor-based pagination |

---

## 8. Performance Budgets

| Metric | Good | Warning | Fail |
|---|---|---|---|
| Cold Start TTI | ≤ 1.5s iOS / ≤ 2.0s Android | ≤ 2.5s | > 3.0s |
| Screen Transition | ≤ 300ms | ≤ 500ms | > 700ms |
| List Scroll FPS | 60 FPS | 50-59 FPS | < 50 FPS |
| Memory Peak | ≤ 200MB (3GB device) | ≤ 350MB | > 400MB |
| JS Bundle (gzipped) | ≤ 2 MB | ≤ 4 MB | > 6 MB |
| API → First Render | ≤ 300ms WiFi | ≤ 1.0s | > 1.5s |
| App Install Size | ≤ 20 MB AAB | ≤ 50 MB | > 80 MB |

---

## 9. Monitoring & Profiling Tools

| Need | Tool |
|---|---|
| Dev JS debugging | React Native DevTools (RN 0.76+, press `j` in Metro) |
| Native iOS profiling | Xcode Instruments (Time Profiler + Leaks) |
| Native Android profiling | Android Studio Profiler (CPU System Trace) |
| Production monitoring | Sentry React Native SDK |
| Custom traces (TTI) | Firebase Performance / `react-native-performance` |
| Bundle analysis | `react-native-bundle-visualizer` / Expo Atlas |
| Render regression CI | Reassure (Callstack) |
| Android perf scoring CI | Flashlight (BAM/Theodo) |
| E2E testing | Maestro (preferred) / Detox |
| Memory leak (Android) | LeakCanary |
| Memory leak (iOS) | Xcode Instruments Leaks |

### Sentry Setup
```tsx
import * as Sentry from '@sentry/react-native';

Sentry.init({
  dsn: 'YOUR_DSN',
  tracesSampleRate: 0.15,
  profilesSampleRate: 0.1,
  enableNativeFramesTracking: true,
  enableStallTracking: true,
});
```

---

## 10. Optimization Checklist by Effort Level

### Level 1 — Quick Wins (< 1 day)
- [ ] Verify Hermes enabled
- [ ] Enable `inlineRequires` in metro.config.js
- [ ] Switch to react-native-bootsplash
- [ ] Run bundle visualizer, replace heavy deps (moment→dayjs)
- [ ] Add `keyExtractor` with stable IDs to all lists
- [ ] Move static styles to `StyleSheet.create()`
- [ ] Enable `lazy: true` on tab navigators
- [ ] Replace AsyncStorage with MMKV

### Level 2 — Standard (1-3 days)
- [ ] Replace FlatList with FlashList for large lists
- [ ] Add React.memo + useCallback cho list items
- [ ] Switch to expo-image / @d11/react-native-fast-image
- [ ] Setup TanStack Query with staleTime + MMKV persist
- [ ] Lazy load screens with React.lazy + Suspense
- [ ] Defer analytics/crash reporting init post-startup
- [ ] Add useEffect cleanup cho tất cả subscriptions
- [ ] Request thumbnail sizes từ CDN

### Level 3 — Advanced (1-2 weeks)
- [ ] Migrate to New Architecture (RN 0.76+)
- [ ] Replace Animated API with Reanimated 3/4
- [ ] Setup Sentry performance monitoring
- [ ] Add Reassure render benchmarks to CI
- [ ] Implement cursor-based pagination
- [ ] Setup WebSocket singleton cho real-time features
- [ ] Flatten navigation depth to ≤ 3 levels

### Level 4 — Expert (> 2 weeks)
- [ ] Custom TurboModules for heavy native operations
- [ ] Implement performance budgets in CI pipeline
- [ ] Setup Flashlight + Maestro for automated perf testing
- [ ] Evaluate React Compiler (RN 0.78+)
- [ ] RAM Bundles / Re.Pack for large apps
- [ ] Upgrade to Hermes V1 (RN 0.82+)
