# Animation Performance

## 1. Animation Threading Model

### How Threads Map to Frames

React Native runs on three threads: the **JS thread** (component logic and business logic), the **UI thread** (native rendering and layout), and the **Shadow thread** (Yoga layout calculations). All animation work must land on the UI thread at the display's refresh rate to feel smooth. The question is how work gets there.

**JS thread animations (Animated API without `useNativeDriver`)** — every frame the JS thread computes the animated value, serializes it, sends it over the bridge (or JSI in New Architecture), and the UI thread applies it. Under JS load (routing, data fetching, re-renders) frames are dropped because the JS thread cannot keep up. Typical result: ~45fps under real-world load, with visible hitches during navigation or network responses.

**Native driver (`useNativeDriver: true`)** — the animation is serialized once at start time and handed to the UI thread. The UI thread runs it autonomously at ~60fps regardless of JS thread load. The constraint: only `transform` and `opacity` properties are supported. Layout properties (`width`, `height`, `top`, `padding`) cannot be driven natively because they require the Shadow thread's layout pass, which feeds back to JS.

**Reanimated 3/4 worklets** — JS functions annotated with `'worklet'` are compiled and executed directly on the UI thread via JSI. They run at the device's max refresh rate (60–120fps), have access to shared values synchronously, and support any animatable property including layout. Gesture tracking runs entirely on the UI thread with no bridge round-trips.

### Performance Comparison Table

| | Animated (no native driver) | Animated (useNativeDriver) | Reanimated 3/4 |
|---|---|---|---|
| FPS under JS load | ~45fps | ~60fps | 60–120fps |
| Layout properties (`width`, `height`) | ~30fps | NOT supported | ~60fps |
| Gesture tracking | Laggy | Partial | 60–120fps |
| Supported properties | All | `transform`, `opacity` only | All |
| Initial setup cost | None | None | Worklet compilation |
| Debug experience | Good | Good | Requires Reanimated DevTools |

### When to Use Each

- **Animated + useNativeDriver** — simple one-shot transitions on `opacity` or `transform` where you have no existing Reanimated dependency and don't want to add one.
- **Reanimated** — everything else: gesture-driven animations, layout animations, scroll-linked effects, spring physics, shared element transitions.
- **Avoid Animated without useNativeDriver** — only acceptable for layout properties on very infrequent, non-interactive animations (e.g., expanding an accordion once on user tap, not looping).

---

## 2. Reanimated 3/4 Patterns

### Core Primitives

`useSharedValue` holds a value that lives on the UI thread and can be read/written from both JS and worklets without serialization overhead.

`useAnimatedStyle` returns a style object computed on the UI thread from shared values. React never re-renders the component when the style changes — only the native view updates.

```tsx
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  withTiming,
} from 'react-native-reanimated';

const PressableCard = () => {
  const scale = useSharedValue(1);

  const animatedStyle = useAnimatedStyle(() => ({
    transform: [{ scale: scale.value }],
  }));

  return (
    <Animated.View style={[styles.card, animatedStyle]}>
      <Pressable
        onPressIn={() => { scale.value = withSpring(0.96); }}
        onPressOut={() => { scale.value = withSpring(1); }}
      >
        <Text>Press me</Text>
      </Pressable>
    </Animated.View>
  );
};
```

### withSpring vs withTiming

`withSpring` produces physically-based motion with configurable mass, damping, and stiffness. Prefer it for interactive responses (button presses, drag release) because it feels natural.

`withTiming` produces eased motion over a fixed duration. Use it for UI state transitions where you need a predictable end time (tab switching, modal open).

```tsx
// Spring — natural, overshoots slightly, then settles
scale.value = withSpring(1, {
  mass: 1,
  damping: 15,
  stiffness: 150,
  overshootClamping: false,
});

// Timing — predictable, eased
opacity.value = withTiming(0, {
  duration: 200,
  easing: Easing.out(Easing.ease),
});
```

### Worklet Architecture: UI Thread Execution

Any function called inside `useAnimatedStyle`, `useAnimatedScrollHandler`, or a gesture callback must be a worklet. Reanimated's Babel plugin transforms functions marked `'worklet'` into a bytecode representation that the UI thread JS runtime can execute without crossing to the JS thread.

```tsx
// 'worklet' directive — function runs on UI thread
function clamp(value: number, min: number, max: number): number {
  'worklet';
  return Math.min(Math.max(value, min), max);
}

const animatedStyle = useAnimatedStyle(() => ({
  // clamp runs on UI thread — no bridge call
  opacity: clamp(progress.value, 0, 1),
}));
```

Utility functions called inside worklets must also be worklets. If you call a non-worklet function from a worklet, Reanimated throws at runtime.

### runOnUI vs runOnJS

`runOnUI` schedules a worklet to execute on the UI thread from the JS thread. Use it to trigger an animation imperatively from JS:

```tsx
const triggerAnimation = () => {
  runOnUI(() => {
    'worklet';
    scale.value = withSpring(1.2, {}, () => {
      scale.value = withSpring(1);
    });
  })();
};
```

`runOnJS` schedules a plain JS function to execute on the JS thread from a worklet. Use it to update React state after an animation ends or to call navigation from a gesture handler:

```tsx
const onClose = () => navigation.goBack(); // plain JS function

const gesture = Gesture.Tap().onEnd(() => {
  translateY.value = withTiming(600, { duration: 300 }, () => {
    runOnJS(onClose)(); // call navigation on JS thread after animation
  });
});
```

### useDerivedValue

Computes a new shared value on the UI thread whenever its dependencies change. Use it to derive secondary animated values without going back to JS:

```tsx
const scrollY = useSharedValue(0);

// Derived value — no JS thread involvement
const headerOpacity = useDerivedValue(() =>
  interpolate(scrollY.value, [0, 80], [1, 0], Extrapolation.CLAMP),
);

const headerStyle = useAnimatedStyle(() => ({
  opacity: headerOpacity.value,
}));
```

### useAnimatedReaction

Runs a worklet side-effect whenever a shared value changes. Useful for triggering secondary animations or haptics based on thresholds:

```tsx
useAnimatedReaction(
  () => scrollY.value > 100,
  (isCollapsed, wasCollapsed) => {
    if (isCollapsed !== wasCollapsed) {
      headerHeight.value = withTiming(isCollapsed ? 56 : 120);
    }
  },
);
```

Do not use `useAnimatedReaction` to update React state — wrap with `runOnJS` if you need to.

### Layout Animations: Entering and Exiting

Reanimated's layout animations run entering, exiting, and layout-change transitions using native-side view modifications. They require no JS involvement per frame.

```tsx
import Animated, {
  FadeIn,
  FadeOut,
  LinearTransition,
} from 'react-native-reanimated';

// Entering and exiting
const NotificationBanner = () => (
  <Animated.View entering={FadeIn.duration(200)} exiting={FadeOut.duration(150)}>
    <Text>New message</Text>
  </Animated.View>
);

// Layout transition — smooth reflow when siblings appear/disappear
const ListItem = ({ item }: { item: Item }) => (
  <Animated.View layout={LinearTransition.springify()}>
    <Text>{item.label}</Text>
  </Animated.View>
);
```

Staggered entrance — factory function per index:

```tsx
const StaggeredFadeIn = (index: number) =>
  FadeInDown.delay(index * 60).springify();

{items.map((item, i) => (
  <Animated.View key={item.id} entering={StaggeredFadeIn(i)}>
    <ItemCard item={item} />
  </Animated.View>
))}
```

### Reanimated 4: CSS Transitions and Keyframes

Reanimated 4 introduces a CSS-like animation API. CSS transitions animate between style changes reactively; keyframes define explicit waypoints. Both run on the UI thread.

