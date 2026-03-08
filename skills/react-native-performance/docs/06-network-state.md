# Network & State Management Performance

## State Management Library Comparison

| Library | Bundle Size | Initial Subscribe (1000 components) | Re-render Scope | Notes |
|---|---|---|---|---|
| Zustand | ~8 KB | ~0.8 ms | Only subscribed selectors | Best general-purpose choice |
| Jotai | ~4 KB | ~0.9 ms | Only subscribed atoms | Excellent for atomic, fine-grained state |
| Redux Toolkit | ~43 KB | ~1.2 ms | Only subscribed selectors | Large apps with complex state machines |
| React Context | 0 KB | ~2.5 ms+ (grows with consumers) | ALL consumers on any change | Only for low-frequency state (theme, auth) |
| MobX | ~22 KB | ~1.0 ms | Only observed values | Good for OOP-heavy teams |
| Recoil | ~21 KB | ~1.1 ms | Only subscribed atoms | Largely superseded by Jotai |

---

## Zustand: Selector Pattern

The most common Zustand mistake is subscribing to the entire store. Every field change triggers every subscriber.

```ts
// Bad — re-renders on any store change
const { user, posts, theme, notifications } = useStore();

// Good — re-renders only when `user.name` changes
const userName = useStore(state => state.user.name);

// Good — multiple fields with shallow equality
import { useShallow } from 'zustand/react/shallow';

const { name, avatar } = useStore(
  useShallow(state => ({ name: state.user.name, avatar: state.user.avatar }))
);
```

**Custom equality function for deep objects**:

```ts
import { isEqual } from 'lodash-es/isEqual';

const filters = useStore(state => state.filters, isEqual);
// only re-renders when filters deeply changes, not on reference change
```

**Slice pattern for large stores**:

```ts
// store/slices/user-slice.ts
export type UserSlice = {
  user: User | null;
  setUser: (user: User) => void;
};

export const createUserSlice = (set: SetState<AppStore>): UserSlice => ({
  user: null,
  setUser: user => set({ user }),
});

// store/index.ts
export const useStore = create<AppStore>()((...args) => ({
  ...createUserSlice(...args),
  ...createPostsSlice(...args),
  ...createUISlice(...args),
}));
```

---

## Context API Pitfalls

React Context re-renders **every** component that calls `useContext` whenever the context value reference changes. This is not configurable.

```ts
// Bad — CartContext re-renders checkout, header, and badge on every cart change
const CartContext = createContext<CartState>({ items: [], total: 0, addItem: () => {} });

function CartProvider({ children }) {
  const [state, dispatch] = useReducer(cartReducer, initialState);
  // new object reference every render → all consumers re-render
  return (
    <CartContext.Provider value={{ ...state, dispatch }}>
      {children}
    </CartContext.Provider>
  );
}
```

**Rule**: Never put high-frequency state (cart items, notifications count, form state, timers) in Context. Context is appropriate for:
- Theme (changes once)
- Locale (changes once)
- Auth user (changes rarely)
- Feature flags (changes on deploy)

---

## Split Context Pattern

When you must use Context, split into data and dispatch contexts. Dispatch never changes (stable function reference), so dispatch-only consumers never re-render.

```ts
const CartDataContext = createContext<CartState | null>(null);
const CartDispatchContext = createContext<CartDispatch | null>(null);

function CartProvider({ children }) {
  const [state, dispatch] = useReducer(cartReducer, initialState);

  return (
    <CartDispatchContext.Provider value={dispatch}>  {/* stable reference */}
      <CartDataContext.Provider value={state}>
        {children}
      </CartDataContext.Provider>
    </CartDispatchContext.Provider>
  );
}

// AddToCartButton only needs dispatch — never re-renders on cart data change
function AddToCartButton({ product }) {
  const dispatch = useContext(CartDispatchContext);
  return <Button onPress={() => dispatch({ type: 'ADD', payload: product })} />;
}

// CartBadge needs count — re-renders only when state changes
function CartBadge() {
  const { items } = useContext(CartDataContext);
  return <Badge count={items.length} />;
}
```

