# React Native Startup Optimization — Deep Dive

## 1. Cold Start Lifecycle Breakdown

A cold start begins the moment the OS launches the app process and ends when the user can meaningfully interact with the first screen (TTI — Time To Interactive). The pipeline has five distinct phases.

### Phase 1: Native Initialization (0–200 ms)
The OS creates the app process, links dynamic libraries, runs `+load` / `__attribute__((constructor))` functions, and initializes the AppDelegate (iOS) or MainActivity (Android). This phase is largely outside your control, but third-party SDKs that register `+load` methods silently add cost here.

- iOS flagship: ~50–80 ms
- Mid-tier Android: ~100–200 ms
- Low-end Android: ~150–300 ms

**What inflates it:** too many `+[Class load]` methods (Objective-C), JVM class initialization (Android), large number of linked dynamic frameworks.

### Phase 2: Bridge / JSI Initialization (50–150 ms)
React Native creates the JS runtime (Hermes or JavaScriptCore) and wires up the communication layer — either the legacy Bridge or the new JSI + Fabric pipeline. TurboModules are registered here.

- With Hermes + New Architecture: ~50–80 ms
- With JSC + Old Architecture: ~100–150 ms

**What inflates it:** JSC is slower to initialize than Hermes; old Bridge serializes the full native module table at startup.

### Phase 3: JS Bundle Load & Evaluation (100–600 ms)
Metro bundles all JS into a single file (or multiple chunks). The runtime reads the file from disk, parses it, and evaluates every `require()` call at the top level unless `inlineRequires` is enabled.

- 1 MB gzip bundle, Hermes bytecode: ~100–150 ms
- 4 MB gzip bundle, JSC: ~400–600 ms

**What inflates it:** large bundles, synchronous `require()` chains, moment.js (entire locale set), lodash (full build), unoptimized barrel exports.

### Phase 4: React Render (50–300 ms)
React mounts the root component tree: context providers, navigation container, authentication gate, and the first screen. Shadow tree reconciliation (Fabric) or layout calculation (old renderer) happens here.

- Shallow tree, no data fetching: ~50–80 ms
- Deep provider tree + async auth check: ~150–300 ms

**What inflates it:** too many context providers at root, synchronous storage reads in component body, heavy computation in `useMemo` during first render, deeply nested navigators all mounting simultaneously.

### Phase 5: First Meaningful Paint → TTI
The native layout pass completes, the splash screen hides, and JS event handlers are attached. TTI is reached when the user can tap a button and get a response within 100 ms.

### Full Timeline (Hermes + New Architecture, iOS Flagship)

```
0 ms      Process created
  50 ms   Native init complete
  120 ms  JSI + Hermes initialized
  220 ms  Bundle read from disk
  320 ms  Bundle evaluation complete (inlineRequires ON)
  380 ms  Root component mounted
  430 ms  First screen rendered
  470 ms  Splash hidden, TTI reached   ← target ≤ 500 ms visible
```

---

## 2. Cold Start Targets

| Device Tier | Example Devices | Target TTI |
|---|---|---|
| iOS flagship | iPhone 15 Pro, iPhone 14 | ≤ 1.5 s |
| iOS mid-range | iPhone 12, iPhone SE 3 | ≤ 1.8 s |
| Android flagship | Pixel 8, Samsung S24 | ≤ 1.5 s |
| Mid-tier Android | Pixel 6a, Moto G73 | ≤ 2.0 s |
| Low-end Android | Redmi 12C, Galaxy A14 | ≤ 2.5 s |

**Budget allocation (mid-tier Android, 2.0 s target):**

| Phase | Budget |
|---|---|
| Native init | 250 ms |
| JSI init | 150 ms |
| Bundle load + eval | 700 ms |
| React render | 400 ms |
| Paint + TTI | 500 ms |

---

## 3. Quick Wins

### 3.1 Enable Hermes

Hermes compiles JS to bytecode at build time, eliminating parse time at runtime. Verify it is active:

```ts
// app entry point or debug screen
const isHermes = () => !!global.HermesInternal;
console.log('Hermes enabled:', isHermes());
```

In `android/app/build.gradle`:
```gradle
project.ext.react = [
  enableHermes: true,
]
```

In Podfile (iOS), Hermes is the default since RN 0.70. For Expo, set in `app.json`:
```json
{
  "expo": {
    "jsEngine": "hermes"
  }
}
```

Benchmark: switching from JSC to Hermes typically reduces bundle evaluation time by 40–60% on Android.

### 3.2 Enable `inlineRequires` in Metro

`inlineRequires` transforms `import` / `require` calls so that module evaluation is deferred until the first time that module is actually used — instead of eagerly evaluating every module when the bundle loads.

```js
// metro.config.js
const { getDefaultConfig } = require('@expo/metro-config');
const config = getDefaultConfig(__dirname);

config.transformer.minifierConfig = {};
config.transformer.getTransformOptions = async () => ({
  transform: {
    experimentalImportSupport: false,
    inlineRequires: true,        // <-- defer module evaluation
  },
});

module.exports = config;
```

Effect: a screen that is never visited contributes zero evaluation cost at startup. Typical saving: 100–300 ms on a 3 MB bundle.

**Caveat:** modules with side effects on `require` may behave differently. Test thoroughly after enabling.

### 3.3 Splash Screen — react-native-bootsplash vs react-native-splash-screen

`react-native-splash-screen` has a known white-flash issue on Android because it hides the splash and shows a blank white view before React renders. `react-native-bootsplash` uses a native activity theme for the splash, so there is zero white flash.

```ts
// Correct bootsplash hide — fade out after first render is ready
import BootSplash from 'react-native-bootsplash';

function App() {
  const onLayoutRootView = useCallback(async () => {
    await BootSplash.hide({ fade: true });
  }, []);

  return <RootNavigator onLayout={onLayoutRootView} />;
}
```

### 3.4 Visualize Your Bundle

```bash
npx react-native-bundle-visualizer
```

This generates an interactive treemap of every module by byte size. Use it to identify which packages dominate the bundle and whether tree shaking is working.

### 3.5 Replace Heavy Libraries

| Before | After | Saving |
|---|---|---|
| `moment` (330 KB) | `dayjs` (7 KB) | ~320 KB |
| `lodash` (full build, 72 KB gzip) | Individual imports `lodash/debounce` | ~60 KB |
| `uuid` | `crypto.randomUUID()` (native) | ~12 KB |
| `axios` | `fetch` + custom wrapper | ~14 KB |
| `@expo/vector-icons` (full set) | Icon subset via `createIconSet` | ~200 KB |

---

## 4. Lazy Loading Strategies

### 4.1 React.lazy + Suspense for Screens

```tsx
import React, { Suspense, lazy } from 'react';
import { ActivityIndicator } from 'react-native';

const ProfileScreen = lazy(() => import('./ProfileScreen'));
const SettingsScreen = lazy(() => import('./SettingsScreen'));

function Navigator() {
  return (
    <Suspense fallback={<ActivityIndicator />}>
      <Stack.Screen name="Profile" component={ProfileScreen} />
      <Stack.Screen name="Settings" component={SettingsScreen} />
    </Suspense>
  );
}
```

### 4.2 Navigation Lazy Loading

React Navigation supports lazy tab mounting out of the box:

```tsx
<Tab.Navigator screenOptions={{ lazy: true }}>
  <Tab.Screen name="Home" component={HomeScreen} />
  <Tab.Screen name="Explore" component={ExploreScreen} />  {/* not mounted until tab is tapped */}
  <Tab.Screen name="Profile" component={ProfileScreen} />
</Tab.Navigator>
```

### 4.3 Dynamic Import for Heavy Modules

```ts
// Don't import at the top of the file
// import { manipulateAsync } from 'expo-image-manipulator';

async function processPhoto(uri: string) {
  // Load only when the feature is invoked
  const { manipulateAsync, SaveFormat } = await import('expo-image-manipulator');
  return manipulateAsync(uri, [{ resize: { width: 800 } }], { format: SaveFormat.JPEG });
}
```

