# Bundle Size Optimization

## Why Bundle Size Matters

Every kilobyte in your JS bundle costs time across three dimensions: download (initial install and OTA updates), disk read (the OS loads the bundle from storage on every cold start), and parse/evaluate (the JS runtime processes each module before the first frame renders). On a mid-tier Android device with a 2 MB minified bundle, parse alone can consume 300–500 ms of your cold start budget. Hermes bytecode mitigates the parse step, but disk read and OTA download costs remain proportional to raw size.

---

## 1. How Tree Shaking Works in React Native

Tree shaking is the process of statically analyzing import/export graphs and removing unreachable code. It requires ES module syntax (`import`/`export`) because the module graph must be deterministic at build time. CommonJS (`require`) is dynamic — any string can be passed to `require()` at runtime — so static analysis is impossible.

Metro, React Native's default bundler, converts ES modules to CommonJS before bundling. This conversion destroys the static analyzability that tree shaking depends on. [Metro issue #632](https://github.com/facebook/metro/issues/632) has tracked this limitation since 2018 with no native resolution.

**Practical consequence:** importing a single utility from a lodash-style barrel file causes Metro to include the entire library.

### Metro vs webpack: capability comparison

| Feature | Metro (native) | webpack 5 / Re.Pack | esbuild serializer |
|---|---|---|---|
| Unused export elimination | No | Full | Partial |
| Cross-module analysis | No | Yes | Yes |
| `sideEffects` field | No | Yes | Yes |
| Dynamic `import()` splitting | No | Yes | No |
| `export *` barrel handling | No | Yes | Partial |

### ES modules vs CommonJS

```ts
// ES Modules — statically analyzable, tree-shakeable
import { debounce } from 'lodash-es'; // only debounce enters the bundle

// CommonJS — dynamic, not tree-shakeable
const { debounce } = require('lodash'); // entire lodash enters the bundle
// Metro cannot determine at build time what properties are used
```

### Workarounds in order of adoption effort

**Option A — `@rnx-kit/metro-serializer-esbuild`** (lowest effort, 0–20% reduction)

Replaces Metro's serializer stage with esbuild. Respects the `sideEffects` field in `package.json` and performs dead-code elimination after Metro resolves the module graph.

```js
// metro.config.js
const { makeMetroConfig } = require('@rnx-kit/metro-config');
const { MetroSerializer, esbuildTransformerConfig } = require('@rnx-kit/metro-serializer-esbuild');

module.exports = makeMetroConfig({
  serializer: {
    customSerializer: MetroSerializer([], { minify: true }),
  },
  transformer: {
    ...esbuildTransformerConfig,
  },
});
```

**Option B — Expo experimental tree shaking** (SDK 52+, medium effort)

Expo's Metro fork gained experimental tree shaking. It handles `export *` re-exports (barrel files), respects `sideEffects`, and performs DCE on the resolved graph.

```json
{
  "expo": {
    "experiments": {
      "treeShaking": true
    }
  }
}
```

Verify results with `npx expo export --dump-sourcemap` and inspect with Expo Atlas.

**Option C — Re.Pack** (highest effort, maximum control)

Re.Pack replaces Metro entirely with webpack, giving you the full webpack tree shaking pipeline including `sideEffects`, scope hoisting, and Module Federation 2 for micro-frontends.

```js
// webpack.config.mjs (Re.Pack)
import { RepackPlugin } from '@callstack/repack';

export default (env) => ({
  optimization: {
    usedExports: true,
    sideEffects: true,
  },
  plugins: [new RepackPlugin()],
});
```

### The `sideEffects` field

Libraries that mark themselves as side-effect-free allow bundlers to skip entire files whose exports are unused. Metro natively ignores this field; esbuild and webpack respect it fully.

```json
{ "sideEffects": false }

{ "sideEffects": ["./src/polyfills.js", "*.css"] }
```

---

## 2. Common Tree Shaking Failures

The libraries below are responsible for the largest unexpected size contributions in most React Native codebases.

| Library | Problem | Parsed Size | Solution | Savings |
|---|---|---|---|---|
| lodash | CommonJS build; no ESM | ~71 KB | `lodash-es` or `lodash/specific` | ~55–60 KB |
| moment.js | Monolithic + all locales bundled | ~232 KB | `dayjs` (~2 KB) | ~230 KB |
| firebase (compat) | Namespaced API includes entire SDK | ~150 KB+ | Modular v9+ | ~70–100 KB |
| axios | Full HTTP client with adapters | ~13 KB | Native `fetch` | ~13 KB |
| uuid | Ships crypto polyfills for all environments | ~12 KB | `crypto.randomUUID()` | ~12 KB |
| date-fns (CJS) | Barrel + CJS build in older versions | ~75 KB | `date-fns/esm` subpath or v3+ | ~60 KB |

### lodash — direct subpath imports

```ts
// Bad — Metro loads all ~200 lodash modules
import { debounce, pick } from 'lodash';

// Good — loads only the debounce module (~2 KB)
import debounce from 'lodash/debounce';
import pick from 'lodash/pick';

// Best — lodash-es with a tree-shaking-capable bundler
import { debounce, pick } from 'lodash-es';
```

### moment.js → dayjs

```ts
// Bad — 232 KB, all locales bundled
import moment from 'moment';
const formatted = moment(date).format('YYYY-MM-DD');

// Good — 2 KB
import dayjs from 'dayjs';
const formatted = dayjs(date).format('YYYY-MM-DD');

// dayjs locales are separate plugins — opt-in only
import 'dayjs/locale/ko';
dayjs.locale('ko');
```

### Firebase modular API

```ts
// Bad — compat API, tree shaking impossible (~150 KB+)
import firebase from 'firebase/compat/app';
import 'firebase/compat/auth';

// Good — modular v9+, each import is a discrete chunk
import { initializeApp } from 'firebase/app';
import { getAuth, signInWithEmailAndPassword } from 'firebase/auth';
```

### axios → native fetch

```ts
// Bad — adds ~13 KB
import axios from 'axios';
const data = await axios.get('/api/users').then(r => r.data);

// Good — zero KB, built into Hermes
const data = await fetch('/api/users').then(r => r.json());

// If you need interceptors: ky (~4 KB) or wretch (~3 KB)
import ky from 'ky';
const data = await ky.get('/api/users').json();
```

### uuid → crypto.randomUUID()

```ts
// Bad — uuid ships crypto polyfills for every environment (~12 KB)
import { v4 as uuidv4 } from 'uuid';
const id = uuidv4();

// Good — native, supported in Hermes (RN 0.73+)
const id = crypto.randomUUID();
```

### date-fns subpath imports

```ts
// Bad — barrel + CJS pulls everything (~75 KB)
const { format, addDays } = require('date-fns');

// Good — ESM subpath entrypoints (date-fns v3+)
import { format } from 'date-fns/format';
import { addDays } from 'date-fns/addDays';
```

---

## 3. The Barrel File Anti-Pattern

A barrel file re-exports everything from a directory so consumers can use a single import path. When Metro resolves this barrel, it loads and evaluates every file listed — even if the consumer only uses one export.

