# Flutter Performance — Advanced Patterns Reference

Deep-dive reference for advanced Flutter performance optimization. Read this when the SKILL.md quick reference isn't enough.

## 1. Impeller Internals & Optimization

### How Impeller Renders

Impeller replaces Skia as Flutter's rendering backend:
1. **Build time**: All shaders compiled offline during Flutter Engine build
2. **Tile-based rendering**: Divides each frame into ~256x256 pixel tiles
3. **Dirty region tracking**: Only re-rasterizes tiles whose content changed
4. **Pipeline state objects**: Built upfront, not lazily at runtime

### Impeller vs Skia Performance Comparison

| Metric | Skia | Impeller |
|---|---|---|
| First-frame shader compile | 50-300ms jank | 0ms (pre-compiled) |
| Frame rasterization | Baseline | ~50% faster |
| 120fps consistency | Frequent drops | Stable |
| GPU memory usage | Higher (shader cache) | Lower (no runtime cache) |
| Complex clip paths | Fast | Slower (more draw calls) |

### Impeller-Aware Coding Patterns

**Avoid complex clip operations:**
```dart
// Impeller generates more draw calls for complex clips
// BAD — custom clipper with bezier curves
ClipPath(
  clipper: WavyClipper(), // complex path = many draw calls
  child: Image.asset('bg.webp'),
)

// GOOD — use decoration or simple clips
Container(
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(16),
    image: DecorationImage(image: AssetImage('bg.webp'), fit: BoxFit.cover),
  ),
)
```

**Minimize overlapping opacity layers:**
```dart
// BAD — stacked Opacity widgets create separate composition layers
Stack(children: [
  Opacity(opacity: 0.8, child: Background()),
  Opacity(opacity: 0.5, child: Overlay()),
  Opacity(opacity: 0.3, child: Shadow()),
])

// GOOD — combine into single paint operation
Stack(children: [
  Background(),
  Container(color: Colors.black.withOpacity(0.5)),
  // Use color-level opacity, not widget-level
])
```

### Checking Impeller Status

```dart
// Verify Impeller is active in debug builds
import 'dart:ui' as ui;

void checkImpeller() {
  // In Flutter 3.27+, Impeller is default on iOS and Android API 29+
  debugPrint('Renderer: ${ui.PlatformDispatcher.instance.implicitView?.display}');
}
```

### Disabling Impeller (Troubleshooting Only)

```bash
# iOS — Info.plist
<key>FLTEnableImpeller</key>
<false/>

# Android — AndroidManifest.xml
<meta-data
  android:name="io.flutter.embedding.android.EnableImpeller"
  android:value="false" />
```

## 2. Custom RenderObject Performance

For maximum rendering performance, bypass the widget layer:

```dart
class FastCircle extends LeafRenderObjectWidget {
  final Color color;
  final double radius;

  const FastCircle({super.key, required this.color, required this.radius});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderFastCircle(color: color, radius: radius);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderFastCircle renderObject) {
    renderObject
      ..color = color
      ..radius = radius;
  }
}

class _RenderFastCircle extends RenderBox {
  Color _color;
  double _radius;

  _RenderFastCircle({required Color color, required double radius})
      : _color = color,
        _radius = radius;

  set color(Color value) {
    if (_color == value) return; // skip if unchanged
    _color = value;
    markNeedsPaint(); // only repaint, no layout
  }

  set radius(double value) {
    if (_radius == value) return;
    _radius = value;
    markNeedsLayout(); // layout changed
  }

  @override
  void performLayout() {
    size = Size(_radius * 2, _radius * 2);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final paint = Paint()..color = _color;
    context.canvas.drawCircle(
      offset + Offset(_radius, _radius),
      _radius,
      paint,
    );
  }
}
```

**When to use custom RenderObjects:**
- Rendering hundreds of similar elements (charts, graphs, games)
- Need sub-millisecond paint performance
- Widget overhead is measurable in profiling

## 3. Platform Channel Optimization

### Reduce Serialization Overhead

```dart
// BAD — sending complex nested Maps, large strings
final result = await platform.invokeMethod('processData', {
  'items': items.map((e) => e.toJson()).toList(),  // serializes entire list
});

// GOOD — send binary data for large payloads
final bytes = Uint8List.fromList(utf8.encode(jsonEncode(items)));
final result = await platform.invokeMethod('processData', bytes);

// BEST — use Pigeon for type-safe, efficient platform channels
// Pigeon generates optimized serialization code at build time
```

### Batch Platform Calls

