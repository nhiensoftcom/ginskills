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

### 4.6 Expo Router Lazy Loading

Expo Router's file-based routing introduces routing overhead that is worth understanding. Every file under `app/` is registered as a route at startup, but screen modules are code-split automatically — only the currently active route's module is evaluated.

**File-based routing performance implications:**

- Route discovery (scanning `app/` directory) happens at build time, not runtime — no overhead at startup.
- Dynamic segments (`app/user/[id].tsx`) run a regex match per navigation event. On deeply nested or heavily parameterized routes this is negligible (<1 ms), but avoid deeply stacked dynamic segments on the critical path.
- Expo Router wraps React Navigation internally; the `lazy` option on tab navigators is respected.

**Automatic code splitting with Expo Router:**

Metro splits each route file into its own chunk when `bundleSplitting` is enabled (Expo SDK 51+). Each screen file is only downloaded and evaluated on first visit.

```json
// app.json
{
  "expo": {
    "experiments": {
      "reactCanary": false
    }
  }
}
```

**Lazy screen routes in tab/stack configuration:**

```tsx
// app/(tabs)/_layout.tsx
import { Tabs } from 'expo-router';

export default function TabLayout() {
  return (
    // lazy={true} is the default in Expo Router — tabs are not mounted until first visit
    <Tabs screenOptions={{ lazy: true }}>
      <Tabs.Screen name="index" options={{ title: 'Home' }} />
      <Tabs.Screen name="explore" options={{ title: 'Explore' }} />
      {/* This tab's JS module is never evaluated until the user taps it */}
      <Tabs.Screen name="settings" options={{ title: 'Settings' }} />
    </Tabs>
  );
}
```

```tsx
// app/(tabs)/explore.tsx — this entire module is deferred until first tab visit
import { HeavyChart } from '../../components/HeavyChart';

export default function ExploreScreen() {
  return <HeavyChart />;
}
```

**Optimized Expo Router app entry:**

```tsx
// app/_layout.tsx — keep this as lean as possible; it runs on every cold start
import { Stack } from 'expo-router';
import { SplashScreen } from 'expo-router';
import { useEffect } from 'react';
import { useFonts } from 'expo-font';

// Prevent splash from hiding before assets are ready
SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const [fontsLoaded] = useFonts({
    'Inter-Regular': require('../assets/fonts/Inter-Regular.ttf'),
  });

  useEffect(() => {
    if (fontsLoaded) {
      // Hide splash only after fonts are ready — avoids FOUT
      SplashScreen.hideAsync();
    }
  }, [fontsLoaded]);

  if (!fontsLoaded) return null;

  return (
    <Stack>
      {/* index is on the critical path — keep it lightweight */}
      <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
      {/* Modal screens are lazy — not evaluated until opened */}
      <Stack.Screen name="modal/camera" options={{ presentation: 'modal' }} />
      <Stack.Screen name="modal/share" options={{ presentation: 'modal' }} />
    </Stack>
  );
}
```

**Dynamic route matching overhead:** If you have many dynamic routes, prefer static routes for your most-visited paths. For example, use `app/profile.tsx` for the self-profile (static) and `app/user/[id].tsx` for other users (dynamic). The static match short-circuits before the regex engine runs.

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

### 6.4 expo-splash-screen vs react-native-bootsplash

Both libraries solve the splash screen problem, but with meaningfully different trade-offs depending on your project setup.

| Feature | `expo-splash-screen` | `react-native-bootsplash` |
|---|---|---|
| Expo managed workflow | Native support, zero config | Requires bare workflow or config plugin |
| Expo bare / RN CLI | Supported via config plugin | Fully supported, manual setup |
| White flash on Android | Possible if `hideAsync` called late | None — uses Activity theme for splash |
| Animated transition | JS-only fade/scale via `Animated` | Native `UIViewPropertyAnimator` (iOS) + ObjectAnimator (Android) |
| Lottie support | No native lottie | Yes, via `@bam.tech/react-native-bootsplash` v5 |
| Asset generation CLI | `npx expo install` + config | `npx react-native generate-bootsplash` |
| Dark mode splash | Supported via asset catalogs | Supported via asset catalogs |
| Custom brand animation | Manual (JS Animated API) | Native animation, lower jank risk |
| Bundle size impact | ~2 KB (JS only) | ~8 KB native + ~3 KB JS |
| Recommended for | Expo Go / managed workflow | Bare workflow with custom animations |

