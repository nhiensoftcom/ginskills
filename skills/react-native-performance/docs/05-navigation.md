# Navigation Performance

## Library Choice

| Library | Renderer | Performance | Use Case |
|---|---|---|---|
| `@react-navigation/native-stack` | Native (UINavigationController / FragmentManager) | Best | Default choice for all apps |
| `@react-navigation/stack` | JS (Animated API) | Worst | Avoid — only for custom animated headers |
| Expo Router | Native-stack under the hood | Best | File-based routing in Expo |
| Wix React Native Navigation (RNN) | Native | Best | Large apps needing full native integration |

**Rule**: Always use `createNativeStackNavigator`. The JS stack runs transitions entirely in JS thread and drops frames under load.

```ts
// Bad
import { createStackNavigator } from '@react-navigation/stack';

// Good
import { createNativeStackNavigator } from '@react-navigation/native-stack';
const Stack = createNativeStackNavigator();
```

---

## enableScreens

Call `enableScreens(true)` once at app entry point before any navigator renders.

```ts
// app/_layout.tsx or App.tsx
import { enableScreens } from 'react-native-screens';
enableScreens(true);
```

**What it does**: replaces React Native's `View`-based screen containers with native `Screen` components (`RNSScreen`). Offscreen screens are detached from the layout pass entirely.

**Impact**: 30–40% memory reduction for deep navigation stacks. Without it, every mounted screen keeps its full view hierarchy alive and participates in layout calculations.

Expo includes `react-native-screens` by default. For bare RN, install it manually and run `pod install`.

---

## Lazy Loading Screens

```ts
<Tab.Navigator
  screenOptions={{
    lazy: true,          // do not render tab screen until first visit
    lazyPreloadDistance: 0,  // 0 = only render on visit, not adjacent tabs
  }}
>
```

For stack navigators, screens are always lazy by default (rendered when pushed). The setting above only applies to tab and drawer navigators where all screens mount simultaneously.

**When to set `lazyPreloadDistance: 1`**: if adjacent tab data takes 500ms+ to fetch and you want it ready before the user taps — but measure first, pre-rendering costs memory.

---

## useFocusEffect vs useEffect

```ts
// useEffect — runs once on mount, stays subscribed even when screen is blurred
useEffect(() => {
  fetchUserProfile(); // runs once, never refreshes when navigating back
}, []);

// useFocusEffect — runs every time the screen comes into focus
useFocusEffect(
  useCallback(() => {
    fetchUserProfile(); // re-fetches when user navigates back to this screen
    return () => {
      // cleanup runs when screen loses focus
      cancelPendingRequests();
    };
  }, [])
);
```

**Decision matrix**:

| Scenario | Hook |
|---|---|
| One-time data load, no staleness concern | `useEffect` |
| Data that changes while user is on another screen | `useFocusEffect` |
| Subscribing to a real-time source | `useFocusEffect` (subscribe on focus, unsubscribe on blur) |
| Starting/stopping a timer | `useFocusEffect` |
| Analytics screen view event | `useFocusEffect` |

**Pattern — conditional refresh with TanStack Query**:

```ts
const { refetch } = useQuery({ queryKey: ['profile'], queryFn: fetchProfile });

useFocusEffect(
  useCallback(() => {
    // only refetch if data is older than 30 seconds
    refetch();
  }, [refetch])
);
```

---

## InteractionManager.runAfterInteractions

Navigation animations run on the JS thread (even with native-stack, some JS work happens during transition). Heavy synchronous work during a push/pop causes dropped frames.

```ts
import { InteractionManager } from 'react-native';

function ProductScreen() {
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const task = InteractionManager.runAfterInteractions(() => {
      // runs after push animation completes (~300ms)
      setReady(true);
    });
    return () => task.cancel();
  }, []);

  if (!ready) return <SkeletonScreen />;
  return <HeavyProductContent />;
}
```

**What counts as "heavy work"**: parsing large JSON, building complex FlatList data, initializing charting libraries, running regex on large strings.

**Do not defer**: screen layout, skeleton placeholders, above-the-fold static content. Those should render immediately.

