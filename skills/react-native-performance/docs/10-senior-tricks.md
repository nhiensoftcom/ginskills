# Senior-Level React Native Performance Tricks

A collection of hard-won performance knowledge for React Native engineers working on production applications at scale.

---

## 1. Hidden Performance Killers

### console.log in Production

Every `console.log` call serializes its arguments, crosses the JS-to-native bridge, and blocks the JS thread while doing so. In development this is acceptable noise. In production it is silent death by a thousand cuts.

Strip all console calls at build time using the Babel plugin:

```bash
npm install --save-dev babel-plugin-transform-remove-console
```

```js
// babel.config.js
module.exports = {
  plugins: [
    ['transform-remove-console', { exclude: ['error', 'warn'] }],
  ],
};
```

Do not rely on runtime guards like `if (__DEV__)` — the check itself still executes. The plugin removes the call entirely at compile time.

Keep `error` and `warn` if your error tracking system hooks into them, otherwise remove all levels.

### StyleSheet.create vs Inline Style Objects

`StyleSheet.create` registers styles with the native layer once at module initialization and sends them as integer IDs across the bridge. Inline style objects (`style={{ color: 'red' }}`) allocate a new object on every render, increasing GC pressure and preventing the bridge optimization.

```tsx
// Bad — new object every render
<View style={{ flex: 1, backgroundColor: '#fff' }} />

// Good — registered once
const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#fff' },
});
<View style={styles.container} />
```

Exception: truly dynamic values (e.g., `{ width: someVariable }`) must be inline or memoized with `useMemo`.

### Debug Mode is 7-10x Slower

Metro bundles without minification in development. The JS engine runs in interpreted mode, not Hermes bytecode. Remote debugging (deprecated) was even worse — all JS executed in Chrome's V8 over a WebSocket.

**Always profile release builds.** A screen that feels smooth in development may drop frames in production under real-world conditions.

```bash
# Android
npx react-native run-android --variant=release

# iOS
npx react-native run-ios --configuration Release
```

### Flipper: Removed from Template — Stop Adding It Back

Flipper was removed from the React Native default template in RN 0.73. It adds native startup overhead (plugin initialization, socket setup, network interception) and its React DevTools plugin duplicates functionality now available in the standalone **React Native DevTools**, which ships with RN 0.73+ and launches automatically with Metro.

Use React Native DevTools for component inspection, profiling, and network debugging. It has zero production overhead.

### Context Re-renders Every Consumer

React Context has no selector mechanism. Any state change in a context value re-renders **all** consumers of that context, regardless of whether the specific field they use changed.

```tsx
// Bad — all consumers re-render when anything changes
const AppContext = createContext({ user: null, theme: 'light', cart: [] });

// Better — split by update frequency
const UserContext = createContext(null);   // changes rarely
const ThemeContext = createContext('light'); // changes rarely
const CartContext = createContext([]);      // changes often
```

For fine-grained subscriptions without splitting, use Zustand selectors or `use-context-selector`. In React 19+, `use(Context)` with compiler optimizations may alleviate this, but splitting remains the cleaner architecture.

### Platform.select Inside Render

`Platform.select` and `Platform.OS` are constants that never change at runtime. Evaluating them inside a component body is wasted work on every render.

```tsx
// Bad — evaluated every render
function MyComponent() {
  const paddingTop = Platform.select({ ios: 44, android: 0 });
  return <View style={{ paddingTop }} />;
}

// Good — evaluated once at module load
const HEADER_PADDING = Platform.select({ ios: 44, android: 0 });

function MyComponent() {
  return <View style={{ paddingTop: HEADER_PADDING }} />;
}
```

---

## 2. Native-Level Optimizations

### Fabric View Flattening

With the New Architecture (Fabric renderer), React Native automatically flattens layout-only views — views that contribute to layout but render no pixels (no background, border, or touch handler). This reduces native view hierarchy depth and improves traversal speed.

If you hold a `ref` to a view that gets flattened, the ref will be `null`. Use `collapsable={false}` to prevent flattening for a specific view:

```tsx
<View ref={myRef} collapsable={false} style={styles.target} />
```

Do not apply `collapsable={false}` broadly — it defeats the optimization.

### FlashList Cell Recycling

React Native's `FlatList` creates and destroys native views as cells scroll in and out of the viewport. `FlashList` (by Shopify) recycles the view instances — it swaps the data binding instead of destroying and recreating the native view tree. Benchmarks show 5-10x faster scroll performance on large lists.

```bash
npm install @shopify/flash-list
```

```tsx
import { FlashList } from '@shopify/flash-list';

<FlashList
  data={items}
  renderItem={({ item }) => <ItemCard item={item} />}
  estimatedItemSize={80}
  keyExtractor={(item) => item.id}
/>
```