```ts
// src/components/index.ts — barrel file
export { Button } from './Button';
export { Modal } from './Modal';
export { Avatar } from './Avatar';
export { DatePicker } from './DatePicker'; // pulls in date-picker library
export { Chart } from './Chart';           // pulls in charting library
// ... 40 more exports

// Consuming file — only uses Button, but gets all 42 modules
import { Button } from '@/components';
```

Fix: import directly from source files.

```ts
// Good — loads only Button
import { Button } from '@/components/Button';
```

Enforce direct imports via ESLint to prevent regression:

```js
// eslint.config.js
export default [
  {
    rules: {
      'no-restricted-imports': ['error', {
        patterns: [{
          group: ['@/components', '@/components/index'],
          message: 'Import directly from the component file, not the barrel.',
        }],
      }],
    },
  },
];
```

Expo's experimental tree shaking (SDK 52+) resolves `export *` barrel patterns automatically and is the only Metro-based solution that handles this without requiring import changes across the codebase.

---

## 4. Bundle Analysis Tools

### react-native-bundle-visualizer

Generates an interactive treemap from your production bundle.

```bash
npx react-native-bundle-visualizer
# Generates report.html — open in browser
```

### Expo Atlas (SDK 51+)

Atlas reports module sizes after Metro's transform step, before minification, so sizes reflect what Metro actually included. It also shows the full "imported by" chain — trace exactly why a module ended up in the bundle.

```bash
EXPO_ATLAS=1 npx expo export --platform android
# Opens Atlas UI at localhost:8081/atlas
```

In development:

```bash
EXPO_UNSTABLE_ATLAS=true npx expo start
# http://localhost:8081/_expo/atlas
```

### source-map-explorer

Works with any React Native project that produces a source map.

```bash
npx react-native bundle \
  --platform android \
  --dev false \
  --entry-file index.js \
  --bundle-output /tmp/bundle.js \
  --sourcemap-output /tmp/bundle.js.map

npx source-map-explorer /tmp/bundle.js /tmp/bundle.js.map
```

### Reading the treemap

Focus on three signals:

1. **Large unexpected boxes** — a library that should be tiny (e.g., `uuid`) taking 12 KB signals a polyfill problem.
2. **Duplicate module names** — two versions of `react` or `@babel/runtime` indicate hoisting failures in your monorepo. Run `yarn why <package>` to find the conflict.
3. **`node_modules` dominance** — if `node_modules` is more than 60% of your bundle, audit your top-10 dependencies first. Seeing `lodash/_baseEach` when you only use `debounce` means you have a CommonJS import that needs switching to a subpath.

---

## 5. Metro Bundler Optimizations

### inlineRequires

By default Metro evaluates every `require()` at startup. `inlineRequires` moves `require()` calls to the point of first use, deferring module evaluation until the module is actually needed. This does not reduce bundle size on disk, but it dramatically reduces startup evaluation time. Facebook reported a 42% TTI reduction with Hermes after enabling this.

```js
// metro.config.js
const { getDefaultConfig } = require('@react-native/metro-config');

const config = getDefaultConfig(__dirname);

config.transformer.inlineRequires = true;

module.exports = config;
```

### Hermes bytecode

Hermes pre-compiles JS to bytecode at build time, eliminating the parse step at runtime. The bytecode bundle is approximately 33% smaller than minified JS on disk and loads significantly faster on low-end Android hardware. Enabled by default in RN 0.70+.

Verify in `android/app/build.gradle`:

```groovy
project.ext.react = [
  enableHermes: true,
]
```

And in `ios/Podfile`:

```ruby
use_react_native!(
  :hermes_enabled => true
)
```

### babel-plugin-transform-remove-console

```bash
npm install --save-dev babel-plugin-transform-remove-console
```

```js
// babel.config.js
module.exports = {
  presets: ['module:@react-native/babel-preset'],
  env: {
    production: {
      plugins: ['transform-remove-console'],
    },
  },
};
```

Saves 5–15 KB depending on logging density. More importantly, prevents sensitive data from being logged in production.

### `__DEV__` dead code elimination

Metro injects `__DEV__ = false` in production builds. The minifier then eliminates dead branches. Use this for development-only utilities:

```ts
if (__DEV__) {
  // Entire block removed in production bundle
  const Reactotron = require('./ReactotronConfig');
  Reactotron.connect();
}
```

The pattern works for any constant-folded boolean: `process.env.NODE_ENV === 'development'` is also folded.

### Platform-specific files

Metro resolves platform-specific extensions before generic ones. Split large platform-divergent modules to avoid shipping iOS code to Android:

```
ImagePicker.ios.ts      // iOS-only
ImagePicker.android.ts  // Android-only
ImagePicker.ts          // Fallback type declarations only
```

Metro resolves `import ImagePicker from './ImagePicker'` to the correct platform file automatically. With a 50/50 user split, this effectively halves the bundle size contribution for that feature.

### metro-minify-esbuild

Replaces Metro's default Terser minifier with esbuild. Produces equivalent output size but 10–20x faster minification, which matters significantly in CI pipelines.

```bash
npm install --save-dev metro-minify-esbuild
```

```js
// metro.config.js
const { getDefaultConfig } = require('@react-native/metro-config');

const config = getDefaultConfig(__dirname);

config.transformer.minifierPath = 'metro-minify-esbuild';
config.transformer.minifierConfig = {
  target: 'es2019',
};

module.exports = config;
```

---

## 6. Advanced Bundle Optimization

### Re.Pack with Module Federation 2

Re.Pack enables true micro-frontend architecture in React Native via Module Federation 2. Shell apps load feature modules on demand from remote URLs, keeping the initial bundle minimal.

```bash
npm install --save-dev @callstack/repack
```

```ts
// Shell app — dynamically loads a feature
const ProfileFeature = React.lazy(() =>
  import('ProfileApp/ProfileScreen')
);

function App() {
  return (
    <Suspense fallback={<LoadingSpinner />}>
      <ProfileFeature />
    </Suspense>
  );
}
```

```js
// webpack.config.mjs for the ProfileApp remote
import { ModuleFederationPlugin } from '@module-federation/enhanced/webpack';

export default {
  plugins: [
    new ModuleFederationPlugin({
      name: 'ProfileApp',
      filename: 'ProfileApp.container.js',
      exposes: {
        './ProfileScreen': './src/ProfileScreen',
      },
      shared: { react: { singleton: true }, 'react-native': { singleton: true } },
    }),
  ],
};
```

Use for: super-app architecture, apps over 5 MB bundle size, or teams where features ship independently.

### Android App Bundles

Publishing an `.aab` instead of a flat `.apk` lets Google Play deliver only the ABIs and screen densities the user's device requires. Average download size reduction: 30%.

```groovy
// android/app/build.gradle
android {
  bundle {
    language { enableSplit = true }
    density { enableSplit = true }
    abi { enableSplit = true }
  }
}
```

Build the bundle:

```bash
cd android && ./gradlew bundleRelease
```

### ProGuard / R8

R8 shrinks and obfuscates native Java/Kotlin code (not the JS bundle). Typical reduction: 10–20% of native code size, critical for apps with large native dependencies (Firebase, Google Maps, ML Kit).

