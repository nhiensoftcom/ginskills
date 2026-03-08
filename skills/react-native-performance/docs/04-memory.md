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
