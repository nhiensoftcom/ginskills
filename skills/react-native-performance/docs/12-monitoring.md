# 12. Performance Monitoring & Profiling

## 1. Development Tools

| Tool | Platform | Best For |
|---|---|---|
| React Native DevTools | Both | JS profiling, press `j` in Metro (RN 0.76+) |
| React DevTools Profiler | Both | Component render times, why-did-render |
| why-did-you-render | Both | Identify unnecessary re-renders |
| Xcode Instruments | iOS | Time Profiler, Leaks, Allocations |
| Android Studio Profiler | Android | CPU System Trace, Memory, Network |

---

## 1a. React Native DevTools (RN 0.76+)

React Native DevTools is the built-in replacement for Flipper. It ships with Metro and connects automatically in RN 0.76+ with the New Architecture enabled.

### Opening DevTools

Press `j` in the Metro terminal, or run:

```bash
npx react-native start
# Metro starts, then press j to open DevTools in your default browser
```

On physical devices, DevTools auto-connects over the same USB tunnel Metro uses — no manual port forwarding required.

### RN 0.76+ Auto-Connect Features

- **Automatic target discovery**: DevTools lists all running RN processes (simulator + device) and connects to the first available target.
- **Persistent connection**: The session survives fast-refresh reloads; breakpoints and profiler state are preserved across reloads.
- **New Architecture support**: The CDP (Chrome DevTools Protocol) bridge runs natively via JSI, removing the need for a WebSocket bridge that Flipper relied on.

### Source Map Debugging

Metro generates inline source maps in debug builds. DevTools resolves them automatically so you step through `.tsx` source instead of Hermes bytecode:

```bash
# Verify source maps are being generated (look for this in Metro output)
# BUNDLE ./index.js  (with `-- source maps enabled`)

# For release builds, generate and upload source maps to Sentry:
npx react-native bundle \
  --platform ios \
  --dev false \
  --entry-file index.js \
  --bundle-output /tmp/main.jsbundle \
  --sourcemap-output /tmp/main.map
```

For production symbolication, upload the `.map` file to Sentry or Firebase Crashlytics after each build so crash stack traces resolve to original source lines.

### Memory Tab (New Architecture)

With the New Architecture (`newArchEnabled: true`), DevTools exposes a **Memory** tab backed by the Hermes heap inspector:

1. Open DevTools (`j` in Metro).
2. Click the **Memory** tab.
3. Click **Take snapshot** before the suspected leak.
4. Perform the action (navigate to screen, trigger data fetch, navigate back).
5. Force GC: click the garbage can icon.
6. Take a second snapshot.
7. Switch the view to **Comparison** — objects with a positive delta are leak candidates.

This is equivalent to Hermes heap snapshots via `HermesInternal.createSnapshotToFile` but with a visual diff UI.

### Comparison with Deprecated Flipper

| Capability | Flipper (deprecated) | React Native DevTools |
|---|---|---|
| JS debugging | Via Hermes CDP plugin | Native CDP, no plugin needed |
| Network inspection | Flipper Network plugin | Use Proxyman/Charles (see Section 9) |
| Layout inspector | Layout plugin | React DevTools Elements tab |
| Crash logs | Log plugin | Sentry / Metro console |
| Native modules | Custom plugins | Android Studio / Xcode directly |
| Setup burden | Plugin installation + native link | Zero config, ships with Metro |

Flipper was deprecated in RN 0.74 and removed from the default template in RN 0.75. Do not add it to new projects.

---

## 2. Xcode Instruments

### Time Profiler

1. Product > Profile (Cmd+I) to build a release-like binary.
2. Choose **Time Profiler**.
3. Record for 10-15 seconds while exercising the slow path.
4. Filter the call tree: check **Hide System Libraries**, uncheck **Invert Call Tree**.
5. Look for JS thread vs main thread hot spots — JS work appears under `JSC::Interpreter` or `Hermes::*`.

### Leaks Instrument

- Detects retain cycles in Objective-C/Swift code and in native modules.
- Run periodically after adding new native modules.
- A leak in a native module will show up as a red flag in the timeline.

### Allocations Instrument

- Tracks cumulative memory growth — useful for finding unbounded cache growth.
- Use **Generation Analysis**: mark a generation before navigating to a screen, navigate away, force GC, then check what survived.

### Main Thread Checker

