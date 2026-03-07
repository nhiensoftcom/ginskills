---
name: flutter-performance
description: |
  **Flutter Performance Optimization**: Comprehensive guide for optimizing Flutter app performance — widget rebuilds, jank reduction, memory leaks, Dart isolates, image caching, state management perf, Impeller rendering, DevTools profiling. Targets 60/120fps production apps.
  - MANDATORY TRIGGERS: flutter performance, flutter optimization, flutter jank, flutter fps, flutter rebuild, flutter memory leak, flutter isolate, flutter image cache, flutter profiling, flutter devtools, flutter impeller, flutter shader, flutter widget rebuild, flutter slow, flutter laggy, flutter frame drop, flutter startup time, flutter app size, flutter tree shaking, flutter repaint boundary, flutter const constructor, flutter state management performance, flutter listview performance, flutter animation performance, dart isolate, flutter scroll jank, flutter build method, flutter dispose
  - Use this skill whenever the user is optimizing Flutter app performance, debugging jank or frame drops, profiling with DevTools, fixing memory leaks, or reviewing Flutter code for performance anti-patterns. Also trigger when discussing widget rebuild optimization, Impeller rendering, Dart isolate usage, or app size reduction — even casual mentions like "my Flutter app is slow" or "how do I improve FPS?".
---

# Flutter Performance Optimization

Analyze and optimize Flutter apps for consistent 60/120fps rendering. Covers widget rebuilds, jank elimination, memory management, Dart isolates, image optimization, Impeller rendering, and DevTools profiling. Targets production apps on both iOS and Android.

## Core Mental Model

**Flutter renders at 60fps (16ms per frame) or 120fps (8ms per frame).** Every frame goes through Build → Layout → Paint → Composite. If any phase exceeds the frame budget, you get jank — visible stuttering. The goal: keep the main isolate free for UI work, minimize widget rebuilds, and let Impeller handle GPU rendering efficiently.

Key principles:
- **Measure first** — use DevTools before optimizing blindly
- **Rebuild less** — const constructors, selective state, RepaintBoundary
- **Offload heavy work** — Dart isolates for CPU-intensive tasks
- **Cache aggressively** — images, computed values, widget subtrees
- **Let Impeller work** — avoid patterns that defeat its optimizations

## 1. Widget Rebuild Optimization

### const Constructors (Up to 70% Fewer Rebuilds)

```dart
// BAD — rebuilds every time parent rebuilds
Widget build(BuildContext context) {
  return Column(
    children: [
      Text('Static Title'),          // rebuilt unnecessarily
      Icon(Icons.star),              // rebuilt unnecessarily
      MyDynamicWidget(data: _data),
    ],
  );
}

// GOOD — const widgets are skipped during rebuild
Widget build(BuildContext context) {
  return Column(
    children: [
      const Text('Static Title'),    // skipped — same instance
      const Icon(Icons.star),        // skipped — same instance
      MyDynamicWidget(data: _data),  // only this rebuilds
    ],
  );
}
```

Enable the `prefer_const_constructors` lint:
```yaml
# analysis_options.yaml
linter:
  rules:
    prefer_const_constructors: true
    prefer_const_declarations: true
    prefer_const_literals_to_create_immutables: true
```

### Decompose Large build() Methods

```dart
// BAD — 200+ line build method, entire tree rebuilds on any setState
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Column(children: [
      // ...hundreds of lines of widgets...
    ]),
  );
}

// GOOD — extracted const/stateless sub-widgets
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Column(children: [
      const HeaderSection(),       // separate StatelessWidget
      ContentSection(data: _data), // only rebuilds when _data changes
      const FooterSection(),       // separate StatelessWidget
    ]),
  );
}
```

### Avoid Inline Closures That Cause Rebuilds

```dart
// BAD — new function instance every build → child always rebuilds
ListView.builder(
  itemBuilder: (context, index) => ItemTile(
    onTap: () => _handleTap(items[index]),  // new closure each build
  ),
)

// GOOD — stable callback reference
ListView.builder(
  itemBuilder: (context, index) => ItemTile(
    item: items[index],
    onTap: _handleTap,  // stable reference, pass item via widget
  ),
)
```

