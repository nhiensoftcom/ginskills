# React Native New Architecture — Deep-Dive Reference

## Overview

React Native's New Architecture ships as the default in RN 0.76+. It replaces the legacy asynchronous Bridge with a set of interoperable C++ layers: JSI, Fabric, TurboModules, and Hermes V1. Together they reduce cold TTI from ~3.6s to ~2.1s on mid-range Android and cut native method call latency by 92–99.98%.

---

## 1. JSI (JavaScript Interface)

### What Changed

The legacy Bridge serialized every JS↔Native message to JSON and posted it across an asynchronous queue. Every `NativeModules.Foo.bar()` call involved:

1. JSON serialization in JS
2. Queue flush (batch or timeout)
3. JSON deserialization in Java/ObjC
4. Method dispatch
5. JSON serialize result
6. Async callback back to JS

JSI replaces this with a thin C++ layer that lets the JS engine hold direct references to C++ host objects. No serialization, no queue, no round-trip.

### Benchmarks

| Metric | Bridge (JSC) | JSI + Hermes | Delta |
|--------|-------------|--------------|-------|
| Cold TTI (mid-range Android) | 3.6s | 2.1s | -42% |
| App startup | baseline | ~55% faster | — |
| Native method call (simple) | ~6µs | ~0.04µs | -99.3% |
| Native method call (complex) | ~18µs | ~1.4µs | -92.2% |

### Synchronous Native Calls

Because JSI binds C++ objects directly into the JS runtime, a TurboModule method can return a value synchronously:

```typescript
// Old Bridge — always async, callback or Promise required
NativeModules.Crypto.hash(data, (result) => { /* ... */ });

// JSI / TurboModule — synchronous return is possible
const hash = NativeCrypto.hashSync(data); // returns immediately
```

The JS engine calls into C++ via the JSI `HostFunction` interface. No thread hop is needed when both sides share the same runtime context.

### Host Objects

A `HostObject` is a C++ class that implements `jsi::HostObject`. It exposes named properties to JS, making a native object look like a plain JS object.

```cpp
// C++ side
class NativeCacheHostObject : public jsi::HostObject {
public:
  jsi::Value get(jsi::Runtime& rt, const jsi::PropNameID& name) override {
    auto propName = name.utf8(rt);
    if (propName == "get") {
      return jsi::Function::createFromHostFunction(rt, name, 1,
        [this](jsi::Runtime& rt, const jsi::Value&,
               const jsi::Value* args, size_t) -> jsi::Value {
          std::string key = args[0].asString(rt).utf8(rt);
          return jsi::String::createFromUtf8(rt, cache_.get(key));
        });
    }
    return jsi::Value::undefined();
  }
private:
  LocalCache cache_;
};
```

```typescript
// JS side — object feels native
const result = global.NativeCache.get('user_session');
```

### HostFunction Pattern

For standalone functions (not object methods) use `jsi::Function::createFromHostFunction`. Reanimated's `runOnUI` and `runOnJS` are implemented this way — C++ functions installed directly on the JS global.

### Memory Sharing

JSI does not copy data between runtimes. For large binary payloads (images, audio buffers) use `jsi::ArrayBuffer` backed by a shared memory region:

```cpp
// C++ creates a buffer pointing to native-owned memory
auto buffer = std::make_shared<jsi::MutableBuffer>(nativePtr, size);
auto arrayBuffer = jsi::ArrayBuffer(rt, std::move(buffer));
// JS receives a view into the same bytes — zero copy
```

---

## 2. Fabric Renderer

### Architecture

Fabric is the New Architecture's UI renderer. It replaces the legacy UIManager (which communicated over the Bridge) with a C++ shadow tree that lives entirely in native memory and is accessible from JSI.

Key phases:

1. **Render phase** — React produces a new element tree on the JS thread (unchanged from legacy)
2. **Commit phase** — Fabric clones the shadow tree, runs Yoga layout, and atomically swaps the committed tree (can happen on any thread)
3. **Mount phase** — Platform views are created/updated on the main thread from the committed tree

### Synchronous Rendering via JSI

Because the shadow tree is a C++ object exposed through JSI, React can synchronously query layout measurements without a round-trip:

```typescript
// Synchronous layout read — no async callback needed
const { x, y, width, height } = ref.current.measureInWindow();
```

### React Concurrent Mode Support

Fabric's commit phase is interruptible. React can abandon a render in progress and start a higher-priority update. This enables:

- `useTransition` for non-urgent screen transitions
- `useDeferredValue` for expensive list filters
- Time-sliced reconciliation — long renders no longer block the JS thread

```typescript
import { useTransition, useState } from 'react';

function SearchScreen() {
  const [isPending, startTransition] = useTransition();
  const [query, setQuery] = useState('');

  const handleChange = (text: string) => {
    // Input update is urgent — immediate
    setQuery(text);
    // Filter render is non-urgent — interruptible
    startTransition(() => setFilteredResults(computeResults(text)));
  };

  return (
    <>
      <TextInput onChangeText={handleChange} />
      {isPending && <ActivityIndicator />}
      <ResultsList data={filteredResults} />
    </>
  );
}
```