- Enabled by default in debug builds.
- Flags any UIKit/AppKit access from a background thread.
- Violations pause the app and print to the console.

---

## 3. Android Profiling

### Android Studio Memory Profiler

1. Run > Profile (not Debug) to avoid profiler overhead artifacts.
2. Open **Memory** lane.
3. Trigger **Capture heap dump** after the suspect action.
4. Filter by package name; look for growing instance counts.

### LeakCanary

Add one line to `app/build.gradle` (debug only via `debugImplementation`):

```groovy
debugImplementation 'com.squareup.leakcanary:leakcanary-android:2.14'
```

LeakCanary auto-hooks into `Activity` and `Fragment` lifecycle. When a leak is detected it sends a notification with the retain chain.

### StrictMode

Enable in your `Application.onCreate()` for debug builds to catch disk and network access on the main thread:

```kotlin
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

### GPU Overdraw Detection

- Developer Options > Debug GPU overdraw > Show overdraw areas.
- Blue = 1x overdraw (acceptable), Green = 2x, Pink = 3x, Red = 4x+ (fix these).
- Common RN culprit: stacked `<View>` backgrounds where only the top one is visible.

---

## 3a. Startup Trace Analysis

Cold start performance is one of the highest-impact metrics for user retention. Break it into distinct phases to target optimizations precisely.

### Cold Start Phase Breakdown

| Phase | What happens | Typical cost |
|---|---|---|
| **Native init** | OS loads the binary, Obj-C/Swift runtime initializes | 50–200 ms |
| **Bridge / JSI init** | Hermes VM starts, turbo module registry builds | 80–300 ms |
| **Module evaluation** | `index.js` + all `require()` calls execute | 100–600 ms |
| **First render** | Root component renders, layout is computed | 50–200 ms |
| **TTI (Time to Interactive)** | First meaningful frame + JS event loop free | sum of above |

### Xcode Instruments — Time Profiler for iOS Startup

1. Product > Profile (Cmd+I) — builds a release-like binary.
2. Choose **Time Profiler**.
3. **Before recording**, add a launch argument: `App > Edit Scheme > Arguments > Arguments Passed On Launch > -com.apple.CoreData.ConcurrencyDebug 0` (keeps logs clean).
4. Press Record, then launch the app from the home screen (not from Xcode — that skips cold start).
5. Stop after the first screen is interactive.
6. In the call tree: filter by your bundle identifier, check **Hide System Libraries**.
7. JS startup appears under `hermesvm::Runtime::runBytecode` or `JSC::Interpreter::execute`. The duration of this frame is your module evaluation cost.

### Android Systrace for Startup Timeline

```bash
# Start a systrace capture covering app launch (10-second window)
python $ANDROID_HOME/platform-tools/systrace/systrace.py \
  --time=10 \
  -o /tmp/startup_trace.html \
  app view sched freq gfx input

# Launch the app immediately after running this command
adb shell am start -n com.myapp/.MainActivity
```

Open the resulting HTML in Chrome. Look for:
- `bindApplication` → end of `activityStart`: native init cost
- `JS__require` spans: each `require()` call during module evaluation
- `performTraversals`: first layout pass

### Hermes CPU Profiler for JS Evaluation Cost

```tsx
// Wrap your root index.js to measure module evaluation time
const moduleEvalStart = global.performance?.now?.() ?? Date.now();

// ... all your imports happen here during require() evaluation ...

import { AppRegistry } from 'react-native';
import App from './App';

AppRegistry.registerComponent('MyApp', () => {
  const moduleEvalEnd = global.performance?.now?.() ?? Date.now();
  console.log(`[Startup] Module eval: ${(moduleEvalEnd - moduleEvalStart).toFixed(1)} ms`);
  return App;
});
```

For a deep breakdown of which modules are expensive, use the Hermes sampling profiler immediately around startup:

```tsx
// In a debug-only native module or Metro plugin — NOT production code
HermesInternal?.enableSamplingProfiler?.();

// After first render completes:
setTimeout(() => {
  HermesInternal?.dumpSampledTraceToFile?.('/tmp/startup_hermes.json');
}, 2000);
```

Load `startup_hermes.json` in `chrome://tracing`. Sort by self-time to find the most expensive `require()` calls.

### Automated TTI Measurement in CI

Define TTI as the timestamp when the first interactive screen's key component mounts. Report it from the app via a custom native module or a log marker that your test harness reads:

```tsx
// In your root navigator's first screen component
useEffect(() => {
  const tti = performance.now(); // relative to JS bundle execution start
  console.log(`[TTI] ${tti.toFixed(0)} ms`);

  // Forward to Sentry as a custom measurement
  Sentry.getCurrentScope().setMeasurement('tti', tti, 'millisecond');
}, []);
```

In CI, use Maestro + `logcat` / `Console.app` to capture the TTI log line and assert it against a budget:

```bash
# Android: launch app, capture logs, extract TTI
adb logcat -c
adb shell am start -n com.myapp/.MainActivity -W
adb logcat -d | grep '\[TTI\]' | awk '{print $NF}' > /tmp/tti.txt
TTI=$(cat /tmp/tti.txt | tr -d ' ms')
[ "$TTI" -lt 2000 ] || (echo "TTI $TTI ms exceeds 2000 ms budget" && exit 1)
```

---

## 4. Hermes Profiling

### Heap Snapshots

```tsx
import { HermesInternal } from 'react-native';

const snapshot1 = HermesInternal?.createSnapshotToFile?.('/tmp/snap1.heapshot');
// ... perform the suspected leaking action ...
const snapshot2 = HermesInternal?.createSnapshotToFile?.('/tmp/snap2.heapshot');
```

Load both files in Chrome DevTools (Memory tab > Load) and use **Comparison** view to see what was allocated between the two snapshots.

### Chrome DevTools via CDP

1. Start Metro, open Chrome, navigate to `chrome://inspect`.
2. Click **inspect** next to the Hermes target.
3. Go to the **Performance** tab and record a trace.
4. The flame chart shows JS execution on the JS thread.

### Hermes Sampling Profiler

```tsx
import { HermesInternal } from 'react-native';

HermesInternal?.enableSamplingProfiler?.();
// ... run the scenario ...
HermesInternal?.dumpSampledTraceToFile?.('/tmp/hermes_trace.json');
```

Open the resulting file in `chrome://tracing` or the React Native Hermes Profiler UI.

---

## 5. Production Monitoring

### Sentry Setup

```bash
npx @sentry/wizard@latest -i reactNative
```

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

Wrap the root component:

```tsx
export default Sentry.wrap(App);
```

### App Start Monitoring

Sentry automatically captures `app.start` span. Check the **Performance** dashboard for P50/P95 cold and warm start times segmented by OS version and device class.

### Slow and Frozen Frames

- Slow frame: rendered in > 16 ms (below 60 fps).
- Frozen frame: rendered in > 700 ms.
- `enableNativeFramesTracking: true` reports these per transaction automatically.
- Target: < 1% frozen frames across all sessions.

### Firebase Performance Custom Traces

```tsx
import perf from '@react-native-firebase/perf';

async function loadFeed() {
  const trace = await perf().startTrace('feed_load');
  trace.putAttribute('source', 'network');
  try {
    const data = await fetchFeed();
    trace.putMetric('item_count', data.length);
    return data;
  } finally {
    await trace.stop();
  }
}
```

Custom traces appear in the Firebase console under **Performance > Custom traces**.

---

## 5a. JS Thread Stall Detection

A JS thread stall occurs when the event loop is blocked for an extended period, making the UI unresponsive. Stalls > 100 ms are noticeable; stalls > 700 ms produce frozen frames.

### Sentry Stall Tracking

`enableStallTracking: true` (already set in the Sentry init above) automatically measures JS thread stalls per transaction:

```tsx
Sentry.init({
  dsn: 'YOUR_DSN',
  tracesSampleRate: 0.15,
  enableStallTracking: true,       // measures stall time per transaction
  stallThreshold: 100,             // ms — stalls below this are ignored
});
```

Sentry attaches `stall_count`, `stall_total_time`, and `stall_longest_time` to every transaction. In the Performance dashboard, sort by `stall_longest_time` to find the worst offenders.

**Stall severity thresholds:**

| Duration | Classification |
|---|---|
| 50–100 ms | Minor / borderline |
| 100–300 ms | Significant — investigate |
| 300–700 ms | Severe — users feel lag |
| > 700 ms | Frozen frame — block ship if new |

### Common Stall Patterns