---

## Normalized State Shape

Storing arrays of objects causes O(n) lookups and full array re-renders on any item update.

```ts
// Bad — array shape
type BadState = {
  posts: Post[]; // finding post by id = O(n) scan
};

// updating one post = create new array = all list consumers re-render
const updatePost = (id: string, changes: Partial<Post>) =>
  set(state => ({
    posts: state.posts.map(p => (p.id === id ? { ...p, ...changes } : p)),
  }));

// Good — normalized shape (entity adapter pattern)
type NormalizedState = {
  posts: {
    ids: string[];       // ordered list for rendering
    entities: Record<string, Post>; // O(1) lookup by id
  };
};

const updatePost = (id: string, changes: Partial<Post>) =>
  set(state => ({
    posts: {
      ...state.posts,
      entities: {
        ...state.posts.entities,
        [id]: { ...state.posts.entities[id], ...changes },
      },
    },
  }));
```

**Selector for list rendering**:

```ts
const postIds = useStore(state => state.posts.ids);
const post = useStore(state => state.posts.entities[id]); // per-item subscription
```

Each `PostCard` subscribes to its own entity. Updating one post re-renders only that card.

---

## Computed vs Stored State

Never store values that can be derived from existing state. Derived state must be kept in sync manually and wastes memory.

```ts
// Bad — storing derived values
type BadState = {
  cartItems: CartItem[];
  cartTotal: number;    // must sync with cartItems manually
  cartCount: number;    // same
  hasItems: boolean;    // same
};

// Good — compute at read time with selectors
type GoodState = {
  cartItems: CartItem[];
};

// Selector — computed once, memoized by Zustand's shallow comparison
const cartTotal = useStore(state =>
  state.cartItems.reduce((sum, item) => sum + item.price * item.quantity, 0)
);
```

For expensive computations, memoize with `useMemo`:

```ts
const cartItems = useStore(state => state.cartItems);
const cartTotal = useMemo(
  () => cartItems.reduce((sum, item) => sum + item.price * item.quantity, 0),
  [cartItems]
);
```

---

## Immer vs Spread Updates

```ts
// Spread — faster (~2x), but verbose for deep nesting
set(state => ({
  user: {
    ...state.user,
    address: {
      ...state.user.address,
      city: 'Seoul',
    },
  },
}));

// Immer — ~2x slower but safe for deep mutations
import { produce } from 'immer';

set(produce(draft => {
  draft.user.address.city = 'Seoul';
}));
```

**Decision**: use spread for shallow updates (1–2 levels). Use Immer when nesting is 3+ levels deep — the safety against accidental mutation outweighs the performance cost. Do not use Immer for high-frequency updates (>10/s, e.g., drag gestures, real-time cursors).

---

## TanStack Query: Optimal Configuration

```ts
// app/_layout.tsx or App.tsx
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 5,    // 5 minutes — data is fresh, no refetch on mount
      gcTime: 1000 * 60 * 10,      // 10 minutes — keep in cache after unmount
      retry: 2,                    // 2 retries on failure (not 3)
      retryDelay: attempt => Math.min(1000 * 2 ** attempt, 30_000), // exponential
      refetchOnWindowFocus: false, // mobile apps do not benefit from this
      refetchOnReconnect: true,    // refetch stale queries when network returns
    },
  },
});
```

**staleTime vs gcTime**:
- `staleTime`: how long data is considered fresh. During this window, `useQuery` returns cached data with no network request.
- `gcTime`: how long unused query data stays in cache after all subscribers unmount. Longer = faster back-navigation at cost of memory.

---

## MMKV Persistence

AsyncStorage is 5–10x slower than MMKV for synchronous reads. Use MMKV for persisting query cache.

