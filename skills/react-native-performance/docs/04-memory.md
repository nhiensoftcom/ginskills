# Memory Management in React Native

## 1. Memory Leak Patterns (22+ Patterns with Fixes)

---

### Pattern 1 — Keyboard Listener

```tsx
// BAD
useEffect(() => {
  Keyboard.addListener('keyboardDidShow', handleShow);
}, []);

// GOOD
useEffect(() => {
  const sub = Keyboard.addListener('keyboardDidShow', handleShow);
  return () => sub.remove();
}, []);
```

---

### Pattern 2 — AppState Listener

```tsx
// BAD
useEffect(() => {
  AppState.addEventListener('change', handleAppStateChange);
}, []);

// GOOD
useEffect(() => {
  const sub = AppState.addEventListener('change', handleAppStateChange);
  return () => sub.remove();
}, []);
```

---

### Pattern 3 — Dimensions Listener

```tsx
// BAD
useEffect(() => {
  Dimensions.addEventListener('change', handleDimensionsChange);
}, []);

// GOOD
useEffect(() => {
  const sub = Dimensions.addEventListener('change', handleDimensionsChange);
  return () => sub.remove();
}, []);
```

---

### Pattern 4 — DeviceEventEmitter

```tsx
// BAD
useEffect(() => {
  DeviceEventEmitter.addListener('onPushNotification', handlePush);
}, []);

// GOOD
useEffect(() => {
  const sub = DeviceEventEmitter.addListener('onPushNotification', handlePush);
  return () => sub.remove();
}, []);
```

---

### Pattern 5 — NativeEventEmitter

```tsx
// BAD
useEffect(() => {
  const emitter = new NativeEventEmitter(NativeModules.BleManager);
  emitter.addListener('BleManagerDiscoverPeripheral', handleDiscovery);
}, []);

// GOOD
useEffect(() => {
  const emitter = new NativeEventEmitter(NativeModules.BleManager);
  const sub = emitter.addListener('BleManagerDiscoverPeripheral', handleDiscovery);
  return () => sub.remove();
}, []);
```

---

### Pattern 6 — BackHandler

```tsx
// BAD
useEffect(() => {
  BackHandler.addEventListener('hardwareBackPress', handleBack);
}, []);

// GOOD
useEffect(() => {
  const sub = BackHandler.addEventListener('hardwareBackPress', handleBack);
  return () => sub.remove();
}, []);
```

---

### Pattern 7 — Linking Listener

```tsx
// BAD
useEffect(() => {
  Linking.addEventListener('url', handleUrl);
}, []);

// GOOD
useEffect(() => {
  const sub = Linking.addEventListener('url', handleUrl);
  return () => sub.remove();
}, []);
```

---

### Pattern 8 — NetInfo Subscription

```tsx
// BAD
useEffect(() => {
  NetInfo.addEventListener((state) => setIsConnected(state.isConnected));
}, []);

// GOOD
useEffect(() => {
  const unsubscribe = NetInfo.addEventListener((state) => {
    setIsConnected(state.isConnected);
  });
  return () => unsubscribe();
}, []);
```

---

### Pattern 9 — Timers (setTimeout / setInterval)

```tsx
// BAD
useEffect(() => {
  setTimeout(() => setState('done'), 3000);
  setInterval(() => poll(), 5000);
}, []);

// GOOD
useEffect(() => {
  const timeoutId = setTimeout(() => setState('done'), 3000);
  const intervalId = setInterval(() => poll(), 5000);
  return () => {
    clearTimeout(timeoutId);
    clearInterval(intervalId);
  };
}, []);
```

---

### Pattern 10 — requestAnimationFrame

```tsx
// BAD
useEffect(() => {
  const animate = () => {
    updateFrame();
    requestAnimationFrame(animate);
  };
  requestAnimationFrame(animate);
}, []);

// GOOD
useEffect(() => {
  let rafId: number;
  const animate = () => {
    updateFrame();
    rafId = requestAnimationFrame(animate);
  };
  rafId = requestAnimationFrame(animate);
  return () => cancelAnimationFrame(rafId);
}, []);
```

---

### Pattern 11 — Async Operations (fetch after unmount)

```tsx
// BAD
useEffect(() => {
  fetch('/api/user').then((res) => res.json()).then((data) => {
    setUser(data); // component may be unmounted
  });
}, []);

// GOOD
useEffect(() => {
  const controller = new AbortController();
  fetch('/api/user', { signal: controller.signal })
    .then((res) => res.json())
    .then((data) => setUser(data))
    .catch((err) => {
      if (err.name !== 'AbortError') throw err;
    });
  return () => controller.abort();
}, []);
```

---

### Pattern 12 — WebSocket Connection

```tsx
// BAD
useEffect(() => {
  const ws = new WebSocket('wss://example.com/socket');
  ws.onmessage = (e) => setMessages((prev) => [...prev, e.data]);
}, []);

// GOOD
useEffect(() => {
  const ws = new WebSocket('wss://example.com/socket');
  ws.onmessage = (e) => setMessages((prev) => [...prev, e.data]);
  return () => {
    ws.onmessage = null;
    ws.close();
  };
}, []);
```

---

### Pattern 13 — Reanimated Shared Values and Worklet References

```tsx
// BAD — shared value holds reference to a large object captured in worklet
const data = useLargeDataObject(); // 10 MB object
const animatedStyle = useAnimatedStyle(() => {
  return { opacity: data.opacity }; // captures entire `data` in worklet closure
});

// GOOD — extract only the primitive needed
const opacity = data.opacity;
const animatedStyle = useAnimatedStyle(() => {
  return { opacity };
});

// Also: cancel derived values and animation handles on unmount
useEffect(() => {
  return () => {
    cancelAnimation(sharedValue);
  };
}, []);
```

---

### Pattern 14 — React Navigation Listeners

```tsx
// BAD
useEffect(() => {
  navigation.addListener('focus', handleFocus);
  navigation.addListener('blur', handleBlur);
}, [navigation]);

// GOOD
useEffect(() => {
  const unsubFocus = navigation.addListener('focus', handleFocus);
  const unsubBlur = navigation.addListener('blur', handleBlur);
  return () => {
    unsubFocus();
    unsubBlur();
  };
}, [navigation]);
```

---

### Pattern 15 — Gesture Handler References

```tsx
// BAD — gesture composed inside render, new ref each render
function MyComponent() {
  const gesture = Gesture.Pan().onUpdate((e) => {
    sharedX.value = e.translationX;
  });
  return <GestureDetector gesture={gesture}><View /></GestureDetector>;
}

// GOOD — memoize the gesture definition
function MyComponent() {
  const gesture = useMemo(
    () => Gesture.Pan().onUpdate((e) => { sharedX.value = e.translationX; }),
    []
  );
  return <GestureDetector gesture={gesture}><View /></GestureDetector>;
}
```

---

### Pattern 16 — Native Module Event Subscriptions

```tsx
// BAD — assumes NativeModule cleans itself up
useEffect(() => {
  LocationModule.startUpdating();
  NativeModules.LocationModule.addListener('onLocation', handleLocation);
}, []);

// GOOD
useEffect(() => {
  LocationModule.startUpdating();
  const emitter = new NativeEventEmitter(NativeModules.LocationModule);
  const sub = emitter.addListener('onLocation', handleLocation);
  return () => {
    sub.remove();
    LocationModule.stopUpdating();
  };
}, []);
```

---

### Pattern 17 — Image Cache Growing Unbounded

```tsx
// BAD — no cache limit configured
import { Image } from 'expo-image';
// Default cache is unbounded; thousands of remote images fill disk + memory

// GOOD — configure cache policy per image
<Image
  source={{ uri: imageUrl }}
  cachePolicy="memory-disk"
  contentFit="cover"
/>

// Also: periodically clear stale cache in onLowMemory
import { clearDiskCache, clearMemoryCache } from 'expo-image';

async function handleMemoryWarning() {
  await clearMemoryCache();
  // optionally clearDiskCache() for disk pressure
}

// For react-native-fast-image:
import FastImage from 'react-native-fast-image';

useEffect(() => {
  return () => {
    FastImage.clearMemoryCache();
    // Only clear disk when truly necessary — expensive op
  };
}, []);
```

---

### Pattern 18 — Large Arrays/Objects Retained in Closures

```tsx
// BAD — callback captures entire API response (may be 5 MB)
const response = await fetchProductCatalog(); // 5,000 products
const handlePress = useCallback(() => {
  console.log(response.products[0].name); // retains all 5,000 products
}, [response]);

// GOOD — capture only the primitive needed
const firstName = response.products[0]?.name ?? '';
const handlePress = useCallback(() => {
  console.log(firstName);
}, [firstName]);
```

