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