### 4.4 TurboModules Lazy Initialization

New Architecture TurboModules are lazy by default — they are only instantiated when first accessed. Verify your native modules are not calling into JS eagerly during `initialize()`.

### 4.5 Conditional Feature Loading

```ts
async function loadPremiumFeatures() {
  const user = await getUser();
  if (user.plan === 'premium') {
    // Only load the premium bundle chunk if the user needs it
    const { PremiumDashboard } = await import('./features/premium/PremiumDashboard');
    return PremiumDashboard;
  }
  return null;
}
```

---

## 5. Defer Non-Critical Initialization

Services like analytics, crash reporting, push notifications, and social SDKs are not needed before the first frame paints. Delaying them removes their cost from the critical path.

```tsx
import { InteractionManager, useEffect } from 'react';
import * as Sentry from '@sentry/react-native';
import analytics from '@react-native-firebase/analytics';

function AppInit() {
  useEffect(() => {
    // Run after all animations and interactions settle
    const task = InteractionManager.runAfterInteractions(async () => {
      // Crash reporting
      Sentry.init({ dsn: process.env.SENTRY_DSN });

      // Analytics (no events are lost — they queue until init)
      await analytics().setAnalyticsCollectionEnabled(true);

      // Push notifications (permission prompt should not block first render)
      await registerPushNotifications();

      // Social SDKs
      await initializeFacebookSDK();
    });

    return () => task.cancel();
  }, []);

  return null;
}
```

**Deferral priority table:**

| Service | Strategy | Rationale |
|---|---|---|
| Sentry | After first render | Stack traces still captured; init cost ~80 ms |
| Firebase Analytics | After interactions | Events are buffered internally |
| Push notifications | After interactions | Permission prompt must not appear on cold start |
| Social login SDKs | Lazy TurboModule | Only needed at sign-in screen |
| Deep link processing | Queue + drain after TTI | Link data is available in state; no urgency |
| Ad SDKs | Lazy, first ad request | Never init at startup |

### Deep Link Queueing Pattern

```ts
// deepLinkQueue.ts
const queue: string[] = [];
let isReady = false;

export function enqueueDeepLink(url: string) {
  if (isReady) {
    processDeepLink(url);
  } else {
    queue.push(url);
  }
}

export function drainDeepLinkQueue() {
  isReady = true;
  queue.splice(0).forEach(processDeepLink);
}

// In App.tsx, after TTI:
useEffect(() => {
  InteractionManager.runAfterInteractions(() => {
    drainDeepLinkQueue();
  });
}, []);
```

---

## 6. Splash Screen Strategies

The ideal progression:

```
Native splash (instant) → JS splash/skeleton → Skeleton with data → Full content
```

### 6.1 react-native-bootsplash Setup

```ts
// App.tsx
import BootSplash from 'react-native-bootsplash';
import { NavigationContainer } from '@react-navigation/native';

function App() {
  return (
    <NavigationContainer
      onReady={() => {
        // Hide only when navigation is fully mounted
        BootSplash.hide({ fade: true });
      }}
    >
      <RootNavigator />
    </NavigationContainer>
  );
}
```

### 6.2 Skeleton Screen Pattern

Show a skeleton that mirrors the layout of the content screen, so the transition feels instant even if data is loading:

```tsx
function HomeScreen() {
  const { data, isLoading } = useHomeData();

  if (isLoading) {
    return <HomeScreenSkeleton />;   // matches exact layout of HomeScreen
  }

  return <HomeScreenContent data={data} />;
}

function HomeScreenSkeleton() {
  return (
    <View style={styles.container}>
      <SkeletonBox width="60%" height={24} style={styles.title} />
      <SkeletonBox width="100%" height={120} style={styles.hero} />
      {Array.from({ length: 4 }).map((_, i) => (
        <SkeletonBox key={i} width="100%" height={72} style={styles.listItem} />
      ))}
    </View>
  );
}
```