### Selective setState — Minimize Rebuild Scope

```dart
// BAD — setState at root rebuilds EVERYTHING
class _HomePageState extends State<HomePage> {
  int _counter = 0;
  void _increment() => setState(() => _counter++);

  Widget build(BuildContext context) {
    return Column(children: [
      const HeavyHeader(),   // rebuilds unnecessarily!
      Text('$_counter'),
      const HeavyFooter(),   // rebuilds unnecessarily!
    ]);
  }
}

// GOOD — isolate changing widget with a dedicated StatefulWidget or Builder
class _HomePageState extends State<HomePage> {
  Widget build(BuildContext context) {
    return Column(children: [
      const HeavyHeader(),
      const CounterWidget(),  // only this subtree rebuilds
      const HeavyFooter(),
    ]);
  }
}
```

### RepaintBoundary — Isolate Expensive Paints

```dart
// Wrap frequently-animating or complex widgets
RepaintBoundary(
  child: CustomPaint(
    painter: ComplexChartPainter(data),
    size: const Size(300, 200),
  ),
)
```

Use when: animations, custom painters, frequently-updating regions. Don't overuse — each boundary has memory overhead for its own layer.

## 2. List & Scroll Performance

### ListView.builder (Lazy Construction)

```dart
// BAD — builds ALL items upfront, even offscreen
ListView(
  children: items.map((item) => ItemTile(item: item)).toList(),
)

// GOOD — only builds visible items + cacheExtent
ListView.builder(
  itemCount: items.length,
  itemExtent: 72,  // skip measurement pass — major win for fixed-height items
  itemBuilder: (context, index) => ItemTile(item: items[index]),
)
```

### cacheExtent Tuning

```dart
ListView.builder(
  cacheExtent: 500,  // pixels to pre-build offscreen (default: 250)
  // Higher = smoother fast scrolling, but more memory
  // Lower = less memory, but may show blank frames during fast scroll
)
```

### SliverList for Mixed Scroll Content

```dart
// Instead of nesting ListView inside ScrollView:
CustomScrollView(
  slivers: [
    const SliverToBoxAdapter(child: HeaderWidget()),
    SliverList.builder(
      itemCount: items.length,
      itemBuilder: (context, index) => ItemTile(item: items[index]),
    ),
    const SliverToBoxAdapter(child: FooterWidget()),
  ],
)
```

### Keys for Stateful List Items

```dart
// BAD — index keys cause state mismatch on reorder/insert
ListView.builder(
  itemBuilder: (context, index) => ItemTile(key: ValueKey(index)),
)

// GOOD — stable unique key preserves widget state
ListView.builder(
  itemBuilder: (context, index) => ItemTile(key: ValueKey(items[index].id)),
)
```

## 3. Image Optimization

### CachedNetworkImage (Disk + Memory Cache)

```dart
import 'package:cached_network_image/cached_network_image.dart';

CachedNetworkImage(
  imageUrl: '$cdnBaseUrl/product/${product.id}.webp?w=400&q=75',
  placeholder: (context, url) => const ShimmerPlaceholder(),
  errorWidget: (context, url, error) => const Icon(Icons.error),
  memCacheWidth: 400,   // decode at display size, not full resolution
  memCacheHeight: 400,
  fadeInDuration: const Duration(milliseconds: 200),
)
```

### Precache Critical Images

```dart
@override
void didChangeDependencies() {
  super.didChangeDependencies();
  // Precache hero images before they're needed
  precacheImage(
    const AssetImage('assets/images/hero.webp'),
    context,
  );
  precacheImage(
    NetworkImage('$cdnUrl/banner.webp'),
    context,
  );
}
```

### Resolution-Aware Loading

```dart
// Request appropriately-sized images from CDN
final pixelRatio = MediaQuery.devicePixelRatioOf(context);
final width = (containerWidth * pixelRatio).toInt();
final imageUrl = '$cdnUrl/image.webp?w=$width&q=80&fm=webp';
```

### Image Memory Budget

| Device RAM | ImageCache Size | ImageCache Size Bytes |
|---|---|---|
| 1-2 GB | 50 images | 50 MB |
| 3-4 GB | 100 images | 100 MB |
| 6+ GB | 200 images | 200 MB |