```dart
// BAD — N platform channel calls
for (final file in files) {
  await platform.invokeMethod('processFile', file.path);
}

// GOOD — single call with batch
await platform.invokeMethod('processFiles', files.map((f) => f.path).toList());
```

### Use EventChannel for Streams

```dart
// For continuous data from native (sensors, location, etc.)
const eventChannel = EventChannel('com.app/sensor_data');
final stream = eventChannel.receiveBroadcastStream();

// In widget
StreamBuilder<dynamic>(
  stream: stream,
  builder: (context, snapshot) {
    if (!snapshot.hasData) return const SizedBox.shrink();
    return SensorDisplay(data: snapshot.data);
  },
)
```

## 4. Isolate Advanced Patterns

### Worker Pool for Parallel Processing

```dart
import 'dart:async';
import 'dart:isolate';

class IsolatePool {
  final int size;
  final List<Isolate> _isolates = [];
  final List<SendPort> _sendPorts = [];
  int _nextWorker = 0;

  IsolatePool(this.size);

  Future<void> start() async {
    for (var i = 0; i < size; i++) {
      final receivePort = ReceivePort();
      final isolate = await Isolate.spawn(_worker, receivePort.sendPort);
      _isolates.add(isolate);
      _sendPorts.add(await receivePort.first as SendPort);
    }
  }

  Future<R> execute<R>(Function task) async {
    final worker = _sendPorts[_nextWorker % size];
    _nextWorker++;
    final responsePort = ReceivePort();
    worker.send([task, responsePort.sendPort]);
    return await responsePort.first as R;
  }

  void dispose() {
    for (final isolate in _isolates) {
      isolate.kill();
    }
  }

  static void _worker(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    receivePort.listen((message) {
      final task = message[0] as Function;
      final replyPort = message[1] as SendPort;
      replyPort.send(task());
    });
  }
}
```

### Isolate with Streaming Results

```dart
// For progress reporting from isolate
Future<void> processWithProgress(List<String> files) async {
  final receivePort = ReceivePort();
  await Isolate.spawn(_processFiles, _ProcessRequest(files, receivePort.sendPort));

  await for (final message in receivePort) {
    if (message is double) {
      // Progress update (0.0 - 1.0)
      setState(() => _progress = message);
    } else if (message is List<ProcessedFile>) {
      // Final result
      setState(() => _results = message);
      receivePort.close();
    }
  }
}

static void _processFiles(_ProcessRequest request) {
  final results = <ProcessedFile>[];
  for (var i = 0; i < request.files.length; i++) {
    results.add(_process(request.files[i]));
    request.sendPort.send((i + 1) / request.files.length); // progress
  }
  request.sendPort.send(results); // final result
}
```

## 5. State Management Performance Deep-Dive

### Riverpod — select() Granularity

```dart
// ANTI-PATTERN — watching entire provider
final user = ref.watch(userProvider);
// Rebuilds when ANY field changes: name, email, avatar, settings...

// Level 1 — select single field
final name = ref.watch(userProvider.select((u) => u.name));

// Level 2 — select computed value
final isAdmin = ref.watch(userProvider.select((u) => u.role == 'admin'));

// Level 3 — select multiple fields with record
final (name, avatar) = ref.watch(
  userProvider.select((u) => (u.name, u.avatarUrl)),
);
```

### Provider — Consumer vs context.watch

```dart
// BAD — context.watch at root
Widget build(BuildContext context) {
  final theme = context.watch<ThemeModel>();
  return MaterialApp(/* ... */); // ENTIRE app rebuilds on theme change
}

// GOOD — Consumer wraps only the dependent subtree
Consumer<ThemeModel>(
  builder: (context, theme, child) {
    return MaterialApp(
      theme: theme.data,
      home: child!, // child NOT rebuilt
    );
  },
  child: const HomePage(),
)
```

### Bloc — Event Debouncing

```dart
// Prevent rapid-fire events from causing rebuild storms
on<SearchChanged>(
  (event, emit) async {
    final results = await _search(event.query);
    emit(state.copyWith(results: results));
  },
  transformer: debounce(const Duration(milliseconds: 300)),
);

EventTransformer<E> debounce<E>(Duration duration) {
  return (events, mapper) => events.debounceTime(duration).flatMap(mapper);
}
```

## 6. Scroll Performance Advanced

### AutomaticKeepAliveClientMixin

```dart
// Keep tab content alive when switching tabs (avoid rebuild)
class _TabContentState extends State<TabContent>
    with AutomaticKeepAliveClientMixin {

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // REQUIRED
    return ExpensiveContent();
  }
}
```