### 6.3 Progressive Content Loading

Use TanStack Query's `placeholderData` to show stale data immediately while fresh data loads in the background:

```ts
const { data } = useQuery({
  queryKey: ['home-feed'],
  queryFn: fetchHomeFeed,
  placeholderData: keepPreviousData,   // show last known data instantly
  staleTime: 30_000,
});
```

---

## 7. Module Initialization Order

### Critical Path (must be ready before first render)

1. Async storage / SecureStore — for auth token retrieval
2. Auth state resolver — determine if user is logged in
3. Navigation container — determines which screen to mount
4. Core UI theme / design tokens

### Deferred Path (init after TTI)

1. Analytics SDK
2. Push notification registration
3. Social login SDKs (Facebook, Google)
4. Ad networks
5. Feature flag polling

### How `inlineRequires` Changes Evaluation Order

Without `inlineRequires`, all modules are evaluated top-to-bottom at bundle load time. With it enabled, modules are evaluated on first access:

```ts
// This import is hoisted to the call site at runtime when inlineRequires is ON
import heavyModule from './heavyModule';  // evaluated on first use, not at bundle load

function onUserTapFeature() {
  heavyModule.doWork();  // <-- heavyModule is first evaluated HERE
}
```

For modules you need immediately (auth, navigation), this is neutral. For modules used only in later screens, this is a significant win.

### require() vs import for Lazy Modules

```ts
// Eager (bad for startup) — evaluated at bundle load
import { Chart } from 'react-native-chart-kit';

// Lazy alternative — evaluated only when ChartScreen mounts
function ChartScreen() {
  const [ChartModule, setChartModule] = useState(null);

  useEffect(() => {
    import('react-native-chart-kit').then(m => setChartModule(() => m.Chart));
  }, []);

  if (!ChartModule) return <Skeleton />;
  return <ChartModule data={chartData} />;
}
```

---

## 8. Resource Preloading

### 8.1 Font Preloading

```ts
// Expo
import * as Font from 'expo-font';

async function preloadFonts() {
  await Font.loadAsync({
    'Inter-Regular': require('./assets/fonts/Inter-Regular.ttf'),
    'Inter-Bold': require('./assets/fonts/Inter-Bold.ttf'),
  });
}

// In App.tsx root, before rendering any text
const [fontsLoaded] = useFonts({
  'Inter-Regular': require('./assets/fonts/Inter-Regular.ttf'),
});

if (!fontsLoaded) return <SplashScreen />;
```

### 8.2 Image Prefetching

```ts
// React Native built-in
await Image.prefetch('https://cdn.example.com/hero-image.jpg');

// expo-image (preferred — uses shared cache, supports blurhash placeholder)
import { Image } from 'expo-image';

await Image.prefetch([
  'https://cdn.example.com/avatar-1.jpg',
  'https://cdn.example.com/avatar-2.jpg',
]);

// Show placeholder while loading
<Image
  source={{ uri: imageUrl }}
  placeholder={blurhash}
  contentFit="cover"
  transition={200}
/>
```

### 8.3 Data Prefetching with TanStack Query

```ts
// Prefetch critical data before navigation — user perceives zero loading time
import { queryClient } from './queryClient';

async function onAppReady() {
  // Prefetch in parallel
  await Promise.all([
    queryClient.prefetchQuery({
      queryKey: ['user', userId],
      queryFn: () => fetchUser(userId),
      staleTime: 60_000,
    }),
    queryClient.prefetchQuery({
      queryKey: ['home-feed'],
      queryFn: fetchHomeFeed,
      staleTime: 30_000,
    }),
  ]);
}
```

### 8.4 Pre-warming the JS Engine on Android

Android supports `ReactInstanceManager` pre-warming. When using Expo or the default RN setup, you can trigger engine pre-warm during the native splash before the JS bundle is requested:

```java
// MainApplication.java (Old Architecture)
@Override
public void onCreate() {
  super.onCreate();
  // Pre-warm: starts Hermes initialization in background thread
  ReactNativeHost host = getReactNativeHost();
  host.getReactInstanceManager().createReactContextInBackground();
}
```