---

## Navigation Depth

**Rule**: maximum 3 levels of stack nesting. Beyond that, users lose context and back navigation becomes confusing.

```
Root
├── Tab A (Home)
├── Tab B (Explore)
│   └── Detail (level 1)
│       └── Sub-detail (level 2) — stop here
└── Modal: Settings (root-level, not nested under any tab)
```

**Flatten with root-level screens for modals and sheets**:

```ts
// Good — modal lives at root level, not inside tab stack
<Stack.Navigator>
  <Stack.Screen name="Tabs" component={TabNavigator} />
  <Stack.Screen
    name="CreatePost"
    component={CreatePostScreen}
    options={{ presentation: 'modal' }}
  />
  <Stack.Screen
    name="ImageViewer"
    component={ImageViewerScreen}
    options={{ presentation: 'fullScreenModal' }}
  />
</Stack.Navigator>
```

Nesting modals inside tab stacks causes the modal to re-render when the tab re-renders and complicates the back stack.

---

## Screen Transition Optimization

**Preload data before navigation**:

```ts
const queryClient = useQueryClient();

function ProductCard({ productId }: Props) {
  const handlePress = () => {
    // prefetch before navigating — data arrives during animation
    queryClient.prefetchQuery({
      queryKey: ['product', productId],
      queryFn: () => fetchProduct(productId),
    });
    navigation.navigate('ProductDetail', { productId });
  };

  return <Pressable onPress={handlePress} />;
}
```

**Skeleton screens**: render the skeleton as the default state, not after a loading check. This avoids a blank flash during the push animation.

```ts
function ProductDetailScreen() {
  const { data, isLoading } = useQuery(/* ... */);

  // skeleton shows during animation AND while loading
  if (isLoading) return <ProductDetailSkeleton />;
  return <ProductDetailContent data={data} />;
}
```

**Shared element transitions**: use `react-native-reanimated`'s `SharedTransition` or Expo Router's `sharedTransitionTag`. Only apply to 1–2 elements per transition — more than that causes jank.

---

## Deep Linking Performance

Deep links that arrive while the app is launching race with the navigator mounting. Processing them too early causes "navigate before navigator ready" errors.

```ts
// Correct pattern — queue and process after TTI
const [pendingDeepLink, setPendingDeepLink] = useState<string | null>(null);
const navigationRef = useNavigationContainerRef();

useEffect(() => {
  const handleUrl = ({ url }: { url: string }) => {
    if (navigationRef.isReady()) {
      processDeepLink(url, navigationRef);
    } else {
      setPendingDeepLink(url); // queue it
    }
  };

  const sub = Linking.addEventListener('url', handleUrl);
  Linking.getInitialURL().then(url => url && handleUrl({ url }));
  return () => sub.remove();
}, []);

// Process queued link once navigator is ready
const onNavigatorReady = () => {
  if (pendingDeepLink) {
    processDeepLink(pendingDeepLink, navigationRef);
    setPendingDeepLink(null);
  }
};
```

**Expo Router** handles this automatically via its `<ExpoRouter.Router>` component.

---

## Tab Navigator Optimization

```ts
<Tab.Navigator
  screenOptions={{
    lazy: true,
    lazyPreloadDistance: 0,
  }}
>
```

**Pre-fetch adjacent tab data on idle**:

```ts
// In the active tab, prefetch the next tab's data during idle time
import { useIsFocused } from '@react-navigation/native';

function HomeTab() {
  const isFocused = useIsFocused();
  const queryClient = useQueryClient();

  useEffect(() => {
    if (!isFocused) return;
    const id = requestIdleCallback(() => {
      queryClient.prefetchQuery({ queryKey: ['explore'], queryFn: fetchExplore });
    });
    return () => cancelIdleCallback(id);
  }, [isFocused]);
}
```

**Re-use tab screens**: avoid unmounting/remounting tabs by keeping `lazy: true` but not using `unmountOnBlur`. Unmounting on blur is almost never the right choice — it wastes the first-load cost every time the user switches.

---

