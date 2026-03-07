# State Management — Zustand v5 + MMKV

## Architecture Overview

- **Server state**: React Query (never duplicate in Zustand)
- **Client state**: Zustand with MMKV or AsyncStorage persistence
- **Secure storage**: react-native-keychain (JWT tokens only)
- **Fast sync storage**: MMKV (non-sensitive persisted state)

## Zustand Store Patterns

### Simple Store

```typescript
import { create } from "zustand"
import { persist, createJSONStorage } from "zustand/middleware"
import { MMKV } from "react-native-mmkv"

const storage = new MMKV()
const mmkvStorage = {
  getItem: (name: string) => storage.getString(name) ?? null,
  setItem: (name: string, value: string) => storage.set(name, value),
  removeItem: (name: string) => storage.delete(name),
}

interface UserStore {
  user: UserRes | null
  setUser: (user: UserRes | null) => void
  updateUser: (partial: Partial<UserRes>) => void
  clearUser: () => void
  isPremium: () => boolean
}

export const useUserStore = create<UserStore>()(
  persist(
    (set, get) => ({
      user: null,
      setUser: (user) => set({ user }),
      updateUser: (partial) => set({ user: { ...get().user!, ...partial } }),
      clearUser: () => set({ user: null }),
      isPremium: () => get().user?.subscription === "premium",
    }),
    {
      name: "user-store",
      storage: createJSONStorage(() => mmkvStorage),
      partialize: (state) => ({ user: state.user }),
    },
  ),
)
```

### Composite Store with Slice Factories

The app uses a composite store pattern:

```typescript
import { StateCreator } from "zustand"

// Slice factory
interface StySlice {
  styBalance: StyBalance | null
  isCheckInSheetVisible: boolean
  setStyBalance: (balance: StyBalance | null) => void
  syncStyBalance: () => Promise<void>
  hasSty: () => boolean
}

export const createStySlice: StateCreator<AppStore, [], [], StySlice> = (set, get) => ({
  styBalance: null,
  isCheckInSheetVisible: false,
  setStyBalance: (balance) => set({ styBalance: balance }),
  syncStyBalance: async () => {
    try {
      const balance = await getStyBalance()
      set({ styBalance: balance })
    } catch (error) {
      appLog.error("[Sty] Failed to sync balance:", error)
    }
  },
  hasSty: () => (get().styBalance?.total ?? 0) > 0,
})

// Composite store (app-store.ts)
type AppStore = AppState & ChatSlice & StySlice & AdaptySlice

export const useAppStore = create<AppStore>()(
  persist(
    (set, get) => ({
      ...createChatSlice(set, get),
      ...createStySlice(set, get),
      ...createAdaptySlice(set, get),
      isAuthenticated: false,
      isAppInitialized: false,
      isHydrated: false,
      setAuthenticated: (v) => set({ isAuthenticated: v }),
      logout: () => { clearTokens(); set({ isAuthenticated: false }) },
      initializeApp: () => set({ isAppInitialized: true }),
    }),
    {
      name: "app-store",
      storage: createJSONStorage(() => AsyncStorage),
      partialize: (state) => ({ isAuthenticated: state.isAuthenticated }),
      onRehydrateStorage: () => () => {
        useAppStore.setState({ isHydrated: true })
      },
    },
  ),
)
```

### Using Stores in Components

**ALWAYS use `useShallow`** when selecting multiple fields:

```typescript
import { useShallow } from "zustand/react/shallow"

// CORRECT — useShallow prevents unnecessary re-renders
const { user, setUser } = useUserStore(
  useShallow((state) => ({ user: state.user, setUser: state.setUser })),
)

// CORRECT — single primitive selector (no useShallow needed)
const styBalance = useUserStore((state) => state.styBalance)

// WRONG — creates new object reference every render
const { user, setUser } = useUserStore((state) => ({
  user: state.user,
  setUser: state.setUser,
}))
```

### Feature Dialog Stores

Features use dedicated stores for dialog state:

```typescript
interface ItemDialogsStore {
  activeDialog: ItemDialogTypeEnum | null
  selectedItemId: string | null
  openDialog: (type: ItemDialogTypeEnum, itemId: string) => void
  closeDialog: () => void
}

export const useItemDialogsStore = create<ItemDialogsStore>((set) => ({
  activeDialog: null,
  selectedItemId: null,
  openDialog: (type, itemId) => set({ activeDialog: type, selectedItemId: itemId }),
  closeDialog: () => set({ activeDialog: null, selectedItemId: null }),
}))
```

### Hydration Check

```typescript
// Wait for Zustand hydration before using persisted state
const isHydrated = useAppStore((s) => s.isHydrated)

// Or use persist API
const isHydrated = useAppStore.persist.hasHydrated()
useEffect(() => {
  const unsub = useAppStore.persist.onFinishHydration(() => { /* ready */ })
  return unsub
}, [])
```

## Existing Stores

| Store | File | Purpose |
|-------|------|---------|
| `useAppStore` | `shared/stores/app-store.ts` | Composite: auth + chat + sty + adapty slices |
| `useUserStore` | `shared/stores/user-store.ts` | User profile, subscription, access level |
| `useFeedbackStore` | `shared/stores/feedback-store.ts` | Feedback dialog state |
| `useTryOnStore` | `shared/stores/try-on-store.ts` | Try-on feature state |
| `useNewItemsStore` | `shared/stores/new-items-store.ts` | New items tracking |
| `useFullBodyImageStore` | `shared/stores/full-body-image-store.ts` | Full body photo state |
| `useVersionCheckStore` | `shared/stores/version-check-store.ts` | App version check |
| `useStylistNameStore` | `shared/stores/stylist-name-store.ts` | AI stylist name |
| `useDuplicateCheckStore` | `shared/stores/duplicate-check-store.ts` | Duplicate detection |
| `useUnreadStylistStore` | `shared/stores/unread-stylist-store.ts` | Unread chat badge |

## MMKV Direct Usage

For simple key-value outside Zustand:

```typescript
import { MMKV } from "react-native-mmkv"
const storage = new MMKV()

storage.set("user.language", "en")        // String
storage.set("onboarding.complete", true)  // Boolean
storage.set("app.launchCount", 5)         // Number
const lang = storage.getString("user.language")
storage.delete("key")
storage.contains("key")
```

## Best Practices

- **Server state in React Query**, not Zustand — never cache API responses in stores
- **Use `partialize`** to exclude runtime-only state from persistence
- **Use `useShallow`** when selecting multiple fields
- **Single selector for primitives** — no `useShallow` needed
- **Keep stores small** — split by domain
- **MMKV for speed** — synchronous, 30-100x faster than AsyncStorage
- **Keychain for secrets** — JWT tokens only in `react-native-keychain`
- **Batch state updates** in single `set()` call
- **Use `getState()`** for reading in async functions (no hook needed)
- **Atomic updates**: Read + write in single `set()` or use `get()` inside setter
