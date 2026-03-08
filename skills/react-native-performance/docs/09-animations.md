# Animation Performance

## 1. Animation Threading Model

### How Threads Map to Frames

React Native runs on three threads: the **JS thread** (your component and business logic), the **UI thread** (native rendering and layout), and the **Shadow thread** (Yoga layout calculations). All animation work must land on the UI thread at 60Hz to feel smooth. The question is how work gets there.

**JS thread animations (Animated API without `useNativeDriver`)** — every frame the JS thread computes the animated value, serializes it, sends it over the bridge (or JSI in New Architecture), and the UI thread applies it. Under JS load (routing, data fetching, re-renders) frames are dropped because the JS thread cannot keep up. Typical result: ~45fps under real-world load, with visible hitches during navigation or network responses.

**Native driver (`useNativeDriver: true`)** — the animation is serialized once at start time and handed to the UI thread. The UI thread runs it autonomously at ~60fps regardless of JS thread load. The constraint: only `transform` and `opacity` properties are supported. Layout properties (`width`, `height`, `top`, `padding`) cannot be driven natively because they require the Shadow thread's layout pass, which feeds back to JS.

**Reanimated 3/4 worklets** — JS functions annotated with `'worklet'` are compiled and executed directly on the UI thread via JSI. They can run at the device's max refresh rate (60–120fps), have access to shared values synchronously, and support any animatable property including layout. Gesture tracking runs entirely on the UI thread with no bridge round-trips.

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

- **Animated + useNativeDriver** — simple one-shot transitions on `opacity` or `transform` where you have no existing Reanimated dependency and don't want to add one. Entry/exit fades, scale pops.
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
      // Trigger header collapse animation
      headerHeight.value = withTiming(isCollapsed ? 56 : 120);
    }
  },
);
```

Do not use `useAnimatedReaction` to update React state — call `runOnJS` if you need to.

### Layout Animations

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

Custom layout animations — implement `LayoutAnimationFunction` for full control:

```tsx
import { BaseAnimationBuilder, FadeInDown } from 'react-native-reanimated';

const StaggeredFadeIn = (index: number) =>
  FadeInDown.delay(index * 60).springify();

// In a list render:
{items.map((item, i) => (
  <Animated.View key={item.id} entering={StaggeredFadeIn(i)}>
    <ItemCard item={item} />
  </Animated.View>
))}
```

### Shared Element Transitions

Reanimated 3 (New Architecture) ships `useSharedTransition` for shared element transitions between screens. On Old Architecture, use `react-native-shared-element` with React Navigation bindings.

```tsx
// New Architecture — Reanimated 3 shared transitions
import Animated from 'react-native-reanimated';

// In list screen
<Animated.Image
  source={{ uri: item.imageUrl }}
  sharedTransitionTag={`image-${item.id}`}
  style={styles.thumbnail}
/>

// In detail screen — same tag, Reanimated handles the morph
<Animated.Image
  source={{ uri: item.imageUrl }}
  sharedTransitionTag={`image-${item.id}`}
  style={styles.hero}
/>
```

---

## 3. Gesture Performance

### React Native Gesture Handler vs Pressable

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
      // Runs entirely on UI thread — 60-120fps
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

### Simultaneous Gesture Handling

Use `Gesture.Simultaneous` to allow two gestures to recognize at the same time (e.g., pan + pinch):

```tsx
const pinch = Gesture.Pinch().onUpdate((e) => {
  scale.value = savedScale.value * e.scale;
});

const pan = Gesture.Pan().onUpdate((e) => {
  translateX.value = savedX.value + e.translationX;
  translateY.value = savedY.value + e.translationY;
});

const composed = Gesture.Simultaneous(pan, pinch);

return (
  <GestureDetector gesture={composed}>
    <Animated.View style={animatedStyle} />
  </GestureDetector>
);
```

### Gesture Conflict Resolution

When a child gesture needs to block a parent gesture (e.g., horizontal swipe inside a vertical scroll), use `Gesture.Exclusive` or `activeOffsetX`/`failOffsetY` to define when the gesture activates:

```tsx
const horizontalSwipe = Gesture.Pan()
  .activeOffsetX([-10, 10])   // Only activates on horizontal movement
  .failOffsetY([-5, 5]);      // Fails if vertical movement detected first