```groovy
// android/app/build.gradle
android {
  buildTypes {
    release {
      minifyEnabled true
      shrinkResources true
      proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
    }
  }
}
```

```
# proguard-rules.pro — prevent R8 from removing reflection-accessed code
-keep class com.facebook.react.** { *; }
-keep class com.swmansion.reanimated.** { *; }
```

### iOS App Thinning

Xcode App Thinning delivers only the assets and binary slices needed by each device configuration. Use asset catalogs for images — resources in asset catalogs are automatically thinned by density. Typical download size reduction: 20–40%.

Enable during distribution: Product → Archive → Distribute App → "Enable App Thinning".

### Font subsetting

Shipping full font files is the most common overlooked size source. A font with Latin + CJK glyphs can be 2–8 MB. Subset to the Unicode ranges your app actually uses for a 50–80% reduction.

```bash
pip install fonttools

pyftsubset Inter-Regular.ttf \
  --unicodes="U+0020-007E,U+00A0-00FF" \
  --output-file=Inter-Regular-subset.ttf \
  --flavor=woff2
# Full font: 350 KB → Latin subset: ~70 KB
```

### Asset optimization

Convert PNGs to WebP at build time. WebP is 25–34% smaller than PNG for photos and 26% smaller for graphics with transparency. Metro resolves `.webp` automatically on both platforms in RN 0.65+.

```bash
# Batch convert in CI
find ./src/assets -name "*.png" -exec cwebp -q 90 {} -o {}.webp \;
```

Run SVGO on SVG icons before committing. For `react-native-svg`, the SVG is compiled to JS at build time — smaller SVG equals less JS.

```bash
npx svgo --multipass --folder ./src/assets/icons
```

### RAM bundles (deprecated with Hermes)

RAM bundles store each module as a separate indexed section, loading only needed sections at runtime. Hermes with `inlineRequires` achieves the same result and is the preferred approach. RAM bundles remain available for non-Hermes environments.

```bash
react-native bundle \
  --platform android \
  --indexed-ram-bundle \
  --dev false \
  --entry-file index.js \
  --bundle-output android/app/src/main/assets/index.android.bundle
```

---

## 7. CI/CD Bundle Size Monitoring

### GitHub Actions workflow

```yaml
# .github/workflows/bundle-size.yml
name: Bundle Size

on:
  pull_request:
    branches: [main]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm

      - run: npm ci

      - name: Build production bundle
        run: |
          npx react-native bundle \
            --platform android \
            --dev false \
            --entry-file index.js \
            --bundle-output /tmp/bundle.js \
            --sourcemap-output /tmp/bundle.js.map

      - name: Measure and report size
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const bytes = fs.statSync('/tmp/bundle.js').size;
            const kb = (bytes / 1024).toFixed(1);
            const budget = 3 * 1024 * 1024; // 3 MB
            const status = bytes > budget ? 'OVER BUDGET' : 'OK';
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `**Android bundle size:** ${kb} KB — ${status}`,
            });
            if (bytes > budget) core.setFailed(`Bundle size ${bytes} exceeds 3 MB budget`);

      - name: Upload bundle report
        uses: actions/upload-artifact@v4
        with:
          name: bundle-report
          path: /tmp/bundle.js.map
          retention-days: 30
```

### size-limit configuration

`size-limit` integrates with CI to enforce budgets and block PRs that exceed them.

```bash
npm install --save-dev size-limit @size-limit/file
```

```js
// .size-limit.js
module.exports = [
  {
    name: 'Android JS bundle (gzip)',
    path: '/tmp/bundle.js',
    gzip: true,
    limit: '1.5 MB',
  },
  {
    name: 'iOS JS bundle (gzip)',
    path: '/tmp/bundle.ios.js',
    gzip: true,
    limit: '1.5 MB',
  },
];
```

```yaml
# package.json script
"scripts": {
  "size": "size-limit",
  "size:ci": "size-limit --json > /tmp/size-limit-result.json"
}
```

### Tracking size over time

Store bundle sizes as CI artifacts or push them to a time-series store. Gradual growth from dependency updates is the most common cause of unexplained slow startup regressions in mature apps.

```bash
node -e "
const fs = require('fs');
const bytes = fs.statSync('/tmp/bundle.js').size;
const record = {
  sha: process.env.GITHUB_SHA,
  date: new Date().toISOString(),
  platform: 'android',
  bytes,
};
fs.writeFileSync('/tmp/bundle-record.json', JSON.stringify(record));
"
```

### Target bundle sizes

| App type | JS bundle (gzip) | Android download | iOS download |
|---|---|---|---|
| Small utility app | < 500 KB | < 15 MB | < 20 MB |
| Medium product app | < 1.5 MB | < 40 MB | < 60 MB |
| Large feature-rich app | < 3 MB | < 100 MB | < 150 MB |
| Super-app (with code splitting) | < 500 KB initial | varies | varies |

---

## 8. react-native-reanimated Tree Shaking Issues

Reanimated is one of the heaviest animation libraries in the React Native ecosystem. Its worklet architecture — which serializes JS functions and runs them on the UI thread — actively resists tree shaking because the worklet compiler must include every function body that could be called from any worklet closure.

### Reanimated 2 vs 3 bundle size differences

| Metric | Reanimated 2 | Reanimated 3 |
|---|---|---|
| JS core (minified) | ~120 KB | ~95 KB |
| Worklet runtime overhead | Separate thread bootstrap | Shared Hermes runtime |
| Unused animation helpers included | Yes (all exported) | Reduced (improved DCE) |
| `useAnimatedStyle` pull-in | Entire `interpolate` graph | Same, slightly smaller |
| Typical total JS contribution | ~130–150 KB | ~100–120 KB |

Reanimated 3 improves the situation through a redesigned worklet runtime that shares the Hermes engine rather than bootstrapping a separate thread, but the fundamental tree shaking problem with worklets persists in both versions.

### Why worklets break tree shaking

The Reanimated Babel plugin transforms functions decorated with `'worklet'` into serializable objects that can be transferred to the UI thread. This transformation happens at the Babel level — before Metro resolves the module graph — so any function referenced inside a worklet becomes a hard dependency even if it appears unused from the call site.

```ts
// This looks like it only imports useAnimatedStyle and withTiming
import { useAnimatedStyle, withTiming, interpolate, Extrapolation } from 'react-native-reanimated';

function MyComponent({ progress }: { progress: SharedValue<number> }) {
  // The Babel worklet plugin serializes this entire closure.
  // Even though `interpolate` and `Extrapolation` look tree-shakeable,
  // the worklet compiler sees them referenced inside the closure and
  // pulls in the full interpolation module.
  const style = useAnimatedStyle(() => {
    'worklet';
    return {
      opacity: interpolate(progress.value, [0, 1], [0, 1], Extrapolation.CLAMP),
    };
  });

  return <Animated.View style={style} />;
}
```

The worklet plugin instruments the entire module to find all reachable symbols from each `'worklet'` function. The result is that any module that uses a `useAnimatedStyle`, `useAnimatedReaction`, `useDerivedValue`, or raw `runOnUI` call effectively imports a large portion of the Reanimated runtime.

### `useAnimatedStyle` causing full module inclusion