---

### Pattern 19 — Zustand Store Subscriptions

```tsx
// BAD — manual subscribe without unsubscribe
useEffect(() => {
  useAuthStore.subscribe((state) => setUser(state.user));
}, []);

// GOOD
useEffect(() => {
  const unsubscribe = useAuthStore.subscribe((state) => setUser(state.user));
  return () => unsubscribe();
}, []);

// BETTER — use selector inside component (no manual subscribe needed)
const user = useAuthStore((state) => state.user);
```

---

### Pattern 20 — TanStack Query Observer Leaks

```tsx
// BAD — manually created observer never removed
useEffect(() => {
  const observer = new QueryObserver(queryClient, { queryKey: ['user'] });
  observer.subscribe((result) => setData(result.data));
}, []);

// GOOD
useEffect(() => {
  const observer = new QueryObserver(queryClient, { queryKey: ['user'] });
  const unsubscribe = observer.subscribe((result) => setData(result.data));
  return () => {
    unsubscribe();
    observer.destroy();
  };
}, []);

// BEST — just use useQuery hook which handles its own lifecycle
const { data } = useQuery({ queryKey: ['user'], queryFn: fetchUser });
```

---

### Pattern 21 — Context Providers Holding Stale References

```tsx
// BAD — value object recreated every render, and holds old callbacks
const MyContext = createContext(null);
function MyProvider({ children }) {
  const [state, setState] = useState(initialState);
  // New object reference every render → all consumers re-render
  return <MyContext.Provider value={{ state, setState }}>{children}</MyContext.Provider>;
}

// GOOD — split state and dispatch; memoize value
function MyProvider({ children }) {
  const [state, dispatch] = useReducer(reducer, initialState);
  const stableDispatch = useCallback(dispatch, []); // dispatch is stable, but make intent clear
  const value = useMemo(() => ({ state, dispatch: stableDispatch }), [state, stableDispatch]);
  return <MyContext.Provider value={value}>{children}</MyContext.Provider>;
}
```

---

### Pattern 22 — Global Variables / Singletons Accumulating Data

```tsx
// BAD — Map grows forever, never evicted
const eventCache = new Map<string, EventData>();

function trackEvent(id: string, data: EventData) {
  eventCache.set(id, data); // no cleanup → memory grows without bound
}

// GOOD — bounded LRU map
class LRUMap<K, V> {
  private map = new Map<K, V>();
  constructor(private maxSize: number) {}

  set(key: K, value: V) {
    if (this.map.has(key)) this.map.delete(key);
    if (this.map.size >= this.maxSize) {
      this.map.delete(this.map.keys().next().value);
    }
    this.map.set(key, value);
  }

  get = (key: K) => this.map.get(key);
  has = (key: K) => this.map.has(key);
  clear = () => this.map.clear();
}

const eventCache = new LRUMap<string, EventData>(500);
```

---

### Pattern 23 — Map vs WeakMap for Object-Keyed Caches

```tsx
// BAD — Map keeps strong references; component instances are never GC'd
const styleCache = new Map<object, StyleSheet>();

// GOOD — WeakMap allows GC when key object is no longer referenced
const styleCache = new WeakMap<object, StyleSheet>();

// Rule of thumb:
// - WeakMap: use when key is an object whose lifetime you don't control
// - Map: use when keys are primitives or you explicitly manage eviction
```

---

### Pattern 24 — Third-Party SDK Listeners (Firebase, Analytics, Push)

```tsx
// BAD
useEffect(() => {
  firebase.messaging().onMessage((msg) => handleMessage(msg));
  analytics().logEvent('screen_view', { screen_name: 'Home' });
}, []);

// GOOD
useEffect(() => {
  const unsubscribeMessage = firebase.messaging().onMessage((msg) => handleMessage(msg));
  const unsubscribeToken = firebase.messaging().onTokenRefresh((token) => updateToken(token));
  return () => {
    unsubscribeMessage();
    unsubscribeToken();
  };
}, []);
```

---

### Pattern 25 — Video/Audio Players Not Released

```tsx
// BAD — expo-av Sound object held in ref, never unloaded
useEffect(() => {
  Audio.Sound.createAsync({ uri: audioUrl }).then(({ sound }) => {
    soundRef.current = sound;
    sound.playAsync();
  });
}, []);

// GOOD
useEffect(() => {
  let sound: Audio.Sound | null = null;
  Audio.Sound.createAsync({ uri: audioUrl }).then(({ sound: s }) => {
    sound = s;
    s.playAsync();
  });
  return () => {
    sound?.stopAsync().then(() => sound?.unloadAsync());
  };
}, [audioUrl]);

// For react-native-video — set source to null before unmount
// <Video ref={videoRef} source={isVisible ? { uri } : null} />
```

---

### Pattern 26 — WebView Instances Not Destroyed

```tsx
// BAD — WebView keeps JS context alive even when offscreen
{showWebView && <WebView source={{ uri }} style={{ flex: 1 }} />}

// GOOD — conditionally mount (unmounts and destroys the context)
{showWebView && (
  <WebView
    source={{ uri }}
    onError={() => setShowWebView(false)}
    style={{ flex: 1 }}
  />
)}

// For persistent WebViews: use opacity/display toggling carefully —
// the JS context stays alive, which is intentional but keep refs clean.
const webViewRef = useRef<WebView>(null);
useEffect(() => {
  return () => {
    webViewRef.current = null;
  };
}, []);
```

---

### Pattern 27 — Animated.Value Listeners Not Removed

```tsx
// BAD
useEffect(() => {
  animatedValue.addListener(({ value }) => {
    console.log(value);
  });
}, []);

// GOOD
useEffect(() => {
  const listenerId = animatedValue.addListener(({ value }) => {
    console.log(value);
  });
  return () => animatedValue.removeListener(listenerId);
}, [animatedValue]);

// Or: remove all listeners at once (use carefully in multi-listener scenarios)
return () => animatedValue.removeAllListeners();
```

---

### Pattern 28 — InteractionManager Handles Not Cancelled

```tsx
// BAD
useEffect(() => {
  InteractionManager.runAfterInteractions(() => {
    loadHeavyData(); // runs even if component unmounted mid-transition
  });
}, []);

// GOOD
useEffect(() => {
  const handle = InteractionManager.runAfterInteractions(() => {
    loadHeavyData();
  });
  return () => handle.cancel();
}, []);
```

---

### Pattern 29 — Notification Listeners (expo-notifications / @notifee)

```tsx
// BAD — expo-notifications
useEffect(() => {
  Notifications.addNotificationReceivedListener((notification) => {
    handleNotification(notification);
  });
}, []);

// GOOD — expo-notifications
useEffect(() => {
  const receivedSub = Notifications.addNotificationReceivedListener(handleNotification);
  const responseSub = Notifications.addNotificationResponseReceivedListener(handleResponse);
  return () => {
    receivedSub.remove();
    responseSub.remove();
  };
}, []);

// BAD — @notifee
useEffect(() => {
  notifee.onForegroundEvent(({ type, detail }) => {
    if (type === EventType.PRESS) handlePress(detail);
  });
}, []);

// GOOD — @notifee
useEffect(() => {
  const unsubscribe = notifee.onForegroundEvent(({ type, detail }) => {
    if (type === EventType.PRESS) handlePress(detail);
  });
  return () => unsubscribe();
}, []);
```

---

### Pattern 30 — Refs Pointing to Unmounted Components

```tsx
// BAD — ref used to call methods after component unmounts
const childRef = useRef<ChildComponent>(null);
setTimeout(() => {
  childRef.current?.doSomething(); // component may already be unmounted
}, 5000);

// GOOD — check if still mounted using an isMounted flag
useEffect(() => {
  let isMounted = true;
  const timerId = setTimeout(() => {
    if (isMounted && childRef.current) {
      childRef.current.doSomething();
    }
  }, 5000);
  return () => {
    isMounted = false;
    clearTimeout(timerId);
  };
}, []);
```

---

## 2. Detection Techniques

### Xcode Instruments

**Leaks instrument**
1. Product > Profile (Cmd+I) → select "Leaks"
2. Run the suspect user flow 3-4 times
3. Red bars in the timeline indicate leaked allocations
4. Click a leak to see the allocation backtrace → identify the retained object

**Allocations instrument**
1. Use "Mark Generation" after each screen navigation
2. Compare generation snapshots — objects that survive across marks are candidates
3. Filter by "Created and still living" to isolate growing allocations

