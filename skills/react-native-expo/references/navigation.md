# Navigation — Expo Router v5

## Route Structure

```
src/app/
  _layout.tsx              # Root: providers + auth guards (Stack.Protected)
  +native-intent.tsx       # Native deep link handler
  (auth)/
    _layout.tsx            # Auth stack (fade animation, no gesture back)
    login.tsx              # Apple, Google, email OAuth
  (onboarding)/
    _layout.tsx            # Onboarding stack (slide_from_right, no gesture back)
    select-language.tsx    # Language selection
    step1-7.tsx            # 7-step setup flow
  (main)/
    _layout.tsx            # Main stack: registers all push/modal screens
    index.tsx              # Main entry redirect
    (tabs)/                # 4 tabs: Home, Wardrobe, Stylist, Profile
      _layout.tsx          # Dual-mode: NativeTabs (iOS 26+ Liquid Glass) or ClassicTabs
      home/
      stylist/
      profile/
      (wardrobe)/          # Items + outfits sub-tabs
    (wardrobe)/            # Push screens: item-detail, overview, upload-animation
    (outfits)/             # Modals: maker (slide_from_bottom), save-modal (transparentModal)
    (styling)/             # Modals: tryon, feedback (slide_from_bottom), about-stylist (push)
    (discover)/            # Transparent modal: product-modal
    (calendar)/            # Outfit calendar screens
    (shared)/              # Shared modals: earn-credits, feedback-modal, referral, sty-history
    notifications/
  (global)/                # Transparent modals accessible from anywhere: loading, product-modal
```

## Route-Screen Delegation Pattern

Route files in `src/app/` are **thin delegators** (under 10 lines). Screen logic lives in `src/screens/` mirroring the same path:

```typescript
// src/app/(main)/(tabs)/home/index.tsx — THIN DELEGATOR
import HomeScreen from "@/screens/(main)/(tabs)/home"
export default function HomeRoute() {
  return <HomeScreen />
}
```

Some route files wrap screens with feature dialogs:

```typescript
// src/app/(main)/(wardrobe)/item-detail.tsx
import ClosetItemDetailScreen from "@/screens/(main)/(wardrobe)/item-detail"
import { ItemDialogs } from "@/features/item/_ui/item-dialogs"
import { useLocalSearchParams } from "expo-router"

export default function ClosetItemDetailRoute() {
  const { item_id } = useLocalSearchParams<{ item_id: string }>()
  return (
    <>
      <ClosetItemDetailScreen />
      <ItemDialogs item_id={item_id} />
    </>
  )
}
```

Screen folders contain `index.tsx` plus `_components/` for screen-specific sub-components:

```
src/screens/(main)/(tabs)/home/
  index.tsx
  _components/
    compact-header.tsx
    weather-row.tsx
    todays-picks-section.tsx
    ai-stylist-row.tsx
```

## Auth Flow

Root `_layout.tsx` uses `Stack.Protected guard={condition}` to gate access:

```typescript
const isLoggedIn = isAuthenticated && !!user
const needsOnboarding = isLoggedIn && !user?.is_onboarding_completed
const isAppReady = !isLoading && isAppInitialized && isOtaReady

<Stack>
  <Stack.Protected guard={!isLoggedIn}>
    <Stack.Screen name="(auth)" />
  </Stack.Protected>
  <Stack.Protected guard={isLoggedIn && needsOnboarding}>
    <Stack.Screen name="(onboarding)" />
  </Stack.Protected>
  <Stack.Protected guard={isLoggedIn && !needsOnboarding}>
    <Stack.Screen name="(main)" />
  </Stack.Protected>
  <Stack.Screen name="(global)" />
</Stack>
```

Global overlays in root layout: `NetworkErrorOverlay`, `ForceUpdateOverlay`, `DailyCheckInSheet`, `QuotaExceededDialog`, `RemoteDialogContainer`.

## Tab Layout (Dual-Mode)

```typescript
// iOS 26+ uses NativeTabs (Liquid Glass native zoom + slide animations)
// Older iOS + Android uses ClassicTabs (custom tab bar)
const isLiquidGlass = Platform.OS === "ios" && parseInt(Platform.Version, 10) >= 26

// Tabs: home, (wardrobe), stylist, profile
// Tab config loaded from @/screens/(main)/(tabs)/_constants/tabs.const
```

## Navigation Patterns

### Typed Routes

```typescript
import { router } from "expo-router"
import { ROUTES } from "@/shared/constant/route"

// Navigate with typed routes
router.push(ROUTES.ITEM_DETAIL.path)
router.push({ pathname: "/(main)/(wardrobe)/item-detail", params: { item_id: "123" } })
router.back()
router.replace(ROUTES.LOGIN.path)
router.setParams({ date: newDate })  // Update current route params
```

### Route Params

```typescript
// Extract params in route/screen files
const { item_id } = useLocalSearchParams<{ item_id: string }>()

// Complex params (JSON-encoded)
const { productData } = useLocalSearchParams()
const product = productData ? JSON.parse(productData) : null
```

### Modal Presentation

```typescript
<Stack.Screen
  name="(outfits)/maker"
  options={{ presentation: "modal", animation: "slide_from_bottom", headerShown: false }}
/>
<Stack.Screen
  name="(discover)/product-modal"
  options={{ presentation: "transparentModal", animation: "fade" }}
/>
```

## Creating a New Screen

1. Create screen: `src/screens/(main)/(section)/screen-name/index.tsx`
2. Add sub-components: `src/screens/(main)/(section)/screen-name/_components/`
3. Create thin route: `src/app/(main)/(section)/screen-name.tsx`
4. Register in parent `_layout.tsx` Stack
5. Add to `ROUTES` constant in `src/shared/constant/route.ts`

## Screen Component Pattern

```typescript
export default function HomeScreen() {
  const { t } = useTranslation()
  const { top } = useSafeAreaInsets()
  const queryClient = useQueryClient()

  const onRefresh = useCallback(async () => {
    await queryClient.invalidateQueries()
  }, [queryClient])

  useFocusEffect(useCallback(() => {
    logEvent("home_viewed")
  }, []))

  return (
    <View style={styles.screen}>
      <ScrollView>{/* Content */}</ScrollView>
    </View>
  )
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: Theme.color.backgroundSubtle },
})
```

## Best Practices

- Keep route files under 10 lines — delegate to screens
- Use route groups `()` for organization without affecting URL
- Prefer `router.push()` over `<Link>` for programmatic navigation
- Use `useLocalSearchParams()` for type-safe params
- Use `useFocusEffect()` for screen focus side effects (analytics, refresh)
- Avoid nesting more than 3 levels of stack navigators
- Use `(shared)` group for screens accessible from multiple tabs
- Feature dialogs live alongside route files, not inside screens