`useAnimatedStyle` is the single biggest Reanimated bundle contributor. It depends on:

- The worklet scheduler
- The shared value system (`makeMutable`)
- The style flattener and diff engine
- The interpolation helpers (pulled in transitively)
- Platform-specific ViewDescriptor infrastructure

Because the worklet Babel plugin cannot know at transform time which helpers a worklet will actually call at runtime, it includes conservative dependencies. Avoid `useAnimatedStyle` for simple transforms that can be expressed with a single `SharedValue` driving a static style.

```ts
// High cost — pulls in full useAnimatedStyle machinery (~40 KB)
const style = useAnimatedStyle(() => ({ opacity: opacity.value }));

// Lower cost — useAnimatedStyle with no interpolation still carries overhead,
// but you avoid pulling in the interpolation graph
// Consider Animated.Value for simple opacity/transform if Reanimated is marginal
import { Animated } from 'react-native'; // ~5 KB marginal cost on RN core
const opacity = useRef(new Animated.Value(0)).current;
```

### Workarounds for selective Reanimated imports

**Workaround 1 — Lazy-load Reanimated screens**

Keep Reanimated out of your initial bundle entirely by colocating animated components with the screens that use them and loading those screens lazily.

```ts
// navigation/AppNavigator.tsx
const AnimatedGallery = React.lazy(() => import('../screens/AnimatedGallery'));
// Reanimated is only evaluated when the user navigates to AnimatedGallery
```

**Workaround 2 — Audit with `REANIMATED_PROFILE=1`**

Reanimated 3 exposes a profiling flag that logs every worklet registration with its serialized size. Use this to find closures capturing large scopes.

```bash
REANIMATED_PROFILE=1 npx react-native bundle --platform android --dev false \
  --entry-file index.js --bundle-output /tmp/bundle.js 2>&1 | grep '\[Reanimated\]'
```

**Workaround 3 — Isolate worklet utilities**

Keep worklet utility functions in files that import nothing from user-space to prevent the Babel plugin from following import chains into application code.

```ts
// utils/worklets.ts — keep this file free of non-Reanimated imports
import { interpolate, Extrapolation } from 'react-native-reanimated';

export function clampedInterpolate(value: number, inputRange: number[], outputRange: number[]) {
  'worklet';
  return interpolate(value, inputRange, outputRange, Extrapolation.CLAMP);
}
```

**Workaround 4 — `memoize` expensive derived values**

`useDerivedValue` re-runs on every shared value change and keeps the derivation worklet alive. If the derived value only changes infrequently, compute it on the JS thread and pass it via `runOnUI` to avoid registering a persistent worklet.

```ts
// Instead of a persistent useDerivedValue worklet (always registered),
// push a one-shot update when the JS-side value changes
const sharedColor = useSharedValue('#fff');

useEffect(() => {
  runOnUI((color: string) => {
    'worklet';
    sharedColor.value = color;
  })(computedColor);
}, [computedColor]);
```

---

## 9. OTA Update Size Optimization

Over-the-air updates bypass app store review but still consume user bandwidth. A 3 MB JS bundle pushed via OTA on a cellular connection costs users real data and increases abandonment before the update completes. The strategies below apply regardless of OTA provider (Expo Updates or CodePush).

### Expo Updates delta/incremental strategy

Expo Updates supports delta updates starting with `expo-updates` 0.18+. Instead of shipping the full bundle on each release, the Expo Updates server diffs the old and new bundle and ships only changed segments. This requires a compatible hosting configuration (EAS Update or a self-hosted updates server with delta support enabled).

```json
// eas.json — configure EAS Update channels
{
  "build": {
    "production": {
      "channel": "production"
    },
    "staging": {
      "channel": "staging"
    }
  }
}
```

```bash
# Push an update; EAS Update automatically computes and serves the delta
eas update --channel production --message "Fix checkout bug"

# Inspect the resulting bundle size on the EAS dashboard
eas update:list --channel production
```

To measure the actual delta size served to a device, check the `expo-updates` native log output:

```
[EAS Update] Downloaded update manifest (1.2 KB)
[EAS Update] Downloading patch: 87.4 KB (full bundle: 2.8 MB)
```

The delta is computed per-asset and per-module-chunk. Keeping modules small and stable reduces the number of chunks that change on each release, shrinking the delta.

### CodePush bundle splitting

AppCenter CodePush ships full bundles by default. Reduce OTA payload by separating the bundle into a base bundle (stable dependencies) and a diff bundle (frequently changing application code).

```bash
# Build the base bundle (stable: node_modules, shared libraries)
npx react-native bundle \
  --platform android \
  --dev false \
  --entry-file base.index.js \
  --bundle-output /tmp/base.android.bundle \
  --assets-dest /tmp/base-assets

# Build the diff bundle (application code only)
npx react-native bundle \
  --platform android \
  --dev false \
  --entry-file app.index.js \
  --bundle-output /tmp/app.android.bundle \
  --assets-dest /tmp/app-assets

# Push only the app bundle via CodePush — 60-70% smaller OTA payload
appcenter codepush release-react -a MyOrg/MyApp-Android \
  --bundle-path /tmp/app.android.bundle
```

The trade-off: the base bundle must be shipped in the native binary, increasing initial install size slightly. The OTA payload for subsequent releases drops to the application-code bundle only.

### Managing OTA budgets over cellular

Set a maximum OTA bundle size and block releases that exceed it in CI.

```bash
#!/usr/bin/env bash
# scripts/check-ota-budget.sh
MAX_BYTES=512000  # 500 KB OTA budget

BUNDLE_SIZE=$(wc -c < /tmp/bundle.js | tr -d ' ')
GZIP_SIZE=$(gzip -c /tmp/bundle.js | wc -c | tr -d ' ')

echo "Raw bundle: $(( BUNDLE_SIZE / 1024 )) KB"
echo "Gzip bundle: $(( GZIP_SIZE / 1024 )) KB"

if [ "$GZIP_SIZE" -gt "$MAX_BYTES" ]; then
  echo "ERROR: OTA bundle exceeds $((MAX_BYTES / 1024)) KB gzip budget"
  exit 1
fi

echo "OTA budget OK"
```

Additionally, configure Expo Updates to respect the network condition before applying:

```ts
// app/(app)/_layout.tsx
import * as Updates from 'expo-updates';
import NetInfo from '@react-native-community/netinfo';

async function checkAndApplyUpdate() {
  const netInfo = await NetInfo.fetch();

  // Skip OTA update on cellular if bundle exceeds 200 KB
  if (!netInfo.isConnected) return;

  const update = await Updates.checkForUpdateAsync();
  if (!update.isAvailable) return;

  // Only apply large updates on WiFi
  const isWifi = netInfo.type === 'wifi';
  const isCritical = update.manifest?.extra?.isCriticalUpdate === true;

  if (!isWifi && !isCritical) {
    console.log('[Updates] Deferring non-critical OTA on cellular');
    return;
  }

  await Updates.fetchUpdateAsync();
  await Updates.reloadAsync();
}
```

### Measuring OTA download size separately

The JS bundle gzip size approximates OTA download cost, but assets bundled alongside the JS (images, fonts) are shipped separately and may not be included in OTA updates at all. Measure each component:

```bash
# JS bundle (gzip) — primary OTA cost
gzip -c /tmp/bundle.js | wc -c

# Asset manifest — lists all hashed assets in the update
# With Expo Updates: inspect the manifest JSON returned by the update server
curl https://updates.example.com/api/manifest \
  -H "expo-platform: android" \
  -H "expo-channel-name: production" | jq '.assets[] | {key, size}'

# Delta size — only available from EAS Update dashboard or CDN logs
eas update:view <update-id>
```

### Manifest-driven selective updates

A manifest-driven approach lets the app decide which modules to download based on user behavior and device state. This is most practical with Re.Pack + Module Federation.

```ts
// src/services/selective-update.ts
import * as Updates from 'expo-updates';

interface UpdateManifest {
  version: string;
  modules: {
    name: string;
    url: string;
    sizeBytes: number;
    priority: 'critical' | 'high' | 'low';
  }[];
}

async function applySelectiveUpdate(manifest: UpdateManifest): Promise<void> {
  const netInfo = await NetInfo.fetch();
  const isWifi = netInfo.type === 'wifi';

  // Always apply critical modules regardless of network
  const toDownload = manifest.modules.filter(
    (mod) => mod.priority === 'critical' || isWifi,
  );

  const totalBytes = toDownload.reduce((sum, mod) => sum + mod.sizeBytes, 0);
  console.log(`[SelectiveUpdate] Downloading ${toDownload.length} modules (${(totalBytes / 1024).toFixed(1)} KB)`);

  for (const mod of toDownload) {
    await downloadAndCacheModule(mod.url, mod.name);
  }
}

async function downloadAndCacheModule(url: string, name: string): Promise<void> {
  // Implementation depends on Module Federation dynamic imports
  // Cache the downloaded chunk in the filesystem before registering it
  const RNFS = await import('react-native-fs');
  const dest = `${RNFS.DocumentDirectoryPath}/mf-chunks/${name}.js`;
  await RNFS.downloadFile({ fromUrl: url, toFile: dest }).promise;
}
```

---

## 10. Native Code Size Analysis

The JS bundle is only one dimension of total app size. Native code — `.so` libraries on Android, frameworks on iOS — frequently accounts for 50–80% of the total download size. Reductions here directly impact install conversion rates, particularly in markets with limited storage devices.

### Android .so library stripping and ABI splits

React Native ships prebuilt `.so` files for four ABIs: `armeabi-v7a`, `arm64-v8a`, `x86`, and `x86_64`. In a flat APK, all four are included. An `.aab` with ABI splits delivers only the ABI the device uses.

```groovy
// android/app/build.gradle — enable ABI splits for flat APKs
android {
  splits {
    abi {
      enable true
      reset()
      include 'arm64-v8a', 'armeabi-v7a'  // drop x86/x86_64 for production
      universalApk false  // don't also generate the fat APK
    }
  }

  // Strip debug symbols from .so files in release builds
  buildTypes {
    release {
      ndk {
        debugSymbolLevel 'SYMBOL_TABLE'  // keep minimal for crash symbolication
      }
    }
  }
}
```

Stripping debug symbols from `.so` files alone reduces the `.so` payload by 40–60%. The stripped symbols can be uploaded separately to Google Play for crash symbolication without affecting user download size.

```bash
# Measure .so sizes before and after stripping
find android/app/build/intermediates/stripped_native_libs -name "*.so" \
  -exec du -sh {} \; | sort -h

# Compare with unstripped
find android/app/build/intermediates/merged_native_libs -name "*.so" \
  -exec du -sh {} \; | sort -h
```

### iOS framework binary size tools

Use `otool` and `nm` to inspect iOS framework contents, and `bloaty` for a detailed size breakdown.

```bash
# List symbols in a framework binary (find large symbol tables)
nm -size-sort Pods/RNReanimated/RNReanimated.xcframework/ios-arm64/RNReanimated.framework/RNReanimated \
  | tail -30

# Segment breakdown with otool
otool -l Pods/RNReanimated/RNReanimated.xcframework/ios-arm64/RNReanimated.framework/RNReanimated \
  | grep -A4 'segname\|size'

# Detailed breakdown with bloaty (install: brew install bloaty)
bloaty Pods/RNReanimated/RNReanimated.xcframework/ios-arm64/RNReanimated.framework/RNReanimated \
  --domain=vm -d segments,sections
```

Xcode's Link Map also provides a complete breakdown of what the linker included and from which library.

```bash
# Enable link map generation in Xcode (or xcconfig)
# Build Settings → Write Link Map File → YES
# Link Map File Path → $(TARGET_TEMP_DIR)/$(PRODUCT_NAME)-LinkMap-$(CURRENT_VARIANT)-$(CURRENT_ARCH).txt

# Parse the link map to find the top 20 largest object files
awk '/^#.*Object files/,/^#.*Sections/' \
  ~/Library/Developer/Xcode/DerivedData/*/Build/Intermediates.noindex/*.build/Release-iphoneos/*.build/*-LinkMap-normal-arm64.txt \
  | sort -t$'\t' -k2 -rn | head -20
```

### ProGuard/R8 advanced rules for React Native

Beyond the basic rules shown in section 6, R8 in full-mode (the default for AGP 7+) applies global optimizations. Some RN libraries break under full-mode R8 without custom keep rules.

```
# proguard-rules.pro

# React Native core — always keep
-keep class com.facebook.react.** { *; }
-keep class com.facebook.hermes.** { *; }
-keep class com.facebook.jni.** { *; }

# Reanimated — worklets use reflection
-keep class com.swmansion.reanimated.** { *; }
-keepclassmembers class * {
  @com.facebook.react.bridge.ReactMethod *;
}

# Remove unused R8 warnings from libraries that ship their own rules
-dontwarn org.bouncycastle.**
-dontwarn com.google.errorprone.**

# R8 full-mode: inline methods aggressively (save 5-10% native code size)
-optimizationpasses 5
-allowaccessmodification
-mergeinterfacesaggressively

# Rewrite enum classes to ints (significant saving in Firebase-heavy apps)
-optimizations !code/simplification/cast,field/*,class/merging/*
```

Enable R8 full mode explicitly:

```groovy
// gradle.properties
android.enableR8.fullMode=true
```

Verify R8 is active (not ProGuard fallback):

```bash
./gradlew assembleRelease --info 2>&1 | grep -i "r8\|proguard"
# Should show: "Running R8" not "Running ProGuard"
```

### Unused native framework detection

React Native links every pod/dependency unconditionally, including frameworks that are only needed for specific features. Detect unused native modules at runtime:

```ts
// src/debug/unused-native-modules.ts — dev only
if (__DEV__) {
  const { NativeModules } = require('react-native');
  const availableModules = Object.keys(NativeModules);
  const usedModules = new Set<string>();

  // Wrap NativeModules to track access
  const originalAccess = Object.getOwnPropertyDescriptors(NativeModules);
  availableModules.forEach((name) => {
    Object.defineProperty(NativeModules, name, {
      get() {
        usedModules.add(name);
        return originalAccess[name]?.value;
      },
      configurable: true,
    });
  });

  // Log unused modules after 10s of app usage
  setTimeout(() => {
    const unused = availableModules.filter((m) => !usedModules.has(m));
    console.log('[NativeModules] Potentially unused:', unused);
  }, 10_000);
}
```

