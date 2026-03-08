# Bundle Size & Tree Shaking

## How Tree Shaking Works in React Native

Tree shaking is the process of removing unused exports from the final bundle. It relies on static analysis of ES module `import`/`export` statements.

### Metro Bundler Capabilities

Metro (the default RN bundler) performs **basic dead code elimination** but is significantly weaker than webpack's tree shaking:

| Feature | Metro | Webpack 5 | Re.Pack |
|---|---|---|---|
| Unused export elimination | Partial | Full | Full (via webpack) |
| Cross-module analysis | Limited | Yes | Yes |
| Dynamic import() splitting | No | Yes | Yes |
| sideEffects field support | No | Yes | Yes |

**Metro's limitation**: Metro resolves modules at the file level, not at the export level. Importing a named export from a file still pulls in the entire file's module scope. This means barrel files (`index.ts` that re-exports everything) are particularly harmful — any import from the barrel pulls every module in the barrel.

### ES Modules vs CommonJS

```ts
// ES Modules — statically analyzable, tree-shakeable
import { debounce } from 'lodash-es'; // only debounce enters the bundle

// CommonJS — dynamic, not tree-shakeable
const { debounce } = require('lodash'); // entire lodash enters the bundle
// Metro cannot determine at build time what properties are used
```

**Why it matters**: many older libraries (lodash, moment, some Firebase SDKs) ship CommonJS. Their ESM variants are separate packages.

### sideEffects Field

In `package.json`, `"sideEffects": false` tells bundlers the package has no side effects and unused exports are safe to drop. Metro does not yet honor this field, but Re.Pack (webpack-based) does.

```json
{
  "name": "my-utils",
  "sideEffects": false
}
```

Files with side effects (CSS imports, polyfills, global registrations) should be listed explicitly:

```json
{
  "sideEffects": ["*.css", "./src/polyfills.ts"]
}
```

---

## Common Tree Shaking Failures

### lodash

```ts
// Bad — pulls in entire lodash (~72 KB minified+gzipped)
import { debounce, cloneDeep } from 'lodash';
import _ from 'lodash';

// Good option 1 — per-method packages (~1-2 KB each)
import debounce from 'lodash/debounce';
import cloneDeep from 'lodash/cloneDeep';

// Good option 2 — lodash-es (ESM build, tree-shakeable)
import { debounce, cloneDeep } from 'lodash-es';
```

### moment.js → dayjs

| Library | Minified+Gzipped | Locale support |
|---|---|---|
| moment.js | ~72 KB | All locales bundled |
| date-fns | ~13 KB (tree-shaken) | Per-locale imports |
| dayjs | ~2 KB | Plugin system |
| Temporal API | 0 KB (native) | Platform support varies |

```ts
// Bad — moment.js bundles all locale data
import moment from 'moment';
const formatted = moment(date).format('YYYY-MM-DD');

// Good — dayjs (~2 KB)
import dayjs from 'dayjs';
const formatted = dayjs(date).format('YYYY-MM-DD');

// dayjs with locale (still small, plugins are separate)
import 'dayjs/locale/ko';
dayjs.locale('ko');
```

### Firebase

```ts
// Bad — legacy modular import bundles entire Firebase SDK (~200 KB+)
import firebase from 'firebase/app';
import 'firebase/firestore';

// Good — tree-shakeable modular SDK (v9+)
import { getFirestore, doc, getDoc } from 'firebase/firestore';
import { getAuth, signInWithEmailAndPassword } from 'firebase/auth';
// Only imported functions enter the bundle
```

### Barrel File Anti-Pattern

```ts
// features/ui/index.ts — barrel file (ANTI-PATTERN in Metro)
export { Button } from './button';
export { Input } from './input';
export { Modal } from './modal';
export { DatePicker } from './date-picker'; // pulls in date-picker library
export { Chart } from './chart';            // pulls in charting library

// Consuming file — only uses Button, but gets everything above
import { Button } from '@/features/ui';
// Metro includes Button, Input, Modal, DatePicker, Chart, and all their deps
```

```ts
// Good — direct imports bypass the barrel
import { Button } from '@/features/ui/button';
import { Input } from '@/features/ui/input';
// Only button.tsx and input.tsx enter the bundle
```

**Exception**: barrel files in monorepos where the package boundary is a published npm package work fine, because the package consumer only imports the package's public API.

### Icon Libraries

```ts
// Bad — react-native-vector-icons links ALL font files (~2 MB+ of font data)
import Icon from 'react-native-vector-icons/MaterialIcons';

// Good option 1 — use only the icon sets you need, configure native side
// ios/Podfile: only include MaterialIcons
// android/app/build.gradle: only include MaterialIcons

// Good option 2 — SVG icons (zero unused glyphs)
import SearchIcon from '@/assets/icons/search.svg';
// Only the SVGs you import enter the bundle, no unused font data
```