**VM Tracker**
- Shows dirty memory split: JS heap, image buffers, native heaps
- Image buffer category growing unbounded → image cache leak
- Useful to distinguish JS vs native memory pressure

### Android Studio Memory Profiler

1. Run > Profile > Memory
2. Navigate through flows, click the GC button between actions
3. Capture heap dump → filter by your package name
4. Look for retained Activity/Fragment/View instances (sign of context leak)
5. Object count growing per navigation cycle → leak

**LeakCanary setup**

```kotlin
// app/build.gradle
dependencies {
  debugImplementation 'com.squareup.leakcanary:leakcanary-android:2.13'
}
// No other code needed — LeakCanary auto-installs via ContentProvider
```

LeakCanary will display a notification with a full reference chain when it detects a leak. The chain shows exactly which object is holding the reference preventing GC.

### React Native DevTools Memory Tab

1. Open DevTools (shake device → Open DevTools, or `npx react-devtools`)
2. Switch to the "Memory" tab
3. Take a heap snapshot before a flow
4. Execute the flow (navigate to screen, then back)
5. Take another snapshot
6. Use "Comparison" view — look for objects with positive delta that are component instances

### Hermes Heap Snapshots

```bash
# Trigger snapshot via Metro / ADB
adb shell "curl http://localhost:8081/json" # check debugger endpoint

# Programmatic snapshot (in __DEV__ code)
if (global.HermesInternal) {
  // Trigger via Chrome DevTools connected to Hermes
  // chrome://inspect → select Hermes device → Memory tab → Take snapshot
}
```

**Comparing snapshots:**
1. Take baseline snapshot (Snapshot 1)
2. Execute the suspect operation
3. Take second snapshot (Snapshot 2)
4. In DevTools: select "Snapshot 2" → change view to "Comparison"
5. Sort by "# Delta" descending — objects with large positive delta are leak candidates
6. Click any object class to see retaining paths

### Custom Memory Monitor Hook

```tsx
import { useEffect, useRef, useCallback } from 'react';
import { Platform, NativeModules } from 'react-native';

interface MemoryStats {
  jsHeapUsed?: number;    // bytes
  jsHeapTotal?: number;
  nativeMemory?: number;
}

function getJsMemory(): MemoryStats {
  // Available in Chrome debug mode and Hermes
  if (typeof performance !== 'undefined' && (performance as any).memory) {
    const m = (performance as any).memory;
    return { jsHeapUsed: m.usedJSHeapSize, jsHeapTotal: m.totalJSHeapSize };
  }
  return {};
}

export function useMemoryMonitor(
  label: string,
  intervalMs = 5000,
  enabled = __DEV__
) {
  const baseline = useRef<number | null>(null);

  const sample = useCallback(() => {
    const stats = getJsMemory();
    if (stats.jsHeapUsed !== undefined) {
      baseline.current ??= stats.jsHeapUsed;
      const deltaMB = (stats.jsHeapUsed - baseline.current) / 1024 / 1024;
      const usedMB = stats.jsHeapUsed / 1024 / 1024;
      if (__DEV__) {
        console.log(`[Memory:${label}] used=${usedMB.toFixed(1)}MB delta=+${deltaMB.toFixed(1)}MB`);
        if (deltaMB > 50) {
          console.warn(`[Memory:${label}] LEAK SUSPECTED — delta exceeded 50 MB`);
        }
      }
    }
  }, [label]);

  useEffect(() => {
    if (!enabled) return;
    sample(); // immediate baseline
    const id = setInterval(sample, intervalMs);
    return () => clearInterval(id);
  }, [enabled, intervalMs, sample]);
}

// Usage
function MyScreen() {
  useMemoryMonitor('MyScreen');
  // ...
}
```

### Production Monitoring with Sentry

```tsx
import * as Sentry from '@sentry/react-native';

// Breadcrumb on memory warning
import { AppState } from 'react-native';

AppState.addEventListener('memoryWarning', () => {
  Sentry.addBreadcrumb({
    category: 'memory',
    message: 'Low memory warning received',
    level: 'warning',
  });
  Sentry.captureMessage('Memory warning', 'warning');
});

// Custom measurement in transactions
const transaction = Sentry.startTransaction({ name: 'ProductList.load' });
// ... load data ...
const stats = getJsMemory();
if (stats.jsHeapUsed) {
  transaction.setMeasurement('js_heap_mb', stats.jsHeapUsed / 1024 / 1024, 'megabyte');
}
transaction.finish();
```

---

## 3. Fix Patterns (Utilities)

### Universal Cleanup Hook

```tsx
import { useEffect, useRef } from 'react';

type Cleanup = () => void;

export function useCleanup() {
  const cleanups = useRef<Cleanup[]>([]);

  const register = (cleanup: Cleanup) => {
    cleanups.current.push(cleanup);
  };

  useEffect(() => {
    return () => {
      cleanups.current.forEach((fn) => fn());
      cleanups.current = [];
    };
  }, []);

  return { register };
}

// Usage
function MyScreen() {
  const { register } = useCleanup();

  useEffect(() => {
    const sub = AppState.addEventListener('change', handleChange);
    register(() => sub.remove());

    const timerId = setInterval(poll, 3000);
    register(() => clearInterval(timerId));

    const ws = new WebSocket(WS_URL);
    register(() => ws.close());
  }, []);
}
```

### Subscription Manager Utility

```tsx
class SubscriptionManager {
  private cleanups: Array<() => void> = [];

  add(cleanup: () => void): this {
    this.cleanups.push(cleanup);
    return this;
  }

  addEventEmitter(emitter: { remove(): void }): this {
    return this.add(() => emitter.remove());
  }

  addTimer(id: ReturnType<typeof setTimeout | typeof setInterval>, type: 'timeout' | 'interval'): this {
    return this.add(() =>
      type === 'timeout' ? clearTimeout(id) : clearInterval(id as ReturnType<typeof setInterval>)
    );
  }

  cleanup(): void {
    this.cleanups.forEach((fn) => fn());
    this.cleanups = [];
  }
}

// Usage in a class-based service or hook
function useSubscriptionManager() {
  const managerRef = useRef(new SubscriptionManager());
  useEffect(() => () => managerRef.current.cleanup(), []);
  return managerRef.current;
}
```

### Memory-Safe Event Emitter

```tsx
import EventEmitter from 'eventemitter3';

class SafeEventEmitter extends EventEmitter {
  private listenerCounts = new Map<string, number>();
  private readonly MAX_LISTENERS = 20;

  on(event: string, fn: (...args: any[]) => void, context?: any) {
    const count = this.listenerCount(event);
    if (count >= this.MAX_LISTENERS) {
      console.warn(`[SafeEventEmitter] Max listeners (${this.MAX_LISTENERS}) reached for event "${event}"`);
    }
    return super.on(event, fn, context);
  }

  // Returns a cleanup function for easy useEffect integration
  subscribe(event: string, fn: (...args: any[]) => void): () => void {
    this.on(event, fn);
    return () => this.off(event, fn);
  }
}

export const appEvents = new SafeEventEmitter();

// Usage
useEffect(() => {
  const unsub = appEvents.subscribe('userLoggedOut', handleLogout);
  return () => unsub();
}, []);
```

### LRU Cache with TTL Eviction

```tsx
interface CacheEntry<V> {
  value: V;
  expiresAt: number;
}

export class LRUCache<K, V> {
  private cache = new Map<K, CacheEntry<V>>();

  constructor(
    private maxSize: number,
    private ttlMs: number = 5 * 60 * 1000 // 5 minutes default
  ) {}

  set(key: K, value: V): void {
    if (this.cache.has(key)) this.cache.delete(key);
    if (this.cache.size >= this.maxSize) {
      this.cache.delete(this.cache.keys().next().value);
    }
    this.cache.set(key, { value, expiresAt: Date.now() + this.ttlMs });
  }

  get(key: K): V | undefined {
    const entry = this.cache.get(key);
    if (!entry) return undefined;
    if (Date.now() > entry.expiresAt) {
      this.cache.delete(key);
      return undefined;
    }
    // Refresh position (LRU touch)
    this.cache.delete(key);
    this.cache.set(key, entry);
    return entry.value;
  }

  evictExpired(): void {
    const now = Date.now();
    for (const [key, entry] of this.cache.entries()) {
      if (now > entry.expiresAt) this.cache.delete(key);
    }
  }

  get size() { return this.cache.size; }
  clear() { this.cache.clear(); }
}

// Singleton usage
export const apiResponseCache = new LRUCache<string, unknown>(200, 10 * 60 * 1000);
```