```

For nested ScrollViews and gesture handlers, wrap the outer scroll with `GestureHandlerRootView` and set `waitFor` to explicitly hand off between gestures.

### Touch Feedback Without JS Bridge

Use RNGH's built-in `TouchableHighlight` or `Pressable` from RNGH rather than the core RN version to ensure the pressed state updates on the UI thread:

```tsx
import { Pressable } from 'react-native-gesture-handler'; // RNGH version

// Or build it with GestureDetector for full control:
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
import Animated, { useAnimatedScrollHandler, useSharedValue } from 'react-native-reanimated';

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

### ScrollView vs FlatList for Small Lists

For fewer than 20 items a `ScrollView` that renders all children at once is often faster than `FlatList` because it avoids the virtualization bookkeeping overhead. FlatList's `initialNumToRender`, windowing, and recycling logic adds JS work that only pays off at larger counts.

Rule of thumb: `ScrollView` for static lists under 20 items, `FlashList` for everything else.

### Sticky Headers

`SectionList` sticky headers require an offscreen render pass on iOS to position them correctly. If sticky headers are not needed, set `stickySectionHeadersEnabled={false}`:

```tsx
<SectionList
  sections={sections}
  stickySectionHeadersEnabled={false} // skip the offscreen pass
  renderSectionHeader={({ section }) => <SectionHeader title={section.title} />}
  renderItem={renderItem}
/>
```

For scroll-linked sticky headers (e.g., collapse on scroll), implement with Reanimated and `useAnimatedStyle` rather than `SectionList`'s built-in sticky mechanism — you get more control and it runs on the UI thread.

### Pull-to-Refresh Optimization

The default `RefreshControl` on Android runs on the JS thread. For a smoother experience, trigger the network request immediately when `onRefresh` fires and set `refreshing` to false as soon as the data arrives — do not wait for animations to complete:

```tsx
const [refreshing, setRefreshing] = useState(false);
const { refetch } = useQuery({ queryKey: ['feed'], queryFn: fetchFeed });

const onRefresh = useCallback(async () => {
  setRefreshing(true);
  await refetch();
  setRefreshing(false);
}, [refetch]);

<FlatList refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />} />
```

### Parallax Scroll Patterns

Implement parallax with Reanimated to keep it on the UI thread:

```tsx
const ParallaxHeader = ({ scrollY }: { scrollY: SharedValue<number> }) => {
  const parallaxStyle = useAnimatedStyle(() => ({
    transform: [
      {
        translateY: interpolate(
          scrollY.value,
          [-200, 0, 200],
          [-100, 0, 60], // header moves at 30% of scroll speed
          Extrapolation.CLAMP,
        ),
      },
    ],
  }));

  return (
    <Animated.Image
      source={{ uri: heroImageUrl }}
      style={[styles.heroImage, parallaxStyle]}
    />
  );
};
```

### Nested Scroll Containers

Avoid nesting a `ScrollView` inside another `ScrollView` with the same scroll axis — both try to capture the gesture and conflict. When you need vertical scroll inside a vertical scroll (e.g., a bottom sheet over a feed), use `ScrollView`'s `nestedScrollEnabled` prop on Android and RNGH's `ScrollView` to let the gesture recognizer decide which container should scroll:

```tsx
import { ScrollView } from 'react-native-gesture-handler';

// Inner scroll inside a bottom sheet
<ScrollView nestedScrollEnabled bounces={false}>
  {sheetContent}
</ScrollView>
```

For horizontal scroll inside a vertical list row, use `GestureDetector` with `failOffsetY` on the horizontal gesture so it only activates on horizontal movement and the vertical scroll remains active.

---

## 5. Screen Transition Performance

### Native Stack vs JS Stack

`@react-navigation/native-stack` uses native `UINavigationController` (iOS) and `FragmentTransaction` (Android) for transitions — hardware-accelerated, runs at 60fps regardless of JS load. The JS stack (`@react-navigation/stack`) builds transitions in JS with the Animated API, which drops frames during heavy navigation.

Always prefer `native-stack`. Only fall back to `stack` when you need a fully custom JS-driven transition that native stack cannot achieve.

```tsx
import { createNativeStackNavigator } from '@react-navigation/native-stack';

const Stack = createNativeStackNavigator();

<Stack.Navigator
  screenOptions={{
    animation: 'slide_from_right',       // Native iOS slide
    animationDuration: 350,
    gestureEnabled: true,
    fullScreenGestureEnabled: true,      // Swipe-back from anywhere (iOS)
  }}
>
  <Stack.Screen name="Feed" component={FeedScreen} />
  <Stack.Screen name="Detail" component={DetailScreen} />
</Stack.Navigator>
```