Size comparison for common icon approaches:
- All vector-icons fonts: ~2.1 MB
- Single font file (MaterialIcons only): ~130 KB
- SVG icons (100 icons): ~80 KB (depends on complexity)
- SVG icons (20 icons): ~15 KB

### axios → native fetch

```ts
// Bad — axios adds 13 KB (minified+gzipped)
import axios from 'axios';
const data = await axios.get('/api/users').then(r => r.data);

// Good — native fetch (0 KB, built into Hermes)
const data = await fetch('/api/users').then(r => r.json());

// If you need interceptors, a thin wrapper around fetch:
// ky (~4 KB) or wretch (~3 KB)
import ky from 'ky';
const data = await ky.get('/api/users').json();
```

### uuid → crypto.randomUUID()

```ts
// Bad — uuid package adds ~5 KB
import { v4 as uuidv4 } from 'uuid';
const id = uuidv4();

// Good — native (Hermes supports crypto.randomUUID() in RN 0.73+)
const id = crypto.randomUUID();

// Polyfill for older RN versions
import 'react-native-get-random-values';
import { v4 as uuidv4 } from 'uuid'; // uuid uses the polyfilled crypto
```

### date-fns

```ts
// Bad — date-fns CommonJS pulls everything
const { format, addDays } = require('date-fns');

// Good — ESM individual imports
import { format } from 'date-fns/format';
import { addDays } from 'date-fns/addDays';
// date-fns v3 exports each function as a separate entrypoint
```

---

## Bundle Analysis

### react-native-bundle-visualizer

```bash
npx react-native-bundle-visualizer
# Generates an interactive treemap at ./report.html
# Shows every module, its size, and which package it belongs to
```

Open `report.html` in a browser. The treemap area = bytes. Look for:
- Unexpectedly large third-party modules
- Duplicate modules (same library at two versions)
- Entire libraries included when only one function is needed

### Expo Atlas

Available in Expo SDK 51+. Enabled automatically in development.

```bash
EXPO_UNSTABLE_ATLAS=true npx expo start
# Open http://localhost:8081/_expo/atlas in browser
```

Atlas shows a per-platform treemap with accurate sizes after Hermes compilation. More accurate than source-map-explorer for Expo projects.

### source-map-explorer

```bash
# Build production bundle with source maps
npx react-native bundle \
  --platform ios \
  --dev false \
  --entry-file index.js \
  --bundle-output /tmp/main.jsbundle \
  --sourcemap-output /tmp/main.map

npx source-map-explorer /tmp/main.jsbundle /tmp/main.map
```

### Reading Treemaps

Interpretation guide:
- **Large rectangles with a library name**: that library is fully included. Check if you can use a lighter alternative or tree-shake it.
- **Many small rectangles with the same prefix**: many small files from the same package — usually fine if the package is actually used.
- **Duplicate rectangles**: two versions of the same library. Run `yarn why <package>` or `npm ls <package>` to find who requires both versions and deduplicate.
- **Unexpected internals**: seeing `lodash/_baseEach` when you only use `debounce` = CommonJS import, switch to per-method imports.

---

## Metro Optimizations

### inlineRequires

`inlineRequires` delays module evaluation until the module is actually called, instead of evaluating all modules at startup.

```ts
// Without inlineRequires — all requires evaluated at startup
const HeavyChart = require('./heavy-chart'); // evaluated even if never rendered

// With inlineRequires — require moves inside the function that uses it
function renderChart() {
  const HeavyChart = require('./heavy-chart'); // evaluated on first call
}
```

Enable in `metro.config.js`:

```js
// metro.config.js
const { getDefaultConfig } = require('@react-native/metro-config');

const config = getDefaultConfig(__dirname);

config.transformer.inlineRequires = true;

module.exports = config;
```

**Impact**: reduces TTI (Time to Interactive) by 200–500ms on large apps. Does not reduce total bundle size, but reduces startup evaluation time.

### Minification

```js
// metro.config.js
config.transformer.minifierConfig = {
  ecma: 8,
  keep_classnames: false,
  keep_fnames: false,
  module: true,
  mangle: {
    keep_classnames: false,
    keep_fnames: false,
  },
  compress: {
    drop_console: true,      // remove console.* in production
    pure_funcs: ['console.log', 'console.info', 'console.debug'],
  },
};
```

### Hermes Bytecode vs JS Bundle

Hermes pre-compiles JS to bytecode at build time:
- Bytecode loads ~30% faster than JS source (no parsing step at runtime)
- Bytecode is larger on disk (~20% larger) but the startup gain is worth it
- Enabled by default in RN 0.70+ on both platforms