### SliverPrototypeExtentList (Variable But Similar Heights)

```dart
// When items have similar but not identical heights
CustomScrollView(
  slivers: [
    SliverPrototypeExtentList(
      prototypeItem: const ItemTile(item: Item.prototype),
      delegate: SliverChildBuilderDelegate(
        (context, index) => ItemTile(item: items[index]),
        childCount: items.length,
      ),
    ),
  ],
)
```

### Pagination with Scroll Controller

```dart
class _ListState extends State<InfiniteList> {
  final _scrollController = ScrollController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_isLoading) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 200) { // 200px threshold
      _loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
```

## 7. Animation Advanced Patterns

### Staggered Animations

```dart
class _StaggeredState extends State<StaggeredDemo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _opacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.3)),
    );
    _slide = Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.1, 0.6, curve: Curves.easeOut)),
    );
    _scale = Tween(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.3, 0.8, curve: Curves.easeOut)),
    );

    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: SlideTransition(
            position: _slide,
            child: ScaleTransition(scale: _scale, child: child),
          ),
        );
      },
      child: const CardContent(), // cached, not rebuilt
    );
  }
}
```

### Physics-Based Animations (60fps Guaranteed)

```dart
final _spring = SpringSimulation(
  const SpringDescription(mass: 1, stiffness: 200, damping: 15),
  0,    // start
  1,    // end
  0,    // velocity
);

_controller.animateWith(_spring);
```

## 8. CI Performance Benchmarking

### Flutter Integration Test Benchmarks

```dart
// test_driver/perf_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scrolling performance', (tester) async {
    await tester.pumpWidget(const MyApp());

    await binding.traceAction(
      () async {
        final listFinder = find.byType(ListView);
        await tester.fling(listFinder, const Offset(0, -500), 1000);
        await tester.pumpAndSettle();
        await tester.fling(listFinder, const Offset(0, 500), 1000);
        await tester.pumpAndSettle();
      },
      reportKey: 'scrolling_timeline',
    );
  });
}
```

```bash
# Run benchmark and generate timeline
flutter drive \
  --driver=test_driver/perf_test.dart \
  --target=integration_test/app_test.dart \
  --profile \
  --no-dds

# CI pipeline example (GitHub Actions)
# Compare against baseline — fail if P99 frame time > 16ms
```

### Custom Performance Metrics

```dart
// Track custom metrics with Timeline
import 'dart:developer';

void expensiveOperation() {
  Timeline.startSync('ExpensiveOperation');
  // ... work ...
  Timeline.finishSync();
}

// Visible in DevTools Performance timeline
```

## 9. Memory Profiling Checklist

### Using DevTools Memory View

1. **Open Memory tab** in Flutter DevTools
2. **Take heap snapshot** before and after navigation
3. **Compare snapshots** — look for objects that should have been GC'd
4. **Filter by class** — search for your widget/state classes
5. **Check retaining paths** — find what's holding the reference

### Common Leak Patterns & Detection

| Symptom | Likely Cause | Detection |
|---|---|---|
| Memory grows on repeated navigation | Undisposed controllers | Heap snapshot diff |
| Memory grows over time | Uncancelled subscriptions | Monitor RSS over 5 min |
| Sudden memory spikes | Large image decode | Memory timeline |
| OOM crash on low-end devices | Image cache too large | Monitor max RSS |

### Leak Canary Equivalent for Flutter

```dart
// Debug-only leak detection
assert(() {
  // Track widget disposal
  debugPrint('Widget disposed: $runtimeType');
  return true;
}());
```

## 10. Production Monitoring

### Firebase Performance (Recommended)

```dart
import 'package:firebase_performance/firebase_performance.dart';

// Custom trace for critical paths
final trace = FirebasePerformance.instance.newTrace('checkout_flow');
await trace.start();
// ... checkout logic ...
trace.setMetric('items_count', cart.items.length);
await trace.stop();

// HTTP metric
final metric = FirebasePerformance.instance.newHttpMetric(url, HttpMethod.Get);
await metric.start();
final response = await http.get(Uri.parse(url));
metric.httpResponseCode = response.statusCode;
metric.responsePayloadSize = response.contentLength;
await metric.stop();
```

### Sentry Flutter Performance

```dart
import 'package:sentry_flutter/sentry_flutter.dart';

await SentryFlutter.init(
  (options) {
    options.dsn = 'YOUR_DSN';
    options.tracesSampleRate = 0.2;
    options.profilesSampleRate = 0.1;
    options.enableAutoPerformanceTracing = true;
  },
  appRunner: () => runApp(const MyApp()),
);
```