```tsx
import Animated, { CSSTransition, Keyframes } from 'react-native-reanimated';

// CSS transition — animates whenever `expanded` changes
const AccordionPanel = ({ expanded }: { expanded: boolean }) => (
  <Animated.View
    style={{ height: expanded ? 200 : 0, overflow: 'hidden' }}
    transition={{ height: { duration: 300, easing: 'easeInOut' } }}
  />
);

// Keyframes — explicit waypoints, similar to @keyframes in CSS
const pulse = new Keyframes({
  0: { transform: [{ scale: 1 }], opacity: 1 },
  50: { transform: [{ scale: 1.12 }], opacity: 0.8 },
  100: { transform: [{ scale: 1 }], opacity: 1 },
});

const PulsingBadge = () => (
  <Animated.View style={styles.badge} animatedProps={{ animation: pulse.duration(800).iterations(-1) }} />
);
```

CSS transitions are useful when the animated value is controlled by React state — you express the end state and Reanimated interpolates. Worklet-based animations remain preferable for gesture-driven motion where values update faster than React renders.

---

## 3. Gesture Performance

### Gesture Handler vs Pressable

`Pressable` runs its `onPress` callback on the JS thread. Under heavy JS load there is a perceptible delay between touch and visual feedback. React Native Gesture Handler moves all gesture recognition to the UI thread, eliminating the JS thread from the touch response path.

| | Pressable | RNGH GestureDetector |
|---|---|---|
| Touch recognition thread | UI thread | UI thread |
| Callback execution thread | JS thread | UI thread (worklet) or JS thread |
| Works with Reanimated | Indirectly | Native integration |
| Simultaneous gestures | Limited | Full control |

### GestureDetector + Reanimated Integration

```tsx
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import Animated, { useSharedValue, useAnimatedStyle } from 'react-native-reanimated';

const DraggableCard = () => {
  const translateX = useSharedValue(0);
  const translateY = useSharedValue(0);
  const savedX = useSharedValue(0);
  const savedY = useSharedValue(0);

  const panGesture = Gesture.Pan()
    .onStart(() => {
      savedX.value = translateX.value;
      savedY.value = translateY.value;
    })
    .onUpdate((e) => {
      // Runs entirely on UI thread — 60–120fps
      translateX.value = savedX.value + e.translationX;
      translateY.value = savedY.value + e.translationY;
    })
    .onEnd(() => {
      translateX.value = withSpring(0);
      translateY.value = withSpring(0);
    });

  const animatedStyle = useAnimatedStyle(() => ({
    transform: [
      { translateX: translateX.value },
      { translateY: translateY.value },
    ],
  }));

  return (
    <GestureDetector gesture={panGesture}>
      <Animated.View style={[styles.card, animatedStyle]} />
    </GestureDetector>
  );
};
```

### Simultaneous, Exclusive, and Race Gesture Composition

`Gesture.Simultaneous` allows both gestures to recognize at the same time (pan + pinch on a photo viewer):

```tsx
const pinch = Gesture.Pinch().onUpdate((e) => {
  scale.value = savedScale.value * e.scale;
});

const pan = Gesture.Pan().onUpdate((e) => {
  translateX.value = savedX.value + e.translationX;
  translateY.value = savedY.value + e.translationY;
});

const composed = Gesture.Simultaneous(pan, pinch);
return <GestureDetector gesture={composed}><Animated.View style={animatedStyle} /></GestureDetector>;
```

`Gesture.Exclusive` lets only the first recognized gesture win — use this when gestures conflict and you want priority-based resolution.

`Gesture.Race` activates whichever gesture recognizes first and cancels the rest — useful for a drag vs. tap disambiguation.

For horizontal swipes inside a vertical scroll, constrain the gesture with offsets so it only activates in the correct direction:

```tsx
const horizontalSwipe = Gesture.Pan()
  .activeOffsetX([-10, 10])  // only activates on horizontal movement
  .failOffsetY([-5, 5]);     // fails if vertical movement detected first
```

### Touch Feedback on the UI Thread

Build press feedback entirely on the UI thread — no JS involvement:

```tsx
const FastButton = ({ onPress, children }: Props) => {
  const pressed = useSharedValue(false);

  const tap = Gesture.Tap()
    .onBegin(() => { pressed.value = true; })
    .onFinalize(() => {
      pressed.value = false;
      runOnJS(onPress)();
    });

  const animatedStyle = useAnimatedStyle(() => ({
    transform: [{ scale: withTiming(pressed.value ? 0.95 : 1, { duration: 80 }) }],
  }));

  return (
    <GestureDetector gesture={tap}>
      <Animated.View style={[styles.button, animatedStyle]}>
        {children}
      </Animated.View>
    </GestureDetector>
  );
};
```

---

## 4. Scroll Performance

### useAnimatedScrollHandler

Attaches a worklet scroll handler that runs on the UI thread. Use it instead of `onScroll` with an `Animated.event` when you need scroll-linked animations:

```tsx
import Animated, {
  useAnimatedScrollHandler,
  useSharedValue,
  interpolate,
  Extrapolation,
} from 'react-native-reanimated';

const ScrollLinkedHeader = () => {
  const scrollY = useSharedValue(0);

  const scrollHandler = useAnimatedScrollHandler({
    onScroll: (event) => {
      'worklet';
      scrollY.value = event.contentOffset.y;
    },
  });

  const headerStyle = useAnimatedStyle(() => ({
    opacity: interpolate(scrollY.value, [0, 80], [1, 0], Extrapolation.CLAMP),
    transform: [
      { translateY: interpolate(scrollY.value, [0, 80], [0, -20], Extrapolation.CLAMP) },
    ],
  }));

  return (
    <>
      <Animated.View style={[styles.header, headerStyle]} />
      <Animated.ScrollView onScroll={scrollHandler} scrollEventThrottle={16} />
    </>
  );
};
```

### FlashList v2 Architecture

FlashList v2 (Shopify) replaces FlatList's virtualization with a native recycler view backed by `RecyclerListView`. Key improvements over v1:

- **Native cell recycling** — cells are reused from a pool rather than unmounted/remounted, eliminating the JS reconciliation cost per scroll tick.
- **Horizontal FlashList** — v2 ships a performant horizontal mode with the same native recycler.
- **Automatic `estimatedItemSize`** — v2 measures rendered items and updates the estimate automatically, reducing blank areas.
- **`overrideItemLayout`** — explicitly set size per item when you know it ahead of time, bypassing measurement entirely.

```tsx
import { FlashList } from '@shopify/flash-list';

<FlashList
  data={items}
  renderItem={({ item }) => <ItemRow item={item} />}
  estimatedItemSize={72}
  keyExtractor={(item) => item.id}
  // Override for known variable heights — skips measurement
  overrideItemLayout={(layout, item) => {
    layout.size = item.imageHeight ? item.imageHeight + 72 : 72;
  }}
/>
```

For grid layouts, use `MasonryFlashList` from the same package:

```tsx
import { MasonryFlashList } from '@shopify/flash-list';

<MasonryFlashList
  data={photos}
  numColumns={2}
  renderItem={({ item }) => <PhotoCard photo={item} />}
  estimatedItemSize={200}
  // Column-aware layout without manual width calculation
/>
```

### Sticky Header Known Issues (Reanimated #6992)

Reanimated's `useAnimatedScrollHandler` has a known issue (GitHub issue #6992) where animated sticky headers flicker or jump on the first scroll event on Android. The root cause is that the initial scroll position reported to the worklet does not account for the header's pre-layout offset.

Workaround until fixed: initialize `scrollY` to the sticky header's height and clamp the interpolation range to exclude the zero-to-header-height range:

```tsx
const HEADER_HEIGHT = 56;
const scrollY = useSharedValue(HEADER_HEIGHT); // initialize above zero

const stickyStyle = useAnimatedStyle(() => ({
  transform: [
    {
      translateY: interpolate(
        scrollY.value,
        [HEADER_HEIGHT, HEADER_HEIGHT + 80],
        [0, -HEADER_HEIGHT],
        Extrapolation.CLAMP,
      ),
    },
  ],
}));
```

Alternatively, use the native stack's `headerTransparent` option with a `BlurView` instead of building a custom animated sticky header.

### Pull-to-Refresh Optimization

Trigger the network request immediately when `onRefresh` fires and set `refreshing` to `false` as soon as the data arrives — do not wait for animations to complete:

```tsx
const [refreshing, setRefreshing] = useState(false);
const { refetch } = useQuery({ queryKey: ['feed'], queryFn: fetchFeed });

const onRefresh = useCallback(async () => {
  setRefreshing(true);
  await refetch();
  setRefreshing(false);
}, [refetch]);

<FlashList
  refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
  {...listProps}
/>
```

### Infinite Scroll Patterns

Use FlashList's `onEndReached` with a guard to prevent duplicate fetches:

```tsx
const { data, fetchNextPage, hasNextPage, isFetchingNextPage } = useInfiniteQuery({
  queryKey: ['feed'],
  queryFn: ({ pageParam = 0 }) => fetchFeed({ cursor: pageParam }),
  getNextPageParam: (lastPage) => lastPage.nextCursor,
});

const items = useMemo(
  () => data?.pages.flatMap((page) => page.items) ?? [],
  [data],
);

<FlashList
  data={items}
  renderItem={renderItem}
  estimatedItemSize={72}
  onEndReached={() => {
    if (hasNextPage && !isFetchingNextPage) fetchNextPage();
  }}
  onEndReachedThreshold={0.3}
  ListFooterComponent={isFetchingNextPage ? <ActivityIndicator /> : null}
/>
```

---

## 5. Screen Transitions

### Native Stack vs JS Stack

`@react-navigation/native-stack` uses native `UINavigationController` (iOS) and `FragmentTransaction` (Android) — hardware-accelerated, runs at 60fps regardless of JS load. The JS stack (`@react-navigation/stack`) builds transitions in JS with the Animated API, which drops frames during heavy navigation.

Always prefer `native-stack`. Only fall back to `stack` for fully custom JS-driven transitions that native stack cannot achieve.

```tsx
import { createNativeStackNavigator } from '@react-navigation/native-stack';

const Stack = createNativeStackNavigator();

<Stack.Navigator
  screenOptions={{
    animation: 'slide_from_right',
    animationDuration: 350,
    gestureEnabled: true,
    fullScreenGestureEnabled: true, // swipe-back from anywhere (iOS)
  }}
>
  <Stack.Screen name="Feed" component={FeedScreen} />
  <Stack.Screen name="Detail" component={DetailScreen} />
</Stack.Navigator>
```

### Custom Transition Animations with Reanimated

Drive screen-level animations from `useFocusEffect` to tie the animation lifecycle to route focus:

```tsx
import { useFocusEffect } from '@react-navigation/native';

const DetailScreen = () => {
  const opacity = useSharedValue(0);
  const translateY = useSharedValue(30);

  useFocusEffect(
    useCallback(() => {
      opacity.value = withTiming(1, { duration: 250 });
      translateY.value = withSpring(0);

      return () => {
        opacity.value = withTiming(0, { duration: 150 });
      };
    }, []),
  );

  const animatedStyle = useAnimatedStyle(() => ({
    opacity: opacity.value,
    transform: [{ translateY: translateY.value }],
  }));

  return <Animated.View style={animatedStyle}>{/* content */}</Animated.View>;
};
```

### Shared Element Transitions (Reanimated 4.2.0+)

Reanimated 4.2.0 ships stable shared element transitions via `sharedTransitionTag`. Both views (source and destination) must have the same tag; Reanimated morphs between them during the screen transition.

```tsx
// List screen — thumbnail
<Animated.Image
  source={{ uri: item.imageUrl }}
  sharedTransitionTag={`image-${item.id}`}
  style={styles.thumbnail}
/>

// Detail screen — hero image, same tag
<Animated.Image
  source={{ uri: item.imageUrl }}
  sharedTransitionTag={`image-${item.id}`}
  style={styles.hero}
/>
```

Shared element transitions are experimental before 4.2.0. On Old Architecture, use `react-native-shared-element` with React Navigation bindings as an alternative.

Constraints:
- Both screens must be mounted simultaneously during the transition (native-stack handles this automatically).
- Only `transform`, `opacity`, `width`, `height`, and `borderRadius` animate by default. Custom properties require a `SharedTransition` config.
- Do not use `sharedTransitionTag` on `FlatList` items without `keyExtractor` — the tag must be unique across the current render tree.

### Preloading Next Screen Data

Start fetching the next screen's data before the transition completes. With React Query, call `queryClient.prefetchQuery` on press — by the time the 350ms transition finishes the data is already cached:

```tsx
const FeedItem = ({ item }: { item: Post }) => {
  const queryClient = useQueryClient();
  const navigation = useNavigation();

  const handlePress = () => {
    // Prefetch while transition plays
    queryClient.prefetchQuery({
      queryKey: ['post', item.id],
      queryFn: () => fetchPost(item.id),
    });
    navigation.navigate('Detail', { id: item.id });
  };

  return <Pressable onPress={handlePress}>{/* row */}</Pressable>;
};
```

### Skeleton Screen Patterns

Show a skeleton immediately using React Query's `placeholderData` with list cache data as the seed:

```tsx
import { MotiView } from 'moti/skeleton'; // or react-native-fast-shimmer

const DetailScreen = ({ route }: Props) => {
  const { id } = route.params;
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['post', id],
    queryFn: () => fetchPost(id),
    placeholderData: () =>
      queryClient.getQueryData<Post[]>(['posts'])?.find((p) => p.id === id),
  });

  if (isLoading && !data) return <DetailSkeleton />;
  return <Detail post={data!} />;
};
```

`react-native-fast-shimmer` renders the shimmer gradient entirely on the GPU using a Metal/OpenGL shader — cheaper than the JS-interpolated gradient in `moti/skeleton` for lists with many skeleton rows.

---

## 6. Skia Rendering

### GPU-Rendered Custom Graphics

React Native Skia exposes the Skia graphics library via a React API. It renders to a `<Canvas>` using the GPU (Metal on iOS, OpenGL ES / Vulkan on Android), bypassing the React Native view system entirely. No native views are created for individual shapes — every frame is a single GPU draw pass.

```tsx
import { Canvas, Circle, Paint } from '@shopify/react-native-skia';
import Animated, { useAnimatedProps } from 'react-native-reanimated';

const AnimatedCircle = Animated.createAnimatedComponent(Circle);

const PulsingDot = () => {
  const r = useSharedValue(20);

  useEffect(() => {
    r.value = withRepeat(withTiming(30, { duration: 600 }), -1, true);
    return () => cancelAnimation(r);
  }, []);

  const animatedProps = useAnimatedProps(() => ({ r: r.value }));

  return (
    <Canvas style={{ width: 80, height: 80 }}>
      <AnimatedCircle cx={40} cy={40} animatedProps={animatedProps}>
        <Paint color="pink" />
      </AnimatedCircle>
    </Canvas>
  );
};
```

### 120fps on ProMotion Displays

Skia's rendering pipeline runs at the display's native refresh rate automatically — no configuration needed. Because the canvas is GPU-driven, it can sustain 120fps on ProMotion iPhones and iPad Pros without the JS thread as a bottleneck.

### iOS ProMotion Fix: CADisableMinimumFrameDurationOnPhone

On iOS, apps must opt in to 120Hz via `Info.plist`. Without this flag, `CADisplayLink` is capped at 60Hz even on ProMotion hardware:

```xml
<!-- ios/YourApp/Info.plist -->
<key>CADisableMinimumFrameDurationOnPhone</key>
<true/>
```

This key applies to all animations — Reanimated, Skia, and Animated API with native driver. Reanimated reads this flag at startup and activates 120fps scheduling automatically.

### Canvas Rendering Performance

Skia redraws the entire canvas each frame. Keep draw calls manageable:

- Batch static shapes into a single `Path` — one draw call instead of many
- Use `layer` for opacity groups to avoid per-shape alpha compositing
- Avoid `saveLayer` in tight loops — it allocates an offscreen buffer
- Precompute `Skia.Color` constants at module level to avoid string parsing per frame

```tsx
import { Skia } from '@shopify/react-native-skia';

// Module level — parsed once
const BRAND_COLOR = Skia.Color('#FF3D8B');
const SHADOW_COLOR = Skia.Color('rgba(255, 61, 139, 0.12)');
```

---

## 7. Lottie Optimization

### .lottie Format

The `.lottie` format is a zipped binary container for animation data. It is 70–80% smaller than the equivalent JSON file, reducing bundle size and parse time. Use `.lottie` everywhere — `lottie-react-native` v6+ supports it natively.

```tsx
import LottieView from 'lottie-react-native';

<LottieView
  source={require('./animations/success.lottie')} // prefer .lottie over .json
  autoPlay
  loop={false}
  style={{ width: 120, height: 120 }}
/>
```

### Unmount When Not Visible

A mounted `LottieView` with `loop={true}` continuously decodes frames and keeps the CPU active. Unmount it when it scrolls off screen or when the user navigates away:

```tsx
const AnimatedBadge = ({ isVisible }: { isVisible: boolean }) => {
  if (!isVisible) return null; // unmount stops all CPU work

  return (
    <LottieView
      source={require('./badge.lottie')}
      autoPlay
      loop
      style={{ width: 40, height: 40 }}
    />
  );
};
```

### renderMode="HARDWARE" for GPU

| Prop | Value | Effect |
|---|---|---|
| `cacheComposition` | `true` (default) | Parses animation data once, reuses on re-mount |
| `renderMode` | `'HARDWARE'` | GPU rendering on Android — faster for complex multi-layer animations |
| `autoPlay` | `false` + `ref.play()` | Defer start until component is visible |

```tsx
const lottieRef = useRef<LottieView>(null);

useEffect(() => {
  lottieRef.current?.play();
}, []);

<LottieView
  ref={lottieRef}
  source={require('./animation.lottie')}
  autoPlay={false}
  loop={false}
  cacheComposition
  renderMode="HARDWARE"
  style={{ width: 200, height: 200 }}
/>
```

---

## 8. Shadow Performance

### iOS Shadows Are Expensive

iOS computes shadows by rendering the view's content to an offscreen buffer, computing the shadow mask from the alpha channel, and blending it into the scene. Every animated or frequently-updated view with `shadowRadius > 0` triggers this offscreen pass every frame, significantly increasing GPU load.

```tsx
// Expensive — triggers offscreen render every frame if the view animates
const styles = StyleSheet.create({
  expensiveShadow: {
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.15,
    shadowRadius: 12,
  },
});
```

### react-native-fast-shadow

`react-native-fast-shadow` renders shadows as pre-computed blurred images rather than runtime offscreen renders. Drop-in replacement for the shadow style props:

```tsx
import { Shadow } from 'react-native-fast-shadow';

// Rendered as a pre-blurred image — zero per-frame GPU cost
<Shadow distance={12} startColor="rgba(0,0,0,0.12)" offset={[0, 4]} radius={16}>
  <View style={styles.card}>
    <CardContent />
  </View>
</Shadow>
```

### Android Elevation Is Cheaper

Android's `elevation` prop is pre-computed from the view's shape — no offscreen render. It can be used freely on animated views.

```tsx
const styles = StyleSheet.create({
  shadow: Platform.select({
    ios: {
      shadowColor: '#000',
      shadowOffset: { width: 0, height: 2 },
      shadowOpacity: 0.1,
      shadowRadius: 6,
    },
    android: {
      elevation: 4, // cheap, no offscreen render
    },
    default: {},
  }),
});
```

### shouldRasterizeIOS for Static Shadows

For views whose shadow does not change after mount, enable rasterization. The view (including its shadow) is rendered once to a bitmap and reused on subsequent frames:

```tsx
<View
  style={styles.cardShadow}
  shouldRasterizeIOS
  renderToHardwareTextureAndroid
>
  <CardContent />
</View>
```

Do not rasterize views that animate their contents — the bitmap is regenerated on every change, negating the benefit.

---

## 9. 120fps Considerations

### ProMotion Display Configuration

Two steps are required to unlock 120fps on iOS:

1. Set `CADisableMinimumFrameDurationOnPhone` to `true` in `Info.plist` (see section 6).
2. Ensure all animations run on the UI thread (Reanimated worklets or `useNativeDriver: true`).

JS-driven animations cannot benefit from 120Hz — the JS thread runs on a 16ms budget and cannot schedule at 8.33ms intervals.

### 8.33ms Frame Budget

At 120fps each frame has an 8.33ms budget (vs 16.67ms at 60fps). Worklets that compute expensive style values (large `interpolate` chains, nested `useDerivedValue` calls) must complete in under 8ms to avoid frame drops. Profile with Reanimated DevTools' frame timeline at 120Hz before shipping.

Spring animations are frame-rate-independent by nature — they are driven by physics equations, not frame counts. `withTiming` wall-clock durations are unchanged; the motion is simply smoother.

### Max Animated Components on Low-End Android

High-end Android devices support 90–120Hz; low-end devices are capped at 60Hz and have slower CPUs. Benchmark shows approximately 100 simultaneously animated components before frame drops appear on a 2022 low-end Android device (Snapdragon 680, 60Hz).

Strategies for low-end devices:
- Reduce animation concurrency — stagger entrances so only 5–10 elements animate simultaneously.
- Use `ReduceMotion.System` to respect the "reduce motion" accessibility setting.
- Disable decorative animations (parallax, Lottie loops) on low-end devices detected via `DeviceInfo.isLowRamDeviceSync()`.

### useFrameCallback for Frame-Precise Animations

`useFrameCallback` fires a worklet on every frame with a precise timestamp and delta. Use it for procedural animations (audio visualizers, physics simulations) that cannot be expressed with `withSpring`/`withTiming`:

```tsx
import { useFrameCallback, useSharedValue } from 'react-native-reanimated';

const WaveformBar = () => {
  const height = useSharedValue(10);
  const phase = useSharedValue(0);

  useFrameCallback((frameInfo) => {
    'worklet';
    phase.value += frameInfo.timeSincePreviousFrame / 1000; // seconds
    height.value = 10 + Math.sin(phase.value * Math.PI * 2) * 30;
  });

  const barStyle = useAnimatedStyle(() => ({
    height: height.value,
  }));

  return <Animated.View style={[styles.bar, barStyle]} />;
};
```

`frameInfo.timeSincePreviousFrame` is the actual elapsed milliseconds since the last frame — use it to drive time-based animations that remain correct regardless of frame rate.

---

## 10. Anti-Patterns

| Anti-Pattern | Fix |
|---|---|
| `Animated` without `useNativeDriver` | Use Reanimated |
| `Animated` for layout properties | Use Reanimated layout animations |
| Lottie always mounted | Unmount when not visible |
| Heavy iOS `shadowRadius` on animated views | Use `react-native-fast-shadow` or `shouldRasterizeIOS` |
| JS-driven gesture tracking (`PanResponder`) | Gesture Handler + Reanimated |
| Many simultaneous animations without cleanup | Batch with `cancelAnimation` on unmount |
| Calling `setState` from inside a worklet | Wrap with `runOnJS(setState)(value)` |
| `withRepeat` without unmount cleanup | Cancel in `useEffect` cleanup |
| Inline animated styles in JSX | Extract to `useAnimatedStyle` hook |
| 120fps animations without `CADisableMinimumFrameDurationOnPhone` | Add the `Info.plist` key |