## Modal Optimization — Portal Pattern

When a modal is a child of a screen component, it re-renders every time the parent re-renders. Use a portal to lift the modal to root level.

```ts
// Without portal — modal re-renders with parent
function FeedScreen() {
  const [open, setOpen] = useState(false);
  const posts = usePosts(); // re-renders every poll

  return (
    <View>
      <PostList posts={posts} />
      {open && <CreatePostModal />} {/* re-renders on every post update */}
    </View>
  );
}

// With portal — modal is isolated
import { Portal } from '@gorhom/portal';

function FeedScreen() {
  const [open, setOpen] = useState(false);

  return (
    <View>
      <PostList />
      <Portal>
        {open && <CreatePostModal />} {/* isolated from FeedScreen re-renders */}
      </Portal>
    </View>
  );
}
```

---

## react-native-screens Freezing

When `enableScreens(true)` is active, offscreen screens are "frozen": their component tree stays mounted (preserving state) but React suspends re-renders and the native view is detached from the window.

**Implications**:
- State is preserved — no need to persist tab scroll position manually
- `useEffect` cleanup does NOT run when a screen is frozen (it runs on unmount)
- `useFocusEffect` cleanup DOES run when a screen loses focus — use this for subscriptions
- Network requests initiated on a frozen screen still complete; the UI updates when the screen unfreezes

**Debugging freezing issues**:

```ts
import { useIsFocused } from '@react-navigation/native';

function DebugScreen() {
  const focused = useIsFocused();
  // if focused is false but component is mounted, screen is frozen
  console.log('focused:', focused);
}
```

Memory savings come from the native side: detached screens do not hold GPU textures or participate in layout. The JS heap savings are smaller since the component tree stays in memory.

---

## Expo Router v4 Performance

Expo Router is file-based routing built on top of React Navigation's native-stack. It adds a build-time route manifest and a runtime route resolver. Understanding where the overhead sits helps you avoid common pitfalls.

**File-based routing performance implications**

The route manifest is generated at build time and bundled with the app. At runtime the router reads this manifest to resolve segment matching — no filesystem access occurs on-device. The net overhead is one extra JavaScript object lookup per navigation call, which is negligible.

The cost you do pay is **eager module evaluation**: every file in `app/` is included in the initial JS bundle unless you use dynamic imports. A deep `app/` tree with many routes increases TTI if all route modules are parsed upfront.

**Route preloading with Expo Router**

```ts
// app/(tabs)/index.tsx
import { Link } from 'expo-router';

// Preload a route module on pointer-down (web) or long-press (native)
// so the JS module is evaluated before the user lifts their finger.
<Link href="/product/[id]" prefetch>
  View Product
</Link>
```

On native, `prefetch` triggers background evaluation of the route module. Combine with TanStack Query prefetching to eliminate both the JS parse cost and the data fetch latency:

```ts
import { useRouter } from 'expo-router';
import { useQueryClient } from '@tanstack/react-query';

function ProductCard({ productId }: { productId: string }) {
  const router = useRouter();
  const queryClient = useQueryClient();

  const handlePress = () => {
    queryClient.prefetchQuery({
      queryKey: ['product', productId],
      queryFn: () => fetchProduct(productId),
    });
    router.push(`/product/${productId}`);
  };

  return <Pressable onPress={handlePress} />;
}
```

**Dynamic route matching overhead**

Segments like `[id]` and `[...slug]` run a regex match at navigation time. With fewer than 50 routes this cost is sub-millisecond. If your app has 100+ routes, prefer static routes for high-frequency paths and reserve dynamic segments for lower-frequency flows.

Avoid nested dynamic segments more than two levels deep (`app/[a]/[b]/[c].tsx`) — each level adds a regex pass and makes the URL shape harder to type-check.

**Static generation for web**

Expo Router supports static rendering for web via `expo export --platform web`. Statically generated routes skip client-side route resolution entirely — the HTML shell arrives pre-rendered and React hydrates in place. Enable it in `app.json`:

```json
{
  "expo": {
    "web": {
      "output": "static"
    }
  }
}
```