### Yoga 2 Layout Engine

Fabric uses Yoga 2, which rewrites the layout algorithm in C++ (Yoga 1 was C). Key wins:

- 5,000 `<Text>` elements render ~20% faster than legacy UIManager
- Inline styles are resolved during the Yoga pass rather than serialized back to JS
- Absolute layout is now fully parallel across independent subtrees

### View Flattening

Fabric automatically eliminates "collapsable" wrapper views that exist only for layout purposes — a pattern common in styled-component hierarchies.

```typescript
// Before flattening — 3 native views
<View style={styles.outer}>       // layout only
  <View style={styles.inner}>     // layout only
    <Text>Hello</Text>            // real view
  </View>
</View>

// After Fabric view flattening — 1 native view
// The outer/inner views are merged into the Text's layout parameters
```

To opt out (e.g. for accessibility or gesture hit areas):

```typescript
<View collapsable={false} style={styles.inner}>
```

---

## 3. TurboModules

### Lazy Loading

Legacy `NativeModules` initialized every registered module at startup. TurboModules are lazy: a module's Java/ObjC class is not instantiated until the first JS call.

```typescript
// Old — module initialized even if never used
import { NativeModules } from 'react-native';
const { Analytics } = NativeModules; // initialized at startup

// New — module init deferred until first call
import { TurboModuleRegistry } from 'react-native';
const Analytics = TurboModuleRegistry.get<Spec>('Analytics'); // lazy
Analytics?.track('app_open'); // init happens here, on first call
```

**Practical impact**: defer analytics, crash reporting, and push notification modules out of the startup critical path. Each heavy SDK that lazy-initializes saves 30–120ms of cold start time.

### Codegen Type Safety

TurboModules use Codegen to generate C++ and Java/ObjC bridge glue from a TypeScript spec. This eliminates entire categories of type mismatch crashes.

```typescript
// NativeAnalyticsSpec.ts — source of truth
import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export interface Spec extends TurboModule {
  track(event: string, properties: Object): void;
  identify(userId: string): Promise<boolean>;
  flush(): Promise<void>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('Analytics');
```

Codegen reads this file and emits:
- `NativeAnalyticsSpec.h` / `NativeAnalyticsSpec.mm` for iOS
- `NativeAnalyticsSpec.java` for Android
- Type-checked method signatures — wrong argument types are compile errors, not runtime crashes

### Custom TurboModule (iOS example)

```objc
// RCTAnalytics.mm
#import "RCTAnalytics.h"

@implementation RCTAnalytics

RCT_EXPORT_MODULE()

- (void)track:(NSString *)event properties:(JS::NativeAnalytics::SpecTrackProperties &)properties {
  // Implementation
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params {
  return std::make_shared<facebook::react::NativeAnalyticsSpecJSI>(params);
}

@end
```

### Performance vs Old NativeModules

| Scenario | NativeModules | TurboModules | Savings |
|----------|--------------|--------------|---------|
| Module init at startup | All modules | Only used modules | 200–500ms |
| Method call overhead | ~6µs (JSON) | ~0.04µs (JSI) | ~99% |
| Type mismatch | Runtime crash | Compile error | — |
| Null module access | Silent undefined | Exception at call site | — |

---

## 4. Hermes Engine (V1 — RN 0.82+/0.84 default)

### AOT Bytecode Precompilation

Hermes V1 (the bytecode-at-build-time variant) compiles JS to Hermes bytecode during the Metro build step, not at app launch. The device never parses or compiles JS — it executes precompiled bytecode directly.

```bash
# Metro produces a .hbc file instead of .js bundle
# The bundler runs hermesc at build time:
hermesc -emit-binary -out index.hbc index.js
```

### Benchmarks (Hermes V1 vs Hermes Legacy)

| Metric | Hermes Legacy | Hermes V1 | Delta |
|--------|--------------|-----------|-------|
| TTI — iOS | baseline | +2.5% faster | — |
| TTI — Android | baseline | +7.6% faster | — |
| Bundle load — iOS | baseline | +9% faster | — |
| Bundle load — Android | baseline | +3.1% faster | — |
| Bytecode size | minified JS | ~33% smaller | — |
| Peak memory | ~185MB (JSC) | ~136MB | -26% |

The memory reduction is significant on low-end devices where OOM kills are the #1 cause of crash-rate regression.

### Hermes Garbage Collector

Hermes uses GenGC — a generational garbage collector with:

- **Young generation (nursery)**: short-lived objects; collected frequently and cheaply
- **Old generation**: long-lived objects promoted from nursery; collected less often
- **Concurrent marking**: GC mark phase runs concurrently with JS execution, reducing pause times

For performance-critical apps, avoid creating large numbers of temporary objects in hot paths (list render callbacks, gesture handlers) to reduce nursery pressure.

### Verifying Hermes Is Active

