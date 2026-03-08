# Senior/Staff-Level React Native Performance Tricks

A deep-dive reference for engineers operating beyond the basics. Each section targets a distinct performance surface area with concrete, actionable guidance.

---

## 1. Hidden Performance Killers

These issues are invisible in dev mode but degrade real-user experience significantly.

### console.log in Production

Every `console.log` call crosses the JS-to-native bridge synchronously. On a mid-range Android device this costs approximately 1 ms per call. In tight loops or render functions this compounds quickly.

Strip all console calls at build time using `babel-plugin-transform-remove-console`:

```js
// babel.config.js
module.exports = {
  plugins: [
    process.env.NODE_ENV === 'production' && 'transform-remove-console',
  ].filter(Boolean),
};
```

Do not rely on runtime guards like `if (__DEV__)` — the check itself still executes.

### StyleSheet.create vs Inline Style Objects

`StyleSheet.create` registers styles with the native layer once at module load time. Inline objects are allocated fresh every render, triggering both JS GC pressure and potential layout recalculations.

```js
// Bad: new object every render
<View style={{ flex: 1, backgroundColor: '#fff' }} />

// Good: registered once
const styles = StyleSheet.create({ container: { flex: 1, backgroundColor: '#fff' } });
<View style={styles.container} />
```

Benchmarks on complex style trees show approximately 3x faster style application with `StyleSheet.create`.

### Debug Mode Is 10x Slower

The Metro bundler in development mode disables minification, enables source maps, and activates the React DevTools protocol. The JS engine is unoptimized and Hermes JIT is partially disabled. **Never profile in dev mode.** Always build a release variant:

```bash
# Android
npx react-native run-android --variant=release

# iOS
npx react-native run-ios --configuration Release
```

### Flipper Overhead

Flipper injects a native SDK into both Android and iOS that opens sockets, intercepts network calls, and mirrors the layout tree. On startup alone this costs 10–20% of launch time.

Remove Flipper from release builds:

```ruby
# ios/Podfile
if !ENV['NO_FLIPPER'] || ENV['NO_FLIPPER'] == '0'
  use_flipper!
end
```

```groovy
// android/app/build.gradle
releaseImplementation('com.facebook.flipper:flipper') { transitive = false }
// Remove from release dependencies entirely
```

### Context Re-Render Propagation

Every `Context.Provider` value change re-renders all consumers in the subtree, even those that don't use the changed slice. This is the most common source of invisible re-renders in large apps.

Strategies:
1. **Split context by update frequency**: separate `UserContext` (rare) from `UIContext` (frequent)
2. **Use Zustand or Jotai** for high-frequency state (animations, counters, search input)
3. **useMemo the value** to prevent reference churn when the data hasn't changed

```js
// Avoid
const value = { user, settings, theme }; // new object every parent render
<AppContext.Provider value={value}>

// Fix
const value = useMemo(() => ({ user, settings, theme }), [user, settings, theme]);
<AppContext.Provider value={value}>
```

### Platform.select / Platform.OS Inside Render

`Platform.OS` is a constant that never changes at runtime. Evaluating it inside a render function is wasted work on every call.

```js
// Bad: evaluated every render
const hitSlop = Platform.select({ ios: 8, android: 4 });

// Good: evaluated once at module level
const HIT_SLOP = Platform.select({ ios: 8, android: 4 });
```

### React Native DevTools When Profiling

The RN DevTools bridge adds measurable latency to all state updates when the debugger is attached. Detach DevTools before capturing production-representative flamecharts.

---

## 2. Native-Level Optimizations

### View Flattening (New Architecture / Fabric)

In the Old Architecture, every React `<View>` mapped to a native view node, making deep component trees expensive. Fabric's renderer detects purely layout views with no visual output (no background, no border, no touch handling) and flattens them out of the native view hierarchy automatically.

To help the renderer: avoid adding `backgroundColor`, `border`, or `onPress` to wrapper views unless actually needed. Use `collapsable={true}` on Android for manual hints in the Old Architecture.

### FlashList View Recycling

FlashList (Shopify) mirrors RecyclerView (Android) and UICollectionView (iOS) by maintaining a pool of off-screen views and recycling them rather than destroying and creating. Key implications:

- **Do not store component-local state** in list items — the component instance is reused for a different item
- `keyExtractor` must return stable, unique keys so recycling maps to the right data
- Set `estimatedItemSize` as accurately as possible; wrong values cause layout thrashing during scroll

### GPU vs CPU Rendering

The compositor (GPU) handles transforms and opacity without involving the JS thread or even the main thread layout pass. CPU-bound properties (anything affecting layout: `width`, `height`, `padding`, `backgroundColor`) require a layout pass and repaint.

