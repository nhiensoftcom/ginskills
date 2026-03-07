# Performance — Animations, Lists, and Optimization

## React Native Reanimated v4

Runs animations on the UI thread for 60fps regardless of JS thread activity. Uses `react-native-worklets` (separate package in v4).

### Shared Values & Animated Styles

```typescript
import Animated, {
  useSharedValue, useAnimatedStyle,
  withTiming, withSpring, withDelay, withSequence, withRepeat,
  interpolate, Extrapolation, runOnJS,
} from "react-native-reanimated"

const Component = () => {
  const opacity = useSharedValue(0)
  const translateY = useSharedValue(50)

  const animatedStyle = useAnimatedStyle(() => ({
    opacity: opacity.value,
    transform: [{ translateY: translateY.value }],
  }))

  const show = () => {
    opacity.value = withTiming(1, { duration: 300 })
    translateY.value = withSpring(0, { damping: 15, stiffness: 150 })
  }

  return <Animated.View style={animatedStyle} />
}
```

### Animation Functions

| Function | Use Case |
|----------|----------|
| `withTiming(toValue, { duration })` | Duration-based, predictable |
| `withSpring(toValue, { damping, stiffness })` | Physics-based, natural |
| `withDelay(ms, animation)` | Delayed start |
| `withSequence(anim1, anim2, ...)` | Sequential |
| `withRepeat(animation, count, reverse)` | Looping |
| `interpolate(value, inputRange, outputRange)` | Value mapping |

### Spring Presets

```typescript
const snappy = { damping: 15, stiffness: 200, mass: 0.8 }   // Buttons, toggles
const gentle = { damping: 20, stiffness: 100, mass: 1 }      // Modals, panels
const bouncy = { damping: 8, stiffness: 150, mass: 0.5 }     // Playful elements
```

### Gesture Handler Integration

```typescript
import { Gesture, GestureDetector } from "react-native-gesture-handler"

const DraggableCard = () => {
  const translateX = useSharedValue(0)
  const translateY = useSharedValue(0)

  const gesture = Gesture.Pan()
    .onUpdate((e) => {
      translateX.value = e.translationX
      translateY.value = e.translationY
    })
    .onEnd(() => {
      translateX.value = withSpring(0)
      translateY.value = withSpring(0)
    })

  const style = useAnimatedStyle(() => ({
    transform: [{ translateX: translateX.value }, { translateY: translateY.value }],
  }))

  return (
    <GestureDetector gesture={gesture}>
      <Animated.View style={style}>{/* content */}</Animated.View>
    </GestureDetector>
  )
}
```

### Entering/Exiting Layout Animations

```typescript
import Animated, { FadeIn, FadeOut, SlideInRight, SlideOutLeft } from "react-native-reanimated"

<Animated.View entering={FadeIn.duration(300)} exiting={FadeOut.duration(200)}>
  {/* content */}
</Animated.View>

// Staggered list items
<Animated.View entering={FadeIn.delay(index * 50).duration(300)}>
  {/* item */}
</Animated.View>
```

### Performance Limits

- Max **100 animated components** on low-end Android
- Max **500 animated components** on iOS
- Never read shared values on JS thread — only in worklets/useAnimatedStyle
- For complex visuals, use `react-native-skia` instead of many animated components

## FlashList v2 — High-Performance Lists

FlashList v2 is New Architecture only, uses recycling for near-native perf. **Always use FlashList, never FlatList.**

### Basic Usage

```typescript
import { FlashList } from "@shopify/flash-list"

<FlashList
  data={items}
  renderItem={({ item }) => <ItemCard item={item} />}
  estimatedItemSize={120}        // Required: approximate item height
  keyExtractor={(item) => item._id}
/>
```

### Optimized Pattern

```typescript
const renderItem = useCallback(({ item }: { item: ItemRes }) => (
  <MemoizedItemCard item={item} />
), [])

const MemoizedItemCard = React.memo(({ item }: { item: ItemRes }) => (
  <View><Typography variant="b2">{item.name}</Typography></View>
))

<FlashList
  data={items}
  renderItem={renderItem}
  estimatedItemSize={120}
  keyExtractor={(item) => item._id}
  drawDistance={250}                    // Pre-render distance
  onEndReached={onEndReached}          // Infinite scroll
  onEndReachedThreshold={0.5}
  numColumns={2}                        // Grid layout
  getItemType={(item) => item.type}    // CRITICAL for mixed item types
  ListFooterComponent={isFetchingNextPage ? <ActivityIndicator /> : null}
  ListEmptyComponent={<EmptyState />}
/>
```

### Key Rules

1. **Never use `key` prop** inside item components — defeats recycling
2. **Use `getItemType`** for heterogeneous lists
3. **Always provide `estimatedItemSize`** — measure one item
4. **Profile in release mode** — dev mode perf is misleading
5. **Memoize `renderItem`** with `useCallback`
6. **Memoize item components** with `React.memo`

## expo-image — Optimized Image Loading

```typescript
import { Image } from "expo-image"

<Image
  source={{ uri: imageUrl }}
  style={{ width: 100, height: 100 }}
  contentFit="cover"
  transition={200}              // Fade-in ms
  cachePolicy="memory-disk"     // Default, recommended
  placeholder={blurhash}        // Optional blurhash
  recyclingKey={item._id}       // For list recycling
/>

// Prefetch
await Image.prefetch(urls)
// Clear cache
await Image.clearDiskCache()
```

| Cache Policy | Description |
|-------------|-------------|
| `memory-disk` | Default. Memory + disk |
| `memory` | Memory only |
| `disk` | Disk only |
| `none` | No caching |

## General Performance Best Practices

### Component Optimization

```typescript
// Memoize expensive components
const ExpensiveChild = React.memo(({ data }) => { /* ... */ })

// Memoize callbacks passed as props
const handlePress = useCallback(() => { /* ... */ }, [dep])

// Memoize computed values
const filtered = useMemo(() => items.filter(i => i.category === selected), [items, selected])
```

### Avoid Common Pitfalls

```typescript
// BAD: Inline styles (new object every render)
<View style={{ padding: 16, backgroundColor: "#fff" }}>

// GOOD: StyleSheet.create (cached)
const styles = StyleSheet.create({
  container: { padding: Spacing.lg, backgroundColor: Theme.color.backgroundElevated },
})

// BAD: Arrow in render (new reference)
<Button onPress={() => handlePress(item._id)} />

// GOOD: Memoized callback
const onPress = useCallback(() => handlePress(item._id), [item._id])
```

### Metro Optimization

- `inlineRequires: true` in `metro.config.js` — defers module loading, improves cold start
- `.lottie` and `.cjs` added as asset/source extensions
- SVG support via `react-native-svg-transformer`

### Platform-Specific

- **Shimmer**: `shimmer.ios.tsx` / `shimmer.android.tsx` (platform file extensions)
- **Android**: `removeClippedSubviews={true}` on large lists
- **Lottie**: Keep files under 100KB; for complex animations use Skia