```dart
// Tune ImageCache in main()
PaintingBinding.instance.imageCache.maximumSize = 100;
PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20; // 100 MB
```

## 4. Memory Management

### Top Memory Leak Sources (90% of Leaks)

**1. Undisposed Controllers:**
```dart
// BAD — controller leaks
class _MyState extends State<MyWidget> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  // ... no dispose()
}

// GOOD — always dispose
@override
void dispose() {
  _controller.dispose();
  _scrollController.dispose();
  super.dispose();
}
```

**2. Uncancelled Stream Subscriptions:**
```dart
// BAD — subscription leaks after widget unmounts
late StreamSubscription _sub;

@override
void initState() {
  super.initState();
  _sub = myStream.listen((data) => setState(() => _data = data));
}

// GOOD — cancel in dispose
@override
void dispose() {
  _sub.cancel();
  super.dispose();
}
```

**3. AnimationController Leaks:**
```dart
// GOOD — dispose animation controllers
class _AnimState extends State<AnimWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

**4. Timer Leaks:**
```dart
Timer? _timer;

@override
void initState() {
  super.initState();
  _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
}

@override
void dispose() {
  _timer?.cancel();
  super.dispose();
}
```

## 5. Dart Isolates — Offload Heavy Work

### When to Use Isolates

Any operation that takes > 16ms on the main isolate should be offloaded:
- JSON parsing of large payloads (> 50KB)
- Image processing / compression
- Encryption / hashing
- Complex data transformations
- Database-heavy operations
- File I/O on large files

### Isolate.run() (Dart 2.19+ / Dart 3.x)

```dart
// Simple one-shot computation
final result = await Isolate.run(() {
  // Runs in a separate isolate — won't block UI
  return heavyJsonParse(largeJsonString);
});
```

### compute() Function

```dart
// Flutter's convenience wrapper — serializes input/output automatically
final parsed = await compute(parseProducts, jsonString);

// Top-level or static function (required for compute)
List<Product> parseProducts(String json) {
  final decoded = jsonDecode(json) as List;
  return decoded.map((e) => Product.fromJson(e)).toList();
}
```

### Long-Running Isolate with Ports

```dart
// For continuous background work (e.g., real-time data processing)
final receivePort = ReceivePort();
await Isolate.spawn(_backgroundWorker, receivePort.sendPort);

final sendPort = await receivePort.first as SendPort;
// Send work to the isolate
sendPort.send(workPayload);
```

**Rule of thumb:** Use `Isolate.run()` for one-shot tasks, `compute()` for simple transformations, and `Isolate.spawn()` for long-running workers.

## 6. State Management Performance

### Performance Characteristics

| Library | Rebuild Granularity | Bundle Impact | Best For |
|---|---|---|---|
| **Riverpod 2.x** | select() per-field | ~15 KB | Enterprise, compile-time safe |
| **Provider** | Consumer/Selector | ~10 KB | Simple apps, official recommendation |
| **Bloc/Cubit** | BlocSelector | ~20 KB | Complex async, event-driven |
| **GetX** | Obx() per-observable | ~25 KB | Rapid prototyping (not recommended for prod) |
| setState | Widget-level | 0 KB | Ephemeral UI state only |

### Selective Rebuilds (Critical Pattern)

```dart
// BAD — entire widget rebuilds when ANY field in UserState changes
Widget build(BuildContext context) {
  final user = ref.watch(userProvider);
  return Text(user.name);
}

// GOOD — only rebuilds when name changes (Riverpod)
Widget build(BuildContext context) {
  final name = ref.watch(userProvider.select((u) => u.name));
  return Text(name);
}

// GOOD — Bloc equivalent
BlocSelector<UserCubit, UserState, String>(
  selector: (state) => state.name,
  builder: (context, name) => Text(name),
)
```

### Avoid Context.watch at Widget Root

```dart
// BAD — Provider: watching at Scaffold level rebuilds everything
Widget build(BuildContext context) {
  final cart = context.watch<CartModel>();
  return Scaffold(
    appBar: AppBar(title: Text('Cart (${cart.itemCount})')),
    body: /* expensive subtree */,
  );
}