**Transition choreography: native splash → skeleton → content**

The goal is a seamless, perceptually fast transition with no blank white frames.

```
[0 ms]    Native splash (Activity theme — zero JS cost)
[+Xms]    JS bundle evaluates, root component mounts
[+Xms]    SplashScreen.hideAsync() called — native fade begins
[+200ms]  Skeleton screen is visible (content layout placeholder)
[+300ms]  Data arrives from cache or network
[+350ms]  Real content replaces skeleton with a subtle fade
```

With `expo-splash-screen`:

```tsx
// app/_layout.tsx
import * as SplashScreen from 'expo-splash-screen';
import Animated, { FadeIn } from 'react-native-reanimated';

SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const [appReady, setAppReady] = useState(false);

  useEffect(() => {
    async function prepare() {
      try {
        await Promise.all([
          loadFonts(),
          resolveAuthState(),
          queryClient.prefetchQuery({ queryKey: ['home-feed'], queryFn: fetchHomeFeed }),
        ]);
      } finally {
        setAppReady(true);
        // Fade takes 300ms on native side, matching our skeleton reveal
        await SplashScreen.hideAsync();
      }
    }
    prepare();
  }, []);

  if (!appReady) return null;

  // Fade-in the first real view so it blends with the native splash fade-out
  return (
    <Animated.View style={{ flex: 1 }} entering={FadeIn.duration(200)}>
      <Stack />
    </Animated.View>
  );
}
```

With `react-native-bootsplash` (bare workflow, Lottie brand animation):

```tsx
// App.tsx
import BootSplash from 'react-native-bootsplash';
import { NavigationContainer } from '@react-navigation/native';

function App() {
  const handleNavigationReady = async () => {
    // Native animator runs: logo shrinks + fades, content rises
    await BootSplash.hide({
      fade: true,     // cross-fade duration: 220ms native
    });
  };

  return (
    <NavigationContainer onReady={handleNavigationReady}>
      <RootNavigator />
    </NavigationContainer>
  );
}
```

**Measuring splash duration:**

```ts
import * as SplashScreen from 'expo-splash-screen';
import { performance } from 'react-native-performance';

// Mark when hide is requested
performance.mark('splash-hide-request');
await SplashScreen.hideAsync();
performance.mark('splash-hide-complete');

performance.measure(
  'splash-visible-duration',
  'nativeLaunchStart',
  'splash-hide-complete',
);

// For bootsplash — it returns a promise that resolves when the animation finishes
const start = Date.now();
await BootSplash.hide({ fade: true });
console.log('Splash visible for', Date.now() - start, 'ms');
```

Target: splash should be visible for no longer than the time needed to mount the first real screen. If it exceeds 800 ms, investigate what is blocking the critical path in `prepare()`.

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

### 9.7 Platform-Specific TTI Measurement

Different platforms expose different tooling for startup analysis. Use the right tool for each platform rather than relying solely on JS-side marks.

**iOS: Xcode Instruments startup breakdown**

1. Open Xcode → Product → Profile (Cmd+I) → choose **Time Profiler** instrument.
2. Add the **App Launch** instrument from the library (available in Xcode 12+).
3. Launch the app through Instruments — it records native init, dyld linking, ObjC runtime, and JS thread start as distinct intervals on the timeline.
4. Key intervals to check:
   - `dyld` loading — identify bloated dynamic frameworks.
   - `_objc_init` / `+load` methods — third-party SDKs that slow native init.
   - The gap between main thread start and the first `CALayer` commit — this is your JS evaluation window.