```json
// android/app/build.gradle
project.ext.react = [
    hermesEnabled: true  // default true in RN 0.70+
]
```

The bytecode bundle (`.hbc` format) is what ships to users on Android. On iOS, it ships as a regular `.jsbundle` but Hermes still compiles it on first launch.

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

**Impact**: removes all `console.*` calls from the production bundle. Saves 5–15 KB depending on how heavily you log. More importantly, prevents sensitive data from being logged in production.

### Strip __DEV__ Code

Metro replaces `__DEV__` with `false` in production builds. Terser then eliminates dead branches:

```ts
if (__DEV__) {
  // This entire block is removed in production bundle
  console.log('Debug info:', state);
  performExpensiveValidation(data);
}
```

**Impact**: 10–50 KB saved depending on how much dev-only code you have. Pattern works for any constant-folded boolean: `process.env.NODE_ENV === 'development'` also gets folded.

---

## Code Splitting with Re.Pack

[Re.Pack](https://re-pack.dev) replaces Metro with a webpack-based bundler. Required for true code splitting in React Native.

```bash
npm install --save-dev @callstack/repack
```

```ts
// Dynamic import — creates a separate chunk loaded on demand
const HeavyFeature = React.lazy(() => import('./heavy-feature'));

function App() {
  return (
    <Suspense fallback={<LoadingSpinner />}>
      <HeavyFeature />
    </Suspense>
  );
}
```

**When to use Re.Pack**: apps > 5 MB bundle size, super-app architecture where features are loaded dynamically, or when you need Module Federation (sharing code between mini-apps).

**Trade-off**: Re.Pack adds build complexity and is not the official bundler. Test thoroughly after switching.

---

## RAM Bundles

RAM (Random Access Module) bundles store each module as a separate indexed section. The runtime loads only the sections it needs.

```bash
# Generate RAM bundle
react-native bundle \
  --platform android \
  --indexed-ram-bundle \
  --dev false \
  --entry-file index.js \
  --bundle-output android/app/src/main/assets/index.android.bundle
```

**When RAM bundles help**: apps with 1000+ modules where many modules are loaded conditionally. Startup time improvement: 10–30%.

**Hermes renders RAM bundles obsolete** for most cases — Hermes achieves similar lazy loading via `inlineRequires`. Use Hermes + inlineRequires before considering RAM bundles.

---

## Platform-Specific Files

Metro resolves platform-specific files automatically:

```
components/
  Button.tsx          // fallback for both platforms
  Button.ios.tsx      // used on iOS only
  Button.android.tsx  // used on Android only
  Button.native.tsx   // used on all native platforms (overrides .tsx)
  Button.web.tsx      // used on web only
```

**Use for**: platform-specific implementations that have different dependencies. For example, `Camera.ios.tsx` might use `react-native-vision-camera` while `Camera.android.tsx` uses a lighter alternative. This keeps iOS-specific code out of the Android bundle and vice versa.

**Size impact**: with a 50/50 user split, platform-specific files effectively halve the bundle size for that feature's users.

---

## Dynamic Feature Delivery (Android App Bundles)

Android App Bundles (`.aab`) allow Google Play to deliver only the APKs relevant to each device configuration.

```groovy
// android/app/build.gradle
android {
    bundle {
        language {
            enableSplit = true  // only deliver user's language
        }
        density {
            enableSplit = true  // only deliver screen density assets
        }
        abi {
            enableSplit = true  // only deliver device ABI (arm64, x86_64, etc.)
        }
    }
}
```

**Size savings**: 30–50% reduction in download size for end users compared to a universal APK. Does not reduce the JS bundle size, but reduces native library and asset delivery size.

---

## Font Subsetting

If you use custom fonts, ship only the glyphs you actually use.

```bash
# pyftsubset from fonttools
pip install fonttools
pyftsubset Inter-Regular.ttf \
  --unicodes="U+0020-007E,U+AC00-D7A3,U+1100-11FF" \
  --output-file=Inter-Regular-subset.ttf
# Full font: 350 KB → Subset (Latin + Korean): 95 KB
```

For icon fonts (if you must use them), subset to only the icon codepoints your app uses. Most icon font tools support this via a configuration file.

---

## Asset Optimization Pipeline

**Images**:

```bash
# PNG optimization (lossless, ~20-30% size reduction)
npx sharp-cli --input src/assets/**/*.png --output dist/assets/ --format png

# JPEG quality tuning (lossy, aggressive compression)
npx sharp-cli --input src/assets/**/*.jpg --output dist/assets/ \
  --format jpeg --quality 80

# WebP conversion (30-50% smaller than JPEG at same quality)
# React Native supports WebP on both platforms
npx sharp-cli --input src/assets/**/*.jpg --output dist/assets/ --format webp
```

Use `@2x` and `@3x` suffixes for density-specific images. Metro automatically selects the correct density at build time. Do not ship `@3x` images to `@1x` devices.

**SVG optimization**:

```bash
npx svgo --config svgo.config.js src/assets/icons/
```

```js
// svgo.config.js
module.exports = {
  plugins: [
    'removeDoctype',
    'removeComments',
    'cleanupIds',
    { name: 'removeAttrs', params: { attrs: 'data-name' } },
  ],
};
```

SVG optimization typically reduces file size by 30–50%. For `react-native-svg`, the SVG file is compiled to JS at build time — smaller SVG = less JS.

---

## ProGuard/R8 for Android

R8 (the successor to ProGuard) shrinks and obfuscates native Android code (Java/Kotlin). It does not touch the JS bundle.

```groovy
// android/app/build.gradle
android {
    buildTypes {
        release {
            minifyEnabled true      // enable R8
            shrinkResources true    // remove unused native resources
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'),
                          'proguard-rules.pro'
        }
    }
}
```

**Impact**: reduces native Android code by 20–50%. Critical for apps with large native dependencies (Firebase, Google Maps, ML Kit).

Add rules to prevent R8 from removing code that is accessed via reflection:

```
# proguard-rules.pro
-keep class com.facebook.react.** { *; }
-keep class com.swmansion.reanimated.** { *; }
```

---

## App Thinning (iOS)

Xcode App Thinning delivers only the assets and binary slices needed by each device:

- **Slicing**: strips unused architecture slices and asset catalog variants
- **On-Demand Resources**: loads assets from the App Store on demand (not commonly used in RN apps)
- **Bitcode**: deprecated in Xcode 14+ (no longer submitted to App Store)

Enable in Xcode: Product → Archive → Distribute App → select "Enable App Thinning".

**Size impact**: 20–40% download size reduction for users. A 100 MB universal IPA might deliver as 60 MB to a specific device.

---

## CI/CD Integration

### Bundle Size Budgets

Define size budgets to catch regressions before they reach production.

```yaml
# .github/workflows/bundle-size.yml
name: Bundle Size Check

on: [pull_request]

jobs:
  bundle-size:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build bundle
        run: |
          npx react-native bundle \
            --platform android \
            --dev false \
            --entry-file index.js \
            --bundle-output /tmp/main.jsbundle

      - name: Check bundle size
        run: |
          SIZE=$(wc -c < /tmp/main.jsbundle)
          BUDGET=3145728  # 3 MB budget
          echo "Bundle size: $SIZE bytes"
          if [ "$SIZE" -gt "$BUDGET" ]; then
            echo "FAIL: Bundle exceeds 3 MB budget ($SIZE bytes)"
            exit 1
          fi
```

### Size Comparison Between Releases

```bash
# Install bundlesize globally
npm install -g bundlesize

# bundlesize config in package.json
{
  "bundlesize": [
    {
      "path": "./dist/main.jsbundle",
      "maxSize": "3 MB",
      "compression": "none"
    }
  ]
}
```

### Automated Analysis in CI

```yaml
- name: Generate bundle report
  run: |
    npx react-native-bundle-visualizer \
      --platform android \
      --output /tmp/report.html

- name: Upload report artifact
  uses: actions/upload-artifact@v4
  with:
    name: bundle-report
    path: /tmp/report.html
    retention-days: 30

- name: Comment PR with size delta
  uses: actions/github-script@v7
  with:
    script: |
      const currentSize = process.env.CURRENT_SIZE;
      const baseSize = process.env.BASE_SIZE;
      const delta = currentSize - baseSize;
      const sign = delta > 0 ? '+' : '';
      github.rest.issues.createComment({
        issue_number: context.issue.number,
        owner: context.repo.owner,
        repo: context.repo.repo,
        body: `Bundle size: ${currentSize} KB (${sign}${delta} KB vs base)`
      });
```

### Target Bundle Sizes

| App Type | JS Bundle (gzipped) | Total App Size (iOS) | Total App Size (Android) |
|---|---|---|---|
| Small utility app | < 500 KB | < 20 MB | < 15 MB |
| Medium product app | < 1.5 MB | < 60 MB | < 40 MB |
| Large feature-rich app | < 3 MB | < 150 MB | < 100 MB |
| Super-app (with code splitting) | < 500 KB initial chunk | varies | varies |

These are targets, not hard limits. Measure your competitors and aim to be within the same range. Users with low storage devices (4–16 GB total) abandon apps that exceed 100 MB.