For dynamic routes that cannot be statically generated, fall back to `"output": "server"` or `"output": "single"` selectively.

**Optimized Expo Router layout**

```ts
// app/_layout.tsx
import { Stack } from 'expo-router';
import { enableScreens } from 'react-native-screens';

// Enable native screens once, before any navigator renders.
enableScreens(true);

export default function RootLayout() {
  return (
    <Stack
      screenOptions={{
        // Hoist shared options here instead of repeating per-screen.
        // This avoids re-creating the options object on every render.
        headerShown: false,
        animation: 'slide_from_right',
        gestureEnabled: true,
      }}
    >
      {/* Screens override only what differs from the root screenOptions. */}
      <Stack.Screen name="(tabs)" />
      <Stack.Screen
        name="product/[id]"
        options={{ animation: 'fade_from_bottom' }}
      />
      <Stack.Screen
        name="modal"
        options={{ presentation: 'modal', headerShown: true }}
      />
    </Stack>
  );
}
```

---

## React Navigation v7 Static API

React Navigation v7 introduced a **static navigator configuration** as an alternative to the JSX-based dynamic API. The static API defines the entire navigation tree as a plain JavaScript object, which allows TypeScript to infer all route names and params without manual type augmentation.

**Static navigator configuration vs dynamic**

```ts
// Dynamic API (v6 style) — types require manual augmentation
declare global {
  namespace ReactNavigation {
    interface RootParamList {
      Home: undefined;
      Profile: { userId: string };
    }
  }
}

const Stack = createNativeStackNavigator();

function AppNavigator() {
  return (
    <Stack.Navigator>
      <Stack.Screen name="Home" component={HomeScreen} />
      <Stack.Screen name="Profile" component={ProfileScreen} />
    </Stack.Navigator>
  );
}
```

```ts
// Static API (v7) — types inferred automatically, no global augmentation
import { createStaticNavigation } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';

const RootStack = createNativeStackNavigator({
  screens: {
    Home: HomeScreen,
    Profile: {
      screen: ProfileScreen,
      // Param types inferred from ProfileScreen's route prop type.
    },
  },
});

export const Navigation = createStaticNavigation(RootStack);

// In app entry:
// <Navigation />
```

**Performance benefits of static typing**

The static API resolves two runtime costs:

1. The navigator component no longer reconciles `<Stack.Screen>` children on every render. The screen map is built once during module evaluation, not on each render cycle.
2. TypeScript catches invalid route names and mismatched params at compile time, eliminating the defensive runtime checks that some codebases add around `navigation.navigate()`.

**Reduced runtime navigation definition overhead**

With the dynamic API, every re-render of the navigator component re-evaluates the JSX children and React Navigation diffs the screen list. For navigators with 10+ screens this is a small but measurable cost on low-end Android devices. The static API eliminates this diff entirely — the screen registry is immutable after initialization.

**Static API setup**

```ts
// navigation/root-navigator.ts
import { createStaticNavigation, StaticParamList } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';

const TabNavigator = createBottomTabNavigator({
  screenOptions: { lazy: true, lazyPreloadDistance: 0 },
  screens: {
    Home: HomeScreen,
    Explore: ExploreScreen,
    Profile: ProfileScreen,
  },
});

const RootStack = createNativeStackNavigator({
  screenOptions: { headerShown: false },
  screens: {
    Tabs: TabNavigator,
    ProductDetail: {
      screen: ProductDetailScreen,
      options: { headerShown: true, title: 'Product' },
    },
    CreatePost: {
      screen: CreatePostScreen,
      options: { presentation: 'modal' },
    },
  },
});

// Export the fully-typed navigation component.
export const RootNavigation = createStaticNavigation(RootStack);

// Export param list type for useNavigation() typing.
export type RootParamList = StaticParamList<typeof RootStack>;
```

```ts
// app entry
import { RootNavigation } from '@/navigation/root-navigator';

export default function App() {
  return (
    <RootNavigation />
  );
}
```

---

## Bottom Sheet Navigation (Gorhom)

