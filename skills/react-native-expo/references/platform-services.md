# Platform Services — Auth, Push, Deep Links, i18n, Analytics

## Authentication

### OAuth Providers

- **Apple**: `expo-apple-authentication` → `src/features/auth/sign-in-with-apple.service.ts`
- **Google**: `@react-native-google-signin/google-signin` → `src/features/auth/sign-in-with-google.service.ts`
- **Facebook**: `react-native-fbsdk-next` (auto-initialized via app.config.ts)
- **Sign out**: `src/features/auth/sign-out.service.ts`

### Auth Bootstrap (`src/shared/hooks/use-auth-init.ts`)

Runs once in root layout:
1. Wait for Zustand hydration (`isHydrated`)
2. Validate token integrity (`validateTokenIntegrity()`)
3. If valid → `setAuthenticated(true)`, else → `logout()`
4. Fetch user profile → set `useUserStore`
5. Init Adapty (subscriptions) + sync Adapty user ID
6. Sync Sty balance + retry pending verifications
7. **15-second timeout guard** → force sign-out if user never loads

Error handling: Network errors keep auth state; 401/404 triggers `handleAuthFailure()` → sign out.

### Token Management

```typescript
import { storeTokens, getAccessToken, clearTokens, hasValidTokens } from "@/shared/libs/token-storage"

await storeTokens({ accessToken, refreshToken })  // After login
// Auto-injected by api-client interceptor
// 401 → auto-refresh (single-flight, max 2 retries) → if fails, sign out
```

## Push Notifications

```typescript
import * as Notifications from "expo-notifications"
import { usePushNotifications } from "@/shared/hooks/use-push-notifications"

// Hook handles: permission request, token registration, notification handlers
Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowAlert: true, shouldPlaySound: true, shouldSetBadge: true,
  }),
})
```

## Deep Linking

### Branch.io

```typescript
import branch from "react-native-branch"

branch.subscribe(({ error, params }) => {
  if (params["+clicked_branch_link"]) {
    router.push({ pathname: params.screen, params: { id: params.id } })
  }
})
```

### Airbridge

Configured via `airbridge-expo-sdk` plugin in `app.config.ts`. Associated domains for universal links.

### Native Intent

`src/app/+native-intent.tsx` processes incoming URLs.

## Internationalization (i18n)

9 languages via `i18next` + `react-i18next`. Config in `src/features/multi-languages/`.

```typescript
import { useTranslation } from "react-i18next"

const { t } = useTranslation()
<Typography variant="b1">{t("home.welcome")}</Typography>
```

Language stored in MMKV for instant startup access. Locale JSON files in `src/features/multi-languages/locales/`.

## Analytics

### Airbridge (Primary) + Facebook

```typescript
import { logEvent } from "@/shared/utils/log-event"

logEvent("item_created", { category: "tops", source: "camera" })
logEvent("outfit_saved", { itemCount: 3 })
logEvent("subscription_started", { plan: "premium" })
```

### User Properties

```typescript
import { setUserProperty } from "@/shared/utils/set-user-property"
setUserProperty("subscription_tier", "premium")
```

## Subscriptions — Adapty

```typescript
import { adapty } from "react-native-adapty"
// Managed via createAdaptySlice in app-store
// Paywall presentation, subscription status, receipt validation
```

### Store Review

```typescript
import * as StoreReview from "expo-store-review"
if (await StoreReview.hasAction()) await StoreReview.requestReview()
```

## Live Activity (iOS)

```typescript
import { useLiveActivityManager } from "@/shared/live-activity"
// Start/update/end live activities for long-running tasks (e.g., outfit generation)
// Uses expo-live-activity with push notification support
```

## Location

```typescript
import { useLocation } from "@/features/location"
// Flow: permission → device location → sync to backend → weather recommendations
// Services in src/features/location/_services/
```

## Haptics

```typescript
import * as Haptics from "expo-haptics"
Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light)    // Buttons
Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium)   // Toggles
Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success)  // Confirmations
```

## Clipboard / Linking / Browser

```typescript
import * as Clipboard from "expo-clipboard"
import * as WebBrowser from "expo-web-browser"
import * as Linking from "expo-linking"

await Clipboard.setStringAsync("text")
await WebBrowser.openBrowserAsync(url)  // In-app browser
await Linking.openURL(url)              // System browser
await Linking.openSettings()            // App settings
```

## Environment Configuration

```
.env.local    → Development (default)
.env.staging  → Staging/Preview
.env.prod     → Production
```

Key env vars: `EXPO_PUBLIC_API_URL`, `EXPO_PUBLIC_APP_NAME`, `APP_VARIANT=development` (appends `.dev` to bundle IDs), `EXPO_ENV` (controls env file loading).

`app.config.ts` loads env files based on `EXPO_ENV`. Production builds set `SKIP_LOCAL_ENV=1`.

## Logging

```typescript
import { Logger } from "@/shared/utils/logger"

Logger.info("User signed in", { userId })
Logger.warn("Slow response", { endpoint, duration })
Logger.error("Upload failed", { error: err.message })
// Dev: console with emojis/colors. Prod: errors shipped via clientLogger (batched, with backoff)
```

Client logger (`src/shared/services/client-logger.service.ts`): max 200 entries queue, batch flush at 20 or every 10s, 429 backoff, connectivity check before flush.