`estimatedItemSize` is required and must be accurate — measure your actual rendered cell height. Inaccurate estimates cause scroll position jumps.

### GPU vs CPU Compositing

Understand which style properties trigger GPU compositing vs CPU layout:

| Property | Pipeline Stage | Cost |
|---|---|---|
| `opacity` | GPU compositing | Low |
| `transform` | GPU compositing | Low |
| `backgroundColor` (change) | CPU paint | Medium |
| `width` / `height` change | CPU layout + paint | High |
| `borderRadius` + shadow | CPU offscreen render | High |

Animate only `opacity` and `transform`. Never animate layout properties (`width`, `height`, `top`, `left`, `margin`, `padding`) — use `transform: [{ translateX }]` instead of animating `left`.

### shouldRasterizeIOS for Static Complex Views

When a view is visually complex but infrequently changes, rasterizing it to a bitmap lets the GPU composite the cached bitmap instead of re-rendering the view hierarchy each frame.

```tsx
<View shouldRasterizeIOS rasterizationScale={PixelRatio.get()}>
  <ComplexStaticBadge />
</View>
```

Use only for truly static views. If the view's content changes frequently, rasterization adds overhead because the bitmap must be invalidated and redrawn.

### iOS Shadows are Expensive

`shadowColor` / `shadowOffset` / `shadowRadius` on iOS trigger an offscreen render pass for the shadow. On a list with 50 cards, that is 50 offscreen passes per frame. On Android, `elevation` uses the Material shadow system which is GPU-accelerated and cheap.

Alternatives for iOS:
- Use a separate sibling "shadow view" positioned behind the card with a blurred background
- Use pre-baked shadow images
- Use a subtle `borderWidth: 1` + `borderColor: 'rgba(0,0,0,0.08)'` — often reads as well as a shadow at a fraction of the cost

### Opacity vs display:none vs Conditional Render

| Technique | Native View Exists | Layout Calculated | JS Component Mounted |
|---|---|---|---|
| `opacity: 0` | Yes | Yes | Yes |
| `display: 'none'` | Yes | No | Yes |
| Conditional render (`&&`) | No | No | No (unmounted) |
| `react-freeze` | Yes | Yes | Yes (frozen) |

Use `display: 'none'` when you want to hide without unmounting (preserves state, avoids re-mount cost). Use conditional rendering when the hidden content is heavy and you want to free memory. Use `opacity: 0` only for animation transitions.

---

## 3. React Compiler (2025 Game-Changer)

### What React Compiler Does

React Compiler (formerly "React Forget") performs static analysis of your component code and automatically inserts memoization — eliminating the need to manually write `useMemo`, `useCallback`, and `React.memo`.

Measured impact from Meta's production rollout across 1,231 components:
- 20-30% reduction in render time
- No code changes required beyond enabling the compiler

### Expo SDK 54 Default Enablement

Expo SDK 54 enables React Compiler by default for new projects. For existing projects:

```bash
npx expo install babel-plugin-react-compiler
```

```js
// babel.config.js
module.exports = {
  plugins: ['babel-plugin-react-compiler'],
};
```

### React Compiler 1.0 Metrics

React Compiler 1.0 (released 2025) shows:
- 12% faster initial load times
- 2.5x quicker interaction response times
- Automatic optimization of previously unoptimized components

### When Manual Memoization Still Matters

React Compiler handles most cases but cannot optimize:
- Impure functions that read external mutable state
- Components using non-standard patterns the compiler cannot analyze
- Third-party library components you do not own

In these cases, manual `useMemo`/`useCallback` remains necessary.

---

## 4. Advanced React Patterns

### react-freeze for Offscreen Tabs

Tab navigators keep all tab screens mounted to preserve state. Those mounted-but-invisible screens still participate in React's render cycle. `react-freeze` uses React's experimental `<Offscreen>` primitive to freeze the render tree of inactive screens.

```bash
npm install react-freeze
```

```tsx
import { enableFreeze } from 'react-freeze';

// Call once at app startup, before any navigation renders
enableFreeze(true);
```

React Navigation 6+ integrates react-freeze automatically via the `freezeOnBlur` prop on `Screen`. No further configuration needed in most setups.

### useTransition and useDeferredValue

For heavy list filtering, search, or sorting operations, defer the expensive re-render to avoid blocking user input:

```tsx
import { useTransition, useDeferredValue } from 'react';

function SearchScreen() {
  const [query, setQuery] = useState('');
  const [isPending, startTransition] = useTransition();
  const deferredQuery = useDeferredValue(query);

  const results = useMemo(
    () => filterLargeDataset(deferredQuery),
    [deferredQuery]
  );

  return (
    <>
      <TextInput
        value={query}
        onChangeText={(text) => {
          setQuery(text); // Immediate update for the input
          startTransition(() => {
            // Transition marker — heavy re-renders are interruptible
          });
        }}
      />
      {isPending && <ActivityIndicator />}
      <ResultsList data={results} />
    </>
  );
}
```