```ts
import { MMKV } from 'react-native-mmkv';
import { createSyncStoragePersister } from '@tanstack/query-sync-storage-persister';
import { persistQueryClient } from '@tanstack/react-query-persist-client';

const storage = new MMKV();

const mmkvPersister = createSyncStoragePersister({
  storage: {
    setItem: (key, value) => storage.set(key, value),
    getItem: key => storage.getString(key) ?? null,
    removeItem: key => storage.delete(key),
  },
});

persistQueryClient({
  queryClient,
  persister: mmkvPersister,
  maxAge: 1000 * 60 * 60 * 24, // 24 hours
  buster: APP_VERSION,          // bust cache on new app version
});
```

---

## Query Key Factory Pattern

Consistent query keys prevent cache misses and enable targeted invalidation.

```ts
// features/products/query-keys.ts
export const productKeys = {
  all: ['products'] as const,
  lists: () => [...productKeys.all, 'list'] as const,
  list: (filters: ProductFilters) => [...productKeys.lists(), filters] as const,
  details: () => [...productKeys.all, 'detail'] as const,
  detail: (id: string) => [...productKeys.details(), id] as const,
};

// Usage
useQuery({ queryKey: productKeys.detail(productId), queryFn: ... });

// Invalidate all product queries
queryClient.invalidateQueries({ queryKey: productKeys.all });

// Invalidate only list queries (not detail caches)
queryClient.invalidateQueries({ queryKey: productKeys.lists() });
```

---

## Prefetching Strategies

```ts
// 1. On hover/long-press (anticipate navigation)
const queryClient = useQueryClient();

<ProductCard
  onLongPress={() => {
    queryClient.prefetchQuery({
      queryKey: productKeys.detail(product.id),
      queryFn: () => fetchProduct(product.id),
      staleTime: 1000 * 60, // don't prefetch if cached within 1 min
    });
  }}
/>

// 2. Prefetch next page in infinite lists
const { data, fetchNextPage } = useInfiniteQuery(/* ... */);

useEffect(() => {
  if (data?.pages.length) {
    const lastPage = data.pages.at(-1);
    if (lastPage?.nextCursor) {
      queryClient.prefetchInfiniteQuery(/* next page args */);
    }
  }
}, [data]);
```

---

## Infinite Query with Cursor Pagination

```ts
const {
  data,
  fetchNextPage,
  hasNextPage,
  isFetchingNextPage,
} = useInfiniteQuery({
  queryKey: productKeys.list(filters),
  queryFn: ({ pageParam }) => fetchProducts({ cursor: pageParam, ...filters }),
  initialPageParam: undefined as string | undefined,
  getNextPageParam: lastPage => lastPage.nextCursor ?? undefined,
});

// Flatten pages for FlatList
const items = useMemo(
  () => data?.pages.flatMap(page => page.items) ?? [],
  [data]
);

<FlatList
  data={items}
  onEndReached={() => hasNextPage && fetchNextPage()}
  onEndReachedThreshold={0.5}
  ListFooterComponent={isFetchingNextPage ? <LoadingSpinner /> : null}
/>
```

---

## Optimistic Updates

```ts
const likePost = useMutation({
  mutationFn: (postId: string) => api.likePost(postId),

  onMutate: async postId => {
    // cancel any in-flight refetches to prevent overwriting our optimistic update
    await queryClient.cancelQueries({ queryKey: productKeys.detail(postId) });

    // snapshot previous value for rollback
    const previousPost = queryClient.getQueryData(productKeys.detail(postId));

    // optimistically update the cache
    queryClient.setQueryData(productKeys.detail(postId), (old: Post) => ({
      ...old,
      likes: old.likes + 1,
      likedByMe: true,
    }));

    return { previousPost };
  },

  onError: (err, postId, context) => {
    // rollback on error
    queryClient.setQueryData(productKeys.detail(postId), context?.previousPost);
  },

  onSettled: postId => {
    // always refetch to sync server state
    queryClient.invalidateQueries({ queryKey: productKeys.detail(postId) });
  },
});
```

---

## Request Deduplication