`@gorhom/bottom-sheet` is a gesture-driven sheet built on Reanimated and Gesture Handler. It is not a React Navigation navigator, but it is frequently used as one — treating snap points as "screens" within a sheet flow. Used correctly it is highly performant; used naively it causes gesture conflicts and dropped frames.

**`@gorhom/bottom-sheet` as a navigation modal**

The most performant pattern is to mount the `BottomSheet` at root level (using a portal), keep it permanently mounted with `enablePanDownToClose={false}`, and drive its content via a Zustand store or context rather than mounting/unmounting the sheet component.

```ts
// stores/bottom-sheet-store.ts
import { create } from 'zustand';

type SheetContent = 'filters' | 'sort' | 'share' | null;

interface BottomSheetStore {
  content: SheetContent;
  open: (content: SheetContent) => void;
  close: () => void;
}

export const useBottomSheetStore = create<BottomSheetStore>((set) => ({
  content: null,
  open: (content) => set({ content }),
  close: () => set({ content: null }),
}));
```

```ts
// components/root-bottom-sheet.tsx
import BottomSheet, { BottomSheetView } from '@gorhom/bottom-sheet';
import { useRef, useCallback, useEffect } from 'react';
import { useBottomSheetStore } from '@/stores/bottom-sheet-store';

const SNAP_OPEN = '60%';
const SNAP_CLOSED = '0%';

export function RootBottomSheet() {
  const sheetRef = useRef<BottomSheet>(null);
  const { content, close } = useBottomSheetStore();

  useEffect(() => {
    if (content) {
      sheetRef.current?.expand();
    } else {
      sheetRef.current?.close();
    }
  }, [content]);

  const handleChange = useCallback(
    (index: number) => {
      if (index === -1) close();
    },
    [close],
  );

  return (
    <BottomSheet
      ref={sheetRef}
      index={-1}
      snapPoints={[SNAP_OPEN]}
      enablePanDownToClose
      onChange={handleChange}
      // Worklet-based style — runs on UI thread, no bridge calls.
      backgroundStyle={{ borderRadius: 16 }}
    >
      <BottomSheetView>
        {content === 'filters' && <FiltersContent />}
        {content === 'sort' && <SortContent />}
        {content === 'share' && <ShareContent />}
      </BottomSheetView>
    </BottomSheet>
  );
}
```

**Snap points performance optimization**

Snap points defined as strings (`'60%'`) are recalculated on every layout change. Use numeric pixel values when the snap height is fixed to avoid repeated percentage-to-pixel conversions:

```ts
import { useWindowDimensions } from 'react-native';
import { useMemo } from 'react';

function useSheetSnapPoints() {
  const { height } = useWindowDimensions();
  // Memoize so the array reference is stable — BottomSheet does a shallow
  // comparison of snapPoints and re-animates if the reference changes.
  return useMemo(() => [Math.round(height * 0.6)], [height]);
}
```

Pass `snapPoints` only from the parent and never recreate the array inline — an inline array literal creates a new reference on every render and forces the sheet to re-evaluate its snap positions.

**Gesture coordination with stack gestures**

When a `BottomSheet` is inside a `NativeStackNavigator`, the stack's swipe-back gesture (iOS) can conflict with the sheet's pan gesture. Resolve this by disabling the stack gesture while the sheet is open:

```ts
import { useNavigation } from '@react-navigation/native';
import { useBottomSheetStore } from '@/stores/bottom-sheet-store';
import { useEffect } from 'react';

function useDisableStackGestureWhenSheetOpen() {
  const navigation = useNavigation();
  const { content } = useBottomSheetStore();

  useEffect(() => {
    navigation.setOptions({ gestureEnabled: !content });
  }, [content, navigation]);
}
```

---

## Navigation State & Serialization Cost

React Navigation maintains an in-memory state tree that mirrors the entire navigator hierarchy. This tree grows as users navigate deeper and carries params from every visited screen. When state persistence is enabled (e.g. via `AsyncStorage`), that entire tree is serialized to JSON on every navigation action.

**Navigation state tree holding old screen data**