```typescript
// Check at runtime
const isHermes = () => !!global.HermesInternal;

// In any component or startup code
if (__DEV__) {
  console.log('Hermes active:', isHermes());
  console.log('Hermes version:', global.HermesInternal?.getRuntimeProperties?.());
}
```

In production builds you can also check the Metro output — a `.hbc` bundle extension confirms AOT compilation.

### Hermes Profiler

```typescript
// Start CPU profile
Hermes.enableSamplingProfiler();

// ... run the code you want to profile ...

// Stop and write profile
const profilePath = await Hermes.dumpSampledTraceToFile();
// Open profilePath in Chrome DevTools > Performance tab (load JSON)
```

For frame-level profiling, combine with Flipper's Hermes Debugger plugin which visualizes the sample trace inline with React component renders.

---

## 5. Bridgeless Mode (RN 0.76+ default)

### What Was Removed

The legacy Bridge runtime initialized on every app launch regardless of whether any Bridge-based modules existed:

- A dedicated message queue thread
- JSON serialization infrastructure
- Callback registry (tracking thousands of pending callbacks)
- Event emitter wiring (NativeEventEmitter over the Bridge)

Bridgeless mode removes all of this. Timers (`setTimeout`, `setInterval`), error handling (`ErrorUtils`), and event emitters are reimplemented as JSI bindings.

**Result: ~50% TTI reduction** on apps that fully adopt New Architecture.

### Timers and Event Emitters in Bridgeless Mode

```typescript
// Timers work identically — implementation is now JSI-backed
setTimeout(() => doWork(), 1000);

// NativeEventEmitter now uses JSI under the hood
import { NativeEventEmitter } from 'react-native';
const emitter = new NativeEventEmitter(NativeModule);
const sub = emitter.addListener('onData', handler);
// Cleanup is identical — API unchanged
sub.remove();
```

### Verifying Bridgeless Mode

```typescript
import { RNTesterTurboModuleRegistry } from 'react-native/Libraries/TurboModule/TurboModuleRegistry';

// Check internals — bridgeless if Bridge is absent
const isBridgeless = () => {
  // @ts-ignore — internal API
  return global.RN$Bridgeless === true;
};
```

Or inspect the Metro bundle: bridgeless apps will not include `MessageQueue.js` in the output.

### Migration Considerations

- Third-party libraries that call `NativeModules` directly (not via TurboModuleRegistry) may break — check `react-native-community` compatibility tables
- Libraries using `RCTBridge` in native code require updates to use `RCTBridgelessModuleProvider`
- Use `npx react-native doctor` and the Upgrade Helper to audit dependencies

---

## 6. Enabling New Architecture

### Android

```properties
# android/gradle.properties
newArchEnabled=true
```

### iOS

```ruby
# ios/Podfile
ENV['RCT_NEW_ARCH_ENABLED'] = '1'

target 'MyApp' do
  use_react_native!(
    :path => config[:reactNativePath],
    :hermes_enabled => true,
    :fabric_enabled => ENV['RCT_NEW_ARCH_ENABLED'] == '1',
  )
end
```

Then reinstall pods:

```bash
cd ios && RCT_NEW_ARCH_ENABLED=1 bundle exec pod install
```

### Verify All Layers Are Active

```typescript
// Runtime verification utility
export function verifyNewArchitecture() {
  const checks = {
    hermes: !!global.HermesInternal,
    bridgeless: global.RN$Bridgeless === true,
    fabric: !!global.nativeFabricUIManager,
  };

  if (__DEV__) {
    console.table(checks);
  }

  return checks;
}
```

---

## 7. Metro Config Optimization

### inlineRequires

`inlineRequires` defers module evaluation to the point of first use. Instead of executing every `require()` at bundle parse time, Metro rewrites imports into lazy getter functions.

```javascript
// metro.config.js
const { getDefaultConfig } = require('@react-native/metro-config');

const config = getDefaultConfig(__dirname);

config.transformer = {
  ...config.transformer,
  inlineRequires: true, // defer all requires by default
};
```

**What it rewrites:**

```javascript
// Before inlineRequires
const Analytics = require('./analytics'); // executed at parse time
export function track() { Analytics.track(); }

// After inlineRequires (Metro transform output)
export function track() {
  require('./analytics').track(); // executed only when track() is called
}
```

**Savings**: on a 5MB bundle with 800 modules, inlineRequires typically saves 300–600ms of startup time by deferring ~60% of module evaluation until after first render.

### allowOptionalDependencies and modulePaths

```javascript
// metro.config.js
config.resolver = {
  ...config.resolver,
  // Resolve symlinks — required for monorepos
  unstable_enableSymlinks: true,
  // Extra node_modules roots (monorepo packages)
  nodeModulesPaths: [
    path.resolve(__dirname, '../../node_modules'),
  ],
  // Exclude platform-specific files from the wrong platform
  platforms: ['ios', 'android', 'native', 'js'],
};
```

### Tree Shaking

Metro's tree shaking is limited compared to webpack. The most effective approach:

1. **Avoid barrel files** — `import { x } from './index'` forces Metro to include the entire barrel
2. **Use direct imports** — `import x from './module/x'` includes only that file
3. **Mark side-effect-free packages** — add `"sideEffects": false` in `package.json`