- **Synchronous storage reads**: `MMKV.getString()` or `AsyncStorage` in a sync context during navigation.
- **Large JSON parse/stringify**: Deserializing a big API response on the JS thread instead of a worker.
- **Unvirtualized list renders**: Rendering hundreds of items in a single pass from a flat `map()`.
- **Navigation parameter serialization**: Passing non-serializable objects through React Navigation params triggers deep equality checks.
- **Crypto / hashing**: Running heavy PBKDF2 or SHA operations synchronously.

### Custom Stall Detector

Use this in development to surface stalls before they reach production:

```tsx
// utils/stallDetector.ts
const STALL_THRESHOLD_MS = 100;
let lastTick = performance.now();

function installStallDetector() {
  if (!__DEV__) return;

  function checkTick() {
    const now = performance.now();
    const delta = now - lastTick;

    if (delta > STALL_THRESHOLD_MS) {
      console.warn(
        `[StallDetector] JS thread stalled for ${delta.toFixed(0)} ms`,
        new Error().stack, // captures the approximate call site
      );
    }

    lastTick = now;
    setTimeout(checkTick, 16); // schedule next check every frame
  }

  setTimeout(checkTick, 16);
}

export { installStallDetector };
```

Call `installStallDetector()` early in `index.js` in debug builds. The stack trace in the warning points to what was running when the stall started. Pair this with the Hermes sampling profiler for deeper analysis.

### Monitoring Long Tasks via PerformanceObserver

```tsx
// Works in Hermes with RN 0.71+
const observer = new PerformanceObserver((list) => {
  for (const entry of list.getEntries()) {
    if (entry.duration > 100) {
      console.warn(`[LongTask] ${entry.name}: ${entry.duration.toFixed(0)} ms`);
      Sentry.addBreadcrumb({
        category: 'long-task',
        message: `${entry.name} blocked JS for ${entry.duration.toFixed(0)} ms`,
        level: 'warning',
      });
    }
  }
});

observer.observe({ entryTypes: ['longtask'] });
```

---

## 5b. Network Waterfall Visualization

Network requests often form sequential waterfalls where each call blocks the next. Visualizing the sequence identifies avoidable delays.

### Request Sequence Visualization Tools

| Tool | Platform | Strengths |
|---|---|---|
| **Proxyman** | macOS / iOS | Auto-intercepts via Wi-Fi proxy, waterfall chart built-in |
| **Charles Proxy** | macOS / Windows / Linux | Mature, SSL pinning bypass helpers, HAR export |
| **React Native Debugger** | Both | Embedded Network tab via `REACT_DEBUGGER` env var |
| **Android Studio Profiler** | Android | Native + JS network requests in one timeline |
| **Flipper Network plugin** | Both | Deprecated — use Proxyman/Charles instead |

### Setting Up Proxyman (iOS Simulator)

1. Install Proxyman (`brew install --cask proxyman`).
2. Open Proxyman > Certificate > Install Certificate on iOS Simulator.
3. Run the app — all HTTP(S) requests appear in the waterfall timeline.
4. Filter by your API domain and look for sequential requests that could be parallelized.

### Critical Path Analysis for API Calls

A waterfall means request B starts only after request A completes. Identify the critical path:

```
App open
  └─► /auth/refresh          [200ms] ← blocks everything
        └─► /user/profile    [150ms] ← blocked by auth
              └─► /feed      [300ms] ← blocked by profile
                                        Total: 650ms sequential
```

Optimizations:
- **Parallelize independent calls**: fetch profile and feed concurrently once auth is done.
- **Prefetch on auth completion**: start non-critical requests before the screen mounts.
- **Persist auth tokens**: eliminate the `/auth/refresh` call on warm starts.

```tsx
// Before: sequential waterfall
const profile = await fetchProfile();
const feed = await fetchFeed(profile.id);

// After: parallel where possible
const [profile, feedData] = await Promise.all([
  fetchProfile(),
  fetchFeed(), // if feed endpoint accepts userId from token, no profile needed
]);
```

### Network Request Timing Instrumentation

Instrument fetch at the global level to capture timing for all requests without modifying individual call sites:

```tsx
// utils/networkTiming.ts
const originalFetch = global.fetch;

global.fetch = async function timedFetch(
  input: RequestInfo | URL,
  init?: RequestInit,
): Promise<Response> {
  const url = typeof input === 'string' ? input : input.toString();
  const start = performance.now();

  try {
    const response = await originalFetch(input, init);
    const duration = performance.now() - start;

    if (duration > 500) {
      console.warn(`[Network] Slow request: ${url} took ${duration.toFixed(0)} ms`);
    }

    Sentry.addBreadcrumb({
      category: 'network',
      message: url,
      data: {
        status: response.status,
        duration_ms: Math.round(duration),
      },
      level: duration > 1000 ? 'warning' : 'info',
    });

    return response;
  } catch (error) {
    const duration = performance.now() - start;
    console.error(`[Network] Failed: ${url} after ${duration.toFixed(0)} ms`, error);
    throw error;
  }
};
```

Install this patch early in `index.js` (after Sentry init, before app registration). All fetch-based network calls — including React Query and Axios if configured to use fetch — are automatically timed.

### Identifying Sequential Waterfalls in React Query

```tsx
// Waterfall: second query depends on first query's data
const { data: user } = useQuery({ queryKey: ['user'], queryFn: fetchUser });
const { data: feed } = useQuery({
  queryKey: ['feed', user?.id],
  queryFn: () => fetchFeed(user!.id),
  enabled: !!user?.id,   // ← this creates a waterfall
});

// Fix: use prefetchQuery in the parent loader or router loader
// so both requests fire before the component mounts
export async function loader() {
  await queryClient.prefetchQuery({ queryKey: ['user'], queryFn: fetchUser });
  const user = queryClient.getQueryData<User>(['user']);
  if (user) {
    queryClient.prefetchQuery({
      queryKey: ['feed', user.id],
      queryFn: () => fetchFeed(user.id),
    });
  }
}
```

---

## 5c. Real-User Monitoring (RUM)

RUM captures performance data from real users on real devices in production — the only way to see the true distribution across device tiers and network conditions.

### Sentry RUM + Session Replay

```tsx
import * as Sentry from '@sentry/react-native';

Sentry.init({
  dsn: 'YOUR_DSN',

  // Performance sampling — 5% of sessions in production
  tracesSampleRate: 0.05,
  profilesSampleRate: 0.05,

  // Session Replay — record 5% of sessions, 100% of sessions with errors
  replaysSessionSampleRate: 0.05,
  replaysOnErrorSampleRate: 1.0,

  // RUM-relevant options
  enableNativeFramesTracking: true,
  enableStallTracking: true,
  enableUserInteractionTracing: true,  // auto-instruments touch events

  // Silent error capture — don't show dialogs to users
  beforeSend(event) {
    event.extra = { ...event.extra, silent: true };
    return event;
  },
});
```

Session Replay obfuscates text and images by default — verify your data masking rules before enabling in production for privacy compliance.

### Firebase Performance RUM Setup

Firebase Performance auto-instruments HTTP requests and screen rendering without any custom code after the package is initialized:

```tsx
// No code needed for automatic traces — firebase/perf auto-hooks on import
import '@react-native-firebase/perf';

// For custom screen traces tied to navigation:
import { useNavigationContainerRef } from '@react-navigation/native';
import perf from '@react-native-firebase/perf';

let activeTrace: ReturnType<typeof perf['newTrace']> | null = null;

export function useFirebaseScreenTrace() {
  const navigationRef = useNavigationContainerRef();

  useEffect(() => {
    const unsubscribe = navigationRef.addListener('state', async () => {
      await activeTrace?.stop();
      const routeName = navigationRef.getCurrentRoute()?.name ?? 'unknown';
      activeTrace = perf().newTrace(`screen_${routeName}`);
      await activeTrace.start();
    });
    return unsubscribe;
  }, [navigationRef]);
}
```

### Sampling Strategies for Production

| Traffic level | `tracesSampleRate` | `profilesSampleRate` | Notes |
|---|---|---|---|
| < 10k DAU | 0.10–0.20 | 0.05–0.10 | Higher sample rate, affordable quota |
| 10k–100k DAU | 0.02–0.05 | 0.01–0.02 | Balance signal vs cost |
| > 100k DAU | 0.005–0.01 | 0.005 | Use dynamic sampling rules |

Use Sentry's **Dynamic Sampling** rules to oversample:
- Users on older device classes (e.g., < 4 GB RAM)
- Users on slow networks (2G/3G)
- Users who recently experienced an error

```tsx
Sentry.init({
  tracesSampler: (samplingContext) => {
    // Always trace checkout flow — high business impact
    if (samplingContext.transactionContext.name?.includes('Checkout')) {
      return 0.5;
    }
    // Low-powered devices: oversample to catch regressions
    if ((samplingContext.customSamplingContext?.ramGB ?? 8) < 3) {
      return 0.1;
    }
    return 0.02; // default 2%
  },
});
```