On iOS, also audit with `otool -L` on the final binary to see which frameworks are dynamically linked:

```bash
otool -L MyApp.app/MyApp | grep -v Apple | grep -v swift
# Each line is a linked framework — confirm each is actively used
```

### AAB vs APK size differences

| Metric | Universal APK | APK with ABI splits | Android App Bundle (.aab) |
|---|---|---|---|
| Download size (arm64 device) | Full | arm64 only | arm64 only |
| Install size | Full | arm64 only | arm64 only |
| Assets delivered | All densities | All densities | Device density only |
| Language resources | All locales | All locales | Device locale only |
| Typical size vs universal APK | baseline | −30–40% | −40–60% |
| Required for Play Store since | — | — | Aug 2021 |
| Supports local testing | Yes | Yes | Via `bundletool` only |

```bash
# Test AAB locally with bundletool
java -jar bundletool.jar build-apks \
  --bundle=android/app/build/outputs/bundle/release/app-release.aab \
  --output=/tmp/app.apks \
  --ks=my-release-key.jks \
  --ks-key-alias=my-key-alias

# Measure size for a specific device config
java -jar bundletool.jar get-size total \
  --apks=/tmp/app.apks \
  --device-spec=pixel7-spec.json
```

---

## 11. Third-Party SDK Impact Analysis

Large third-party SDKs are the most common source of unexplained app size bloat. Unlike your own code, SDK size is easy to overlook during code review and compounds with every new integration.

### Common SDK sizes

| SDK | JS size (min+gzip) | Native iOS (arm64) | Native Android (arm64 .so) | Notes |
|---|---|---|---|---|
| Firebase App (modular) | ~12 KB | — | — | Core only; each product adds more |
| Firebase Auth | +18 KB JS | ~4 MB | ~3.2 MB | Native SDK included |
| Firebase Firestore | +45 KB JS | ~8 MB | ~6.5 MB | Largest Firebase product |
| Firebase Analytics | +8 KB JS | ~2 MB | ~1.8 MB | Initialized eagerly by default |
| Google Maps RN | ~30 KB JS | ~12 MB | ~9 MB | Largest common SDK |
| Sentry RN | ~85 KB JS | ~3 MB | ~2.5 MB | JS SDK + native crash reporter |
| Amplitude Analytics | ~40 KB JS | ~1 MB | ~0.8 MB | |
| Facebook Login | ~15 KB JS | ~4 MB | ~3.5 MB | Includes full FB SDK |
| Google Sign-In | ~8 KB JS | ~2 MB | ~1.5 MB | Smaller than FB |
| react-native-maps | ~30 KB JS | ~12 MB (Apple Maps) | ~9 MB (Google Maps) | |
| Stripe RN | ~25 KB JS | ~6 MB | ~5 MB | PCI-compliant native layer |
| Lottie RN | ~5 KB JS | ~1.5 MB | ~1.2 MB | |

Native SDK sizes are for the arm64 slice only. The full download size impact of an .aab includes only the device's ABI, so these numbers represent the real-world cost for most users.

### Firebase modular API impact measurement

The Firebase modular API (v9+) is tree-shakeable at the JS level but the native SDK is always included in full when a product is linked. Measure the exact JS contribution of each Firebase module:

```bash
# Build with only firebase/app, measure baseline
npx react-native bundle --platform android --dev false \
  --entry-file index.js --bundle-output /tmp/bundle-firebase-base.js

# Add firebase/firestore to the app, rebuild, compare
npx react-native bundle --platform android --dev false \
  --entry-file index.js --bundle-output /tmp/bundle-firebase-firestore.js

node -e "
const fs = require('fs');
const base = fs.statSync('/tmp/bundle-firebase-base.js').size;
const full = fs.statSync('/tmp/bundle-firebase-firestore.js').size;
console.log('Firestore JS addition:', ((full - base) / 1024).toFixed(1), 'KB');
"
```

Use the modular API consistently — mixing compat and modular imports causes both to be included:

```ts
// Bad — imports both the compat shim and part of the modular SDK
import firebase from 'firebase/compat/app';
import { getFirestore } from 'firebase/firestore';

// Good — modular only
import { initializeApp } from 'firebase/app';
import { getFirestore, collection, getDocs } from 'firebase/firestore';
```

### Analytics SDK selective loading

Analytics SDKs are frequently initialized eagerly at app startup, even for users who have not consented to tracking. Defer initialization until after consent is obtained:

```ts
// src/services/analytics.ts
let analyticsInstance: ReturnType<typeof import('@amplitude/analytics-react-native').init> | null = null;

export async function initAnalyticsAfterConsent(): Promise<void> {
  const { hasGivenConsent } = await ConsentService.getStatus();
  if (!hasGivenConsent) return;

  // Dynamic import ensures Amplitude JS is not evaluated until needed
  const Amplitude = await import('@amplitude/analytics-react-native');
  analyticsInstance = Amplitude.init('API_KEY', undefined, {
    trackingSessionEvents: false,
    // Disable automatic session tracking to reduce event volume
  });
}

export function track(event: string, properties?: Record<string, unknown>): void {
  if (!analyticsInstance) return; // silently drop pre-consent events
  import('@amplitude/analytics-react-native').then(({ track }) => track(event, properties));
}
```

For Google Analytics via Firebase, use `setAnalyticsCollectionEnabled(false)` at startup and enable only after consent:

```ts
import { getAnalytics, setAnalyticsCollectionEnabled } from 'firebase/analytics';

// Startup — disable immediately
const analytics = getAnalytics(firebaseApp);
setAnalyticsCollectionEnabled(analytics, false);

// After user consents
async function onConsentGranted() {
  setAnalyticsCollectionEnabled(analytics, true);
}
```

### Social login SDKs conditional initialization

Social login SDKs (Facebook, Google) initialize their native counterparts at app launch via `AppDelegate` / `MainApplication`, consuming memory and adding to launch time even when the user never logs in with that provider.

Defer native SDK initialization on iOS using the `application:didFinishLaunchingWithOptions:` hook:

```objc
// ios/AppDelegate.mm — defer Facebook SDK initialization
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
  // Only initialize Facebook SDK when the user actually taps "Login with Facebook"
  // Remove the default [[FBSDKApplicationDelegate sharedInstance] application:...] call
  // and call it lazily from a native module instead
  return [super application:application didFinishLaunchingWithOptions:options];
}
```

On Android, use `App Startup` to defer:

```kotlin
// android/app/src/main/java/com/myapp/FacebookInitializer.kt
class FacebookInitializer : Initializer<Unit> {
  override fun create(context: Context) {
    // Leave empty — call FacebookSdk.sdkInitialize() explicitly later
  }

  override fun dependencies(): List<Class<out Initializer<*>>> = emptyList()
}
```

```xml
<!-- AndroidManifest.xml — disable automatic Facebook SDK init -->
<provider
  android:name="com.facebook.internal.FacebookInitProvider"
  android:authorities="${applicationId}.FacebookInitProvider"
  android:exported="false"
  tools:node="remove" />
```