### Custom Transition Animations with Reanimated

For fully custom transitions, use `react-native-navigation` or implement a custom `cardStyleInterpolator` with the JS stack — but measure the frame rate first. Often a native stack with `presentation: 'modal'` covers most custom transition needs.

When you must use Reanimated for screen transitions, drive the animation from `useSharedValue` initialized in the screen and linked to route focus state:

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

### Preloading Data During Transition

Start fetching the next screen's data before the transition completes. With React Query, call `queryClient.prefetchQuery` on press — by the time the 350ms transition finishes the data is already cached:

```tsx
const FeedItem = ({ item }: { item: Post }) => {
  const queryClient = useQueryClient();
  const navigation = useNavigation();

  const handlePress = () => {
    // Prefetch detail data while transition plays
    queryClient.prefetchQuery({
      queryKey: ['post', item.id],
      queryFn: () => fetchPost(item.id),
    });
    navigation.navigate('Detail', { id: item.id });
  };

  return <Pressable onPress={handlePress}>{/* row content */}</Pressable>;
};
```

### Skeleton Screen Patterns During Transition

Show a skeleton immediately on mount using React Query's `placeholderData`:

```tsx
const DetailScreen = ({ route }: Props) => {
  const { id } = route.params;
  const { data, isLoading } = useQuery({
    queryKey: ['post', id],
    queryFn: () => fetchPost(id),
    placeholderData: () =>
      queryClient.getQueryData<Post[]>(['posts'])?.find((p) => p.id === id),
  });

  if (isLoading && !data) return <DetailSkeleton />;

  return <Detail post={data} />;
};
```

### Measuring Transition Performance

Use Flashlight (CLI) on a physical device to capture frame times during navigation. Simulator measurements are unreliable because the CPU/GPU budget is different.

```bash
# Record a session with Flashlight
npx @perf-tools/flashlight measure --bundleId com.yourapp
# Navigate between screens during the recording
# View the FPS timeline in the generated report
```

---

## 6. Lottie Animations

### .lottie Format vs JSON

The `.lottie` format is a zipped binary container for the animation data. It is 70–80% smaller than the equivalent JSON, reducing bundle size and parse time. Use `.lottie` files everywhere you can — `lottie-react-native` v6+ supports them natively.

```tsx
import LottieView from 'lottie-react-native';

// Prefer .lottie over .json
<LottieView
  source={require('./animations/success.lottie')}
  autoPlay
  loop={false}
  style={{ width: 120, height: 120 }}
/>
```

### Unmount When Not Visible

A mounted `LottieView` with `loop={true}` continuously decodes frames and keeps the CPU active. Unmount it when it scrolls off screen or when the user navigates away:

```tsx
const AnimatedBadge = ({ isVisible }: { isVisible: boolean }) => {
  if (!isVisible) return null; // Unmount stops all CPU work

  return (
    <LottieView
      source={require('./badge.lottie')}
      autoPlay
      loop
      style={{ width: 40, height: 40 }}
    />
  );
};

// In a list — use the onViewableItemsChanged pattern
const renderItem = ({ item }: { item: Item }) => (
  <AnimatedBadge isVisible={item.isInViewport} />
);
```

### LottieView Props for Performance

| Prop | Value | Effect |
|---|---|---|
| `cacheComposition` | `true` (default) | Parses JSON once, reuses parsed data |
| `renderMode` | `'HARDWARE'` | Uses GPU rendering (Android) — faster for complex animations |
| `resizeMode` | `'contain'` | Avoids unnecessary scaling recomputation |
| `autoPlay` | `false` + `ref.play()` | Defer start until component is visible |

```tsx
const lottieRef = useRef<LottieView>(null);

useEffect(() => {
  // Only start playing after the component mounts and is visible
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

### When to Use Lottie vs Reanimated vs Skia

| Use Lottie | Use Reanimated | Use Skia |
|---|---|---|
| Designer-authored animations (After Effects) | Interactive, gesture-driven animations | Custom drawing, charts, masks, shaders |
| Complex multi-layer illustrations | Spring physics, drag-release | Text on path, image filters |
| Fixed, non-interactive playback | Scroll-linked effects | Procedural graphics |
| 50–200 layer animations | Simple transforms and opacity | High-fidelity visual effects |

---

## 7. Skia Rendering

### React Native Skia for Custom Drawing

React Native Skia exposes the Skia graphics library via a React API. It renders to a `<Canvas>` using the GPU, bypassing the React Native view system entirely. Every frame is drawn directly — there are no native views created for individual shapes.

```tsx
import { Canvas, Circle, Paint, LinearGradient, vec } from '@shopify/react-native-skia';
import Animated, { useSharedValue, useAnimatedProps } from 'react-native-reanimated';

