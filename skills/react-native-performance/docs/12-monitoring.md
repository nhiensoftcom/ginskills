# 12. Performance Monitoring & Profiling

## 1. Development Profiling Tools

| Tool | Platform | Best For |
|---|---|---|
| React Native DevTools | Both | JS profiling, component renders, press `j` in Metro (RN 0.76+) |
| React DevTools Profiler | Both | Component render times, why did render |
| why-did-you-render | Both | Identify unnecessary re-renders automatically |
| Xcode Instruments | iOS | Time Profiler, Leaks, Allocations, VM Tracker |
| Android Studio Profiler | Android | CPU (System Trace), Memory, Network |
| Flipper | Both | Network, Layout, Databases, Memory (remove in prod!) |

---

## 2. Xcode Instruments Deep Dive

Xcode Instruments is the most powerful native profiling suite for iOS. Launch it via **Product → Profile** (or `Cmd+I`) from Xcode.

### Time Profiler

Samples the call stack at regular intervals to identify which functions consume the most CPU time.

1. Select the **Time Profiler** instrument.
2. Run your app and reproduce the slow interaction.
3. Stop recording and examine the **Call Tree**.
4. Enable **Hide System Libraries** to focus on your code.
5. Enable **Invert Call Tree** to see which leaf functions are hottest.

Key things to look for:
- JS thread spending time in `JSC::execute` or `hermes::vm` — indicates heavy JS computation.
- Main thread blocked by synchronous native calls.
- `RCTBridge` calls on the wrong thread.

### Leaks Instrument

Detects retain cycles and leaked memory objects automatically.

1. Add **Leaks** to your Instruments session alongside Allocations.
2. Navigate through your app — push and pop screens several times.
3. Red markers in the timeline indicate detected leaks.
4. Drill into the leak to see the retain cycle chain.

Common RN leak sources: event listeners not removed, timers not cleared, closures capturing component refs.

### Allocations Instrument

Tracks every memory allocation and deallocation over time.

1. Use **Mark Generation** (the flag button) at stable states (e.g., after each screen push).
2. Compare generations — persistent growth between identical states indicates a leak.
3. Look for `RCTImageView`, `RCTView`, or JS object clusters growing unbounded.

### VM Tracker

Shows virtual memory usage broken down by type: dirty, swapped, resident.

- Useful for detecting native image memory not released by the iOS image cache.
- Compare `IOKit` memory vs JS heap to understand where pressure originates.

### Main Thread Checker

Automatically detects UIKit/AppKit API calls made from background threads — a common crash source.

- Enable via **Scheme → Diagnostics → Main Thread Checker**.
- Will pause execution and log a backtrace when a violation is detected.

### Filtering JS Thread vs Main Thread

In Time Profiler, use the **Thread** filter in the bottom panel:

- Look for threads named `com.facebook.react.JavaScript` (JS thread).
- `main` thread is the UI thread.
- `mqt_native_modules` is the native modules thread.

Isolate each thread separately to understand where time is actually spent.

---

## 3. Android Profiling

### Android Studio CPU Profiler — System Trace

System Trace gives the most detailed view of CPU activity, including thread scheduling.

1. Open **View → Tool Windows → Profiler**.
2. Select your process and click **CPU**.
3. Choose **System Trace** and click **Record**.
4. Reproduce the interaction, then stop recording.
5. Inspect the **Threads** panel for the JS thread and RenderThread.

Look for:
- Long frames in the RenderThread (> 16ms per frame = jank).
- JS thread blocked on `acquireLock` — contention with native modules.
- Gaps in the RenderThread (CPU throttling on debug builds).

### Memory Profiler

1. Open the **Memory** profiler tab.
2. Capture heap dumps at stable points using the heap dump button.
3. Filter by package name to exclude Android framework objects.
4. Look for leaked `Activity`, `Fragment`, or React component instances.

### LeakCanary — Automatic Leak Detection

```kotlin
// app/build.gradle
dependencies {
    debugImplementation 'com.squareup.leakcanary:leakcanary-android:2.x'
}
```

No code changes required — LeakCanary hooks into the Activity/Fragment lifecycle automatically. On leak detection it shows a notification with the full retain chain. Works with React Native's `ReactActivity` out of the box.

### StrictMode

Detect disk I/O and network calls on the main thread during development:

```kotlin
// MainApplication.kt (debug only)
if (BuildConfig.DEBUG) {
    StrictMode.setThreadPolicy(
        StrictMode.ThreadPolicy.Builder()
            .detectDiskReads()
            .detectDiskWrites()
            .detectNetwork()
            .penaltyLog()
            .build()
    )
}
```

### Overdraw Detection