Each screen in a stack keeps its params in the state tree until it is popped. In a deep stack, params from screens 1–5 are all alive in memory while the user is on screen 5. If those params hold large serialized objects (full item details, image URIs, paginated arrays), the state tree balloons.

**Rule**: pass only IDs through navigation params; fetch the full data from cache inside the screen.

```ts
// Bad — passes full object through params
navigation.navigate('ProductDetail', { product: largeProductObject });

// Good — passes only the ID; screen fetches from cache
navigation.navigate('ProductDetail', { productId: 'abc123' });
```

**Params history accumulation in deep stacks**

Navigating without popping (`navigate` repeatedly instead of `push`) can accumulate duplicate entries in the state stack. Use `push` only when a second instance of the screen is intentional; use `navigate` to reuse an existing screen instance:

```ts
// Reuses existing screen if already in stack — no state accumulation
navigation.navigate('Profile', { userId: '123' });

// Always pushes a new screen — use only when a second instance is needed
navigation.push('Profile', { userId: '123' });
```

**State persistence cost (AsyncStorage serialization)**

`NavigationContainer` accepts a `persistenceKey` that causes it to serialize and persist state on every action. On a complex navigation tree (3 nested navigators × 5 screens each) this JSON can exceed 10 KB and hits AsyncStorage synchronously between frames.

Strategies to reduce this cost:

- Persist only the top-level navigator state, not nested stacks
- Debounce persistence: wrap the `onStateChange` callback yourself instead of using `persistenceKey`
- Skip persistence entirely in production; only use it during development for faster reload cycles

```ts
import { useMemo, useCallback, useRef } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import debounce from 'lodash/debounce';

const STATE_KEY = '@nav_state';

function useNavigationPersistence() {
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const onStateChange = useCallback((state: object | undefined) => {
    if (!state) return;
    // Debounce writes — only persist after 500ms of navigation inactivity.
    if (timerRef.current) clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => {
      AsyncStorage.setItem(STATE_KEY, JSON.stringify(state));
    }, 500);
  }, []);

  return { onStateChange };
}
```

**Clearing state on logout/reset**

On logout, reset the navigation state to prevent stale params (or secure data in params) from persisting across sessions:

```ts
import { CommonActions } from '@react-navigation/native';

function logout(navigationRef: React.RefObject<NavigationContainerRef<any>>) {
  // Clear persisted state from storage.
  AsyncStorage.removeItem('@nav_state');

  // Reset the navigator to a clean initial state.
  navigationRef.current?.dispatch(
    CommonActions.reset({
      index: 0,
      routes: [{ name: 'Auth' }],
    }),
  );
}
```

**Lightweight navigation params — summary**

```ts
// Param type contract: IDs only, never full objects
type RootStackParamList = {
  Home: undefined;
  ProductDetail: { productId: string };        // string ID, not Product
  UserProfile: { userId: string };             // string ID, not User
  OrderHistory: { filters?: { status: string } }; // small scalar filters only
};
```

---

## Stack vs Native-Stack Benchmarks

`@react-navigation/stack` (JS stack) runs transitions via the Animated API on the JS thread. `@react-navigation/native-stack` delegates transitions to `UINavigationController` (iOS) and `FragmentManager` (Android) — both run entirely off the JS thread.

**Memory comparison**

| Metric | JS Stack | Native Stack |
|---|---|---|
| Memory per screen (Android mid-range) | ~8–12 MB | ~4–6 MB |
| Memory per screen (iOS) | ~6–10 MB | ~3–5 MB |
| Memory at 5-screen depth | ~50–60 MB extra | ~20–30 MB extra |
| GPU texture retention (offscreen) | Yes (without enableScreens) | No (native detaches) |

**Animation smoothness comparison**

| Scenario | JS Stack | Native Stack |
|---|---|---|
| Idle push (no JS activity) | 60 fps | 60 fps |
| Push while FlatList scrolling | 30–45 fps | 60 fps |
| Push while image decode in progress | 20–40 fps | 58–60 fps |
| Pop with heavy `useEffect` on previous screen | 40–55 fps | 60 fps |
| Custom interpolator (e.g. scale + opacity) | 60 fps | Not supported natively |

