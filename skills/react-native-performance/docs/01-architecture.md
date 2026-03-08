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