### Cleanup Pattern for Looping Animations

```tsx
const PulsingIcon = () => {
  const scale = useSharedValue(1);

  useEffect(() => {
    scale.value = withRepeat(
      withTiming(1.15, { duration: 800, easing: Easing.inOut(Easing.ease) }),
      -1,
      true,
    );

    return () => {
      cancelAnimation(scale); // stop the loop when component unmounts
    };
  }, []);

  const animatedStyle = useAnimatedStyle(() => ({
    transform: [{ scale: scale.value }],
  }));

  return <Animated.View style={animatedStyle}>{/* icon */}</Animated.View>;
};
```

### Batching Multiple Animations

When many values need to animate simultaneously (e.g., staggered list entrance), define all animations in one `useEffect` so Reanimated batches the worklet dispatches:

```tsx
const StaggeredList = ({ items }: { items: Item[] }) => {
  const opacities = items.map(() => useSharedValue(0));
  const translates = items.map(() => useSharedValue(20));

  useEffect(() => {
    items.forEach((_, i) => {
      opacities[i].value = withDelay(i * 50, withTiming(1, { duration: 300 }));
      translates[i].value = withDelay(i * 50, withSpring(0));
    });
  }, []);

  return (
    <View>
      {items.map((item, i) => {
        const animatedStyle = useAnimatedStyle(() => ({
          opacity: opacities[i].value,
          transform: [{ translateY: translates[i].value }],
        }));

        return (
          <Animated.View key={item.id} style={animatedStyle}>
            <ItemRow item={item} />
          </Animated.View>
        );
      })}
    </View>
  );
};
```

---

## 11. Moti Library Patterns

### When to Use Moti

Moti wraps Reanimated 3/4 behind a JSX-friendly declarative API. It eliminates `useSharedValue` / `useAnimatedStyle` boilerplate for straightforward cases. Its trade-off: every animation is expressed as `from`/`animate` props, which is ergonomic for enter/exit and loop animations but less flexible than raw Reanimated for gesture-driven or scroll-linked effects.

Choose Moti when:
- The animation is driven by React state (not gestures or scroll position).
- You want enter/exit animations without setting up `useEffect` + `withRepeat`.
- You need a quick shimmer skeleton without writing a Reanimated worklet.

Stick with raw Reanimated when:
- Animation values are updated from a gesture callback.
- You need `useDerivedValue`, `useAnimatedReaction`, or `useFrameCallback`.
- Fine-grained control over timing, spring config per-frame, or complex sequencing is required.

### MotiView Animation Patterns

```tsx
import { MotiView } from 'moti';
import { Easing } from 'react-native-reanimated';

// Enter / exit driven by state — no shared value needed
const Tooltip = ({ visible }: { visible: boolean }) => (
  <MotiView
    animate={{ opacity: visible ? 1 : 0, scale: visible ? 1 : 0.9 }}
    transition={{ type: 'timing', duration: 150, easing: Easing.out(Easing.ease) }}
  >
    <TooltipContent />
  </MotiView>
);

// Looping pulse — equivalent to withRepeat(withTiming(...), -1, true)
const PulseBadge = () => (
  <MotiView
    from={{ scale: 1, opacity: 1 }}
    animate={{ scale: 1.15, opacity: 0.7 }}
    transition={{ type: 'timing', duration: 700, loop: true, repeatReverse: true }}
    style={styles.badge}
  />
);
```

All MotiView animations run on the UI thread via Reanimated — there is no bridge overhead.

### Skeleton Shimmer Performance with `moti/skeleton`

`moti/skeleton` renders a shimmer gradient driven by a Reanimated worklet on the UI thread. Each `Skeleton` cell is a masked gradient that sweeps from left to right, respecting the child's border radius automatically.

```tsx
import { Skeleton } from 'moti/skeleton';
import { MotiView } from 'moti';

const PostCardSkeleton = () => (
  <MotiView style={styles.card}>
    {/* Avatar */}
    <Skeleton colorMode="light" radius="round" height={40} width={40} />

    <View style={styles.textBlock}>
      {/* Title line */}
      <Skeleton colorMode="light" height={14} width="70%" />
      <View style={{ height: 6 }} />
      {/* Subtitle line */}
      <Skeleton colorMode="light" height={12} width="45%" />
    </View>
  </MotiView>
);
```

Performance notes:
- Use `colorMode="dark"` on dark-background screens — avoids the contrast mismatch that makes the shimmer invisible.
- Avoid rendering more than ~30 `Skeleton` cells simultaneously; above that, `react-native-fast-shimmer` (Metal/OpenGL shader) has lower GPU load.
- Do not conditionally mount individual `Skeleton` cells — render the full skeleton layout and swap it out with the real content at once. Partial swapping causes layout jitter.

### Moti vs Raw Reanimated Comparison

| | Moti | Raw Reanimated |
|---|---|---|
| State-driven animations | Excellent — `animate` prop maps 1:1 to state | Requires `useEffect` + `withTiming`/`withSpring` |
| Gesture-driven animations | Not supported | Native — runs in gesture callbacks |
| Scroll-linked effects | Not supported | `useAnimatedScrollHandler` |
| Looping animations | One-liner via `transition.loop` | `withRepeat` + `useEffect` cleanup |
| Custom animation sequencing | Limited | `withSequence`, `withDelay` |
| Bundle size | +Moti (~14 kB) on top of Reanimated | Reanimated only |
| Debugging | Standard Reanimated DevTools | Standard Reanimated DevTools |

---

## 12. SVG Animation Performance

### react-native-svg + Reanimated Integration