// GOOD — isolate the watch with Consumer
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: Consumer<CartModel>(
        builder: (context, cart, _) => Text('Cart (${cart.itemCount})'),
      ),
    ),
    body: /* expensive subtree — NOT rebuilt */,
  );
}
```

## 7. Impeller Rendering Engine

### Status (Flutter 3.27+)

- **iOS**: Default since Flutter 3.16 — stable, production-ready
- **Android**: Default on API 29+ (Vulkan) since Flutter 3.27
- **Fallback**: OpenGL on older Android devices without Vulkan

### What Impeller Solves

| Problem (Skia) | Solution (Impeller) |
|---|---|
| First-frame shader compilation jank | All shaders pre-compiled at build time |
| Runtime shader compilation stalls | Zero runtime shader compilation |
| Inconsistent frame times | Predictable frame rendering |
| GPU cache misses on new visuals | Tile-based rendering (256x256 tiles) |

### SkSL Warmup (Legacy — Only for Skia Fallback)

```bash
# Only needed if targeting Skia (Android API < 29)
# 1. Capture shaders
flutter run --profile --cache-sksl

# 2. Export shader bundle
flutter build apk --bundle-sksl-path flutter_01.sksl.json
```

**With Impeller (default), SkSL warmup is unnecessary.**

### Impeller-Specific Optimizations

```dart
// AVOID — complex clipping paths increase draw calls in Impeller
ClipPath(
  clipper: ComplexCustomClipper(),  // expensive with Impeller
  child: /* ... */,
)

// PREFER — simple clip shapes
ClipRRect(
  borderRadius: BorderRadius.circular(16),
  child: /* ... */,
)

// AVOID — multiple overlapping opacity layers
Opacity(opacity: 0.5, child: /* ... */)  // creates extra layer

// PREFER — use color opacity or AnimatedOpacity
Container(color: Colors.black.withOpacity(0.5))
AnimatedOpacity(opacity: 0.5, child: /* ... */)
```

## 8. Animation Performance

### Prefer Implicit Animations for Simple Cases

```dart
// GOOD — Flutter handles optimization automatically
AnimatedContainer(
  duration: const Duration(milliseconds: 300),
  curve: Curves.easeOut,
  width: _expanded ? 200 : 100,
  height: _expanded ? 200 : 100,
  color: _expanded ? Colors.blue : Colors.red,
)
```

### AnimatedBuilder for Complex Animations

```dart
// GOOD — only the builder subtree rebuilds, not the entire widget
AnimatedBuilder(
  animation: _controller,
  builder: (context, child) {
    return Transform.rotate(
      angle: _controller.value * 2 * pi,
      child: child,  // child is cached — NOT rebuilt
    );
  },
  child: const ExpensiveWidget(),  // built once, reused
)
```

### Avoid Layout-Triggering Animations

```dart
// BAD — changes size → triggers layout every frame
AnimatedBuilder(
  animation: _controller,
  builder: (context, child) {
    return SizedBox(
      width: 100 * _controller.value,  // layout change every frame!
      child: child,
    );
  },
)

// GOOD — Transform doesn't trigger layout
AnimatedBuilder(
  animation: _controller,
  builder: (context, child) {
    return Transform.scale(
      scale: _controller.value,  // paint-only — no layout
      child: child,
    );
  },
)
```

## 9. Startup Optimization

### Cold Start Targets

| Platform | Target | Warning | Fail |
|---|---|---|---|
| iOS flagship | ≤ 1.0s | ≤ 1.5s | > 2.0s |
| Mid-tier Android | ≤ 1.5s | ≤ 2.5s | > 3.0s |
| Low-end Android | ≤ 2.0s | ≤ 3.0s | > 4.0s |

### Quick Wins

1. **Deferred initialization** — lazy-load services not needed at startup
2. **Deferred imports** — split rarely-used features into deferred loads
3. **Native splash** — use `flutter_native_splash` for instant visual
4. **Reduce main() work** — defer analytics, crash reporting, remote config

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Only essential init here
  await _initCriticalServices(); // auth, storage
  runApp(const MyApp());
  // Defer non-critical init
  _initDeferredServices(); // analytics, crash reporting, remote config
}

Future<void> _initDeferredServices() async {
  await Future.delayed(const Duration(seconds: 1)); // after first frame
  await Firebase.initializeApp();
  await CrashReporting.init();
}
```