### Geographic and Device Segmentation

In the Sentry Performance dashboard, use **Group by** to segment P50/P95 metrics:

- **By `device.family`**: identify device tiers where TTI regresses (e.g., low-end Android).
- **By `os.version`**: catch OS-specific regressions after a new iOS/Android release.
- **By `geo.country_code`**: find regions where network-bound traces are significantly slower.
- **By `app.version`**: confirm that a release improved or degraded performance vs the previous version.

In Firebase Performance, equivalent segmentation is available under **Performance > Traces > [trace name] > Attributes**.

---

## 6. CI/CD Performance Testing

### Reassure

Reassure runs render benchmarks in Jest and flags regressions as PR comments.

```bash
yarn add --dev reassure
```

```tsx
// __tests__/FeedList.perf-test.tsx
import { measureRenders } from 'reassure';
import { FeedList } from '../FeedList';

test('FeedList renders efficiently', async () => {
  await measureRenders(<FeedList items={mockItems} />);
});
```

```json
{
  "scripts": {
    "perf": "reassure"
  }
}
```

In CI, run `yarn perf` and use the Reassure GitHub Action to post a comparison table on the PR showing mean render time and render count changes.

### Flashlight (Android)

Flashlight wraps `systrace` and `perfetto` to produce a **Performance Score** (0-100) for any Maestro or shell-driven flow:

```bash
npx @perf-tools/flashlight measure \
  --bundleId com.myapp \
  --testCommand "maestro test flows/feed_scroll.yaml" \
  --resultsFilePath results.json
```

Use `flashlight report` to generate an HTML report. Track the score in CI and fail the build if it drops below a threshold.

### Bundle Size Tracking

```bash
npx react-native bundle \
  --platform ios \
  --dev false \
  --entry-file index.js \
  --bundle-output /tmp/main.jsbundle \
  --sourcemap-output /tmp/main.map

wc -c /tmp/main.jsbundle
gzip -c /tmp/main.jsbundle | wc -c
```

Store these numbers as CI artifacts and compare against the base branch. Fail the build if the gzipped bundle grows by more than a defined budget (e.g., 10 KB).

### PR Comments with Regression Reports

Use `danger-js` to read the Reassure output JSON and the bundle size diff, then post a formatted Markdown table as a PR comment automatically.

---

## 7. Custom Performance Markers

Use the Web Performance API (available in Hermes) to instrument arbitrary code paths:

```tsx
performance.mark('screen_render_start');

// ... render logic or data fetch ...

performance.mark('screen_render_end');

performance.measure(
  'screen_render',
  'screen_render_start',
  'screen_render_end',
);

const entries = performance.getEntriesByType('measure');
entries.forEach(e => {
  console.log(`${e.name}: ${e.duration.toFixed(2)} ms`);
});
```

For production reporting, wrap the measure call and forward durations to Sentry or Firebase:

```tsx
function reportMeasure(name: string, start: string, end: string) {
  performance.measure(name, start, end);
  const [entry] = performance.getEntriesByName(name, 'measure');
  if (entry) {
    Sentry.metrics.distribution(name, entry.duration, { unit: 'millisecond' });
    performance.clearMeasures(name);
    performance.clearMarks(start);
    performance.clearMarks(end);
  }
}
```

---

## 8. E2E Performance Testing

### Maestro

Maestro drives the app through UI flows and can assert timing via custom scripts:

```yaml
# flows/feed_scroll.yaml
appId: com.myapp
---
- launchApp
- waitForAnimationToEnd
- scrollUntilVisible:
    element:
      id: feed-end-marker
    direction: DOWN
    timeout: 5000
```

Combine with Flashlight to get a Performance Score for the entire scroll flow.

### Detox

Detox supports performance assertions in test code:

```tsx
// feed.perf.test.ts
it('scrolls feed within time budget', async () => {
  await device.launchApp({ newInstance: true });
  const start = Date.now();
  await element(by.id('feed-list')).scroll(2000, 'down');
  const duration = Date.now() - start;
  expect(duration).toBeLessThan(3000);
});
```

Run Detox tests in CI on a physical device farm (e.g., AWS Device Farm) for consistent baseline measurements.