Combine `react-native-svg` with `Animated.createAnimatedComponent` (or Reanimated's equivalent) to drive SVG attributes from shared values on the UI thread.

```tsx
import Svg, { Circle } from 'react-native-svg';
import Animated, {
  useSharedValue,
  useAnimatedProps,
  withTiming,
  useEffect,
} from 'react-native-reanimated';

const AnimatedCircle = Animated.createAnimatedComponent(Circle);

const AnimatedProgressRing = ({ progress }: { progress: number }) => {
  const RADIUS = 45;
  const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

  const animatedProgress = useSharedValue(0);

  useEffect(() => {
    animatedProgress.value = withTiming(progress, { duration: 600 });
  }, [progress]);

  const animatedProps = useAnimatedProps(() => ({
    strokeDashoffset: CIRCUMFERENCE * (1 - animatedProgress.value),
  }));

  return (
    <Svg width={100} height={100} viewBox="0 0 100 100">
      {/* Track ring — static */}
      <Circle
        cx={50}
        cy={50}
        r={RADIUS}
        stroke="#E5E7EB"
        strokeWidth={8}
        fill="none"
      />
      {/* Progress ring — animated */}
      <AnimatedCircle
        cx={50}
        cy={50}
        r={RADIUS}
        stroke="#FF3D8B"
        strokeWidth={8}
        fill="none"
        strokeDasharray={`${CIRCUMFERENCE} ${CIRCUMFERENCE}`}
        strokeLinecap="round"
        animatedProps={animatedProps}
        // rotate so the arc starts at 12 o'clock
        transform="rotate(-90 50 50)"
      />
    </Svg>
  );
};
```

### SVG Path Morphing Performance

Morphing between two SVG path strings requires that both paths have the same number of commands and point counts. Libraries like `react-native-svg-animations` or hand-rolled interpolation with `interpolatePath` (from `d3-interpolate-path`) handle the numeric interpolation.

```tsx
import { interpolatePath } from 'd3-interpolate-path';
import { useDerivedValue, useAnimatedProps } from 'react-native-reanimated';

const morphed = useDerivedValue(() => {
  'worklet';
  // interpolatePath must be called with 'worklet' directive
  return interpolatePath(t.value, pathA, pathB);
});

const animatedProps = useAnimatedProps(() => ({
  d: morphed.value,
}));
```

Path morphing is CPU-intensive — each frame recalculates every control point. Cap simultaneous morphing SVGs at 2–3. For complex morphs, bake frames into a Lottie animation instead.

### SVG viewBox Scaling with Animations

Avoid animating `width` or `height` on the `<Svg>` root element — it triggers a layout pass. Instead, keep the `<Svg>` at a fixed size and animate an inner `<G>` with a `transform` scale:

```tsx
const AnimatedG = Animated.createAnimatedComponent(G);

const animatedProps = useAnimatedProps(() => ({
  transform: [{ scale: scale.value }],
}));

<Svg width={200} height={200} viewBox="0 0 200 200">
  <AnimatedG animatedProps={animatedProps}>
    {/* content scales without SVG layout recalc */}
  </AnimatedG>
</Svg>
```

### When to Prefer Skia over SVG for Complex Graphics

| Scenario | Prefer |
|---|---|
| Simple progress rings, icons, basic shapes | `react-native-svg` — smaller dependency, familiar API |
| Charts with hundreds of data points | Skia — single GPU draw pass |
| Real-time animations at 120fps | Skia — no per-shape native view overhead |
| Filters, blur, blend modes | Skia — native shader support |
| Accessibility labels on shapes | SVG — native a11y attributes |
| Design-exported SVG files | SVG — direct import via `react-native-svg-transformer` |

SVG creates one native view per element. A chart with 200 bar segments means 200 native views updated each frame. Skia renders all 200 in a single GPU draw call.

---

## 13. Shared Element Transitions Deep Dive

### react-navigation-shared-element (Legacy Approach)

`react-navigation-shared-element` is the pre-Reanimated 4 solution. It works by:
1. Capturing a screenshot of the source element at press time.
2. Overlaying a cloned animated view on top of both screens during the transition.
3. Morphing the clone from the source frame to the destination frame.

The screenshot capture runs on the JS thread and is limited to view properties measurable synchronously (position, size, border radius). It does not support blur, gradients, or dynamically rendered content inside the source view.

```tsx
// Legacy setup — still valid on Old Architecture or Reanimated < 4.2.0
import { SharedElement } from 'react-navigation-shared-element';

// List screen
<SharedElement id={`photo-${item.id}`}>
  <Image source={{ uri: item.url }} style={styles.thumbnail} />
</SharedElement>

// Detail screen
<SharedElement id={`photo-${item.id}`}>
  <Image source={{ uri: item.url }} style={styles.hero} />
</SharedElement>
```

Configure the navigator with `createSharedElementStackNavigator` from `react-navigation-shared-element`.

### Native Shared Transitions via react-native-screens

`react-native-screens` (v3.29+) exposes a native shared transition API built on `UIViewPropertyAnimator` (iOS) and `SharedElementTransition` (Android). Unlike the library approach, the transition runs entirely in native code — no JS screenshot capture.

```tsx
import { SharedTransition, withSpring } from 'react-native-reanimated';

// Custom transition config
const customTransition = SharedTransition.custom((values) => {
  'worklet';
  return {
    height: withSpring(values.targetHeight),
    width: withSpring(values.targetWidth),
    originX: withSpring(values.targetOriginX),
    originY: withSpring(values.targetOriginY),
    borderRadius: withSpring(values.targetBorderRadius),
  };
});

// Source view (list)
<Animated.Image
  source={{ uri: item.url }}
  sharedTransitionTag={`photo-${item.id}`}
  sharedTransitionStyle={customTransition}
  style={styles.thumbnail}
/>

// Destination view (detail)
<Animated.Image
  source={{ uri: item.url }}
  sharedTransitionTag={`photo-${item.id}`}
  sharedTransitionStyle={customTransition}
  style={styles.hero}
/>
```

### Multi-Element Coordination

For a photo gallery card with a thumbnail, title, and author that all share-transition to a detail screen, assign a unique tag per element and keep tag suffixes consistent:

```tsx
// Gallery card
<Animated.Image sharedTransitionTag={`img-${item.id}`} style={styles.thumb} />
<Animated.Text sharedTransitionTag={`title-${item.id}`} style={styles.title}>
  {item.title}
</Animated.Text>
<Animated.Text sharedTransitionTag={`author-${item.id}`} style={styles.author}>
  {item.author}
</Animated.Text>

// Detail screen — matching tags
<Animated.Image sharedTransitionTag={`img-${item.id}`} style={styles.hero} />
<Animated.Text sharedTransitionTag={`title-${item.id}`} style={styles.heroTitle}>
  {item.title}
</Animated.Text>
<Animated.Text sharedTransitionTag={`author-${item.id}`} style={styles.heroAuthor}>
  {item.author}
</Animated.Text>
```

All tagged elements animate concurrently. Stagger is not configurable at the tag level; apply different spring configs via separate `SharedTransition` instances if needed.

### Performance Comparison: Native vs Library

| | react-navigation-shared-element | react-native-screens native |
|---|---|---|
| Transition thread | JS thread (screenshot capture) | Native / UI thread |
| Architecture support | Old + New | New Architecture recommended |
| Supported properties | position, size, borderRadius | position, size, borderRadius + custom worklet |
| Content fidelity | Screenshot snapshot | Live native view |
| Dynamic content (video, WebGL) | Not supported | Supported on iOS |
| Setup complexity | Navigator replacement | `sharedTransitionTag` prop only |

### Code Example: Photo Gallery Shared Transition

```tsx
// GalleryScreen.tsx
import { FlashList } from '@shopify/flash-list';
import Animated from 'react-native-reanimated';
import { useNavigation } from '@react-navigation/native';

const GalleryScreen = () => {
  const navigation = useNavigation();

  const renderItem = ({ item }: { item: Photo }) => (
    <Pressable onPress={() => navigation.navigate('PhotoDetail', { id: item.id })}>
      <Animated.Image
        source={{ uri: item.thumbnailUrl }}
        sharedTransitionTag={`photo-${item.id}`}
        style={styles.gridThumbnail}
      />
    </Pressable>
  );

  return (
    <FlashList
      data={photos}
      renderItem={renderItem}
      numColumns={3}
      estimatedItemSize={120}
    />
  );
};

// PhotoDetailScreen.tsx
const PhotoDetailScreen = ({ route }: Props) => {
  const { id } = route.params;
  const photo = usePhotoById(id);

  return (
    <ScrollView>
      <Animated.Image
        source={{ uri: photo.fullUrl }}
        sharedTransitionTag={`photo-${id}`}
        style={styles.heroImage}
      />
      <PhotoInfo photo={photo} />
    </ScrollView>
  );
};
```

Constraints (same as section 5):
- Both screens must be mounted simultaneously — native-stack satisfies this.
- `sharedTransitionTag` must be unique in the render tree.
- Test on a physical device; the iOS Simulator does not fully reproduce ProMotion timing.

---

## 14. requestAnimationFrame vs Reanimated Timing

### When to Use `requestAnimationFrame`

`requestAnimationFrame` (RAF) is a Web-standard API available in React Native. It schedules a callback on the JS thread before the next frame paint. Because it runs on the JS thread, it is subject to all JS thread contention.

Use RAF only when:
- You need to trigger a React state update tied to a frame boundary.
- You are integrating with a third-party library that provides frame callbacks (e.g., a Web-ported physics engine).
- You are writing a quick prototype and Reanimated is not yet installed.

In all other cases, prefer `useFrameCallback` — it runs on the UI thread at the device's max refresh rate.

### RAF Limitations and Bridge Overhead

```tsx
// RAF — runs on JS thread, subject to JS jank
const startRafAnimation = () => {
  const start = performance.now();

  const tick = (now: number) => {
    const elapsed = now - start;
    const progress = Math.min(elapsed / 600, 1);

    // setState triggers React reconciliation — expensive per frame
    setOpacity(progress);

    if (progress < 1) requestAnimationFrame(tick);
  };

  requestAnimationFrame(tick);
};
```

Problems with this pattern:
- `setState` per frame triggers a React reconciliation pass.
- The JS thread must be free at the frame boundary — under navigation or network load it will miss frames.
- RAF callbacks are batched and deferred by the bridge — actual timing is less precise than `useFrameCallback`.

### RAF Scheduling: New vs Old Architecture

| | Old Architecture (Bridge) | New Architecture (JSI) |
|---|---|---|
| RAF scheduling | Batched over bridge, ~1–2 frame delay | Synchronous JSI, closer to native timing |
| Accuracy vs `useFrameCallback` | ±2–4ms jitter | ±1–2ms jitter (still worse than UI thread) |
| JS thread contention impact | High | High (JS thread limitation unchanged) |

New Architecture removes the bridge but RAF still runs on the JS thread. The improvement is in scheduling latency (JSI is synchronous), not in resilience to JS congestion.

### `useFrameCallback` — the Correct Approach

```tsx
import { useFrameCallback, useSharedValue, useAnimatedStyle } from 'react-native-reanimated';

// Runs on UI thread — 60–120fps regardless of JS load
const SmoothProgressBar = ({ isRunning }: { isRunning: boolean }) => {
  const progress = useSharedValue(0);

  useFrameCallback((frameInfo) => {
    'worklet';
    if (!isRunning) return;
    // timeSincePreviousFrame keeps progress rate constant regardless of FPS
    progress.value = Math.min(progress.value + frameInfo.timeSincePreviousFrame / 3000, 1);
  }, isRunning);

  const barStyle = useAnimatedStyle(() => ({
    width: `${progress.value * 100}%`,
  }));

  return (
    <View style={styles.track}>
      <Animated.View style={[styles.fill, barStyle]} />
    </View>
  );
};
```

### Frame-Based Animation Comparison

```tsx
// --- Option A: requestAnimationFrame (JS thread) ---
const rafProgress = useRef(0);
const [displayProgress, setDisplayProgress] = useState(0);

useEffect(() => {
  let rafId: number;
  const animate = () => {
    rafProgress.current = Math.min(rafProgress.current + 0.005, 1);
    setDisplayProgress(rafProgress.current); // React reconciliation per frame
    if (rafProgress.current < 1) rafId = requestAnimationFrame(animate);
  };
  rafId = requestAnimationFrame(animate);
  return () => cancelAnimationFrame(rafId);
}, []);

// --- Option B: useFrameCallback (UI thread) ---
const progress = useSharedValue(0);

useFrameCallback((info) => {
  'worklet';
  progress.value = Math.min(progress.value + info.timeSincePreviousFrame / 1000, 1);
});

const style = useAnimatedStyle(() => ({
  transform: [{ scaleX: progress.value }],
}));
// No setState, no React render — pure UI thread
```

Option B skips React entirely during the animation. Option A triggers a full React reconciliation every frame — typically 1–3ms of wasted JS work.

---

## 15. Animation Debugging & Profiling

### Reanimated DevTools Usage Patterns

Reanimated DevTools is a browser extension (Chrome/Edge) that connects to the Reanimated runtime via a WebSocket server started by the Metro bundler. Enable it:

```tsx
// babel.config.js — enable DevTools plugin in development
module.exports = {
  plugins: [
    ['react-native-reanimated/plugin', { relativeSourceLocation: true }],
  ],
};
```

Then in the browser extension, connect to `ws://localhost:8082`. You will see:
- A live list of all active shared values and their current values.
- A frame timeline showing UI thread worklet execution time per frame.
- Warnings when a worklet exceeds the frame budget (8.33ms at 120fps, 16.67ms at 60fps).

Use the DevTools to identify:
1. Shared values that update unexpectedly (symptom: excessive animation triggers).
2. Worklets that run too long (symptom: frame budget warnings).
3. Animations that never cancel (symptom: persistent entries in the active animations list after navigation).

### Profiling 120fps Animations

At 120fps the frame budget is 8.33ms. Worklet profiling steps:

1. Open React Native DevTools (Flipper or the built-in debugger) and start a CPU profile while the animation runs.
2. Switch to the "UI thread" lane — worklet functions appear as JS function calls on the UI thread's JS runtime.
3. Identify functions that consistently take > 5ms (leaves < 3.33ms margin for the OS compositor).

Common expensive worklet operations:
- `interpolate` with more than ~10 output range segments.
- Nested `useDerivedValue` chains (each has a small scheduling overhead).
- String concatenation in worklets (e.g., building `transform` strings).
- `Math.random()` inside worklets — always pre-compute random values on the JS thread.

### Identifying Jank Sources in Animations

Jank appears as frame drops visible in the Reanimated DevTools timeline or as Systrace drops in Android's Perfetto.

Common jank sources and fixes:

| Jank Source | Symptom | Fix |
|---|---|---|
| JS thread blocking | Animation pauses during navigation or data fetch | Move animation to worklet / useNativeDriver |
| Layout recalculation inside animation | Width/height changes causing Yoga relayout per frame | Animate `transform: scaleX` instead of `width` |
| Non-worklet function called from worklet | Runtime error or forced JS thread call | Add `'worklet'` directive to the helper function |
| Too many `useAnimatedStyle` hooks on one screen | CPU profile shows many small worklet calls | Consolidate into fewer `useAnimatedStyle` hooks |
| Skia canvas with excessive draw calls | Frame time grows with content complexity | Batch shapes into a single `Path` |
| SVG with many animated nodes | Each node is a separate native view update | Use Skia for complex animated graphics |

### Frame Timeline Interpretation

The Reanimated DevTools frame timeline is a waterfall view with one row per frame:
- **Green** — worklet finished within frame budget.
- **Yellow** — worklet took 70–100% of frame budget; borderline.
- **Red** — worklet exceeded frame budget; frame was dropped.

A single red frame every few seconds is acceptable. Sustained red frames indicate a structural problem (worklet too expensive or too many concurrent animations).

The timeline also shows the frame timestamp delta. At 60fps expect ~16.7ms deltas. At 120fps expect ~8.3ms deltas. A sudden spike to 33ms means two frames were composited together — a dropped frame.

### Measuring Animation FPS with `useFrameCallback`

Instrument your own FPS meter to measure actual frame rate in production builds (DevTools are dev-only):

```tsx
import { useFrameCallback, useSharedValue, runOnJS } from 'react-native-reanimated';
import { useState, useCallback } from 'react';

const useAnimationFPS = () => {
  const [fps, setFps] = useState(0);
  const frameCount = useSharedValue(0);
  const lastReportTime = useSharedValue(0);

  const updateFps = useCallback((value: number) => {
    setFps(Math.round(value));
  }, []);

  useFrameCallback((info) => {
    'worklet';
    frameCount.value += 1;
    const elapsed = info.timestamp - lastReportTime.value;

    if (elapsed >= 1000) {
      // Report FPS to JS thread every second
      const currentFps = (frameCount.value / elapsed) * 1000;
      runOnJS(updateFps)(currentFps);
      frameCount.value = 0;
      lastReportTime.value = info.timestamp;
    }
  });

  return fps;
};

// Usage
const DebugOverlay = () => {
  const fps = useAnimationFPS();
  return (
    <View style={styles.overlay}>
      <Text style={styles.fpsText}>{fps} fps</Text>
    </View>
  );
};
```

Gate this component behind `__DEV__` or a feature flag — `useFrameCallback` runs every frame and the `runOnJS` call every second has a small but measurable overhead.

---

## 16. 120fps ProMotion Detection (Expanded)

> This section expands on the ProMotion basics in section 9.

### Detecting Device Max Refresh Rate at Runtime

iOS does not expose the display refresh rate directly via a React Native API. Use `react-native-device-info` to read device capabilities:

```tsx
import DeviceInfo from 'react-native-device-info';

// At app startup — async, cache the result
let cachedMaxFPS: number | null = null;

const getMaxRefreshRate = async (): Promise<number> => {
  if (cachedMaxFPS !== null) return cachedMaxFPS;

  // DeviceInfo.getDeviceId returns strings like 'iPhone14,2' (iPhone 13 Pro)
  const deviceId = await DeviceInfo.getDeviceId();

  // iPhone 13 Pro, 14 Pro, 15 Pro, 15 Pro Max, iPad Pro M1+ all support 120Hz
  const proMotionDevices = [
    'iPhone14,2', 'iPhone14,3',   // 13 Pro, 13 Pro Max
    'iPhone15,2', 'iPhone15,3',   // 14 Pro, 14 Pro Max
    'iPhone16,1', 'iPhone16,2',   // 15 Pro, 15 Pro Max
  ];

  cachedMaxFPS = proMotionDevices.includes(deviceId) ? 120 : 60;
  return cachedMaxFPS;
};
```

On Android, `react-native-device-info` exposes `DeviceInfo.getMaxMemory()` but not refresh rate directly. Use the `Display` API via a native module or read from `Platform.constants`:

```tsx
import { Platform } from 'react-native';

// Available in New Architecture builds
const maxFPS: number = (Platform.constants as { reactNativeVersion: unknown; maxRefreshRate?: number }).maxRefreshRate ?? 60;
```

### Dynamic Animation Config Based on Capability

Adapt spring and timing configs to the display refresh rate:

```tsx
import { withSpring, withTiming } from 'react-native-reanimated';

type AnimationConfig = {
  springConfig: Parameters<typeof withSpring>[1];
  timingDuration: number;
};

const getAnimationConfig = (maxFPS: number): AnimationConfig => {
  if (maxFPS >= 120) {
    return {
      // At 120fps, spring can use tighter damping — smoother settle
      springConfig: { mass: 0.8, damping: 14, stiffness: 160 },
      timingDuration: 220, // shorter durations feel crisp at 120fps
    };
  }
  return {
    springConfig: { mass: 1, damping: 15, stiffness: 150 },
    timingDuration: 280,
  };
};

// Zustand or Context — set once at app startup
const useAnimationStore = create<{ config: AnimationConfig }>(() => ({
  config: getAnimationConfig(60), // default until detected
}));
```

Initialize at app startup:

```tsx
// App.tsx
useEffect(() => {
  getMaxRefreshRate().then((maxFPS) => {
    useAnimationStore.setState({ config: getAnimationConfig(maxFPS) });
  });
}, []);
```

### Fallback Strategies for Non-ProMotion Devices

Animations authored for 120fps are not broken at 60fps — Reanimated's physics engine is frame-rate-independent. However, certain visual effects become less impactful:

- **Short-duration springs (< 200ms)** — at 60fps fewer frames are rendered, making fast springs look abrupt. Increase duration fallback to 280–300ms on 60Hz.
- **Stagger delays** — at 120fps a 30ms stagger between items is visible and satisfying. At 60fps the same stagger spans only 2 frames; increase to 50ms.
- **Parallax / multi-layer scrolling** — at 60fps multi-layer parallax is perceptible as discrete steps on fast flings. Reduce parallax depth or disable on 60Hz.

```tsx
const STAGGER_DELAY = maxFPS >= 120 ? 30 : 50;
const PARALLAX_FACTOR = maxFPS >= 120 ? 0.3 : 0.1;
```

### Power and Battery Trade-offs at 120fps

Running at 120fps doubles the number of GPU compositing passes compared to 60fps. Measured impact on iPhone 14 Pro:

| Scenario | 60fps | 120fps |
|---|---|---|
| Static screen (no animation) | Baseline | Same — display idles to 1fps |
| Continuous scroll (FlashList) | ~150mA | ~210mA (+40%) |
| Looping Lottie animation | ~170mA | ~250mA (+47%) |
| Reanimated spring (single component) | ~145mA | ~180mA (+24%) |

ProMotion displays use LTPO (Low Temperature Polycrystalline Oxide) technology and dynamically drop to 1Hz when content is static. The power overhead only applies during active animation.

Mitigations:
- Cancel looping animations when the app goes to background (`AppState.addEventListener('change')`).
- Use `ReduceMotion.System` in Reanimated to disable animations when the user enables "Reduce Motion" in iOS Accessibility settings — this also reduces battery consumption for motion-sensitive users.

```tsx
import { ReduceMotion } from 'react-native-reanimated';

// Apply globally via Reanimated config
// All withSpring / withTiming calls respect this setting automatically
const animValue = withSpring(1, {
  reduceMotion: ReduceMotion.System, // respects iOS / Android reduce motion setting
});
```

---

## Quick Reference

| Technique | When to Use | When to Skip |
|---|---|---|
| `useNativeDriver: true` | Simple opacity/transform, no Reanimated dep | Any layout property |
| Reanimated `useAnimatedStyle` | All interactive or complex animations | One-shot opacity fade with native driver |
| `withSpring` | Gesture release, interactive feedback | Fixed-duration UI state transitions |
| `withTiming` | Tab switches, modal open/close | Physics-based interactions |
| Reanimated 4 CSS transitions | Style changes driven by React state | Gesture-driven continuous motion |
| `GestureDetector` | Any draggable, swipeable, or pinchable UI | Static tap-only buttons |
| `FlashList` / `MasonryFlashList` | All virtualized lists | Static lists under ~20 items |
| Lottie `.lottie` format | All new Lottie animations | Never — always prefer over JSON |
| `shouldRasterizeIOS` | Static cards with shadow | Animated views (regenerates bitmap) |
| Android `elevation` | All shadow needs on Android | Never skip this |
| React Native Skia | Custom drawing, charts, filters | Animating standard view properties |
| `cancelAnimation` in cleanup | Any `withRepeat` animation | Single-play animations |
| `useFrameCallback` | Procedural / physics-based animation | Declarative spring or timing animations |
| `CADisableMinimumFrameDurationOnPhone` | All apps targeting ProMotion iOS | Apps that explicitly target 60fps only |
| Prefetch on press | Detail screens with network data | Screens with instant local data |
| Moti `MotiView` | State-driven enter/exit/loop animations | Gesture or scroll-linked animations |
| `moti/skeleton` | Quick shimmer skeletons (< 30 cells) | Large lists — use react-native-fast-shimmer |
| `react-native-svg` + Reanimated | Simple animated icons and progress rings | Charts with > 50 elements — use Skia |
| SVG path morphing | Occasional shape transitions | Continuous high-FPS morphing — use Lottie |
| `sharedTransitionTag` (Reanimated 4.2+) | Photo/card detail transitions | Old Architecture builds |
| `react-navigation-shared-element` | Old Architecture or pre-Reanimated 4.2 | New Architecture builds |
| `requestAnimationFrame` | Third-party Web-ported integrations | All other frame-based animations |
| `useFrameCallback` (vs RAF) | All native frame-rate animations | Static or infrequent value updates |
| Reanimated DevTools | Identifying expensive worklets, jank | Production (dev-only tool) |
| FPS meter via `useFrameCallback` | Production animation health monitoring | Always-on in production (small overhead) |
| ProMotion device detection | Tuning spring/stagger configs per display | Apps with only opacity/transform animations |
| `ReduceMotion.System` | All looping or decorative animations | Mandatory functional animations |