### Deferred Imports (Code Splitting)

```dart
// Only load heavy feature when accessed
import 'package:my_app/features/reports/reports.dart' deferred as reports;

Future<void> openReports() async {
  await reports.loadLibrary();
  navigator.push(reports.ReportsPage());
}
```

## 10. App Size Optimization

### Targets

| Metric | Good | Warning | Fail |
|---|---|---|---|
| APK (arm64) | ≤ 15 MB | ≤ 30 MB | > 50 MB |
| App Bundle (AAB) | ≤ 20 MB | ≤ 40 MB | > 60 MB |
| IPA | ≤ 30 MB | ≤ 50 MB | > 80 MB |

### Size Analysis

```bash
# Analyze app size
flutter build apk --analyze-size
flutter build appbundle --analyze-size
flutter build ios --analyze-size

# Compare two builds
flutter build apk --analyze-size --code-size-directory=v1
# ... make changes ...
flutter build apk --analyze-size --code-size-directory=v2
```

### Reduction Techniques

```bash
# Split APK per ABI (~40% reduction)
flutter build apk --split-per-abi

# Enable obfuscation + tree shaking
flutter build apk --obfuscate --split-debug-info=debug-info/

# Use App Bundle for Play Store (automatic per-device optimization)
flutter build appbundle
```

```dart
// Use WebP/AVIF instead of PNG for assets (50-70% smaller)
// Compress with: cwebp -q 80 input.png -o output.webp

// Remove unused packages from pubspec.yaml
// Run: flutter pub deps --no-dev | grep -c "^"  // count dependencies
```

## 11. Anti-Patterns Quick Reference

| Anti-Pattern | Impact | Fix |
|---|---|---|
| No `const` on static widgets | Unnecessary rebuilds | Add `const` keyword |
| `setState` at widget root | Entire tree rebuilds | Extract StatefulWidget or use Builder |
| `Opacity` widget for fading | Creates extra render layer | Use `AnimatedOpacity` or color opacity |
| `ListView(children: [...])` for large lists | All items built upfront | Use `ListView.builder` |
| No `itemExtent` on fixed-height lists | Layout measurement each item | Add `itemExtent` |
| Full-res images for thumbnails | ~8MB RAM per image on Android | Request sized images from CDN |
| Heavy work in `build()` | Blocks frame rendering | Move to `initState` or isolate |
| Undisposed controllers/subs | Memory leaks | `dispose()` everything |
| Synchronous file I/O on main isolate | UI jank during I/O | Use `Isolate.run()` or `compute()` |
| Deep widget nesting (10+ levels) | Slow layout pass | Extract into separate widgets |
| `Column` + `SingleChildScrollView` for lists | No lazy loading | Use `ListView.builder` |
| Complex `ClipPath` with Impeller | Increased draw calls | Use simple `ClipRRect` |
| `context.watch` at root widget | Broadcast rebuilds | Use `Consumer` / `select()` |
| `setState` inside `StreamBuilder` | Double rebuild | Let StreamBuilder manage state |
| No `key` on dynamic list items | State mismatch on reorder | Use `ValueKey(item.id)` |

## 12. Performance Budgets

| Metric | Good | Warning | Fail |
|---|---|---|---|
| Frame Render Time (60fps) | ≤ 16ms | ≤ 24ms | > 32ms |
| Frame Render Time (120fps) | ≤ 8ms | ≤ 12ms | > 16ms |
| Cold Start TTI | ≤ 1.5s iOS / ≤ 2.0s Android | ≤ 2.5s | > 3.5s |
| Widget Rebuild Count/Frame | ≤ 5 | ≤ 15 | > 30 |
| Memory Peak (3GB device) | ≤ 150 MB | ≤ 250 MB | > 350 MB |
| APK Size (arm64) | ≤ 15 MB | ≤ 30 MB | > 50 MB |
| Scroll FPS | 60/120 FPS | 50-55 FPS | < 45 FPS |
| Image Decode Time | ≤ 5ms | ≤ 15ms | > 30ms |