Enable via **Developer Options → Debug GPU overdraw** on device. Regions rendered more than once per frame show as colored overlays (green → teal → pink → red for 1x → 4x overdraw). Reduce by flattening view hierarchies and removing redundant backgrounds.

### Systrace

For lower-level analysis, use systrace from the Android SDK:

```bash
python $ANDROID_HOME/platform-tools/systrace/systrace.py \
  --time=10 -o trace.html gfx view sched
```

Open `trace.html` in Chrome at `chrome://tracing`. Filter for `RenderThread` and `UI Thread` to find frame budget violations.

---

## 4. Hermes Profiling

### Taking Heap Snapshots

In the React Native DevTools (Metro `j` shortcut or standalone DevTools):

1. Go to the **Memory** tab.
2. Click **Take heap snapshot**.
3. Navigate through your app.
4. Take a second snapshot.
5. Switch to **Comparison** view to see objects created between snapshots.

### Comparing Heap Snapshots to Find Leaks

In comparison view, sort by **# New** (count of new objects not yet GC'd). Objects that should not persist (screen components, callbacks) appearing here indicate leaks.

Filter by constructor name to isolate React component instances or closure objects.

### Chrome DevTools Integration for Hermes

Hermes supports the Chrome DevTools Protocol directly:

1. Enable `hermes` in `android/app/build.gradle` (enabled by default in RN 0.70+).
2. Open `chrome://inspect` in Chrome.
3. Click **inspect** on the Hermes runtime.
4. Use the full Chrome DevTools: Sources, Memory, Performance panels.

### Hermes Profiler Sampling

Hermes has a built-in CPU profiler accessible via the CLI:

```bash
# Start sampling
adb shell kill -SIGUSR1 <pid>
# Stop and pull
adb shell kill -SIGUSR2 <pid>
adb pull /data/data/<package>/cache/hermesProfile.json
```

Load the JSON into `chrome://tracing` or the React Native DevTools Performance tab.

---

## 5. Production Monitoring

### Sentry Setup

```tsx
import * as Sentry from '@sentry/react-native';

Sentry.init({
  dsn: 'YOUR_DSN',
  tracesSampleRate: 0.15,        // 15% of sessions for performance
  profilesSampleRate: 0.1,       // 10% of traced sessions get profiles
  enableNativeFramesTracking: true,  // track slow/frozen frames
  enableStallTracking: true,     // track JS thread stalls > 100ms
});
```

Wrap your root component:

```tsx
export default Sentry.wrap(App);
```

#### App Start Monitoring

Sentry automatically instruments cold and warm start durations. View them in **Performance → App Start** in the Sentry dashboard. Drill into individual transactions to see which operations consume startup time.

#### Slow/Frozen Frames Tracking

With `enableNativeFramesTracking: true`, each transaction includes:
- `frames.total` — total frames rendered
- `frames.slow` — frames taking 16–700ms
- `frames.frozen` — frames taking > 700ms

Set alerts when frozen frame rate exceeds your SLA threshold.

#### Custom Spans for Critical Paths

```tsx
import * as Sentry from '@sentry/react-native';

async function loadFeed() {
  const span = Sentry.startInactiveSpan({ name: 'feed.load', op: 'http' });
  try {
    const data = await fetchFeed();
    return data;
  } finally {
    span?.end();
  }
}
```

Use custom spans to measure: data fetching, image processing, navigation transitions, and list hydration.

#### Performance Dashboards

In Sentry, create a **Dashboard** with widgets for:
- P50/P75/P95 transaction durations by screen
- App start duration over time
- Frozen frame rate by app version
- Throughput (transactions per minute)

### Firebase Performance

#### Custom Traces for TTI

```tsx
import perf from '@react-native-firebase/perf';

async function measureScreenLoad() {
  const trace = await perf().startTrace('home_screen_tti');
  try {
    await loadInitialData();
    trace.putAttribute('data_source', 'network');
  } finally {
    await trace.stop();
  }
}
```

#### Network Request Monitoring

Firebase Performance automatically intercepts `fetch` and `XMLHttpRequest` calls. Disable for specific requests if needed:

```tsx
perf().dataCollectionEnabled = false; // opt-out at runtime
```

#### Screen Rendering Traces

Use the `@react-native-firebase/perf` `ScreenTrace` API to track time-to-interactive per screen. Visible in the Firebase console under **Performance → Traces → Screen Rendering**.

---

## 6. CI/CD Performance Testing

### Reassure (Callstack)

Reassure integrates with Jest to measure and compare component render counts and durations across PRs.

```tsx
// ProductList.perf-test.tsx
import { measureRenders } from 'reassure';

test('ProductList renders efficiently', async () => {
  await measureRenders(<ProductList products={mockProducts} />, {
    runs: 20,
  });
});
```