5. Use **System Trace** alongside Time Profiler to see CPU scheduling and identify if the JS thread is being preempted.

```
Xcode Instruments → App Launch timeline sections:
├── Process start → main()              (dyld, ObjC init)
├── main() → RCTBridge init             (AppDelegate setup)
├── RCTBridge init → runJsBundleEnd     (Hermes init + bundle eval)
└── runJsBundleEnd → first CALayer      (React render → paint)
```

**Android: Profiler native timeline aligned with JS timeline**

1. Android Studio → Run → Profile 'app' → CPU → Record method trace from startup.
2. Choose **Callstack Sample** (lower overhead than instrumented) and start recording before launch.
3. In the timeline, find the `Thread: mqt_js` row — this is the JS thread. Align it with the `Thread: main` row to see what native work precedes JS execution.
4. Key signals:
   - `Application.onCreate` duration — add a systrace marker if needed.
   - `ReactHost.start()` → `createReactContextInBackground` gap.
   - The `mqt_js` thread's first activity = start of bundle evaluation.

```bash
# systrace for Android (API < 34) — captures native + JS thread in one trace
python3 $ANDROID_HOME/platform-tools/systrace/systrace.py \
  --time=10 \
  -o startup-trace.html \
  app view gfx sched

# For Android 14+ use Perfetto instead
adb shell perfetto \
  -c /data/misc/perfetto-configs/startup.pbtx \
  -o /data/misc/perfetto-traces/startup.pb \
  --txt
```

**Hermes CPU profiler for startup analysis**

The Hermes sampling profiler is the most accurate way to pinpoint JS-side startup cost. It captures frame-level JS call stacks with ~1 ms resolution.

```ts
// Enable Hermes profiler in development builds only
// In your debug menu or DevSettings screen:
import { HermesInternal } from 'react-native';

function startHermesProfiling() {
  if (global.HermesInternal && __DEV__) {
    // @ts-ignore — Hermes internal API
    HermesInternal.enableSampledStats?.();
  }
}

// After startup is complete, dump the profile:
function dumpHermesProfile() {
  if (global.HermesInternal) {
    // @ts-ignore
    const profile = HermesInternal.getInstrumentedStats?.();
    console.log(JSON.stringify(profile));
  }
}
```

For a full CPU profile usable in Chrome DevTools:

```bash
# Connect device, trigger recording via Flipper Hermes Debugger
# OR use the React Native dev menu → "Enable Sampling Profiler"
# Profile file lands in: /sdcard/Download/hermesprofile-<timestamp>.cpuprofile

# Pull it
adb pull /sdcard/Download/hermesprofile-*.cpuprofile ./

# Open in Chrome: chrome://inspect → Open dedicated DevTools → Profiler → Load
```

**Manual frame-by-frame TTI pinpointing**

When automated marks are not granular enough, record the device screen at 240 fps (iPhone 15 Pro, Pixel 8 Pro) and step through frames.

```bash
# iOS — use QuickTime screen recording at maximum quality
# Android — scrcpy with high framerate
scrcpy --max-fps 60 --record startup.mp4

# Count frames from app icon tap to first interactive frame
# At 60 fps: 1 frame = 16.67 ms
# At 240 fps: 1 frame = 4.17 ms (iPhone slow motion)
```

Mark the exact frame where:
1. App icon lifts (launch animation starts) — frame 0.
2. Native splash appears — frame N.
3. Splash hides, content is visible — frame M.
4. User can tap and receive feedback within 100 ms — TTI frame.

Multiply frame count by frame duration (16.67 ms at 60 fps) to get wall-clock TTI.

**Automated TTI measurement in CI**