### Image Cache Management

```tsx
import { clearMemoryCache, clearDiskCache } from 'expo-image';
import { AppState, AppStateStatus } from 'react-native';

class ImageCacheManager {
  private lastClearAt = 0;
  private readonly CLEAR_INTERVAL_MS = 10 * 60 * 1000; // 10 min

  setup() {
    const sub = AppState.addEventListener('change', this.handleAppState);
    return () => sub.remove();
  }

  private handleAppState = (nextState: AppStateStatus) => {
    if (nextState === 'background') {
      this.clearMemoryIfStale();
    }
  };

  private clearMemoryIfStale() {
    const now = Date.now();
    if (now - this.lastClearAt > this.CLEAR_INTERVAL_MS) {
      clearMemoryCache();
      this.lastClearAt = now;
    }
  }

  async handleLowMemory() {
    await clearMemoryCache();
  }
}

export const imageCacheManager = new ImageCacheManager();
```

### Proper Singleton with Cleanup

```tsx
// BAD — singleton with no way to release resources
class DataService {
  private static instance: DataService;
  private ws = new WebSocket(WS_URL);

  static getInstance() {
    if (!DataService.instance) DataService.instance = new DataService();
    return DataService.instance;
  }
}

// GOOD — singleton with explicit lifecycle
class DataService {
  private static instance: DataService | null = null;
  private ws: WebSocket | null = null;

  static getInstance(): DataService {
    DataService.instance ??= new DataService();
    return DataService.instance;
  }

  connect() {
    this.ws = new WebSocket(WS_URL);
  }

  destroy() {
    this.ws?.close();
    this.ws = null;
    DataService.instance = null;
  }
}
```

---

## 4. Advanced Memory Optimization

### Hermes GC Architecture

Hermes uses a **generational garbage collector (GenGC)** with two main spaces:

- **Young generation (nursery)**: Short-lived allocations. Fast minor GC — survivors promoted to old gen.
- **Old generation**: Long-lived objects. Full GC is expensive (~50-200ms on low-end devices).

**Key implications for RN code:**
- Allocating large objects in render paths forces frequent full GC cycles.
- Avoid creating new arrays/objects inside `useAnimatedStyle` worklets — they run on the UI thread and allocate into the Hermes heap on the JS thread during reconciliation.
- Keep closures small — large closures promote to old gen and increase full GC cost.

### Native Memory vs JS Heap Memory

These are **separate budgets**. A crash can happen even if JS heap looks healthy:

| Memory Space | What Lives There | Budget |
|---|---|---|
| JS Heap | JS objects, React tree, Zustand store | 50–200 MB |
| Native Heap | Native modules, SQLite, MMKV | 20–100 MB |
| Graphics / GPU | Decoded image bitmaps, textures, OpenGL buffers | 50–300 MB |
| Anonymous mmap | Hermes bytecode, shared libs | 30–80 MB |

**Image bitmaps are the most common surprise.** A 4K image decoded into ARGB_8888 uses `4 × width × height` bytes in the graphics memory space — completely invisible to the JS heap profiler.

### Android Bitmap Optimization

```kotlin
// In a custom native module or Glide configuration
val options = BitmapFactory.Options().apply {
  inSampleSize = calculateInSampleSize(options, targetWidth, targetHeight)
  inPreferredConfig = Bitmap.Config.RGB_565 // 2 bytes/px vs 4 bytes for ARGB_8888
}
val bitmap = BitmapFactory.decodeFile(path, options)
```

On the JS side, specify explicit dimensions to prevent full-resolution decodes:
```tsx
<Image source={{ uri }} width={100} height={100} /> // signals decode at 100x100
```

### iOS Autorelease Pool

Objective-C objects created in a tight loop (e.g., processing many images in a native module) accumulate in the autorelease pool until the run loop drains it. For long native operations, wrap in an explicit `@autoreleasepool {}` block to drain early and avoid memory spikes.

### Memory Pressure Handlers

```tsx
// iOS: MemoryWarning → clear non-essential caches
useEffect(() => {
  const sub = AppState.addEventListener('memoryWarning', () => {
    imageCache.clearMemory();
    apiResponseCache.clear();
    queryClient.clear(); // or removeQueries for non-active
  });
  return () => sub.remove();
}, []);
```

```kotlin
// Android: onTrimMemory levels (in MainApplication.kt or custom module)
override fun onTrimMemory(level: Int) {
  super.onTrimMemory(level)
  when {
    level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL -> {
      // App is running, system is critically low — clear everything non-essential
      Glide.get(this).clearMemory()
    }
    level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW -> {
      // App is running, system is moderately low — clear soft caches
    }
    level == ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN -> {
      // App moved to background — good time to clear UI caches
      Glide.get(this).clearMemory()
    }
  }
}
```

### Large List Memory: FlashList and Virtualization

FlashList achieves lower memory than FlatList by **recycling cell views** rather than creating new ones. Key settings:

```tsx
<FlashList
  data={items}
  estimatedItemSize={80}        // must be accurate to minimize recycler pool size
  drawDistance={200}            // pixels rendered outside viewport (default 250)
  overrideItemLayout={(layout, item) => {
    layout.size = item.imageHeight + 32; // avoids layout recalculation
  }}
/>
```

Lower `drawDistance` reduces memory at the cost of more blank frames during fast scrolling. Target 150-250px for typical feeds.

### Offscreen Component Memory: react-freeze and react-native-screens

`react-freeze` suspends rendering of off-screen components without unmounting them:

```tsx
import { Freeze } from 'react-freeze';

function TabNavigator() {
  return (
    <Tab.Navigator>
      <Tab.Screen name="Home" component={() => (
        <Freeze freeze={activeTab !== 'Home'}>
          <HomeScreen />
        </Freeze>
      )} />
    </Tab.Navigator>
  );
}
```

`react-native-screens` with `freezeOnBlur` achieves similar results for native stack screens:
```tsx
<Stack.Screen options={{ freezeOnBlur: true }} />
```

These keep the component tree in memory (preserving scroll position, state) while halting React reconciliation, reducing CPU and GC pressure.

---

## 5. Memory Budgets

| Device RAM | JS Heap Target | Image Cache | Total App Target |
|---|---|---|---|
| 1–2 GB (low-end Android) | < 50 MB | < 30 MB | < 120 MB |
| 3–4 GB (mid-range) | < 100 MB | < 80 MB | < 250 MB |
| 6+ GB (flagship) | < 200 MB | < 200 MB | < 500 MB |

### Per-Screen Targets

| Screen Type | Peak Memory Delta | Acceptable Retained After Pop |
|---|---|---|
| Simple form / settings | +5–10 MB | < 1 MB |
| Feed / list (50 items) | +20–40 MB | < 5 MB |
| Camera / AR | +50–100 MB | < 10 MB |
| Video player | +60–120 MB | < 5 MB |
| Map screen | +30–60 MB | < 5 MB |

### Background vs Foreground Limits

- **Foreground**: Full budget per table above.
- **Background (iOS)**: App can be killed at any time. Reduce to ≤ 50 MB total where possible; iOS may terminate apps exceeding ~200 MB while backgrounded.
- **Background (Android)**: System calls `onTrimMemory` progressively. Apps that release memory on `TRIM_MEMORY_UI_HIDDEN` are much less likely to be killed.

---

## 6. Common Senior-Level Mistakes

### Over-Memoization Causes More Memory

```tsx
// BAD — memoizing a trivial value costs MORE memory (closure + cache entry)
const label = useMemo(() => `Hello ${name}`, [name]); // pointless, string concat is fast

// GOOD — no memo for cheap derivations
const label = `Hello ${name}`;

// Memo is worth it when: expensive computation OR stable reference prevents child re-render
const expensiveData = useMemo(() => processLargeDataset(rawData), [rawData]);
```

### Keeping Entire API Responses in State

```tsx
// BAD — 200KB response stored in state; re-renders pass it everywhere
const [response, setResponse] = useState<ApiResponse | null>(null);

// GOOD — select only what the UI needs
const [userSummary, setUserSummary] = useState<UserSummary | null>(null);

fetch('/api/user/full').then((r) => r.json()).then((data) => {
  setUserSummary({
    id: data.id,
    name: data.name,
    avatarUrl: data.avatarUrl,
  });
});
```

### Not Paginating Data