TanStack Query deduplicates in-flight requests automatically. Multiple components calling `useQuery` with the same key share a single network request. No extra code needed.

```ts
// These three components all mount simultaneously
// TanStack Query makes exactly ONE network request
function Header() { const { data } = useQuery({ queryKey: ['user'] }); }
function Sidebar() { const { data } = useQuery({ queryKey: ['user'] }); }
function Profile() { const { data } = useQuery({ queryKey: ['user'] }); }
```

---

## Parallel Requests: Avoid Waterfall

```ts
// Bad — sequential await waterfall (~900ms total if each is 300ms)
const user = await fetchUser(userId);
const posts = await fetchPosts(userId);
const followers = await fetchFollowers(userId);

// Good — parallel (~300ms total)
const [user, posts, followers] = await Promise.all([
  fetchUser(userId),
  fetchPosts(userId),
  fetchFollowers(userId),
]);

// With TanStack Query — useQueries runs all in parallel
const results = useQueries({
  queries: [
    { queryKey: ['user', userId], queryFn: () => fetchUser(userId) },
    { queryKey: ['posts', userId], queryFn: () => fetchPosts(userId) },
    { queryKey: ['followers', userId], queryFn: () => fetchFollowers(userId) },
  ],
});
```

---

## WebSocket for Real-Time

Polling wastes battery and bandwidth. Use WebSocket for data that updates more than once per minute.

```ts
// Polling — bad for real-time (wastes battery, adds server load)
useQuery({
  queryKey: ['notifications'],
  queryFn: fetchNotifications,
  refetchInterval: 5000, // hits server every 5s even with no changes
});

// WebSocket — good (push only when data changes)
useEffect(() => {
  const ws = new WebSocket(WS_URL);

  ws.onmessage = event => {
    const message = JSON.parse(event.data);
    if (message.type === 'notification') {
      queryClient.setQueryData(['notifications'], (old: Notification[]) => [
        message.payload,
        ...old,
      ]);
    }
  };

  ws.onclose = () => scheduleReconnect(); // exponential backoff

  return () => ws.close();
}, []);
```

---

## Exponential Backoff for Reconnection

```ts
function scheduleReconnect(attempt = 0) {
  const delay = Math.min(1000 * 2 ** attempt, 30_000); // caps at 30s
  setTimeout(() => connectWebSocket(attempt + 1), delay);
}
// Attempt 0: 1s, Attempt 1: 2s, Attempt 2: 4s, ... Attempt 5: 30s (cap)
```

---

## Offline-First Patterns

```ts
import NetInfo from '@react-native-community/netinfo';

// Queue mutations when offline, flush when online
const queryClient = new QueryClient();

// Use TanStack Query's onlineManger
import { onlineManager } from '@tanstack/react-query';

onlineManager.setEventListener(setOnline => {
  return NetInfo.addEventListener(state => {
    setOnline(state.isConnected ?? false);
    // TanStack Query automatically pauses mutations when offline
    // and retries them when connection restores
  });
});
```

For offline-first data, persist the query cache (see MMKV section) and set appropriate `networkMode`:

```ts
useQuery({
  queryKey: ['user'],
  queryFn: fetchUser,
  networkMode: 'offlineFirst', // return cached data immediately, then fetch
});
```

---

## API Response Optimization

**Pagination**: never return unbounded arrays. Always paginate with cursor or page number. Target page size: 20–50 items.

**Field projection**: only return fields the client needs.

```ts
// Requesting minimal fields for list view
GET /posts?fields=id,title,coverImage,author.name,createdAt

// Full fields only for detail view
GET /posts/:id
```

**Compression**: enable gzip/brotli on the API server. React Native's `fetch` sends `Accept-Encoding: gzip` by default. A 100KB JSON payload compresses to ~15–20KB.

**Response size targets**:
- List endpoints: < 50 KB per page
- Detail endpoints: < 100 KB
- Image URLs, not image data (never base64 encode images in API responses)