```yaml
# .github/workflows/startup-benchmark.yml
name: Startup TTI Benchmark
on: [push]

jobs:
  android-tti:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build release APK
        run: cd android && ./gradlew assembleRelease

      - name: Install on emulator
        run: |
          adb install android/app/build/outputs/apk/release/app-release.apk

      - name: Measure cold start with Flashlight
        run: |
          npx @perf-tools/flashlight measure \
            --bundleId com.example.app \
            --scenario cold-start \
            --iterations 10 \
            --output ci-startup.json

      - name: Assert TTI regression
        run: |
          node -e "
            const { results } = require('./ci-startup.json');
            const p95 = results.sort((a,b) => a.tti - b.tti)[Math.floor(results.length * 0.95)].tti;
            const limit = parseInt(process.env.TTI_LIMIT_MS || '2500');
            if (p95 > limit) {
              console.error('P95 TTI REGRESSION: ' + p95 + ' ms (limit: ' + limit + ' ms)');
              process.exit(1);
            }
            console.log('P95 TTI OK: ' + p95 + ' ms');
          "
        env:
          TTI_LIMIT_MS: '2500'

      - name: Upload report
        uses: actions/upload-artifact@v4
        with:
          name: startup-report
          path: ci-startup.json
```

For iOS in CI, use `xcrun simctl` with a booted simulator and measure launch time via `os_signpost` or the `MetricKit` framework in a test target:

```swift
// StartupTests.swift — XCTest performance test for TTI
import XCTest

class StartupPerformanceTests: XCTestCase {
    func testColdStartTTI() throws {
        let app = XCUIApplication()
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            app.launch()
            // Wait for the first interactive element
            XCTAssertTrue(app.buttons["HomeTabButton"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }
}
```

Run in CI with: `xcodebuild test -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 15'`

---

## 10. Hermes Bytecode Precompilation (.hbc)

When Hermes is enabled, your JavaScript bundle is not shipped to the device as plain text. Instead, it is compiled to Hermes Bytecode (`.hbc`) at build time. The device runs the bytecode directly — no parsing, no AST construction, no compilation at launch.

### How .hbc compilation happens at build time

For React Native CLI projects the compilation happens inside the Metro bundler pipeline via `hermesc` (the Hermes compiler):

```
metro bundle → index.js (plain JS)
    ↓
hermesc --emit-binary -out index.android.bundle index.js
    ↓
index.android.bundle  (binary .hbc format, ~33% smaller than plain JS)
    ↓
embedded into APK/IPA at the path assets/index.android.bundle
```

For Expo managed workflow this is handled transparently by `expo export` and EAS Build. You do not invoke `hermesc` directly.

### Hermesc pipeline and verification with hbctool

```bash
# Check hermesc version bundled with your RN version
node_modules/react-native/sdks/hermesc/osx-bin/hermesc --version

# Manually compile a bundle for inspection (rarely needed, but useful for debugging)
node_modules/react-native/sdks/hermesc/osx-bin/hermesc \
  --emit-binary \
  --out /tmp/test.hbc \
  /tmp/index.js

# Inspect the bytecode with hbctool (install: pip3 install hbctool)
hbctool disasm /tmp/test.hbc /tmp/disassembled/

# Verify the output bundle is bytecode (not plain JS)
file android/app/build/intermediates/assets/release/index.android.bundle
# Expected output:
# index.android.bundle: Hermes JavaScript bytecode, version 96
```

If the file command returns `ASCII text` instead of `Hermes JavaScript bytecode`, bytecode precompilation has failed silently.

### Bytecode size vs JS size

Hermes bytecode is consistently smaller than the equivalent plain JS bundle because:
- String constants are deduplicated into a string table.
- The bytecode instruction encoding is denser than source text.
- Sourcemaps are stripped (stored separately as `.map` files).

| Bundle type | Typical size (3 MB app) | Typical size (10 MB app) |
|---|---|---|
| Plain JS (minified + gzip) | 3.0 MB | 10.0 MB |
| Hermes bytecode (.hbc) | ~2.0 MB | ~6.7 MB |
| Reduction | ~33% | ~33% |

Note: the 33% figure is consistent across bundle sizes but depends on the ratio of string literals to logic in your codebase.

### How to detect if bytecode precompilation failed silently

Build pipelines can fall back to plain JS without error if `hermesc` is not found or if the compilation step is skipped. This causes a significant startup regression that is easy to miss.