const AnimatedCircle = Animated.createAnimatedComponent(Circle);

const PulsingDot = () => {
  const r = useSharedValue(20);

  useEffect(() => {
    r.value = withRepeat(withTiming(30, { duration: 600 }), -1, true);
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

### Canvas Rendering Performance

Skia renders the entire canvas each frame. Keep the number of draw calls per frame manageable:

- Batch static shapes into a single `Path` where possible — one draw call vs many
- Use `layer` for opacity groups to avoid per-shape alpha compositing
- Use `saveLayer` sparingly — it creates an offscreen buffer
- Avoid string `color` values inside animated styles; precompute `Skia.Color` constants at module level

```tsx
import { Skia } from '@shopify/react-native-skia';

// Precompute at module level — avoids parsing on every frame
const BRAND_COLOR = Skia.Color('#FF3D8B');
const SHADOW_COLOR = Skia.Color('rgba(255, 61, 139, 0.12)');
```

### When Skia Is Better than Reanimated

Use Skia when you need:
- Clipping to arbitrary paths (not just `borderRadius`)
- Image filters (blur, color matrix, displacement)
- Drawing text along a path
- Procedural waveforms, charts with thousands of data points
- Gradients on animated shapes (Reanimated cannot animate gradient stops natively)

Use Reanimated when you need:
- Animating existing native views (layout, transform, opacity)
- Gesture-driven animations on view hierarchies
- Screen-level enter/exit transitions

### GPU Acceleration

Skia always uses the GPU on iOS (Metal) and Android (OpenGL ES / Vulkan depending on device). The main cost is the draw calls per frame, not the view hierarchy traversal. Profiling Skia performance requires Metal Debugger (Xcode) or RenderDoc (Android) to inspect GPU frame time.

---

## 8. 120fps Considerations

### ProMotion Displays

iPhone 13 Pro and later, iPad Pro, and many high-end Android devices support 120Hz (ProMotion) adaptive refresh. React Native and Reanimated support 120fps automatically on these devices when the animation is running on the UI thread.

Animations using `useNativeDriver: true` or Reanimated worklets will automatically run at the display's native refresh rate. JS-driven animations are capped by the JS frame budget and will not benefit from 120Hz.

### Setting Preferred Frame Rate

On iOS you can request a specific frame rate for a Reanimated animation using the `FrameCallbackPlugin` or by setting the CADisplayLink preferred frame rate via a native module. In practice, letting the system decide is preferred — iOS scales down to 60Hz when the animation is simple to save battery.

```tsx
// Reanimated automatically uses the display's max refresh rate
// No configuration needed — just ensure animations run on UI thread

// If you need to explicitly target 60fps for battery savings:
import { ReduceMotion } from 'react-native-reanimated';

withSpring(1, {
  reduceMotion: ReduceMotion.System, // Respect system accessibility setting
});
```

### Animation Timing Adjustments for 120fps

`withTiming` durations feel shorter at 120fps because more frames are delivered per second. A 300ms timing animation at 60fps has 18 frames; at 120fps it has 36 frames. The perceived duration is the same in wall-clock time, but the motion is smoother. No changes to durations are required when moving from 60 to 120fps.

Spring animations are frame-rate-independent by nature — they are driven by physics equations, not frame counts.

### Performance Overhead of 120fps

Rendering at 120fps roughly doubles the number of draw calls per second. On Skia-heavy canvases or complex layouts this can increase GPU and CPU load. Profile on a real ProMotion device with Xcode Instruments before shipping 120fps-targeted animations.

---

## 9. Shadow Performance

### iOS Shadows Are Expensive

iOS computes shadows by rendering the view's content to an offscreen buffer, computing the shadow mask from the alpha channel, and blending it into the scene. Every animated or frequently-updated view with `shadowRadius > 0` triggers this offscreen pass every frame, significantly increasing GPU load.

```tsx
// Expensive — triggers offscreen render per frame if view animates
const styles = StyleSheet.create({
  expensiveShadow: {
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.15,
    shadowRadius: 12,
  },
});
```

### Rasterize Static Shadows

For views whose shadow does not change after mount, enable rasterization. The view (including its shadow) is rendered once to a bitmap and reused on subsequent frames:

```tsx
<View
  style={styles.cardShadow}
  shouldRasterizeIOS  // rasterize shadow on iOS
  renderToHardwareTextureAndroid  // equivalent for Android GPU texture cache
>
  <CardContent />
</View>
```

Note: do not rasterize views that animate their contents — the bitmap is regenerated on every change, negating the benefit.

### Android Elevation Is Cheaper

Android's `elevation` prop is implemented via a pre-computed shadow derived from the view's shape and elevation value — no offscreen render. It is significantly cheaper than iOS `shadowRadius` and can be used freely on animated views.

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

### Alternatives to Runtime Shadows

- **Pre-rendered shadow images** — for card-shaped views with fixed border radius, export a PNG of the shadow and render it as an absolutely-positioned `Image` behind the card. Zero GPU cost at runtime.
- **Gradient borders** — simulate depth with a subtle gradient instead of a shadow (`LinearGradient` from `expo-linear-gradient` or Skia).
- **Blur overlay** — for bottom sheets and modals, use a `BlurView` for the backdrop instead of a full-screen shadow view.

```tsx
// Pre-rendered shadow as image — zero GPU cost
const CardWithShadow = () => (
  <View>
    <Image
      source={require('./assets/card-shadow.png')}
      style={styles.shadowImage}
      pointerEvents="none"
    />
    <View style={styles.card}>
      <CardContent />
    </View>
  </View>
);

const styles = StyleSheet.create({
  shadowImage: {
    position: 'absolute',
    top: 8,
    left: 8,
    right: -8,
    bottom: -8,
    resizeMode: 'stretch',
  },
  card: {
    borderRadius: 16,
    backgroundColor: '#fff',
  },
});
```

---

## 10. Common Animation Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| `Animated` API without `useNativeDriver` | Runs on JS thread, drops frames under load | Use Reanimated |
| Layout animation with `Animated` API | `useNativeDriver` cannot drive layout properties | Use Reanimated layout animations |
| Lottie always mounted | Continuously decodes frames, burns CPU | Unmount when not visible |
| Heavy `shadowRadius` on animated iOS views | Offscreen render every frame | Rasterize, pre-render, or use elevation |
| JS-driven gesture tracking with `PanResponder` | ~45fps, misses frames under load | Gesture Handler + Reanimated |
| Inline animated styles in JSX | Creates new style object every render | `useAnimatedStyle` hook |
| Many simultaneous animations without cleanup | Memory and CPU accumulation | Call `cancelAnimation` on unmount |
| Calling `setState` from inside a worklet | Cross-thread call without `runOnJS` wrapper | Wrap with `runOnJS(setState)(value)` |
| `withRepeat` without unmount cleanup | Loop continues after component unmounts | Cancel in `useEffect` cleanup |
| Animating non-interpolatable properties | Values jump instead of interpolate | Only animate numeric or color values |

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
      cancelAnimation(scale); // Stop the loop when component unmounts
    };
  }, []);

  const animatedStyle = useAnimatedStyle(() => ({
    transform: [{ scale: scale.value }],
  }));

  return <Animated.View style={animatedStyle}>{/* icon */}</Animated.View>;
};
```

### Batching Multiple Animations

When many values need to animate simultaneously (e.g., a staggered list entrance), define all animations in one `useEffect` and let Reanimated batch the worklet dispatches:

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

## Quick Reference

| Technique | When to Use | When to Skip |
|---|---|---|
| `useNativeDriver: true` | Simple opacity/transform, no Reanimated dep | Any layout property |
| Reanimated `useAnimatedStyle` | All interactive or complex animations | One-shot opacity fade with native driver |
| `withSpring` | Gesture release, interactive feedback | Fixed-duration UI state transitions |
| `withTiming` | Tab switches, modal open/close | Physics-based interactions |
| `GestureDetector` | Any draggable, swipeable, or pinchable UI | Static tap-only buttons |
| Lottie `.lottie` format | All new Lottie animations | — always prefer it over JSON |
| `shouldRasterizeIOS` | Static cards with shadow | Animated views (regenerates bitmap) |
| Android `elevation` | All shadow needs on Android | Never skip this |
| React Native Skia | Custom drawing, charts, filters | Animating standard view properties |
| `cancelAnimation` in cleanup | Any `withRepeat` animation | Single-play animations |
| Prefetch on press | Detail screens with network data | Screens with instant local data |