#### Setup with Jest

```bash
yarn add --dev reassure
```

```js
// jest.config.js
module.exports = {
  testMatch: ['**/*.perf-test.{ts,tsx}'],
};
```

Run baseline on main branch:

```bash
git checkout main
yarn reassure --baseline
```

Run comparison on feature branch:

```bash
git checkout feature/my-change
yarn reassure
```

#### Baseline Comparisons

Reassure compares render count mean, standard deviation, and duration. Results are written to `.reassure/current.perf` and `.reassure/baseline.perf`.

#### PR Comments with Regression Reports

Use the `danger-plugin-reassure` Dangerfile plugin to post comparison tables as PR comments automatically. Configure thresholds to fail the CI check when regressions exceed acceptable limits (e.g., > 20% render count increase).

### Flashlight (BAM/Theodo)

Flashlight automates Android performance scoring on real devices or emulators.

```bash
npx @perf-tools/flashlight measure --apk app-release.apk --test e2e/flows/home.js
```

Produces a score (0–100) with breakdowns for:
- **FPS** — animation smoothness
- **CPU** — processor utilization
- **Memory** — RAM consumption

#### Real Device Testing

Connect an Android device, enable USB debugging, and Flashlight will install and instrument the APK automatically. Scores are reproducible and comparable across builds.

### Bundle Size CI

Track bundle size per PR to prevent unintentional bloat:

```bash
# Generate stats
npx react-native bundle \
  --platform android \
  --dev false \
  --entry-file index.js \
  --bundle-output /tmp/bundle.js \
  --sourcemap-output /tmp/bundle.map

# Analyze
npx source-map-explorer /tmp/bundle.js /tmp/bundle.map --json > bundle-stats.json
```

Set budgets in CI and fail the build if the bundle exceeds the threshold:

```yaml
# .github/workflows/bundle-size.yml
- name: Check bundle size
  run: |
    SIZE=$(wc -c < /tmp/bundle.js)
    BUDGET=3145728  # 3MB
    if [ "$SIZE" -gt "$BUDGET" ]; then
      echo "Bundle size $SIZE exceeds budget $BUDGET"
      exit 1
    fi
```

Compare against the main branch bundle to show size delta in the PR comment.

---

## 7. Custom Performance Markers

Use the `react-native-performance` package for User Timing API-compatible markers:

```tsx
import { PerformanceObserver, performance } from 'react-native-performance';

// Mark the start of a critical operation
performance.mark('screen_render_start');

// ... perform the operation (data fetch, heavy computation, render)

// Mark the end
performance.mark('screen_render_end');

// Measure the duration between marks
performance.measure(
  'screen_render',
  'screen_render_start',
  'screen_render_end'
);

// Observe all measures
const observer = new PerformanceObserver((list) => {
  list.getEntries().forEach((entry) => {
    console.log(`${entry.name}: ${entry.duration.toFixed(2)}ms`);
    // Send to analytics or Sentry
    Sentry.addBreadcrumb({
      category: 'performance',
      message: `${entry.name}: ${entry.duration.toFixed(2)}ms`,
    });
  });
});

observer.observe({ entryTypes: ['measure'] });
```

### Navigation Timing

```tsx
// In a navigation listener
navigation.addListener('focus', () => {
  performance.mark(`${route.name}_focus`);
});

navigation.addListener('transitionEnd', () => {
  performance.mark(`${route.name}_ready`);
  performance.measure(
    `${route.name}_transition`,
    `${route.name}_focus`,
    `${route.name}_ready`
  );
});
```

---

## 8. E2E Performance Testing

### Maestro

Maestro records UI flows and replays them with timing measurements:

```yaml
# flows/home-feed.yaml
appId: com.myapp
---
- launchApp
- takeScreenshot: before_feed
- tapOn: "Feed"
- waitForAnimationToEnd
- takeScreenshot: after_feed
```

Run with performance measurement:

```bash
maestro test flows/home-feed.yaml --format junit
```

Use in CI to catch regressions in interaction timing. Maestro Cloud provides device farms for consistent measurement environments.

### Detox

Detox provides programmatic E2E testing with performance assertions:

```ts
// e2e/performance.test.ts
describe('Home screen performance', () => {
  it('loads feed within 2 seconds', async () => {
    const start = Date.now();
    await element(by.id('feed-tab')).tap();
    await waitFor(element(by.id('feed-list')))
      .toBeVisible()
      .withTimeout(2000);
    const duration = Date.now() - start;
    expect(duration).toBeLessThan(2000);
  });
});
```

Combine with Sentry custom spans to correlate E2E timings with production traces during development.