**Detection method 1 — file inspection (CI-safe):**

```bash
# After building the release APK/IPA, extract and check the bundle
# Android:
unzip -p android/app/build/outputs/apk/release/app-release.apk \
  assets/index.android.bundle > /tmp/bundle

file /tmp/bundle
# Must say: Hermes JavaScript bytecode, version N
# If it says: ASCII text — bytecode compilation is broken

# iOS:
# Extract from the .app directory inside the IPA
unzip -p ios/build/MyApp.ipa Payload/MyApp.app/main.jsbundle > /tmp/bundle
file /tmp/bundle
```

**Detection method 2 — size anomaly check:**

```bash
# Add this to your CI pipeline
BUNDLE_SIZE=$(wc -c < android/app/build/outputs/apk/release/app-release.apk)
EXPECTED_MAX=20971520  # 20 MB — adjust for your app

if [ "$BUNDLE_SIZE" -gt "$EXPECTED_MAX" ]; then
  echo "WARNING: APK size $BUNDLE_SIZE exceeds expected maximum."
  echo "Check if Hermes bytecode compilation is active."
fi
```

**Detection method 3 — startup time spike in production monitoring:**

If your Sentry or Firebase cold start P90 suddenly jumps by 40–100% on a release, and no JS code changes were made, suspect a failed bytecode build.

### Runtime detection of bytecode vs source mode

```ts
// Detect at runtime whether Hermes is running bytecode or interpreting source
function getJSEngineInfo(): { engine: string; bytecodeMode: boolean } {
  const isHermes = !!global.HermesInternal;

  if (!isHermes) {
    return { engine: 'JSC', bytecodeMode: false };
  }

  // HermesInternal.getRuntimeProperties() includes bytecode version info
  // @ts-ignore — Hermes internal API
  const props = global.HermesInternal?.getRuntimeProperties?.() ?? {};

  return {
    engine: 'Hermes',
    // If bytecodeVersion is present and non-zero, we are running precompiled bytecode
    bytecodeMode: typeof props.Bytecode === 'number' && props.Bytecode > 0,
  };
}

// Log in your app's debug screen or startup analytics
const engineInfo = getJSEngineInfo();
console.log('JS engine:', engineInfo.engine, '| Bytecode mode:', engineInfo.bytecodeMode);
// Expected in production: { engine: 'Hermes', bytecodeMode: true }
// If bytecodeMode is false in a production build, bytecode compilation is broken
```

Add this check to your Sentry startup breadcrumb so you get an alert when a production release unexpectedly runs in source mode:

```ts
import * as Sentry from '@sentry/react-native';

const engineInfo = getJSEngineInfo();
Sentry.addBreadcrumb({
  category: 'startup',
  message: 'JS engine info',
  data: engineInfo,
  level: engineInfo.bytecodeMode ? 'info' : 'warning',
});

if (!engineInfo.bytecodeMode && !__DEV__) {
  Sentry.captureMessage('Production build running in JS source mode (bytecode disabled)', 'error');
}
```

---

## 11. Warm Start Optimization

A warm start occurs when the OS restores an app from the background to the foreground. The process already exists in memory; the JS engine is still initialized. Warm start TTI should be near-zero — but it often is not, because apps incorrectly re-run initialization code that is only needed on cold start.

### Memory rehydration patterns

On a warm start, React state and refs are preserved exactly as they were when the app was backgrounded. You do not need to re-fetch data, re-initialize services, or re-run effects that already ran.

The key is to gate initialization logic on whether it has already run:

```ts
// services/appInit.ts
let hasInitialized = false;

export async function initializeApp() {
  if (hasInitialized) {
    // Warm start: skip all initialization
    return;
  }

  // Cold start path
  await Promise.all([
    loadFonts(),
    resolveAuthState(),
    initializeSentry(),
    registerPushNotifications(),
  ]);

  hasInitialized = true;
}
```