**Gesture handling differences**

| Feature | JS Stack | Native Stack |
|---|---|---|
| Swipe-back (iOS) | JS gesture recognizer | Native `UIScreenEdgePanGestureRecognizer` |
| Full-swipe (Android) | JS (configurable threshold) | Native predictive back (Android 14+) |
| Custom swipe direction | Supported | Not supported |
| Gesture interruptibility | Full control | Limited to native behavior |
| Conflict with scroll views | Requires careful tuning | Handled natively |

**When JS stack is still needed**

Use `@react-navigation/stack` only when you need:

- Custom transition interpolators that cannot be expressed as native animation presets
- Full gesture control (e.g. swipe from any edge, diagonal dismissal)
- React-driven header animations that respond to scroll position within the screen

In all other cases, use `createNativeStackNavigator`.

**Migration guide: stack to native-stack**

1. Replace the import:

```ts
// Before
import { createStackNavigator } from '@react-navigation/stack';
const Stack = createStackNavigator();

// After
import { createNativeStackNavigator } from '@react-navigation/native-stack';
const Stack = createNativeStackNavigator();
```

2. Map option names that differ:

| JS Stack option | Native Stack equivalent |
|---|---|
| `cardStyle` | `contentStyle` |
| `cardOverlayEnabled` | (built-in, always on) |
| `gestureEnabled` | `gestureEnabled` (same) |
| `cardStyleInterpolator` | `animation` (preset string) |
| `headerMode: 'float'` | Not supported — header is per-screen |
| `transitionSpec` | `animationDuration` |

3. Remove any `cardStyleInterpolator` imports — they have no equivalent. Replace with the nearest `animation` preset:

```ts
// Before
import { CardStyleInterpolators } from '@react-navigation/stack';
options={{ cardStyleInterpolator: CardStyleInterpolators.forModalPresentationIOS }}

// After
options={{ presentation: 'modal' }}
```

4. If you used a floating header (`headerMode="float"`), move shared header logic into a `screenOptions` callback on the navigator instead of a custom header component — native-stack renders a header per screen.

---

## Screen Header Performance

The screen header is re-evaluated on every navigation state change. An improperly written `screenOptions` or custom header component can cause unnecessary re-renders that affect the entire navigator.

**Static vs dynamic `screenOptions` cost**

```ts
// Bad — inline function creates new object on every render of the navigator
<Stack.Navigator
  screenOptions={({ route, navigation }) => ({
    title: route.params?.title ?? 'App',
    headerRight: () => <SettingsButton />,
  })}
>

// Good — move static options to the Screen definition, dynamic only where needed
<Stack.Navigator screenOptions={{ headerBackTitleVisible: false }}>
  <Stack.Screen
    name="Home"
    component={HomeScreen}
    options={{ title: 'Home' }} // static, never re-evaluated
  />
  <Stack.Screen
    name="ProductDetail"
    component={ProductDetailScreen}
    // Dynamic title set inside the screen via navigation.setOptions()
    options={{ title: '' }}
  />
</Stack.Navigator>
```

Set dynamic header content from inside the screen with `navigation.setOptions()` wrapped in a `useLayoutEffect` (synchronous with render, avoids a title flash):

```ts
function ProductDetailScreen({ route }: Props) {
  const { data } = useQuery(['product', route.params.productId], fetchProduct);

  useLayoutEffect(() => {
    if (data?.name) {
      navigation.setOptions({ title: data.name });
    }
  }, [data?.name, navigation]);
}
```

**Custom header component re-renders**

A custom header component passed via `header:` in `screenOptions` re-renders whenever the navigation state changes. Wrap it in `React.memo` and ensure its props are stable:

```ts
import React, { memo } from 'react';
import type { NativeStackHeaderProps } from '@react-navigation/native-stack';

const AppHeader = memo(function AppHeader({ navigation, route, options }: NativeStackHeaderProps) {
  return (
    <View style={styles.header}>
      <Text style={styles.title}>{options.title ?? route.name}</Text>
      {navigation.canGoBack() && (
        <Pressable onPress={navigation.goBack}>
          <BackIcon />
        </Pressable>
      )}
    </View>
  );
});

// In navigator:
<Stack.Navigator screenOptions={{ header: (props) => <AppHeader {...props} /> }}>
```