```typescript
// Anti-pattern — pulls in all of lodash
import { debounce } from 'lodash';

// Correct — only debounce module
import debounce from 'lodash/debounce';
```

### Custom Serializer for Bundle Analysis

```javascript
// metro.config.js
const { createMetroConfiguration } = require('metro-config');

config.serializer = {
  ...config.serializer,
  customSerializer: async (entryPoint, preModules, graph, options) => {
    // Log module sizes during build
    if (process.env.ANALYZE_BUNDLE) {
      const sizes = [...graph.dependencies.entries()]
        .map(([path, mod]) => ({ path, size: mod.output[0]?.data?.code?.length ?? 0 }))
        .sort((a, b) => b.size - a.size)
        .slice(0, 20);
      console.table(sizes);
    }
    // Delegate to default serializer
    return require('metro/src/DeltaBundler/Serializers/baseJSBundle')(
      entryPoint, preModules, graph, options,
    );
  },
};
```

Run with: `ANALYZE_BUNDLE=true npx react-native bundle --platform android ...`

### minifierConfig

```javascript
config.transformer = {
  ...config.transformer,
  minifierPath: 'metro-minify-terser',
  minifierConfig: {
    compress: {
      drop_console: !__DEV__, // strip console.log in production
      passes: 2,              // two compression passes
      pure_funcs: ['console.info', 'console.debug'],
    },
    mangle: {
      keep_fnames: false,
    },
    output: {
      ascii_only: true,       // safe for all JS engines
    },
  },
};
```

---

## 8. RN 0.77–0.78 Changes

### React Native 0.78: Full React 19 Support with React Compiler

RN 0.78 ships React 19 as the peer dependency and enables the React Compiler (`react-compiler`) by default in new projects. The compiler automatically memoizes components and hooks — eliminating most manual `useMemo`/`useCallback` calls.

```bash
# Verify compiler is active in metro.config.js
# (generated by RN 0.78 template)
module.exports = {
  transformer: {
    unstable_transformProfile: 'hermes-stable',
    // React Compiler Babel plugin is wired in automatically
  },
};
```

```typescript
// Before React Compiler — manual memoization
const expensiveList = useMemo(() => computeList(data), [data]);
const handlePress = useCallback((id: string) => onPress(id), [onPress]);

// After React Compiler — compiler infers these automatically
// You can write this and get the same memoization behavior:
const expensiveList = computeList(data);
const handlePress = (id: string) => onPress(id);
```

React 19 additions relevant to RN 0.78:

- **`use()` hook**: read a Promise or Context inside render without a wrapper component
- **Server Actions**: not applicable to RN directly, but the `use(promise)` pattern unifies suspense-based data fetching
- **Improved error reporting**: distinguishing hydration vs render errors (useful for Fabric's commit-phase errors)
- **`ref` as prop**: `forwardRef` wrapper is no longer required — refs pass through like any prop

### Android XML Vector Drawable Resources

RN 0.77 adds first-class support for Android XML vector drawables as image sources. Previously, vector assets required a third-party library or manual conversion to PNG sprites.

```typescript
// Now supported natively on Android (RN 0.77+)
// Place your .xml file under android/app/src/main/res/drawable/
<Image source={{ uri: 'ic_logo' }} style={{ width: 48, height: 48 }} />

// Or reference via require with an .xml extension if bundling via Metro
// (requires metro-config drawable resolver — see RN docs)
```

Performance implication: vector drawables are resolution-independent and render directly via Android's hardware-accelerated Canvas pipeline — no PNG decode, no extra memory for multiple density buckets.

### Legacy Architecture Freeze

As of RN 0.76, the legacy Bridge architecture is in **maintenance mode only**:

- No new features will be added to the Bridge, UIManager, or legacy `NativeModules`
- Only critical security and crash fixes will be backported
- The `NativeModules` global still works via a compatibility shim in Bridgeless mode, but the shim itself may be removed in a future major release
- `RCTBridge` on iOS and `ReactInstanceManager` on Android are deprecated — new native code should target `ReactHostDelegate` / `RCTReactNativeHost`

**Practical rule**: any new native module written today must be a TurboModule. Any native view written today must be a Fabric component. Do not invest engineering time extending legacy Bridge modules.

---

## 9. Thread Safety & JSI Safety

### JSI Objects Are Not Thread-Safe

JSI host objects and `jsi::Runtime` references are bound to the JS thread. Calling any JSI method from a background thread (network callback, file I/O completion, audio thread) is undefined behavior and will crash in debug builds.

```cpp
// BAD — called from a background thread (e.g. a network completion handler)
void onNetworkResponse(std::string json) {
  // CRASH: runtime_ belongs to the JS thread
  auto result = jsi::String::createFromUtf8(runtime_, json);
  callback_.call(runtime_, result);
}

// GOOD — schedule back to JS thread via the runtime's task runner
void onNetworkResponse(std::string json) {
  jsCallInvoker_->invokeAsync([this, json]() {
    // Now on JS thread — safe to use JSI
    auto result = jsi::String::createFromUtf8(runtime_, json);
    callback_.call(runtime_, result);
  });
}
```

The `CallInvoker` is provided to every TurboModule via its `InitParams`. Always capture it and use `invokeAsync` for any cross-thread JSI access.

### Reanimated's `runOnUI` / `runOnJS` as the Correct Pattern

Reanimated manages two JSI runtimes: the JS runtime and the UI runtime (runs on the UI thread). Its cross-thread helpers are the reference implementation for safe JSI threading:

```typescript
import { runOnJS, runOnUI } from 'react-native-reanimated';

// SAFE: call a JS function from the UI thread
const notifyJS = runOnJS((value: number) => {
  // Executes on the JS thread — safe to update state
  setCurrentValue(value);
});

// SAFE: run worklet code on the UI thread from JS
const startAnimation = () => {
  runOnUI(() => {
    'worklet';
    // Executes on the UI thread — direct access to native view props
    animatedValue.value = withSpring(1);
    notifyJS(animatedValue.value); // schedule back to JS
  })();
};
```

```typescript
// BAD — accessing shared mutable state from two threads without synchronization
const sharedProgress = useSharedValue(0);

function onGestureEvent(e: GestureUpdateEvent) {
  // This runs on the UI thread (worklet context)
  sharedProgress.value = e.translationX;
  // Directly calling a JS closure here is unsafe — do NOT do this:
  jsCallback(sharedProgress.value); // WRONG: not a runOnJS wrapper
}

// GOOD
const jsCallback = runOnJS((v: number) => setState(v));

function onGestureEvent(e: GestureUpdateEvent) {
  'worklet';
  sharedProgress.value = e.translationX;
  jsCallback(sharedProgress.value); // correct: marshalled via runOnJS
}
```

### Thread Ownership Summary

| Object | Owner Thread | Cross-Thread Access |
|--------|-------------|---------------------|
| `jsi::Runtime` | JS thread | Never — use `CallInvoker` |
| Reanimated UI runtime | UI thread | `runOnUI` / `runOnJS` |
| `SharedValue` | Both (lock-free atomic) | Read/write safe from both |
| React state (`useState`) | JS thread | `runOnJS` to update from UI |
| Native view props (Fabric) | UI/main thread | Via Reanimated worklets only |

---

## 10. Native Module Performance — Swift/Kotlin JSI Bindings

### Pure C++ JSI Modules vs Language-Bridged Modules

TurboModules can be implemented in three ways, each with different overhead:

| Implementation | Call path | Overhead |
|----------------|-----------|----------|
| Pure C++ JSI | JS → C++ | ~0.04µs |
| ObjC++ (iOS) | JS → C++ → ObjC++ ABI | ~0.3–0.8µs |
| Swift-bridged (iOS) | JS → C++ → ObjC++ → Swift | ~1.2–2.5µs |
| Kotlin-bridged (Android) | JS → C++ → JNI → Kotlin | ~1.0–2.0µs |

For modules called thousands of times per second (audio, gesture processing, real-time data), the language bridge cost is significant. Pure C++ JSI modules eliminate every hop.

```cpp
// Pure C++ TurboModule — maximum performance
// No ObjC++ or JNI boundary

class NativeAudioProcessor : public NativeAudioProcessorCxxSpec<NativeAudioProcessor> {
public:
  NativeAudioProcessor(std::shared_ptr<CallInvoker> jsInvoker)
    : NativeAudioProcessorCxxSpec(std::move(jsInvoker)) {}

  double processFrame(jsi::Runtime& rt, jsi::Array frame) {
    // Runs entirely in C++ — zero language bridge overhead
    return processor_.processFrame(toFloatVector(rt, frame));
  }

private:
  AudioProcessor processor_;
};
```

### Nitro Modules

[Nitro Modules](https://github.com/mrousavy/nitro) is a library that generates a statically compiled JSI binding layer from a TypeScript interface definition — similar to Codegen, but targeting C++ directly without the ObjC++/JNI bridge overhead.

```typescript
// nitrogen spec — NitroAudio.nitro.ts
import { type HybridObject } from 'react-native-nitro-modules';

export interface NitroAudio extends HybridObject<{ ios: 'c++'; android: 'c++' }> {
  processFrame(samples: number[]): number;
  setGain(db: number): void;
  readonly sampleRate: number;
}
```

Nitro generates:
- A C++ `HybridObject` base class with JSI property descriptors baked in at compile time
- No runtime type dispatch — method routing is resolved at link time
- Swift/Kotlin wrappers are optional and thin (no serialization involved)

```typescript
// Usage is identical to a standard TurboModule
import { NitroModules } from 'react-native-nitro-modules';
import type { NitroAudio } from './NitroAudio.nitro';

const audio = NitroModules.createHybridObject<NitroAudio>('NitroAudio');
const result = audio.processFrame(samples); // synchronous, ~0.04µs
```

### When to Use Nitro Modules vs Hand-Written JSI

| Scenario | Recommendation |
|----------|---------------|
| New module, pure C++ logic | Nitro Modules — fastest, least boilerplate |
| New module, Swift/Kotlin required (platform SDK) | TurboModule with ObjC++ shim; accept language bridge cost |
| Existing Codegen TurboModule, already working | Keep as-is unless profiling shows >1µs call overhead |
| Real-time audio / gesture processing (>10k calls/sec) | Pure C++ JSI or Nitro Modules — language bridge is measurable |
| One-off module called rarely | Standard TurboModule — simplicity wins |

### Profiling Native Module Call Overhead

```typescript
// Measure actual call cost in microseconds
const ITERATIONS = 10_000;

const start = performance.now();
for (let i = 0; i < ITERATIONS; i++) {
  NativeModule.syncMethod(i);
}
const elapsed = performance.now() - start;
console.log(`Average call: ${((elapsed / ITERATIONS) * 1000).toFixed(2)}µs`);
// Target: <1µs for pure C++ JSI, <5µs for ObjC++/JNI bridged
```

---

## 11. Expo vs Bare Workflow Architecture

### Feature Comparison

| Capability | Expo Managed | Expo Bare | Bare RN |
|------------|-------------|-----------|---------|
| New Architecture (Fabric + TurboModules) | Yes (SDK 50+) | Yes | Yes |
| Bridgeless mode | Yes (SDK 53+) | Yes | Yes |
| Custom native modules | No | Yes | Yes |
| Nitro Modules | No | Yes | Yes |
| Pure C++ JSI modules | No | Yes | Yes |
| OTA updates (EAS Update) | Yes | Yes | Manual |
| Config plugins | Yes | Yes | N/A |
| Expo Modules API | Yes | Yes | Optional |
| Direct Podfile/build.gradle edits | No | Yes | Yes |
| `react-native upgrade` | N/A | Via Expo SDK bump | Manual |

### TurboModule / Fabric in Expo Managed

Expo Managed (SDK 50+) enables the New Architecture by default, but through a constrained path:

- All native modules must be Expo Modules API-based (no hand-written ObjC++/JNI)
- Fabric components work via the standard `react-native` package
- Custom TurboModules are not supported — managed workflow apps cannot add native code directly

```json
// app.json — enable New Architecture in Expo Managed
{
  "expo": {
    "newArchEnabled": true
  }
}
```

Under the hood, Expo builds a managed binary (the Expo Go client or a custom dev client via EAS Build) that already includes the New Architecture runtime. Your JS bundle runs against it.

### When Bare Workflow Is Needed for Performance

Switch to bare workflow when you need:

1. **Pure C++ or Nitro Modules** — audio engines, ML inference, crypto, real-time processing
2. **Custom Hermes build flags** — e.g. enabling experimental VM features
3. **Modified Metro serializer** — custom bundle splitting beyond what Expo supports
4. **JNI-level Android optimizations** — custom rendering pipelines, `SurfaceView` integration
5. **Compile-time flag control** — `#ifdef ENABLE_FEATURE` gating in native code

```bash
# Eject from managed to bare
npx expo prebuild --clean
# Generates ios/ and android/ directories
# From here, treat as a standard bare RN project
```

### Expo Modules API Performance Characteristics

The Expo Modules API is a Swift/Kotlin abstraction over TurboModules. It trades some raw call throughput for dramatically reduced boilerplate:

```swift
// Swift — Expo Modules API
// ~60% less code than equivalent ObjC++ TurboModule
public class AudioModule: Module {
  public func definition() -> ModuleDefinition {
    Name("Audio")

    Function("processFrame") { (samples: [Double]) -> Double in
      return AudioProcessor.shared.process(samples)
    }

    AsyncFunction("loadFile") { (path: String, promise: Promise) in
      Task {
        let result = try await AudioLoader.load(path)
        promise.resolve(result)
      }
    }
  }
}
```

Performance characteristics:
- Synchronous `Function`: ~0.8–1.5µs per call (Swift bridge overhead vs ~0.04µs pure C++)
- `AsyncFunction`: async by design — no meaningful sync overhead comparison
- Suitable for most app-layer modules (storage, camera, permissions, analytics)
- Not suitable for modules called >5,000 times/sec — use Nitro Modules or pure C++ instead

---

## 12. Fabric Rendering Pipeline Deep Dive

### Render → Commit → Mount Timing

The three Fabric phases have distinct timing profiles in production:

| Phase | Thread | Typical duration | Blocking? |
|-------|--------|-----------------|-----------|
| Render | JS thread | 2–16ms (component count) | Blocks JS |
| Commit | Background C++ thread | 0.5–4ms (tree diff + Yoga) | Non-blocking |
| Mount | Main/UI thread | 0.5–3ms (view mutations) | Blocks UI |

The commit phase (Yoga layout + shadow tree diff) runs off both the JS and main threads — this is a key Fabric advantage over legacy UIManager, which ran layout on the main thread and blocked touches.

```typescript
// Measure render-to-paint latency with PerformanceObserver
const observer = new PerformanceObserver((list) => {
  for (const entry of list.getEntries()) {
    if (entry.entryType === 'measure') {
      console.log(`${entry.name}: ${entry.duration.toFixed(1)}ms`);
    }
  }
});
observer.observe({ entryTypes: ['measure'] });

performance.mark('render-start');
// ... trigger re-render ...
// In useEffect after render:
performance.mark('render-end');
performance.measure('full-render', 'render-start', 'render-end');
```

### Automatic Batching with React 18+

React 18 (shipped with RN 0.71+) batches all state updates by default — including updates inside `setTimeout`, native event handlers, and Promises. This reduces redundant Fabric commit phases.

```typescript
// React 17 behavior — three separate renders (three Fabric commits)
setTimeout(() => {
  setCount(c => c + 1); // render 1
  setLoading(false);    // render 2
  setData(result);      // render 3
}, 0);

// React 18 behavior — automatic batching — ONE render, ONE Fabric commit
setTimeout(() => {
  setCount(c => c + 1); // \
  setLoading(false);    //  > batched → single commit
  setData(result);      // /
}, 0);

// Opt out when you need immediate intermediate renders
import { flushSync } from 'react-native';

flushSync(() => setCount(c => c + 1)); // forces immediate commit
setLoading(false);                      // separate commit
```

**Impact**: screens with multiple state updates per event (common in form validation, data loading) can see 30–60% fewer Fabric commit phases with automatic batching.

### Priority-Based Rendering with Concurrent Features

Fabric's commit phase is priority-aware. React's scheduler assigns lanes to updates:

| Lane | Priority | Use case |
|------|----------|----------|
| SyncLane | Immediate | Direct user input (`TextInput`, `Pressable`) |
| InputContinuousLane | High | Scroll, drag, continuous gesture |
| DefaultLane | Normal | Data fetching, `setState` in effects |
| TransitionLane | Low | `startTransition` wrapped updates |
| IdleLane | Idle | Background preloading |

```typescript
import { useTransition, useDeferredValue, startTransition } from 'react';

// Pattern 1: useTransition for screen-level transitions
function ProfileScreen() {
  const [isPending, startTransition] = useTransition();
  const [tab, setTab] = useState<'posts' | 'likes'>('posts');

  return (
    <>
      <TabBar
        active={tab}
        onPress={(t) => startTransition(() => setTab(t))} // low priority
      />
      {isPending ? <SkeletonList /> : <PostList tab={tab} />}
    </>
  );
}

// Pattern 2: useDeferredValue for expensive derived renders
function FilterableList({ items }: { items: Item[] }) {
  const [filter, setFilter] = useState('');
  // Deferred copy — lags behind filter by one render cycle
  const deferredFilter = useDeferredValue(filter);
  // Expensive filtering runs at low priority using deferredFilter
  const filtered = useMemo(
    () => items.filter(i => i.name.includes(deferredFilter)),
    [items, deferredFilter],
  );

  return (
    <>
      <TextInput value={filter} onChangeText={setFilter} /> {/* always immediate */}
      <ItemList data={filtered} /> {/* may render stale data briefly */}
    </>
  );
}
```

### Yoga 2 Layout Engine Specifics

Yoga 2 (shipped with Fabric) introduces several layout behaviors that differ from Yoga 1:

**Gap support**: `rowGap`, `columnGap`, and `gap` are now native Yoga properties — no workaround with margin needed.

```typescript
// Yoga 2 native gap — works in Fabric
<View style={{ flexDirection: 'row', gap: 12 }}>
  {items.map(item => <Card key={item.id} />)}
</View>

// Old workaround — no longer needed but still works
<View style={{ flexDirection: 'row' }}>
  {items.map((item, i) => (
    <Card key={item.id} style={i > 0 ? { marginLeft: 12 } : undefined} />
  ))}
</View>
```

**Parallel subtree layout**: independent subtrees (no cross-subtree `%` sizing or baseline alignment) are laid out in parallel using C++ thread pools. On devices with 6+ cores, complex screens with independent sections (header, content, tab bar) see measurable layout speedups.

**Errata flags**: Yoga 2 fixes several long-standing flexbox spec non-conformances. Some existing layouts may shift — test on both platforms after enabling New Architecture.

```typescript
// Check if a known errata is active (for debugging layout regressions)
// Yoga 2 erratas are controlled at the RN C++ layer — no JS API
// If you see layout shifts after enabling New Architecture:
// 1. Check: https://github.com/nicolo-ribaudo/yoga/blob/main/CHANGELOG.md
// 2. Add collapsable={false} to the affected view as a diagnostic step
// 3. File a regression issue with a minimal repro
```

---

## 13. Incremental Adoption & Migration

### Interop Layer: What Works Automatically

When `newArchEnabled=true`, RN 0.76+ ships an interop layer that makes most legacy Bridge modules work in the New Architecture without modification:

- `NativeModules.Foo.bar()` calls are proxied through a compatibility shim
- `requireNativeComponent` views are wrapped in a Fabric interop host component
- `NativeEventEmitter` works via JSI-backed event dispatch

What does **not** work automatically:

- Modules using `RCTBridge` init-time side effects (rely on `bridge:didFinishLaunching`)
- Views using `RCTUIManager` APIs directly in native code
- Modules depending on the Bridge's async callback registry ordering

```typescript
// Check if interop layer is active for a specific module
// Interop modules appear under RN$InteropModuleRegistry in dev builds
if (__DEV__) {
  // @ts-ignore
  const isInteropModule = !!global.RN$InteropModuleRegistry?.hasModule?.('Analytics');
  console.log('Analytics running via interop:', isInteropModule);
}
```

### Dependency Audit for Compatibility

Before enabling New Architecture, audit third-party dependencies:

```bash
# Check react-native-community compatibility table
npx @rnx-kit/align-deps --requirements react-native@0.76

# Detect packages that still use legacy Bridge APIs
npx react-native-new-arch-helper check

# For each incompatible package, check:
# 1. Is there a newer version with New Arch support?
# 2. Is there an actively maintained fork?
# 3. Can it be replaced with a native RN equivalent?
```

Priority order for resolving incompatible dependencies:

1. **Upgrade** — check the package's GitHub for a `new-arch` branch or recent release
2. **Replace** — many third-party modules now have first-party RN equivalents (`@react-native-community/...`)
3. **Patch** — fork and apply the interop shim yourself (only for internal/private packages)
4. **Exclude from New Arch** — use `moduleNameMapper` or conditional require (last resort)

### Phased Rollout by Screen/Route

Rather than enabling New Architecture app-wide on day one, you can roll it out screen-by-screen using feature flags combined with Fabric's per-root-view enablement:

```typescript
// Phase 1: Enable New Arch on a single, low-risk screen
// android/app/src/main/java/com/myapp/MainActivity.kt
override fun createReactActivityDelegate(): ReactActivityDelegate {
  return object : DefaultReactActivityDelegate(this, mainComponentName, fabricEnabled = true) {}
  // fabricEnabled flag allows per-activity control
}
```

```typescript
// Phase 2: Track adoption with feature flags
// Gradually expand to more screens, monitoring crash rates per screen

// Feature flag check (use your own flag system)
const isNewArchScreen = featureFlags.isEnabled('new_arch_home_screen');

// In your navigator — render different root component per flag
const HomeScreen = isNewArchScreen
  ? require('./HomeScreen.newarch').default
  : require('./HomeScreen.legacy').default;
```

**Rollout checklist per screen:**

- [ ] Audit all native modules used by the screen — confirm New Arch compatible
- [ ] Run E2E tests on both platforms
- [ ] Monitor Sentry/Crashlytics for 48h post-rollout
- [ ] Measure TTI before/after with Flashlight or Perfetto
- [ ] Confirm gesture and animation behavior (Reanimated worklets, Gesture Handler)

### Rollback Strategy

```typescript
// android/gradle.properties
# Rollback: disable New Architecture instantly
newArchEnabled=false
# No code changes required — interop layer handles the rest
```

```ruby
# ios/Podfile
# Rollback iOS
ENV['RCT_NEW_ARCH_ENABLED'] = '0'
# Re-run: bundle exec pod install
```

For production rollbacks without an app release, use a remote config flag to gate the `newArchEnabled` behavior at the JS layer (you cannot change native build flags OTA, but you can control which screens use Fabric roots if your app architecture supports it).

**Monitoring signals that indicate rollback is needed:**

| Signal | Threshold | Action |
|--------|-----------|--------|
| Crash-free sessions drop | >0.5% from baseline | Immediate rollback |
| ANR rate increase (Android) | >0.1% | Investigate before rollback |
| JS thread frame drops | >5% increase on P75 | Profile, then decide |
| Native module call errors | Any new error type | Audit interop layer |

---

## Performance Budget Reference

| Layer | Target | Fail Threshold |
|-------|--------|----------------|
| Cold TTI (Android mid-range) | ≤2.1s | >3.0s |
| Cold TTI (iOS) | ≤1.5s | >2.5s |
| Native method call | <1µs | >10µs |
| JS bundle (gzip) | ≤2MB | >6MB |
| Peak memory | ≤200MB | >400MB |
| Startup module evaluation | ≤60% of modules | >80% |

---

## Quick Diagnostic Commands

```bash
# Confirm Hermes bytecode output
file ios/build/Build/Products/Debug-iphonesimulator/MyApp.app/main.jsbundle
# → "Hermes JavaScript bytecode, version N"

# Measure bundle module count
npx react-native bundle --platform android --dev false \
  --entry-file index.js --bundle-output /tmp/bundle.js \
  && wc -l /tmp/bundle.js

# Run Metro with bundle analysis
ANALYZE_BUNDLE=true npx react-native bundle \
  --platform android --dev false --entry-file index.js \
  --bundle-output /dev/null

# Profile startup with systrace (Android)
python $ANDROID_HOME/platform-tools/systrace/systrace.py \
  --time=10 -o /tmp/trace.html app webview sched gfx
```