Rule: animate with `transform` and `opacity` only. Never animate layout properties in a loop.

```js
// GPU — no layout pass
style={{ transform: [{ translateY: animValue }], opacity: fadeValue }}

// CPU — triggers layout + repaint every frame
style={{ top: animValue, height: expandValue }}
```

### iOS Layer Rasterization

For complex, static views (headers, cards that don't change content), `shouldRasterize` + `rasterizationScale` caches the rendered layer as a bitmap on the GPU. Subsequent frames skip compositing entirely.

```js
<View style={{ shouldRasterize: true, rasterizationScale: PixelRatio.get() }}>
  <ComplexStaticCard />
</View>
```

Use with caution: if the view updates frequently, the rasterization cost exceeds the savings.

### iOS Shadow Performance

`shadowColor`, `shadowOffset`, `shadowRadius` force an offscreen render pass on iOS because the shadow must be computed from the view's alpha mask. On Android, `elevation` uses the Material shadow system which is GPU-accelerated.

For iOS: either use a pre-rendered shadow image, wrap in a sibling view with `backgroundColor` and blur effect, or accept the performance cost only for static elements.

### Border Radius Compositing Cost

Complex `borderRadius` (individual corners with different values, combined with `overflow: hidden`) triggers offscreen compositing. Every view with `overflow: hidden` and a non-trivial shape creates a new compositing layer.

Minimize layered `overflow: hidden` — especially avoid nesting them. Prefer uniform `borderRadius` values.

### Opacity vs Conditional Rendering vs display:none

| Approach | Native Cost | JS Cost | Re-render on Show |
|---|---|---|---|
| `opacity: 0` | View exists in hierarchy, GPU skips draw | None | No |
| `display: 'none'` | View removed from layout tree | None | Layout recalc |
| `{condition && <Component />}` | View destroyed/created | Mount/unmount cycle | Full mount |
| `react-freeze` | Subtree frozen in place | Minimal | No |

For tab screens and modals: prefer `opacity: 0` or `react-freeze` to avoid remount cost.

---

## 3. Advanced React Patterns

### react-freeze for Offscreen Screens

When navigating between tabs, the inactive tabs continue re-rendering if their state updates. `react-freeze` wraps a subtree in a Suspense-like boundary that pauses rendering when `freeze={true}`.

```js
import { Freeze } from 'react-freeze';

function TabNavigator({ activeTab }) {
  return (
    <>
      <Freeze freeze={activeTab !== 'home'}><HomeScreen /></Freeze>
      <Freeze freeze={activeTab !== 'profile'}><ProfileScreen /></Freeze>
    </>
  );
}
```

React Navigation 6+ integrates this natively via `freezeOnBlur` prop on `Screen`.

### Strategic Suspense Boundaries

Suspense boundaries serve two performance functions: code splitting (lazy imports) and data loading state. Place boundaries at the lowest level that makes UX sense — a boundary too high up forces a large skeleton, a boundary too low causes waterfall spinners.

Pattern: one boundary per "data region" (a card, a section, a screen), not one global boundary.

### useDeferred Pattern for Heavy Computation

For expensive synchronous work triggered by user input, defer it a tick to keep the input responsive:

```js
function useDeferred<T>(value: T, delay = 0): T {
  const [deferred, setDeferred] = useState(value);
  useEffect(() => {
    const id = setTimeout(() => setDeferred(value), delay);
    return () => clearTimeout(id);
  }, [value, delay]);
  return deferred;
}

// Usage: search input stays snappy, filter runs after 150ms idle
const deferredQuery = useDeferred(query, 150);
const results = useMemo(() => filterItems(items, deferredQuery), [items, deferredQuery]);
```

React 18's `useDeferredValue` handles this natively when Concurrent Mode is available.

### Windowed Rendering for Tall Non-List Content

Not all tall content is a list. Profile pages, dashboards, and feed items with heterogeneous structure don't map cleanly to FlatList. Options:

1. **Chunk rendering**: render sections progressively using `useEffect` and state flags
2. **SectionList with getItemLayout**: provides O(1) scroll position computation
3. **Custom RecyclerListView**: low-level recycling for fully custom layouts

### Compound Component Pattern

Reduces prop drilling (which forces intermediate components to re-render) by sharing context internally:

```js
const CardContext = createContext(null);

function Card({ children, onPress }) {
  const ctx = useMemo(() => ({ onPress }), [onPress]);
  return <CardContext.Provider value={ctx}>{children}</CardContext.Provider>;
}

Card.Title = function Title({ children }) {
  return <Text>{children}</Text>; // reads context only if needed
};

Card.Action = function Action({ label }) {
  const { onPress } = useContext(CardContext);
  return <Pressable onPress={onPress}><Text>{label}</Text></Pressable>;
};
```

Intermediate `Card` sub-components don't re-render unless their own props change.

---

## 4. Build & Release Optimizations

### Hermes Bytecode Precompilation

Hermes compiles JavaScript to bytecode at build time rather than at runtime. This eliminates the JIT warm-up cost that V8/JSC incur on first launch. On Android this is the default since RN 0.64. On iOS since RN 0.70.

Verify Hermes is active:

```js
import { HermesInternal } from 'global';
console.log(!!HermesInternal); // true = Hermes is running
```

Do not disable Hermes for "compatibility" reasons without benchmarking — the startup improvement is typically 20–40%.

### ProGuard / R8 Rules for Android

R8 (the modern replacement for ProGuard) performs dead code elimination, name minification, and class merging. For React Native apps this can reduce APK size by 20–40%.

```groovy
// android/app/build.gradle
buildTypes {
  release {
    minifyEnabled true
    shrinkResources true
    proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
  }
}
```

Common rules to add in `proguard-rules.pro`:

```
# Keep React Native JS interface classes
-keep class com.facebook.react.** { *; }
-keepclassmembers class * { @com.facebook.react.uimanager.annotations.ReactProp *; }
```

### Android App Bundle (AAB) over APK

AAB allows Google Play to serve only the device-relevant native libraries, screen densities, and language resources. This reduces install size by 15–20% compared to a universal APK without any code change.

```bash
cd android && ./gradlew bundleRelease
```

### App Thinning on iOS

Xcode's App Thinning includes:
- **Slicing**: delivers only assets for the target device's screen scale and architecture
- **Bitcode**: allows Apple to recompile for new instruction sets (deprecated in Xcode 14, use only for older targets)
- **On-Demand Resources**: defer large assets (sounds, levels) until needed

Ensure asset catalogs (`.xcassets`) are used instead of bundled files so the slicer can operate.

### OTA Updates: CodePush / EAS Update

Ship JS bundle updates without App Store review. Best practices:

- Use **mandatory** updates only for critical bug fixes; optional for features
- Split the bundle with Metro's `--bundle-output` for partial replacement
- EAS Update supports **branch channels**: `preview`, `staging`, `production`
- Track update adoption rates; always maintain a rollback channel

### Selective Native Module Inclusion

Every native module you include (whether used or not) adds to binary size and startup time because the module registry is initialized at launch.

Audit your `package.json` and `Podfile` annually:
- Remove unused `react-native-*` packages entirely
- For Android, use the `autolink` exclusion list in `react-native.config.js`

### Removing Unused Pods / Gradle Dependencies

```bash
# iOS: audit what's linked
cd ios && pod deintegrate && pod install
# Then review Podfile.lock for unexpected large pods

# Android: check dependency tree
cd android && ./gradlew dependencies --configuration releaseRuntimeClasspath
```

---

## 5. Expo-Specific Optimizations

### expo-image vs React Native Image

`expo-image` is a production-grade image component backed by SDWebImage (iOS) and Glide (Android). Key advantages over the built-in `Image`:

- Supports WebP and AVIF out of the box (30–50% smaller than JPEG/PNG)
- Built-in memory + disk LRU cache with configurable policies
- `placeholder` with blurhash for instant perceived load
- Transition animations without JS bridge involvement

```js
import { Image } from 'expo-image';

<Image
  source={{ uri: imageUrl }}
  placeholder={blurHash}
  contentFit="cover"
  transition={200}
  cachePolicy="memory-disk"
/>
```

### Expo Router Lazy Loading

Expo Router uses React Navigation under the hood but adds automatic route-based code splitting. Each route file becomes a separate JS chunk loaded on demand.

To ensure lazy loading works correctly:
- Do not import heavy screens at the layout level
- Use dynamic `import()` for large third-party components inside screens
- Set `initialRouteName` to load only the entry screen's chunk at startup

### EAS Build Optimizations

- Use **EAS Build cache** (`cache.key` in `eas.json`) to avoid re-running CocoaPods install and Gradle dependency resolution on every CI run
- Pin `node`, `yarn`/`npm`, and Xcode versions in `eas.json` to prevent cache invalidation from version drift
- Use `EXPO_NO_DOTENV=1` in CI to prevent accidental `.env` inclusion

### Dev Build vs Expo Go

Expo Go ships with a superset of native modules to support all possible SDK features. A custom dev build includes only the modules your app actually uses. This makes Metro bundling 3–5x faster and makes the running app behavior identical to production.

Migrate to dev builds once your app has any custom native dependency:

```bash
eas build --profile development --platform ios
```

### Expo Modules API for Custom Native Modules

The Expo Modules API generates Turbo Module-compatible bridges automatically. This is faster to write than raw TurboModule JSI, handles Swift/Kotlin type conversions, and is compatible with both Old and New Architecture.

---

## 6. Performance Testing & CI/CD

### Reassure (Render Regression Testing)

Reassure by Callstack measures the render time and render count of components over a statistical sample. It integrates with Jest and produces a JSON report comparing the current branch to the baseline.

```bash
npx reassure check
```

Add to CI to catch regressions before merge. A component that re-renders 3x when it should render 1x will be flagged automatically.

### Flashlight (Automated Android Benchmarks)

Flashlight runs on a real Android device via ADB and measures FPS, thread CPU, and memory during scripted user flows. Unlike Perfetto/Systrace, it produces a normalized score usable in CI comparisons.

```bash
npx @perf-profiler/cli measure --testName "scroll-feed" --duration 5000
```

### Maestro for UI Performance Flows

Maestro records and replays user flows. Combine with Flashlight to measure performance of specific user journeys (app launch, scroll, checkout) consistently across builds.

### Custom Performance Markers

Use `react-native-performance` to emit named marks and measures that appear in Systrace and Instruments:

```js
import performance from 'react-native-performance';

performance.mark('FeedListStart');
// ... render feed
performance.measure('FeedListRender', 'FeedListStart');
```

Track Time-to-Interactive (TTI) from app launch to first meaningful interaction.

### CI Bundle Size Tracking

Add a size-check step to your CI pipeline:

```bash
npx react-native bundle --platform android --dev false --bundle-output /tmp/bundle.js
wc -c /tmp/bundle.js
# Compare to threshold or previous PR value
```

Use tools like `bundlesize` or a simple shell script to fail the build if the bundle grows beyond an accepted threshold.

### Startup Trace Analysis

- **Android**: `adb shell am start -S -W com.yourapp/.MainActivity` measures cold start. Use Perfetto for detailed systrace.
- **iOS**: Instruments → App Launch template gives a flame chart from pre-main to first frame.

Key phases to measure: pre-main (native init), JS engine start, Metro bundle execution, first React render, first native frame.

---

## 7. Real-World Case Studies (Summary)

### Shopify — FlashList (2022)

Shopify's Restyle team replaced FlatList with a purpose-built recycling list (FlashList). Result: **7.5x improvement in JS thread FPS** on the Shopify mobile app's product listing screen. The key insight: FlatList's virtualizer has a JS-side item pool, while FlashList pushes recycling to a native-aware scheduler.

Published paper and benchmark suite available at `shopify.github.io/flash-list`.

### Coinbase — New Architecture Migration (2023)

Coinbase Wallet migrated from the Old Architecture (asynchronous bridge) to Fabric + TurboModules. Result: **55% reduction in startup time**, measured as time from user tap to first interactive frame. The primary gain came from eliminating bridge serialization overhead during module initialization.

### Discord — Memory Optimization (2021)

Discord audited image caching and found unbounded in-memory caches from `react-native-fast-image` combined with no eviction policy. After implementing LRU eviction and switching to compressed texture formats: **40% reduction in OOM crashes** on mid-range Android devices.

### Bloomberg — Hermes Migration (2020)

Bloomberg Terminal app migrated from JSC to Hermes. Result: **26% reduction in memory usage** and significantly improved garbage collection pause times. Hermes's compact bytecode format and register-based VM reduced heap pressure compared to JSC's tree-walking interpreter.

### Meta — Fabric + TurboModules on Large Screens (2022)

Meta's internal apps using Fabric with concurrent rendering showed **20% improvement in render throughput** on large-screen Android devices (tablets, foldables) where layout complexity is highest. The synchronous native commit in Fabric eliminated a class of frame drops caused by bridge batching delays.

---

## Quick Reference Checklist

### Before Shipping

- [ ] Hermes enabled on both platforms
- [ ] `console.log` stripped via Babel plugin
- [ ] Flipper removed from release builds
- [ ] ProGuard/R8 enabled on Android
- [ ] AAB used for Play Store submissions
- [ ] Release build profiled (not dev)
- [ ] Bundle size tracked in CI
- [ ] Images served as WebP/AVIF

### Before Every Render-Heavy Feature

- [ ] New list component uses FlashList with `estimatedItemSize`
- [ ] List items wrapped in `React.memo`
- [ ] Callbacks in list items wrapped in `useCallback`
- [ ] No `key={index}` in dynamic lists
- [ ] No FlatList nested inside ScrollView
- [ ] Animations use `useNativeDriver: true`
- [ ] No layout properties animated (only `transform` + `opacity`)

### Before Every Navigation Screen

- [ ] Screen is lazily loaded
- [ ] Offscreen tabs use `freezeOnBlur` or `react-freeze`
- [ ] Heavy data fetching deferred until screen is focused
- [ ] Navigation state not stored in global monolithic context