---

## 12. Monorepo Bundle Management

In a monorepo, shared packages and workspace hoisting can cause the same module to appear multiple times in the bundle under different paths, or internal libraries to pull in their entire dependency tree on every consumer. Both problems are invisible until you run a bundle analysis.

### Duplicate module detection across workspaces

Metro resolves modules by traversing the filesystem from each import's location. When two packages in the monorepo depend on different versions of the same library, Metro includes both versions.

```bash
# Detect duplicate packages across the monorepo
yarn why react 2>/dev/null | grep -E "^  └─|^  ├─"

# With npm workspaces
npm ls --all 2>/dev/null | grep -E "deduped|UNMET"

# With pnpm — find packages installed more than once
pnpm list --recursive --depth=1 2>/dev/null | sort | uniq -d
```

Deduplicate with yarn:

```bash
# yarn 1.x
npx yarn-deduplicate --strategy fewer
yarn install

# yarn berry (3.x+)
yarn dedupe
```

With pnpm, enforce a single version via `pnpm.overrides`:

```json
// package.json (root)
{
  "pnpm": {
    "overrides": {
      "react": "18.3.1",
      "react-native": "0.76.0",
      "@babel/runtime": "^7.25.0"
    }
  }
}
```

### Shared dependency hoisting

In a Yarn workspaces monorepo, configure Metro to look for modules in the root `node_modules` first. Without this, Metro finds the package-level `node_modules` first and includes the non-hoisted copy.

```js
// apps/mobile/metro.config.js
const { getDefaultConfig } = require('@react-native/metro-config');
const path = require('path');

const workspaceRoot = path.resolve(__dirname, '../..');
const projectRoot = __dirname;

const config = getDefaultConfig(projectRoot);

config.watchFolders = [workspaceRoot];

config.resolver.nodeModulesPaths = [
  path.resolve(projectRoot, 'node_modules'),
  path.resolve(workspaceRoot, 'node_modules'),
];

// Prevent Metro from resolving node_modules inside packages
// that should be hoisted
config.resolver.disableHierarchicalLookup = false;

module.exports = config;
```

### Bundle analysis per workspace

Run bundle analysis from the mobile app's directory with the monorepo `watchFolders` configured so Atlas or source-map-explorer can trace imports back through workspace packages.

```bash
# From the mobile app workspace
cd apps/mobile

# Expo Atlas with monorepo support
EXPO_ATLAS=1 npx expo export --platform android
# Open the Atlas UI and filter by "packages/" to see which workspace
# packages contribute the most to the bundle

# source-map-explorer for a non-Expo project
npx react-native bundle \
  --platform android \
  --dev false \
  --entry-file index.js \
  --bundle-output /tmp/mono-bundle.js \
  --sourcemap-output /tmp/mono-bundle.js.map

npx source-map-explorer /tmp/mono-bundle.js /tmp/mono-bundle.js.map \
  --html /tmp/mono-bundle-report.html

# Open report and look for packages/* paths — these are workspace packages
open /tmp/mono-bundle-report.html
```

### Preventing internal library bloat

Internal workspace packages (`packages/ui`, `packages/utils`, etc.) are particularly prone to bundling their entire dependency tree because they often use barrel files and export everything. Apply the same rules to internal packages as to third-party libraries.

```json
// packages/ui/package.json
{
  "name": "@myapp/ui",
  "sideEffects": false,
  "exports": {
    "./Button": "./src/Button/index.ts",
    "./Modal": "./src/Modal/index.ts",
    "./Avatar": "./src/Avatar/index.ts"
  }
}
```

```ts
// Bad — pulls in the entire @myapp/ui package
import { Button, Avatar } from '@myapp/ui';

// Good — only Button is loaded
import { Button } from '@myapp/ui/Button';
```

Enforce this in the root ESLint config:

```js
// eslint.config.js (root)
export default [
  {
    rules: {
      'no-restricted-imports': ['error', {
        patterns: [
          {
            group: ['@myapp/ui', '@myapp/utils', '@myapp/shared'],
            message: 'Use subpath imports: @myapp/ui/Button, not @myapp/ui',
          },
        ],
      }],
    },
  },
];
```

### Metro config for monorepo optimization

```js
// apps/mobile/metro.config.js — full monorepo-optimized config
const { getDefaultConfig } = require('@react-native/metro-config');
const { makeMetroConfig } = require('@rnx-kit/metro-config');
const path = require('path');

const workspaceRoot = path.resolve(__dirname, '../..');
const projectRoot = __dirname;

const defaultConfig = getDefaultConfig(projectRoot);

module.exports = makeMetroConfig({
  projectRoot,
  watchFolders: [workspaceRoot],

  resolver: {
    // Prioritize hoisted node_modules
    nodeModulesPaths: [
      path.resolve(projectRoot, 'node_modules'),
      path.resolve(workspaceRoot, 'node_modules'),
    ],
    // Deduplicate singleton packages across workspaces
    resolveRequest: (context, moduleName, platform) => {
      const singletons = ['react', 'react-native', 'react-native-reanimated'];
      if (singletons.some((s) => moduleName === s || moduleName.startsWith(`${s}/`))) {
        return context.resolveRequest(
          { ...context, originModulePath: workspaceRoot + '/node_modules' },
          moduleName,
          platform,
        );
      }
      return context.resolveRequest(context, moduleName, platform);
    },
  },

  transformer: {
    inlineRequires: true,
  },
});
```

---

## 13. Image and Asset Format Selection

### WebP vs PNG vs JPEG vs AVIF trade-offs

| Format | Best for | Compression | Alpha | Animation | RN support | Decode speed |
|---|---|---|---|---|---|---|
| PNG | Logos, icons, sharp edges | Lossless | Yes | No | All versions | Fast |
| JPEG | Photos without transparency | Lossy | No | No | All versions | Fast |
| WebP (lossy) | Photos with transparency | 25–34% < PNG | Yes | Yes | RN 0.65+ | Fast |
| WebP (lossless) | Icons with transparency | 26% < PNG | Yes | Yes | RN 0.65+ | Fast |
| AVIF | Photos, next-gen compression | 50% < JPEG | Yes | Yes | Not native in RN | Slow (software) |
| GIF | Simple animations (legacy) | Poor | Partial | Yes | Limited | Fast |
| SVG | Vector icons, illustrations | Smallest for vectors | Yes | Limited | Via react-native-svg | Very fast |

AVIF is not recommended for React Native: it requires software decoding which is significantly slower than hardware-decoded WebP, and there is no native decoder in the Hermes/RN runtime. The compression advantage is real but the decode cost makes it impractical for frequently rendered assets.

### Choosing the right format by asset type

```
Photos (no transparency):     JPEG q=85 → check size → WebP lossy q=85 if smaller
Photos (with transparency):   WebP lossy q=85
UI illustrations (vectors):   SVG (optimized with SVGO)
App icons, logos:             SVG preferred; WebP lossless as fallback
Pixel-art, sharp graphics:    WebP lossless
Animated content:             WebP animated (replaces GIF)
Splash screens:               PNG (required by native splash tooling)
```

Batch conversion script for CI or pre-commit hooks:

```bash
#!/usr/bin/env bash
# scripts/optimize-assets.sh
ASSETS_DIR="./src/assets/images"

# Convert PNGs and JPEGs to WebP
find "$ASSETS_DIR" \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) | while read file; do
  output="${file%.*}.webp"
  if [ ! -f "$output" ]; then
    cwebp -q 85 "$file" -o "$output" -quiet
    original=$(wc -c < "$file")
    converted=$(wc -c < "$output")
    savings=$(( (original - converted) * 100 / original ))
    echo "$file → $output (${savings}% smaller)"
  fi
done
```

### Responsive image strategies for device densities

React Native resolves `@2x` and `@3x` suffixes automatically. Provide all three densities and let Metro deliver the correct one based on `PixelRatio.get()`.

```
assets/
  hero-image.png      ← 1x (baseline, ~100×50)
  hero-image@2x.png   ← 2x (Retina, ~200×100)
  hero-image@3x.png   ← 3x (Super Retina, ~300×150)
```

```ts
// Metro resolves the correct density automatically
<Image source={require('./assets/hero-image.png')} style={{ width: 100, height: 50 }} />
```

Audit which densities your users actually need. If >95% of your user base has high-density screens, you can drop the `@1x` baseline:

```bash
# Check device density distribution from your analytics
# Most modern devices are 2x or 3x — 1x is rare since 2018
# Dropping @1x saves ~25% of image asset size in the bundle
```

For dynamic images loaded from a URL, use `Image.queryCache` and serve responsive images from your CDN:

```ts
import { Image, PixelRatio } from 'react-native';

const density = PixelRatio.get(); // 1, 2, or 3

function getResponsiveImageUrl(baseUrl: string, width: number): string {
  const pixelWidth = Math.round(width * density);
  return `${baseUrl}?w=${pixelWidth}&format=webp&q=85`;
}
```

### SVG optimization with SVGO aggressive options

SVG files compiled by `react-native-svg-transformer` produce JS at bundle time. Smaller SVG = less JS. SVGO with aggressive settings removes every unnecessary attribute, comment, and redundant path data.

```bash
npm install --save-dev svgo
```

```js
// svgo.config.js
module.exports = {
  multipass: true,  // run multiple passes until size stops decreasing
  plugins: [
    { name: 'preset-default', params: {
        overrides: {
          removeViewBox: false,  // keep viewBox for responsive sizing
          cleanupIds: { minify: true },
        },
      },
    },
    'removeDimensions',          // remove width/height, use viewBox only
    'removeStyleElement',        // remove <style> tags (inline styles only)
    'removeScriptElement',       // remove <script> tags
    {
      name: 'removeAttrs',
      params: { attrs: ['data-name', 'data-testid', 'inkscape:.*', 'sodipodi:.*'] },
    },
    {
      name: 'convertPathData',
      params: { floatPrecision: 2 },  // reduce decimal precision
    },
    {
      name: 'cleanupNumericValues',
      params: { floatPrecision: 2 },
    },
    'mergePaths',        // merge adjacent paths with same attributes
    'convertShapeToPath', // convert rect/circle to path (more optimizable)
    'sortAttrs',         // consistent attribute order (better gzip)
  ],
};
```

Run SVGO as a pre-commit hook:

```bash
# .husky/pre-commit
npx svgo --config svgo.config.js --recursive --folder ./src/assets/icons
git add ./src/assets/icons
```

Typical savings: a Figma-exported SVG icon of 8–12 KB reduces to 1–2 KB after SVGO multipass. For a 50-icon library, this saves 300–500 KB of JS in the bundle.

### Font subsetting for bundle reduction

Every font file shipped with the app is loaded into memory on first use and contributes to the bundle size (or the native binary size for embedded fonts). Subset aggressively to include only the Unicode ranges your app renders.

```bash
pip install fonttools brotli

# Identify which characters your app actually uses
# Grep your source for string literals (imprecise but fast)
grep -rh '"[^"]*"\|'"'"'[^'"'"']*'"'"'' src/ --include="*.ts" --include="*.tsx" \
  | tr -cd '[:print:]' | fold -w1 | sort -u > /tmp/used-chars.txt

# Subset the font to Latin + your specific needs
pyftsubset Inter-Regular.ttf \
  --unicodes="U+0020-007E,U+00A0-00FF,U+2000-206F" \
  --layout-features="kern,liga,calt" \
  --output-file=Inter-Regular-subset.ttf

# Verify the result
python3 -c "
from fontTools.ttLib import TTFont
font = TTFont('Inter-Regular-subset.ttf')
cmap = font.getBestCmap()
print(f'Glyphs in subset: {len(cmap)}')
import os
original = os.path.getsize('Inter-Regular.ttf')
subset = os.path.getsize('Inter-Regular-subset.ttf')
print(f'Size reduction: {original//1024} KB → {subset//1024} KB ({(original-subset)*100//original}%)')
"
```

Common Unicode ranges for Latin-script apps:

| Range | Description | Character count |
|---|---|---|
| U+0020–007E | Basic Latin (ASCII printable) | 95 |
| U+00A0–00FF | Latin-1 Supplement (accented chars) | 96 |
| U+2000–206F | General Punctuation (em dash, curly quotes) | 112 |
| U+20A0–20CF | Currency Symbols | 48 |
| U+2200–22FF | Mathematical Operators | 256 |

If your app supports Korean, Japanese, or Chinese, font subsetting becomes even more impactful. A full CJK font is 5–15 MB. Subsetting to only the characters actually rendered in your static UI strings can reduce this to 200–500 KB.

---

## Quick Reference: Highest-ROI Actions

The single highest-ROI action for most apps is replacing `moment.js` with `dayjs` and switching from full `lodash` to direct subpath imports. These two changes alone routinely eliminate 250–300 KB from the parsed bundle with zero functional change.

| Action | Effort | Typical Saving |
|---|---|---|
| `moment` → `dayjs` | Low | ~230 KB |
| `lodash` → subpath imports | Low | ~55–60 KB |
| Enable `inlineRequires` | Low | 200–500 ms TTI |
| `babel-plugin-transform-remove-console` | Low | 5–15 KB |
| Enable Hermes | Low | ~33% parse time |
| Fix barrel file imports | Medium | 10–100 KB (varies) |
| `firebase` compat → modular | Medium | ~70–100 KB |
| `@rnx-kit/metro-serializer-esbuild` | Medium | 0–20% bundle |
| Expo experimental tree shaking | Medium | varies |
| Android App Bundle + ABI splits | Low | 40–60% download |
| Font subsetting | Medium | 50–80% per font |
| SVG → SVGO multipass | Low | 70–85% per icon |
| WebP conversion (photos) | Low | 25–34% per image |
| Reanimated: lazy-load animated screens | Medium | 100–150 KB initial |
| OTA cellular budget enforcement | Low | user retention |
| Strip .so debug symbols | Low | 40–60% native size |
| R8 full mode + advanced rules | Medium | 10–20% native size |
| Monorepo: deduplicate packages | Medium | varies |
| Monorepo: subpath imports for internal libs | Medium | 10–50 KB (varies) |
| Re.Pack + Module Federation | High | 60–80% initial bundle |