## 13. DevTools Profiling

| Need | Tool |
|---|---|
| Frame rendering analysis | Performance Overlay (`showPerformanceOverlay: true`) |
| Build/Layout/Paint timing | DevTools → Performance tab |
| Widget rebuild tracking | DevTools → Performance → Track Widget Rebuilds |
| Memory leaks | DevTools → Memory tab → Heap Snapshots |
| CPU hotspots | DevTools → CPU Profiler |
| App size analysis | `flutter build --analyze-size` |
| Widget tree inspection | DevTools → Widget Inspector |
| Network requests | DevTools → Network tab |
| Jank detection | DevTools → Performance → Jank Flags |

### Profile Mode (Required for Accurate Benchmarks)

```bash
# ALWAYS profile in profile mode — debug mode is 10x slower
flutter run --profile

# On device (not emulator) for realistic numbers
flutter run --profile -d <device-id>
```

### Performance Overlay

```dart
MaterialApp(
  showPerformanceOverlay: true,  // shows GPU/UI thread frame times
)
```

## 14. Optimization Checklist by Effort

### Level 1 — Quick Wins (< 1 day)
- [ ] Add `const` to all static widgets (enable lint rules)
- [ ] Replace `ListView(children)` with `ListView.builder`
- [ ] Add `itemExtent` to fixed-height lists
- [ ] Dispose all controllers and subscriptions
- [ ] Move heavy computation out of `build()`
- [ ] Use `CachedNetworkImage` for network images
- [ ] Request appropriately-sized images from CDN
- [ ] Enable `--split-per-abi` for APK builds
- [ ] Profile in profile mode on real device

### Level 2 — Standard (1-3 days)
- [ ] Extract large build methods into separate widgets
- [ ] Add `RepaintBoundary` for animations/custom painters
- [ ] Use `select()` in state management (Riverpod/Provider/Bloc)
- [ ] Offload JSON parsing to isolates (`compute()`)
- [ ] Implement deferred imports for heavy features
- [ ] Tune `cacheExtent` on scroll views
- [ ] Add `precacheImage` for critical images
- [ ] Configure `ImageCache` size limits
- [ ] Defer non-critical service initialization

### Level 3 — Advanced (1-2 weeks)
- [ ] Migrate to Impeller (verify on Android API 29+)
- [ ] Replace `Opacity` with `AnimatedOpacity` / color opacity
- [ ] Use `Transform` instead of layout-changing animations
- [ ] Implement `AutomaticKeepAliveClientMixin` for tab preservation
- [ ] Set up CI performance benchmarks
- [ ] Analyze and reduce app size (`--analyze-size`)
- [ ] Implement cursor-based pagination for large lists
- [ ] Profile and optimize startup time

### Level 4 — Expert (> 2 weeks)
- [ ] Custom `RenderObject` for performance-critical layouts
- [ ] Long-running isolates for background processing
- [ ] Platform channel optimization (reduce serialization)
- [ ] Custom Impeller-aware painting strategies
- [ ] Automated performance regression testing in CI

## Scan Process

When asked to analyze a Flutter project for performance issues:

### 1. Determine Scope
Ask (or infer): full audit, specific screen, startup, memory, rendering, or app size.

### 2. Run Automated Checks

```bash
# Anti-pattern scan
./scripts/flutter-perf-scan.sh <project-path>
```

### 3. Manual Review
Follow the anti-patterns table above and check each category.

### 4. Report Findings

Structure by severity:
```
CRITICAL — Causes visible jank or crashes
HIGH — Significant perf impact, fix before release
MEDIUM — Defense-in-depth improvement
LOW — Best practice recommendation
```

For each finding:
```
**[SEVERITY] Title**
Location: file:line
Impact: Frame time / memory / size impact
Before: The anti-pattern code
After: The optimized code
```

### 5. Prioritize Fixes
1. Critical fixes (visible jank, memory leaks)
2. High fixes (rebuild storms, missing lazy loading)
3. Medium fixes (missing const, suboptimal caching)
4. Low fixes (style improvements)

## References

- `references/flutter-patterns.md` — Advanced patterns: custom RenderObjects, platform channels, Impeller internals, CI benchmarking