```tsx
// BAD — loads all 10,000 items into state
const { data: allItems } = useQuery({ queryKey: ['items'], queryFn: () => fetchAllItems() });

// GOOD — paginated with TanStack Query's useInfiniteQuery
const { data, fetchNextPage, hasNextPage } = useInfiniteQuery({
  queryKey: ['items'],
  queryFn: ({ pageParam = 0 }) => fetchItems({ offset: pageParam, limit: 20 }),
  getNextPageParam: (lastPage, pages) => lastPage.nextOffset,
});
```

### Caching Without Eviction

```tsx
// BAD — grows forever
const cache: Record<string, unknown> = {};

// GOOD — bounded with TTL (see LRUCache utility above)
const cache = new LRUCache<string, unknown>(200, 5 * 60 * 1000);
```

### Closures in Loops

```tsx
// BAD — all handlers share the last value of `item`
items.forEach((item) => {
  handlers.push(() => console.log(item.id));
});

// GOOD — each closure captures its own binding (already correct in forEach with const)
// But with var or for-loop:
for (var i = 0; i < items.length; i++) {
  // BAD: var leaks scope
  handlers.push(() => console.log(items[i])); // always logs last item
}
for (let i = 0; i < items.length; i++) {
  // GOOD: let has block scope — each iteration has its own `i`
  handlers.push(() => console.log(items[i]));
}
```

### Storing Derived Data Instead of Computing

```tsx
// BAD — keeping both source and derived in state; source of truth diverges
const [users, setUsers] = useState<User[]>([]);
const [activeUsers, setActiveUsers] = useState<User[]>([]);

// GOOD — compute derived data during render (or useMemo for expensive cases)
const [users, setUsers] = useState<User[]>([]);
const activeUsers = useMemo(() => users.filter((u) => u.isActive), [users]);
```

### Forgetting Native Memory for Images and Videos

A 4K photo (`3840 × 2160`) in `ARGB_8888` = **31.6 MB** of decoded bitmap memory — completely separate from the JS heap. Displaying 10 such images simultaneously = 316 MB of native graphics memory before the JS heap even registers a change.

Always decode images at display size using `width`/`height` props or `resizeMode`, and use `expo-image`'s built-in caching with a `cachePolicy` that evicts on memory pressure.

---

## 7. MMKV vs AsyncStorage

### Performance Comparison

| Operation | MMKV | AsyncStorage | Ratio |
|---|---|---|---|
| Write (string) | ~0.3 ms | ~1.5 ms | ~5× faster |
| Read (string) | ~0.01 ms | ~0.2 ms | ~20× faster |
| Write (large object JSON) | ~1 ms | ~6 ms | ~6× faster |
| Synchronous API | Yes (JSI) | No (bridge) | — |
| Encryption | Yes (AES-256) | No | — |
| Bundle size impact | +200 KB native | ~0 KB native | — |

### When to Use MMKV

- Auth tokens, session data, user preferences (read on every app launch — synchronous is critical)
- Feature flags polled frequently
- Any key-value data read more than once per second

### When AsyncStorage Is Acceptable

- Write-once / read-rarely data (onboarding completion flag, app version)
- Projects where native module overhead outweighs benefit
- Expo Go development without custom dev client

### Migration Pattern

```tsx
import { MMKV } from 'react-native-mmkv';
import AsyncStorage from '@react-native-async-storage/async-storage';

const storage = new MMKV();

async function migrateAsyncStorageToMMKV() {
  const keys = await AsyncStorage.getAllKeys();
  if (!keys.length) return;

  const pairs = await AsyncStorage.multiGet(keys);
  pairs.forEach(([key, value]) => {
    if (value !== null) storage.set(key, value);
  });

  await AsyncStorage.multiRemove(keys);
  console.log(`Migrated ${keys.length} keys from AsyncStorage to MMKV`);
}

// Run once at app startup:
// storage.getBoolean('mmkv_migrated') || (await migrateAsyncStorageToMMKV(), storage.set('mmkv_migrated', true));
```

### MMKV Storage Hook Pattern

```tsx
import { MMKV } from 'react-native-mmkv';
import { useCallback, useState } from 'react';

const storage = new MMKV();

export function useMMKVString(key: string, defaultValue = '') {
  const [value, setValue] = useState(() => storage.getString(key) ?? defaultValue);

  const set = useCallback((newValue: string) => {
    storage.set(key, newValue);
    setValue(newValue);
  }, [key]);

  const remove = useCallback(() => {
    storage.delete(key);
    setValue(defaultValue);
  }, [key, defaultValue]);

  return [value, set, remove] as const;
}
```

---

## 8. Native Module Memory Leaks

JS-side cleanup patterns (Patterns 1–30 above) only address the JS heap. Native modules maintain their own object graphs on iOS and Android. Leaks there are invisible to the Hermes profiler.

### iOS — ARC Retain Cycles

ARC (Automatic Reference Counting) frees objects when their retain count hits zero. Cycles prevent this.

**Delegate retain cycle**

```objc
// BAD — RCTBridgeModule holds a strong reference to a delegate that holds the module
@interface DataModule : NSObject <RCTBridgeModule, DataServiceDelegate>
@property (nonatomic, strong) DataService *service; // strong
@end

@implementation DataModule
- (void)setup {
  self.service = [[DataService alloc] init];
  self.service.delegate = self; // DataService.delegate is strong → cycle
}
@end

// GOOD — delegate property declared weak
// In DataService.h:
@property (nonatomic, weak) id<DataServiceDelegate> delegate;
```

**Block capture cycle**

```objc
// BAD — block captures self strongly; self holds the block
self.completionBlock = ^{
  [self doSomething]; // retains self → cycle
};

// GOOD — weakify before capture
__weak typeof(self) weakSelf = self;
self.completionBlock = ^{
  __strong typeof(weakSelf) strongSelf = weakSelf;
  [strongSelf doSomething];
};
```

**NSTimer retain cycle**

`NSTimer` retains its target strongly. If the timer is stored on `self` and targets `self`, the cycle keeps both alive.

```objc
// BAD
self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                             target:self
                                           selector:@selector(tick)
                                           userInfo:nil
                                            repeats:YES];

// GOOD — use a block-based timer (iOS 10+) with a weak capture
__weak typeof(self) weakSelf = self;
self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                            repeats:YES
                                              block:^(NSTimer *t) {
  [weakSelf tick];
}];

// Always invalidate before release (e.g., in invalidate / dealloc)
- (void)invalidate {
  [self.timer invalidate];
  self.timer = nil;
}
```

**Expose `invalidate` to JS so RN can call it on unmount**

```objc
RCT_EXPORT_METHOD(stopUpdates) {
  [self.timer invalidate];
  self.timer = nil;
}
```

```tsx
// JS side
useEffect(() => {
  MyNativeModule.startUpdates();
  return () => MyNativeModule.stopUpdates();
}, []);
```

### Android — JNI Reference Leaks

JNI functions return **local references** that are valid only within the native call frame. Storing them beyond that frame is undefined behaviour.

```cpp
// BAD — storing a local ref in a global field
static jobject gCallback; // dangling after the JNI call returns

JNIEXPORT void JNICALL Java_com_example_MyModule_setCallback(
    JNIEnv *env, jobject thiz, jobject callback) {
  gCallback = callback; // local ref — invalid outside this frame
}

// GOOD — promote to global ref, and delete when no longer needed
JNIEXPORT void JNICALL Java_com_example_MyModule_setCallback(
    JNIEnv *env, jobject thiz, jobject callback) {
  if (gCallback != nullptr) {
    env->DeleteGlobalRef(gCallback); // release previous
  }
  gCallback = env->NewGlobalRef(callback); // promotes to global
}

// When the module is torn down:
void releaseCallback(JNIEnv *env) {
  if (gCallback != nullptr) {
    env->DeleteGlobalRef(gCallback);
    gCallback = nullptr;
  }
}
```

**WeakReference pattern for Activity/Context**

Native modules that hold a `Context` or `Activity` reference must use `WeakReference` to avoid preventing GC after the screen is destroyed.

```kotlin
// BAD — strong reference keeps Activity alive after finish()
class DataModule(private val activity: Activity) : ReactContextBaseJavaModule()

// GOOD
class DataModule(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

  // currentActivity is already a weak-ref accessor via ReactContext
  private fun doWork() {
    val activity = currentActivity ?: return // null-safe, no leak
    // use activity
  }
}
```

### Profiling Native Memory Independent of the JS Heap

The JS heap profiler (Hermes, Chrome DevTools) shows **only JS allocations**. Use platform tools to see native memory:

| Tool | Platform | What it shows |
|---|---|---|
| Xcode Instruments → Allocations | iOS | Obj-C/Swift heap, malloc blocks |
| Xcode Instruments → VM Tracker | iOS | Dirty memory per region (image buffers, native heap) |
| Android Studio Profiler → Native Heap | Android API 29+ | C/C++ allocations |
| `adb shell dumpsys meminfo <package>` | Android | PSS breakdown: Java heap, native heap, graphics |

**Reading `dumpsys meminfo` output**

```
MEMINFO in pid 12345 [com.myapp]:
                   Pss  Private  Private  SwapPss     Heap     Heap     Heap
                 Total    Dirty    Clean    Dirty     Size    Alloc     Free
                ------   ------   ------   ------   ------   ------   ------
  Native Heap   45231    45100      128      400    60000    44800    15200
  Dalvik Heap   18432    18000      200      100    32000    18200    13800
  ...
  Graphics      23000    23000        0        0        0        0        0
```

- **Native Heap Private Dirty** growing across navigation cycles = C++/JNI leak.
- **Graphics** growing = image bitmap or texture leak.
- These are invisible to the JS heap profiler.

---

## 9. WeakRef and FinalizationRegistry

### Hermes Support Status

| Feature | Hermes ≥ 0.11 (RN 0.71+) | JSC | V8 |
|---|---|---|---|
| `WeakRef` | Supported | Supported | Supported |
| `FinalizationRegistry` | Supported | Supported | Supported |

Both are part of the ES2021 spec. They are available in production Hermes builds (not just `__DEV__`). However, GC timing is non-deterministic — `FinalizationRegistry` callbacks run at some point after the object becomes unreachable, not immediately.

### WeakRef for Cache Patterns

`WeakRef` lets you hold a reference to an object without preventing its GC. Use it for object-keyed caches where you want entries to evict themselves when the key object is no longer needed.

```tsx
// BAD — Map keeps expensive parsed objects alive indefinitely
const parsedSchemaCache = new Map<object, ParsedSchema>();

function getSchema(raw: object): ParsedSchema {
  if (parsedSchemaCache.has(raw)) return parsedSchemaCache.get(raw)!;
  const parsed = expensiveParse(raw);
  parsedSchemaCache.set(raw, parsed); // raw is never GC'd — Map holds it
  return parsed;
}

// GOOD — WeakRef cache: entry disappears when `raw` is GC'd
const parsedSchemaCache = new WeakMap<object, WeakRef<ParsedSchema>>();

function getSchema(raw: object): ParsedSchema {
  const ref = parsedSchemaCache.get(raw);
  const cached = ref?.deref();
  if (cached) return cached;

  const parsed = expensiveParse(raw);
  parsedSchemaCache.set(raw, new WeakRef(parsed));
  return parsed;
}
```

### FinalizationRegistry for Resource Cleanup

`FinalizationRegistry` registers a callback that fires when a target object is GC'd. Use it as a safety net, not a primary cleanup strategy — always call explicit cleanup first.

```tsx
// Safety-net pattern: detect forgotten cleanups in dev
const registry = new FinalizationRegistry((label: string) => {
  if (__DEV__) {
    console.warn(`[FinalizationRegistry] "${label}" was GC'd without explicit cleanup`);
  }
});

class AudioPlayer {
  private sound: Audio.Sound | null = null;
  private readonly label: string;

  constructor(uri: string, label: string) {
    this.label = label;
    registry.register(this, label); // watch this instance
    Audio.Sound.createAsync({ uri }).then(({ sound }) => {
      this.sound = sound;
    });
  }

  async destroy() {
    await this.sound?.stopAsync();
    await this.sound?.unloadAsync();
    this.sound = null;
    // Note: no way to unregister from FinalizationRegistry without holding the token
  }
}
```

**Holding the token for unregistration**

```tsx
const registry = new FinalizationRegistry((id: string) => {
  resourceMap.delete(id);
});

class ManagedResource {
  private token: object; // opaque token returned by register

  constructor(readonly id: string) {
    this.token = {}; // any object works as a token
    registry.register(this, id, this.token);
  }

  dispose() {
    registry.unregister(this.token); // cancel the callback — resource released explicitly
    cleanup(this.id);
  }
}
```

### WeakRef-Based Cache with Cleanup Hook

```tsx
type WeakCache<V extends object> = {
  get: (key: string) => V | undefined;
  set: (key: string, value: V) => void;
  size: () => number;
};

function createWeakCache<V extends object>(
  onEvict?: (key: string) => void
): WeakCache<V> {
  const map = new Map<string, WeakRef<V>>();

  const registry = new FinalizationRegistry((key: string) => {
    map.delete(key);
    onEvict?.(key);
  });

  return {
    get(key) {
      const ref = map.get(key);
      if (!ref) return undefined;
      const value = ref.deref();
      if (!value) {
        map.delete(key); // stale entry — ref already GC'd
        return undefined;
      }
      return value;
    },
    set(key, value) {
      map.set(key, new WeakRef(value));
      registry.register(value, key);
    },
    size: () => map.size,
  };
}

// Usage
const componentCache = createWeakCache<ParsedComponent>((key) => {
  if (__DEV__) console.log(`[WeakCache] evicted: ${key}`);
});
```

---

## 10. WebView Memory Management

### WebView JS Context Lifetime

Each `<WebView>` instance creates a separate JS context (WKWebView on iOS, a WebView/Custom Tab on Android). The context lives as long as the component is mounted, regardless of whether it is visible. Three `<WebView>` components = three independent JS engines in memory simultaneously.

```
Mounted WebView → WKWebView process (iOS) → separate memory space
                                           ↑ NOT included in your app's Hermes heap
```

On iOS, WKWebView runs in a separate process. Its memory is counted against **your app's total memory budget** by the OS (jetsam), but does not appear in the JS heap profiler. On Android, `android.webkit.WebView` runs in-process.

### Communication Bridge Cleanup

`postMessage` listeners and injected JavaScript callbacks must be torn down on unmount. Stale callbacks can keep closures alive after the WebView is gone.

```tsx
// BAD — onMessage callback captures stale component state via closure
function PaymentScreen() {
  const [status, setStatus] = useState<'idle' | 'paid'>('idle');

  return (
    <WebView
      source={{ uri: PAYMENT_URL }}
      onMessage={(event) => {
        // If this fires after unmount, setStatus is called on a dead component
        const msg = JSON.parse(event.nativeEvent.data);
        if (msg.type === 'payment_complete') setStatus('paid');
      }}
    />
  );
}

// GOOD — use a stable ref-based handler; null it on unmount
function PaymentScreen() {
  const [status, setStatus] = useState<'idle' | 'paid'>('idle');
  const webViewRef = useRef<WebView>(null);
  const isMountedRef = useRef(true);

  useEffect(() => {
    return () => {
      isMountedRef.current = false;
      webViewRef.current = null;
    };
  }, []);

  const handleMessage = useCallback((event: WebViewMessageEvent) => {
    if (!isMountedRef.current) return;
    const msg = JSON.parse(event.nativeEvent.data);
    if (msg.type === 'payment_complete') setStatus('paid');
  }, []);

  return (
    <WebView
      ref={webViewRef}
      source={{ uri: PAYMENT_URL }}
      onMessage={handleMessage}
    />
  );
}
```

### Multiple WebView Instances Anti-Pattern

```tsx
// BAD — tab bar renders all three WebViews simultaneously
function BrowserTabs() {
  return (
    <View>
      <WebView source={{ uri: urls[0] }} style={activeTab === 0 ? styles.visible : styles.hidden} />
      <WebView source={{ uri: urls[1] }} style={activeTab === 1 ? styles.visible : styles.hidden} />
      <WebView source={{ uri: urls[2] }} style={activeTab === 2 ? styles.visible : styles.hidden} />
    </View>
  );
  // All three contexts are alive — 3× memory cost
}

// GOOD option A — unmount inactive tabs (loses JS state but frees memory)
function BrowserTabs() {
  return (
    <View>
      {activeTab === 0 && <WebView source={{ uri: urls[0] }} />}
      {activeTab === 1 && <WebView source={{ uri: urls[1] }} />}
      {activeTab === 2 && <WebView source={{ uri: urls[2] }} />}
    </View>
  );
}