### Suspense Boundaries for Code Splitting

React Native supports `React.lazy` with Metro bundler for component-level code splitting. Wrap lazy-loaded components in Suspense boundaries to prevent the entire screen from blocking:

```tsx
const HeavyChart = React.lazy(() => import('./HeavyChart'));

function AnalyticsScreen() {
  return (
    <View>
      <Header />
      <Suspense fallback={<ChartSkeleton />}>
        <HeavyChart />
      </Suspense>
    </View>
  );
}
```

### Error Boundaries Prevent Cascade Re-renders

An unhandled error in a child component causes React to unmount and remount the entire subtree up to the nearest error boundary. Without boundaries, a transient error in a card component can trigger a full-screen remount. Place error boundaries at the route/screen level at minimum, and at the widget level for independently failing UI sections.

### Compound Component Pattern for Forms

Large form components with many conditional fields become slow when the entire form re-renders on each keystroke. The compound component pattern isolates re-renders to individual fields:

```tsx
// Each Field subscribes only to its own value via internal context
<Form onSubmit={handleSubmit}>
  <Form.Field name="email" component={EmailInput} />
  <Form.Field name="password" component={PasswordInput} />
  <Form.Submit label="Sign In" />
</Form>
```

Libraries like `react-hook-form` implement this pattern — input changes do not re-render sibling fields.

---

## 5. Build Optimizations

### Hermes Bytecode Precompilation

Hermes compiles JavaScript to bytecode at build time rather than at runtime on the device. This moves JIT compilation cost from app startup to CI/CD. Hermes is enabled by default in React Native 0.70+.

**Measured impact**: 20-40% reduction in TTI (Time to Interactive) vs JSC.

Verify it is running:

```tsx
import { HermesInternal } from 'global';
const isHermes = () => !!HermesInternal;
```

### Inline Requires (Lazy Module Loading)

Metro supports `inlineRequires` — modules are not evaluated until their first `require()` call during runtime, rather than all being evaluated at startup.

```js
// metro.config.js
module.exports = {
  transformer: {
    getTransformOptions: async () => ({
      transform: {
        inlineRequires: true,
      },
    }),
  },
};
```

Combined with Hermes: **42% TTI reduction** measured in production (3.6s to 2.1s).

### ProGuard/R8 for Android

R8 (the successor to ProGuard) minifies, shrinks, and obfuscates the Android APK. For React Native apps with many Java/Kotlin dependencies, typical result is 50-70% APK size reduction.

```gradle
// android/app/build.gradle
buildTypes {
    release {
        minifyEnabled true
        shrinkResources true
        proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
    }
}
```

### AAB Format Over APK

Android App Bundle (AAB) lets Google Play deliver device-specific APKs — only the ABI, screen density, and language assets needed by the specific device are downloaded. Result: ~30% smaller download size for end users.

```bash
cd android && ./gradlew bundleRelease
```

Use `bundleRelease` instead of `assembleRelease` for Play Store submissions.

### EAS Update for OTA Delta Updates

Expo Application Services (EAS) Update delivers only the changed JS bundle delta, not the full bundle:
- Full bundle: 3-8 MB download
- Delta update: 50-200 KB download

This results in 10-20x smaller OTA updates and dramatically faster update adoption across your user base.

### Asset Optimization Checklist

- Convert PNG/JPEG to **WebP** (25-35% smaller, hardware-decoded on Android)
- Use **.lottie** format (binary Lottie) instead of JSON — up to 90% smaller Lottie files
- **Font subsetting**: include only the Unicode ranges your app uses (tools: `pyftsubset`, `glyphhanger`)
- Enable **asset hashing** in Metro for long-term CDN caching
- Use `@2x` and `@3x` image variants — React Native selects the correct density automatically

---

## 6. Performance Testing in CI/CD

### Reassure — Render Time Regression Testing

Reassure measures React component render time and flags regressions in pull requests. It runs as part of your test suite.

```bash
npm install --save-dev reassure
```

```tsx
// __tests__/ProductList.perf-test.tsx
import { measurePerformance } from 'reassure';

test('ProductList renders efficiently', async () => {
  await measurePerformance(<ProductList items={mockItems} />);
});
```

Reassure generates a performance report comparing `main` vs the PR branch. Integrate with Danger or GitHub Actions to comment the diff on each PR.

### Flashlight — Automated Android Benchmarks

Flashlight wraps Android's `perfetto` tracing and provides a CLI for automated performance measurement:

```bash
npx @perf-tools/flashlight measure --apk MyApp.apk --test e2e/scroll.js
```

Outputs: FPS, frame time percentiles, CPU/GPU usage. Runs in CI against real or emulated devices.

### Maestro — UI Performance Testing

Maestro drives your app via YAML flow files and can measure screen-to-screen transition times:

```yaml
# flows/home-to-detail.yaml
appId: com.myapp
---
- launchApp
- tapOn: "Product Card"
- assertVisible: "Product Detail Screen"
```

Combine with Flashlight to capture frame data during the Maestro flow.

### Bundle Size Tracking Per PR

Track JS bundle size as a CI metric:

```bash
npx react-native bundle --platform android --dev false --entry-file index.js \
  --bundle-output /tmp/bundle.js && wc -c /tmp/bundle.js
```

Set a budget (e.g., fail CI if bundle exceeds 3 MB) and report size delta per PR using the `bundlesize` package or a simple shell threshold check.

---

## 7. Platform-Specific Profiling

### iOS: Instruments Time Profiler

Instruments ships with Xcode and is the authoritative iOS performance tool. For React Native:

1. Build a release scheme in Xcode (`Product > Scheme > Edit Scheme > Run > Release`)
2. Open Instruments (`Xcode > Open Developer Tool > Instruments`)
3. Select **Time Profiler** — shows CPU time per call stack
4. Select **Core Animation** — shows frame rate and dropped frames

Look for JS thread CPU spikes that correlate with frame drops in Core Animation.

### iOS: MetricKit for Production Telemetry

MetricKit (iOS 13+) delivers aggregate performance metrics from real user devices via the App Store. Access via App Store Connect or by implementing the `MXMetricManagerSubscriber` protocol in your AppDelegate.

Key metrics to monitor: `MXAppLaunchDiagnostic`, `MXHangDiagnostic` (JS thread blocking), `MXCPUMetric`.

### Android: GPU Overdraw Detection

Enable overdraw visualization in Developer Options: `Developer Options > Debug GPU overdraw > Show overdraw areas`.

- Blue = 1x overdraw (acceptable)
- Green = 2x
- Pink = 3x
- Red = 4x+ (investigate)

Common React Native overdraw culprits: nested Views with `backgroundColor`, `ImageBackground` with tinted overlay, status bar background duplication.

### Android: systrace

```bash
python $ANDROID_HOME/platform-tools/systrace/systrace.py \
  --time=5 -o trace.html gfx view res
```

Open `trace.html` in Chrome at `chrome://tracing`. Look for `Choreographer#doFrame` duration — anything over 16ms causes a dropped frame.

### 120Hz Frame Budget

On ProMotion displays (iPhone 13 Pro+, many Android flagships), the frame budget is **8.33ms**, not 16.67ms. A component that just barely fits the 60Hz budget will drop frames on 120Hz devices.

React Native does not currently render at 120Hz by default. To enable on iOS experimentally:

```objc
// AppDelegate.mm
RCTSetFrameRate(120);
```

Verify your JS workload can sustain the tighter budget before shipping to users.

---

## 8. Case Studies

### Shopify: Sub-500ms P75 Screen Loads

Shopify's mobile team published benchmarks showing P75 screen load times under 500ms across their React Native app after:

- Migrating all long lists to FlashList (which they created)
- Adopting Hermes with `inlineRequires: true`
- Implementing per-screen Suspense boundaries with skeleton screens
- 86% code shared between iOS and Android

FlashList was created internally at Shopify to solve FlatList performance for their product catalog and open-sourced in 2022.

### Coinbase: Near-Native Performance After Migration

Coinbase migrated from native-per-platform to React Native and documented near-native performance for their core trading screens. Key decisions:

- Full New Architecture adoption (Fabric + TurboModules) from the start
- Custom native modules for cryptographic operations (never in JS)
- Gesture handling with react-native-gesture-handler (native thread)

### Bloomberg: Dual Platform in 5 Months

Bloomberg built their consumer app for both iOS and Android in 5 months with a small team using React Native. Performance parity with their native app was achieved by:

- Keeping data transformation in native modules
- Using native navigation (not JS stack)
- Offloading chart rendering to a native WebGL view

### Measured: Hermes + inlineRequires = 42% TTI Reduction

A production measurement from a mid-size e-commerce app:

| Metric | Before | After | Delta |
|---|---|---|---|
| TTI (P50) | 3.6s | 2.1s | -42% |
| JS parse time | 1.2s | 0.3s | -75% |
| Bundle size | 4.1 MB | 4.1 MB | 0% |

The combination of Hermes bytecode precompilation and `inlineRequires: true` deferred loading of non-critical modules until after first render. No UI or logic changes were made.