Note: even with `memo`, the `header` prop itself is an inline arrow function, which means the navigator will call `memo`'s comparison. Pass the component reference directly if the navigator API allows it, or memoize the render prop:

```ts
// Memoize the header render prop at module level (not inside a component)
const renderAppHeader = (props: NativeStackHeaderProps) => <AppHeader {...props} />;

<Stack.Navigator screenOptions={{ header: renderAppHeader }}>
```

**`useHeaderHeight()` overhead**

`useHeaderHeight()` subscribes to a context that updates whenever the header layout changes (orientation change, dynamic title length change). Components that call `useHeaderHeight()` re-render on every header layout event.

Minimize its call sites: compute it once at layout level and pass the value down as a prop, or use a static constant if your header height is fixed.

```ts
// Instead of calling useHeaderHeight() in many components:
const HEADER_HEIGHT = Platform.select({ ios: 44, android: 56, default: 56 });

// Use the constant where the height is known and static.
// Only call useHeaderHeight() when the height is genuinely dynamic
// (transparent header with blur, large title collapse, etc.).
```

**`headerTransparent` performance implications**

`headerTransparent: true` causes the screen content to extend behind the header. This is implemented via a blur or semi-transparent overlay, which has two costs:

1. On iOS, `UIBlurEffect` adds a GPU compositing layer over the full header width on every frame.
2. The screen must add `paddingTop: headerHeight` to avoid content sitting behind the header — which requires `useHeaderHeight()`, adding the re-render subscription described above.

Only use `headerTransparent` on screens where the visual effect justifies the GPU cost (image-heavy detail screens, profile headers). For standard list screens, a solid opaque header is always faster.

**Optimized custom header**

```ts
// components/optimized-header.tsx
import { memo, useCallback } from 'react';
import { View, Text, Pressable, StyleSheet, Platform } from 'react-native';
import type { NativeStackHeaderProps } from '@react-navigation/native-stack';

// Module-level styles — never re-created.
const styles = StyleSheet.create({
  container: {
    height: Platform.select({ ios: 44, android: 56, default: 56 }),
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    backgroundColor: '#ffffff',
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#e5e5e5',
  },
  title: {
    flex: 1,
    fontSize: 17,
    fontWeight: '600',
    textAlign: 'center',
  },
  backButton: {
    width: 44,
    height: 44,
    justifyContent: 'center',
  },
  rightSlot: {
    width: 44,
    height: 44,
    justifyContent: 'center',
    alignItems: 'flex-end',
  },
});

export const OptimizedHeader = memo(function OptimizedHeader({
  navigation,
  route,
  options,
}: NativeStackHeaderProps) {
  // Stable callback — navigation reference is stable per screen mount.
  const handleBack = useCallback(() => navigation.goBack(), [navigation]);
  const canGoBack = navigation.canGoBack();

  return (
    <View style={styles.container}>
      <View style={styles.backButton}>
        {canGoBack && (
          <Pressable onPress={handleBack} hitSlop={8}>
            <BackChevronIcon />
          </Pressable>
        )}
      </View>

      <Text style={styles.title} numberOfLines={1}>
        {options.title ?? route.name}
      </Text>

      {/* Right action — rendered only when provided to avoid empty View cost */}
      <View style={styles.rightSlot}>
        {options.headerRight?.({ canGoBack })}
      </View>
    </View>
  );
});

// Module-level render prop — stable reference, no re-creation per render.
export const renderOptimizedHeader = (props: NativeStackHeaderProps) => (
  <OptimizedHeader {...props} />
);
```

```ts
// Usage in navigator
import { renderOptimizedHeader } from '@/components/optimized-header';

<Stack.Navigator screenOptions={{ header: renderOptimizedHeader }}>
  {/* screens */}
</Stack.Navigator>
```