```tsx
// App.tsx
import { AppState, AppStateStatus } from 'react-native';

function App() {
  useEffect(() => {
    // Only run on mount (cold start)
    initializeApp();
  }, []);

  // AppState listener for foreground/background transitions
  useEffect(() => {
    const subscription = AppState.addEventListener('change', (nextState: AppStateStatus) => {
      if (nextState === 'active') {
        // Warm start or foreground — do NOT re-initialize services
        // Only handle things that must refresh on each foreground:
        handleForeground();
      }
    });
    return () => subscription.remove();
  }, []);
}

async function handleForeground() {
  // Minimal work: check token expiry, refresh stale data if needed
  await refreshAuthTokenIfExpired();
  queryClient.invalidateQueries({ queryKey: ['user'] }); // background refetch, non-blocking
}
```

### Avoiding full re-initialization on foreground

Common anti-patterns that cause slow warm starts:

```ts
// BAD: re-initializes Sentry on every foreground
AppState.addEventListener('change', (state) => {
  if (state === 'active') {
    Sentry.init({ dsn: ... }); // DO NOT re-init SDKs on foreground
  }
});

// BAD: navigation state reset on foreground destroys warm start feel
AppState.addEventListener('change', (state) => {
  if (state === 'active') {
    navigationRef.current?.reset({ index: 0, routes: [{ name: 'Home' }] });
  }
});

// GOOD: only do the minimum required work on foreground
AppState.addEventListener('change', (state) => {
  if (state === 'active') {
    checkSessionExpiry();  // lightweight token check
  }
});
```

### Measuring warm start TTI vs cold start

```ts
import { AppState } from 'react-native';
import { performance } from 'react-native-performance';

let backgroundedAt: number | null = null;

AppState.addEventListener('change', (nextState) => {
  if (nextState === 'background') {
    backgroundedAt = Date.now();
    performance.mark('app-backgrounded');
  }

  if (nextState === 'active' && backgroundedAt !== null) {
    const warmStartDuration = Date.now() - backgroundedAt;

    performance.mark('app-foregrounded');
    performance.measure('warm-start', 'app-backgrounded', 'app-foregrounded');

    console.log(`Warm start: ${warmStartDuration} ms`);

    // Alert if warm start takes longer than expected — indicates re-initialization bug
    if (warmStartDuration > 500) {
      console.warn('Slow warm start detected. Check for unnecessary re-initialization.');
    }

    backgroundedAt = null;
  }
});
```

Target warm start TTI: < 300 ms on mid-tier Android. If you measure > 500 ms, profile which code is running in `AppState` change listeners and `useEffect` hooks that run on navigation focus.

### Platform-specific: iOS jetsam risk, Android low-memory killer

**iOS — Jetsam:**

iOS terminates backgrounded apps when memory pressure is high (jetsam). After jetsam, the next launch is a full cold start — the process is gone. You cannot prevent jetsam, but you can make recovery from it fast:

- Persist navigation state to AsyncStorage so the user is returned to their last screen.
- Persist scroll position and form state for the current screen.
- Do not store large in-memory caches that cannot be cheaply rebuilt — they inflate your memory footprint and increase jetsam risk.

```ts
// Persist navigation state across jetsam kills
import AsyncStorage from '@react-native-async-storage/async-storage';

const NAV_STATE_KEY = '@nav_state';

async function persistNavState(state: NavigationState) {
  await AsyncStorage.setItem(NAV_STATE_KEY, JSON.stringify(state));
}

async function loadNavState(): Promise<NavigationState | undefined> {
  const raw = await AsyncStorage.getItem(NAV_STATE_KEY);
  return raw ? JSON.parse(raw) : undefined;
}

// In NavigationContainer:
<NavigationContainer
  initialState={await loadNavState()}
  onStateChange={persistNavState}
>
```

Detect jetsam in your analytics:

```ts
// If app was terminated mid-session (backgrounded then jetsammed), Sentry reports this
// as a new cold start. You can detect it by comparing session timestamps:
const lastSessionEnd = await AsyncStorage.getItem('@last_session_end');
const lastSessionEndTime = lastSessionEnd ? parseInt(lastSessionEnd) : 0;
const timeSinceLastSession = Date.now() - lastSessionEndTime;

// If the app was in the background for less than 30 minutes but still cold-started,
// it was likely jetsammed
const wasJetsammed = timeSinceLastSession < 30 * 60 * 1000 && isColdStart();
if (wasJetsammed) {
  analytics().logEvent('app_jetsammed');
}
```

**Android — Low-Memory Killer (LMK):**

Android's LMK terminates cached processes (backgrounded apps) when RAM is constrained. Unlike iOS jetsam, Android provides more predictability via `onTrimMemory` callbacks.

```java
// MainApplication.java — respond to memory pressure signals
@Override
public void onTrimMemory(int level) {
  super.onTrimMemory(level);
  if (level >= ComponentCallbacks2.TRIM_MEMORY_MODERATE) {
    // Release in-memory caches to lower LMK risk
    imageCache.evictAll();
  }
}
```

In React Native (JS side), listen for the memory warning event:

```ts
import { Platform, NativeModules } from 'react-native';

// iOS: memoryWarning is a native event
// Android: no direct equivalent — use onTrimMemory via a native module

if (Platform.OS === 'ios') {
  // expo-notifications and other Expo modules surface this as an AppState event
  // Listen and clear non-critical caches
  const subscription = AppState.addEventListener('memoryWarning' as any, () => {
    queryClient.clear();  // clear React Query cache to free memory
    imageCache?.clear();
  });
}
```

### State preservation across background/foreground cycles

Use Zustand's `persist` middleware with AsyncStorage to make state survive both warm starts and jetsam/LMK kills:

```ts
import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import AsyncStorage from '@react-native-async-storage/async-storage';

interface SessionStore {
  lastViewedFeedId: string | null;
  scrollOffset: number;
  setLastViewedFeedId: (id: string) => void;
  setScrollOffset: (offset: number) => void;
}

export const useSessionStore = create<SessionStore>()(
  persist(
    (set) => ({
      lastViewedFeedId: null,
      scrollOffset: 0,
      setLastViewedFeedId: (id) => set({ lastViewedFeedId: id }),
      setScrollOffset: (offset) => set({ scrollOffset: offset }),
    }),
    {
      name: 'session-store',
      storage: createJSONStorage(() => AsyncStorage),
      // Only persist what is needed for state restoration
      partialize: (state) => ({
        lastViewedFeedId: state.lastViewedFeedId,
        scrollOffset: state.scrollOffset,
      }),
    },
  ),
);
```

On warm start, `useSessionStore` rehydrates from AsyncStorage synchronously (Zustand's persist layer reads the cache on first access). The user sees their previous scroll position without any loading state.

---

## Summary: Startup Optimization Priority

| Priority | Action | Typical Saving |
|---|---|---|
| P0 | Enable Hermes | 40–60% eval time reduction |
| P0 | Verify Hermes bytecode precompilation (.hbc) | ~33% bundle size, eliminates parse time |
| P0 | Enable `inlineRequires` | 100–300 ms |
| P1 | Remove / replace heavy libs | 50–200 ms |
| P1 | Defer analytics + push init | 80–150 ms |
| P1 | Switch to react-native-bootsplash | Eliminates white flash |
| P1 | Gate re-initialization on cold start only | 0–300 ms warm start recovery |
| P2 | Lazy-load non-critical screens | 30–100 ms |
| P2 | Expo Router lazy tabs (lazy: true) | 20–80 ms per deferred tab |
| P2 | Prefetch critical data | Perceived 0 ms load |
| P2 | Persist nav state for jetsam recovery | Perceived instant recovery |
| P3 | Skeleton screens | Perceived performance |
| P3 | Pre-warm JS engine (Android) | 50–100 ms |
| P3 | Image + font preloading | Eliminates layout shift |
| P3 | Native splash → skeleton choreography | Zero white-flash transition |
| P3 | Automated TTI in CI (Flashlight / XCTest) | Regression prevention |