// GOOD option B — keep one WebView, swap source URL (single context, sequential load)
function BrowserTabs() {
  const webViewRef = useRef<WebView>(null);
  return (
    <WebView
      ref={webViewRef}
      source={{ uri: urls[activeTab] }}
    />
  );
}
```

### Hardware Acceleration Memory Cost

On Android, hardware-accelerated WebViews allocate GPU texture layers. Every composited layer occupies GPU memory proportional to its pixel area.

```tsx
// Reduce compositing cost: avoid CSS transforms/animations inside WebView content
// where possible, and disable hardware acceleration for simple static content:

// In AndroidManifest.xml for the WebView activity:
// android:hardwareAccelerated="false"  ← only for known-static content

// Or programmatically in a native module:
// webView.setLayerType(View.LAYER_TYPE_SOFTWARE, null)
```

For content-heavy WebViews (maps, charts), hardware acceleration is necessary — monitor GPU memory with Android Studio Profiler → Memory → Graphics category.

### Proper Cleanup on Unmount

```tsx
function useWebViewCleanup(webViewRef: React.RefObject<WebView>) {
  useEffect(() => {
    return () => {
      if (!webViewRef.current) return;

      // Stop any running loads
      webViewRef.current.stopLoading();

      // Inject JS to cancel pending async work inside the WebView context
      webViewRef.current.injectJavaScript(`
        if (window._cleanup) window._cleanup();
        true; // required for injectJavaScript
      `);

      // Null the ref so callbacks can check mount status
      (webViewRef as React.MutableRefObject<WebView | null>).current = null;
    };
  }, [webViewRef]);
}

// Usage
function EmbeddedMap() {
  const webViewRef = useRef<WebView>(null);
  useWebViewCleanup(webViewRef);

  return <WebView ref={webViewRef} source={{ uri: MAP_URL }} />;
}
```

---

## 11. Image Memory Deep Dive

### Decoded Bitmap Memory Formula

The decoded size of an image in memory has nothing to do with the file size (JPEG/PNG compression). Once decoded:

```
Decoded memory (ARGB_8888) = 4 bytes × width (px) × height (px)

Examples:
  1080 × 1920  (Full HD)    =   8.3 MB
  2048 × 2048  (thumbnail)  =  16.8 MB
  3840 × 2160  (4K)         =  31.6 MB
  4032 × 3024  (iPhone 14)  =  46.3 MB
```

Every image you display at full resolution contributes this amount to **native graphics memory**, not the JS heap.

### RGB_565 vs ARGB_8888

| Format | Bytes/pixel | Alpha channel | Use case |
|---|---|---|---|
| `ARGB_8888` | 4 | Yes (full) | Default; photos, icons with transparency |
| `RGB_565` | 2 | No | Opaque images where 50% memory saving matters more than color fidelity |

```kotlin
// Android: decode at RGB_565 for opaque images (native module / Glide config)
val options = BitmapFactory.Options().apply {
  inPreferredConfig = Bitmap.Config.RGB_565
}
val bitmap = BitmapFactory.decodeFile(path, options)
// Memory: 1080×1920 × 2 bytes = 4.1 MB vs 8.3 MB for ARGB_8888
```

```tsx
// expo-image: no direct pixel format control — rely on downsampling instead
<Image
  source={{ uri }}
  width={displayWidth}   // decode at display size, not original size
  height={displayHeight}
  contentFit="cover"
/>
```

### Streaming Decode vs Full-Resolution Buffer

Full-resolution decode loads the entire bitmap into memory before the first pixel is displayed. Streaming (progressive) decode renders incrementally, showing a blurry low-res pass first.

```tsx
// expo-image uses streaming/progressive decode automatically for JPEG
// Force a placeholder while the full image loads to prevent layout shift:
<Image
  source={{ uri: highResUri }}
  placeholder={{ uri: blurHashUri }} // tiny blurhash, ~30 bytes
  transition={200}
  width={300}
  height={200}
/>
```

On Android with Glide, streaming is enabled by default via `diskCacheStrategy(DiskCacheStrategy.DATA)` — it caches the original compressed bytes and decodes on demand rather than caching the full bitmap.

### Image Pooling in Glide / Fresco / expo-image

Rather than allocating new `Bitmap` objects for each decode, these libraries maintain a **bitmap pool** — a fixed set of reusable buffers sized by pixel dimensions. When a bitmap is no longer displayed, it returns to the pool instead of being freed and re-allocated.

```
Without pooling:  decode → allocate 8 MB → display → GC → allocate 8 MB → ...
With pooling:     decode → allocate 8 MB → display → return to pool → reuse 8 MB → ...
```

Pool size is bounded. Configure Glide's pool in a `GlideModule`:

```kotlin
@GlideModule
class MyGlideModule : AppGlideModule() {
  override fun applyOptions(context: Context, builder: GlideBuilder) {
    val memoryCacheSizeBytes = 1024 * 1024 * 40 // 40 MB total memory cache
    builder.setMemoryCache(LruResourceCache(memoryCacheSizeBytes.toLong()))
    builder.setBitmapPool(LruBitmapPool(memoryCacheSizeBytes.toLong()))
  }
}
```

### Memory Pressure — Automatic Cache Clear

Both Glide and expo-image respond to system memory pressure signals:

- **iOS**: `UIApplicationDidReceiveMemoryWarningNotification` → expo-image clears its in-memory cache tier.
- **Android**: `onTrimMemory(TRIM_MEMORY_RUNNING_CRITICAL)` → Glide clears its bitmap pool and memory cache.

You can also trigger this manually:

```tsx
import { clearMemoryCache } from 'expo-image';
import { AppState } from 'react-native';

useEffect(() => {
  const sub = AppState.addEventListener('memoryWarning', async () => {
    await clearMemoryCache();
    // disk cache is preserved — images reload from disk, not network
  });
  return () => sub.remove();
}, []);
```

---

## 12. Memory Profiling Tools Deep Dive

### Xcode Instruments

**Step 1 — Launch with Instruments**

```
Xcode → Product → Profile (Cmd+I) → Choose template
```

Use a **release build** for accurate numbers — debug builds include extra overhead.

**Allocations instrument**

1. Select the "Allocations" template.
2. Run the app. Click "Mark Generation" (the flag button) at the start of a flow.
3. Navigate through the screen, then back.
4. Click "Mark Generation" again.
5. Click the generation marker in the timeline — it shows objects created during that interval that are **still alive**.
6. Sort by "Persistent Bytes" descending. Growing `RCTView`, `UIImage`, or closure-like objects across repeated navigation cycles signal a leak.

**VM Tracker instrument**

1. Add "VM Tracker" to the Allocations run (or use standalone).
2. Periodically click "Snapshot Now".
3. The **Dirty Size** column shows non-paged, actively-used memory per VM region.
4. Look for `IOSurface` (image buffers) or `MALLOC_*` categories growing between snapshots — these indicate native heap or graphics memory leaks invisible to the JS profiler.

**Leaks instrument**

1. Select the "Leaks" template.
2. Run the suspect flow 3–4 times in a loop.
3. Red bars in the Leaks timeline = confirmed unreachable cycles.
4. Click a red bar → expand the leak entry → see the full allocation backtrace.
5. The "Cycles & Roots" view shows the exact object cycle preventing deallocation.

### Android Studio Memory Profiler

**Basic heap dump workflow**

1. Run > Profile (or attach profiler to a running process).
2. Select the "Memory" profiler tab.
3. Click the GC button (force a collection) before starting the flow.
4. Navigate through the feature, return to start.
5. Click the GC button again, then "Capture heap dump".
6. In the dump viewer, filter by your package name.
7. Look for retained `Activity`, `Fragment`, `Context`, `View`, or `Bitmap` instances. Multiple instances of a screen class that should have only one = leak.

**HPROF conversion for MAT analysis**

Android's heap dump is in HPROF format. Eclipse MAT provides deeper analysis (dominator tree, leak suspects report):

```bash
# Convert Android HPROF to standard format for MAT
hprof-conv original.hprof converted.hprof