For New Architecture, this is handled automatically by the ReactHost lifecycle.

---

## 9. Measuring Startup

### 9.1 react-native-performance

```ts
import { performance, PerformanceObserver } from 'react-native-performance';

// Mark TTI when the first screen is interactive
function HomeScreen() {
  useEffect(() => {
    performance.mark('tti');
    performance.measure('cold-start-to-tti', 'nativeLaunchStart', 'tti');
  }, []);
}

// Observe and log all measures
const observer = new PerformanceObserver((list) => {
  list.getEntries().forEach((entry) => {
    console.log(`[Perf] ${entry.name}: ${entry.duration.toFixed(0)} ms`);
  });
});
observer.observe({ type: 'measure' });
```

Built-in marks available: `nativeLaunchStart`, `nativeLaunchEnd`, `downloadStart`, `downloadEnd`, `runJsBundleStart`, `runJsBundleEnd`.

### 9.2 Custom Performance Marks

```ts
// Track each phase manually for granular profiling
performance.mark('auth-check-start');
const user = await resolveAuthState();
performance.mark('auth-check-end');
performance.measure('auth-check', 'auth-check-start', 'auth-check-end');

performance.mark('navigation-ready');
performance.measure('js-to-nav', 'runJsBundleEnd', 'navigation-ready');
```

### 9.3 Sentry App Start Tracking

```ts
import * as Sentry from '@sentry/react-native';

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  tracesSampleRate: 0.2,
  enableAppStartTracking: true,       // auto-captures cold/warm start spans
  enableNativeFramesTracking: true,
});
```

Sentry automatically captures `app.start.cold` and `app.start.warm` transactions with sub-spans for JS bundle load, first render, and TTI.

### 9.4 Firebase Performance Custom Traces

```ts
import perf from '@react-native-firebase/perf';

async function measureStartup() {
  const trace = await perf().startTrace('cold_start_tti');

  // ... app init logic ...

  trace.putAttribute('hermes_enabled', String(!!global.HermesInternal));
  trace.putMetric('bundle_size_kb', bundleSizeKb);

  await trace.stop();  // reported to Firebase dashboard
}
```

### 9.5 Flipper Startup Profiling

1. Open Flipper → connect device
2. Plugin: **Hermes Debugger** → CPU Profiler → Start profiling
3. Kill and relaunch the app
4. Stop profiling after first screen renders
5. Inspect the flame graph — look for wide synchronous bars in the JS thread during bundle evaluation

For Android, **Android Studio Profiler** (CPU → Callstack Sample) gives native-level insight into what happens before the JS thread starts.

### 9.6 Benchmark Regression Guard

Add a startup time CI check to catch regressions:

```bash
# Using Flashlight (https://flashlight.dev)
flashlight measure \
  --bundleId com.example.app \
  --scenario startup \
  --iterations 5 \
  --output startup-report.json

# Assert TTI < 2000ms in CI
node -e "
  const report = require('./startup-report.json');
  const avgTTI = report.average.timeToInteractive;
  if (avgTTI > 2000) { console.error('TTI regression:', avgTTI); process.exit(1); }
  console.log('TTI OK:', avgTTI);
"
```

---

## Summary: Startup Optimization Priority

| Priority | Action | Typical Saving |
|---|---|---|
| P0 | Enable Hermes | 40–60% eval time reduction |
| P0 | Enable `inlineRequires` | 100–300 ms |
| P1 | Remove / replace heavy libs | 50–200 ms |
| P1 | Defer analytics + push init | 80–150 ms |
| P1 | Switch to react-native-bootsplash | Eliminates white flash |
| P2 | Lazy-load non-critical screens | 30–100 ms |
| P2 | Prefetch critical data | Perceived 0 ms load |
| P3 | Skeleton screens | Perceived performance |
| P3 | Pre-warm JS engine (Android) | 50–100 ms |
| P3 | Image + font preloading | Eliminates layout shift |