# Then open converted.hprof in Eclipse MAT
# Run: File > Open Heap Dump
# Reports > Leak Suspects provides a text report
```

**Native Heap profiler (API 29+)**

Available in Android Studio Electric Eel and later:

1. Memory profiler → click the down-arrow next to "Record" → "Sample Native Allocations".
2. Start recording, run the suspect flow, stop recording.
3. The call tree shows C/C++ allocation sites with byte counts.
4. JNI global ref leaks appear as `NewGlobalRef` call sites with growing byte counts.

### React Native DevTools Memory Tab (New Architecture)

With the New Architecture (RN 0.73+), the Chrome DevTools Protocol is available over a direct connection — no Flipper needed.

```bash
# Connect DevTools
npx react-native start
# In another terminal (Metro must be running):
open "chrome://inspect"
# Click "inspect" next to your app
```

The **Memory** tab in DevTools provides:

- **Heap snapshot**: Full JS object graph. Use "Comparison" between two snapshots to find objects surviving a navigation cycle.
- **Allocation instrumentation**: Records allocations over time. Shows which call sites are allocating the most bytes.
- **Allocation sampling**: Low-overhead sampling profiler — suitable for longer sessions without significant runtime impact.

**Workflow for detecting component leaks:**

1. Take Snapshot 1 (baseline).
2. Navigate to the screen, interact, navigate back.
3. Force GC (click the GC button in the toolbar).
4. Take Snapshot 2.
5. Switch to "Comparison" view, sort "# Delta" descending.
6. Positive delta on `Fiber`, `FiberNode`, or your component's closure objects = retained component tree.

### Flipper Deprecation — What Replaces It

Flipper was the default debugging tool through RN 0.72. It was removed as a default dependency in RN 0.73 due to maintenance burden and incompatibilities with the New Architecture.

| Flipper Plugin | Replacement |
|---|---|
| React DevTools | `npx react-devtools` (standalone) |
| Network inspector | Proxyman, Charles Proxy, or `react-native-network-logger` |
| Layout inspector | React Native DevTools (New Architecture) |
| Databases / MMKV | Custom `useMMKVDebugger` hook + Reactotron |
| Crash reporter | Sentry, Bugsnag (always preferred for production) |
| Hermes Debugger | Chrome DevTools via `chrome://inspect` |

For teams still on RN < 0.73, Flipper remains functional but its Memory plugin only shows the JS heap — use Instruments and Android Studio for native memory.

### Production Memory Monitoring

**Sentry**

```tsx
import * as Sentry from '@sentry/react-native';
import { AppState } from 'react-native';

// Capture memory warning events
AppState.addEventListener('memoryWarning', () => {
  Sentry.addBreadcrumb({
    category: 'memory',
    message: 'OS memory warning received',
    level: 'warning',
    data: { timestamp: Date.now() },
  });
  // Escalate to an event if you want alerting:
  Sentry.captureMessage('Memory pressure warning', 'warning');
});

// Attach JS heap size to performance transactions
const transaction = Sentry.startTransaction({ name: 'FeedScreen.mount' });
// ... load data ...
if (typeof performance !== 'undefined' && (performance as any).memory) {
  const mem = (performance as any).memory;
  transaction.setMeasurement('js_heap_used_mb', mem.usedJSHeapSize / 1024 / 1024, 'megabyte');
}
transaction.finish();
```

**Firebase Performance Monitoring**

```tsx
import perf from '@react-native-firebase/perf';

const trace = await perf().startTrace('screen_feed_load');
// ... load and render ...
trace.putMetric('items_loaded', items.length);
if (typeof performance !== 'undefined' && (performance as any).memory) {
  trace.putMetric(
    'js_heap_mb',
    Math.round((performance as any).memory.usedJSHeapSize / 1024 / 1024)
  );
}
await trace.stop();
```

Custom metrics appear in the Firebase Console under Performance > Custom traces. Track `js_heap_mb` across releases to detect regressions.

---

## 13. Device Tier Memory Budgets (Expanded)

### Budget Table by Device Class

| Device Class | RAM | JS Heap Target | Image Cache | Native Heap | Total Budget |
|---|---|---|---|---|---|
| Low-end Android | 1–2 GB | < 40 MB | < 20 MB | < 30 MB | < 100 MB |
| Mid-range Android / iPhone SE | 3–4 GB | < 80 MB | < 60 MB | < 50 MB | < 200 MB |
| High-end Android / iPhone 14 | 6–8 GB | < 150 MB | < 120 MB | < 80 MB | < 380 MB |
| Flagship (12+ GB) | 12+ GB | < 250 MB | < 200 MB | < 120 MB | < 600 MB |

### Low-End Android (1–2 GB RAM) — Specific Targets

The Android kernel's OOM killer starts terminating background processes when free RAM drops below ~200 MB. Your foreground app is the last to die, but jank and crashes from system pressure start earlier.

- Keep total RSS (Resident Set Size) under 100 MB.
- Disable disk image cache — low-end devices often have slow flash; decode latency matters more than cache hit rate.
- Use `RGB_565` bitmaps for all opaque images.
- Limit `FlashList` `drawDistance` to 100–150 px.
- Avoid keeping more than one screen's worth of data in state.

### iPhone SE — Jetsam Kill Thresholds

iOS uses a private "jetsam" mechanism — a kernel extension that kills processes by priority when memory is scarce, with no warning to the app (unlike `memoryWarning` which fires before jetsam).

Empirical jetsam limits for iPhone SE 2nd gen (3 GB RAM):

| Foreground | Background |
|---|---|
| ~1,200 MB before kill | ~150–200 MB |

The foreground limit seems generous, but that 1.2 GB is **system-wide committed memory** including the OS, graphics, and other processes. Your app's realistic budget before pressure is ~300–400 MB total.

```tsx
// Respond to memoryWarning — fires ~50–100 MB before jetsam
const sub = AppState.addEventListener('memoryWarning', () => {
  // Aggressive cache clear
  clearMemoryCache();
  queryClient.clear();
  apiResponseCache.clear();
});
```

### Flagship (6+ GB) — Caching Optimization Opportunities

On high-RAM devices, aggressive caching improves UX without memory risk:

```tsx
// Increase image cache on flagship devices
import DeviceInfo from 'react-native-device-info';

const totalRAMGb = (await DeviceInfo.getTotalMemory()) / 1024 / 1024 / 1024;
const imageCacheSizeMB = totalRAMGb >= 6 ? 200 : totalRAMGb >= 3 ? 80 : 20;

// Configure Glide (Android) — call from a native module or MainApplication
// builder.setMemoryCache(LruResourceCache((imageCacheSizeMB * 1024 * 1024).toLong()))
```

You can also pre-warm the image cache on flagship devices for predictable feeds:

```tsx
import { Image } from 'expo-image';

// Prefetch next page of images on flagship only
if (totalRAMGb >= 6) {
  Image.prefetch(nextPageUrls);
}
```

### Adaptive Budget: Detect RAM Tier at Runtime

```tsx
import DeviceInfo from 'react-native-device-info';

type MemoryTier = 'low' | 'mid' | 'high' | 'flagship';

let _tier: MemoryTier | null = null;

export async function getMemoryTier(): Promise<MemoryTier> {
  if (_tier) return _tier;

  const totalBytes = await DeviceInfo.getTotalMemory();
  const gb = totalBytes / 1024 / 1024 / 1024;

  if (gb < 2.5) _tier = 'low';
  else if (gb < 5) _tier = 'mid';
  else if (gb < 10) _tier = 'high';
  else _tier = 'flagship';

  return _tier;
}

// Config map — consumed at app init
export const MEMORY_CONFIG = {
  low: {
    imageCacheMB: 20,
    listDrawDistancePx: 100,
    prefetchImages: false,
    maxCachedScreens: 1,
    bitmapFormat: 'RGB_565' as const,
  },
  mid: {
    imageCacheMB: 60,
    listDrawDistancePx: 200,
    prefetchImages: false,
    maxCachedScreens: 2,
    bitmapFormat: 'ARGB_8888' as const,
  },
  high: {
    imageCacheMB: 120,
    listDrawDistancePx: 250,
    prefetchImages: true,
    maxCachedScreens: 3,
    bitmapFormat: 'ARGB_8888' as const,
  },
  flagship: {
    imageCacheMB: 200,
    listDrawDistancePx: 300,
    prefetchImages: true,
    maxCachedScreens: 5,
    bitmapFormat: 'ARGB_8888' as const,
  },
} satisfies Record<MemoryTier, object>;

// Usage at app startup (e.g., App.tsx)
async function initMemoryConfig() {
  const tier = await getMemoryTier();
  const config = MEMORY_CONFIG[tier];

  if (__DEV__) {
    console.log(`[Memory] Tier: ${tier} | RAM config:`, config);
  }

  return config;
}
```

**Apply to FlashList dynamically:**

```tsx
function AdaptiveFeed({ items }: { items: Item[] }) {
  const [config, setConfig] = useState(MEMORY_CONFIG.mid);

  useEffect(() => {
    initMemoryConfig().then(setConfig);
  }, []);

  return (
    <FlashList
      data={items}
      estimatedItemSize={80}
      drawDistance={config.listDrawDistancePx}
      renderItem={({ item }) => <FeedItem item={item} />}
    />
  );
}
```
