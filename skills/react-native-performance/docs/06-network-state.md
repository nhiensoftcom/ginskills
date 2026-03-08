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

---

## GraphQL Performance

### Cache Directives and Cache-First Strategies

Apollo Client's `fetchPolicy` controls whether a query hits the network or the in-memory cache. Choosing the wrong policy for a query type is the most common GraphQL performance mistake.

```ts
// Prefer cache for stable data — zero network latency
useQuery(GET_USER_PROFILE, {
  fetchPolicy: 'cache-first', // read from cache; only fetch if not cached
});

// Prefer cache but sync in background for frequently updated data
useQuery(GET_FEED, {
  fetchPolicy: 'cache-and-network', // return cache immediately, refetch silently
});

// Always fetch — for data that must always be fresh (e.g., payment state)
useQuery(GET_ORDER_STATUS, {
  fetchPolicy: 'network-only',
});
```

| Policy | Cache Read | Network Request | Use When |
|---|---|---|---|
| `cache-first` | Yes | Only if cache miss | Stable reference data (categories, config) |
| `cache-and-network` | Yes (instant) | Always (background) | Feeds, lists that change periodically |
| `network-only` | No | Always | Payment, order status, auth state |
| `cache-only` | Yes | Never | Fully offline mode |
| `no-cache` | No | Always, no write | Ephemeral queries (search suggestions) |

### Persisted Queries for Reduced Payload

With automatic persisted queries (APQ), the client sends a hash of the query string instead of the full query text. On cache hit the server responds immediately with no query parsing cost.

```ts
import { ApolloClient, InMemoryCache, HttpLink } from '@apollo/client';
import { createPersistedQueryLink } from '@apollo/client/link/persisted-queries';
import { sha256 } from 'crypto-hash';

const persistedQueriesLink = createPersistedQueryLink({ sha256 });
const httpLink = new HttpLink({ uri: '/graphql' });

const client = new ApolloClient({
  link: persistedQueriesLink.concat(httpLink),
  cache: new InMemoryCache(),
});
// First request: sends full query + hash → server caches hash
// Subsequent requests: sends hash only (~50 bytes vs 500+ bytes)
```

### Request Batching with Apollo Link

Batch multiple queries fired in the same tick into a single HTTP request.

```ts
import { BatchHttpLink } from '@apollo/client/link/batch-http';

const batchLink = new BatchHttpLink({
  uri: '/graphql',
  batchMax: 10,          // max operations per batch
  batchInterval: 20,     // wait up to 20ms to collect operations
});

const client = new ApolloClient({
  link: batchLink,
  cache: new InMemoryCache(),
});
// 5 useQuery calls in one render → 1 HTTP request with 5 operations
```

Batching trades latency (up to 20ms wait) for throughput. Disable for latency-sensitive mutations.

### InMemoryCache Tuning

```ts
const cache = new InMemoryCache({
  typePolicies: {
    Query: {
      fields: {
        // Cursor-based feed: merge incoming pages rather than replacing
        feed: {
          keyArgs: ['filter'],  // separate caches per filter, ignore cursor arg
          merge(existing = { items: [], nextCursor: null }, incoming) {
            return {
              ...incoming,
              items: [...existing.items, ...incoming.items],
            };
          },
          read(existing) {
            return existing;
          },
        },
      },
    },
    // Use a stable unique key when the default `id` field is absent
    Product: {
      keyFields: ['sku'],
    },
    // Singleton types with no id — store as single cache entry
    AppConfig: {
      keyFields: [],
    },
  },
});
```

### Optimized Apollo Client Setup

```ts
// lib/apollo-client.ts
import {
  ApolloClient,
  InMemoryCache,
  ApolloLink,
  HttpLink,
} from '@apollo/client';
import { RetryLink } from '@apollo/client/link/retry';
import { createPersistedQueryLink } from '@apollo/client/link/persisted-queries';
import { sha256 } from 'crypto-hash';

const retryLink = new RetryLink({
  delay: { initial: 300, max: 10_000, jitter: true },
  attempts: { max: 3, retryIf: error => !!error },
});

const persistedLink = createPersistedQueryLink({ sha256 });

const httpLink = new HttpLink({
  uri: process.env.EXPO_PUBLIC_GRAPHQL_URL,
  headers: { 'Accept-Encoding': 'gzip' },
});

export const apolloClient = new ApolloClient({
  link: ApolloLink.from([retryLink, persistedLink, httpLink]),
  cache: new InMemoryCache({
    typePolicies: {
      /* ... type policies here ... */
    },
  }),
  defaultOptions: {
    watchQuery: {
      fetchPolicy: 'cache-and-network',
      nextFetchPolicy: 'cache-first', // degrade to cache-first after first fetch
    },
  },
});
```

---

## gRPC / Protobuf for Mobile

### Binary Serialization Benefits vs JSON

Protobuf encodes data as binary rather than human-readable text. The savings are significant at scale.

| Metric | JSON | Protobuf | Improvement |
|---|---|---|---|
| Payload size (typical response) | 1,200 bytes | 180–280 bytes | ~5–7x smaller |
| Parse time (1,000 items) | ~8 ms | ~1.2 ms | ~6x faster |
| Serialization time | ~6 ms | ~0.8 ms | ~7x faster |
| Schema enforcement | None (runtime) | Compile-time | Stronger |
| Human-readable | Yes | No | — |

Rule of thumb: protobuf payloads are **2–10x smaller** than equivalent JSON depending on field types and string density.

### Code Generation from .proto Files

```proto
// proto/product.proto
syntax = "proto3";

package product;

message Product {
  string id = 1;
  string name = 2;
  double price = 3;
  repeated string image_urls = 4;
}

message ListProductsResponse {
  repeated Product products = 1;
  string next_cursor = 2;
}
```

Generate TypeScript types and client stubs:

```bash
npx protoc \
  --plugin=protoc-gen-ts_proto=./node_modules/.bin/protoc-gen-ts_proto \
  --ts_proto_out=./src/generated \
  --ts_proto_opt=outputServices=grpc-js \
  --proto_path=./proto \
  ./proto/product.proto
```

### Streaming RPC Patterns for Real-Time

gRPC supports four communication patterns. Server-streaming is the most useful for mobile real-time feeds.

```ts
// Server-streaming RPC — server pushes updates, client reads
const stream = productServiceClient.watchInventory({ productId });

stream.on('data', (update: InventoryUpdate) => {
  setStock(update.availableStock);
});

stream.on('error', err => {
  console.error('Stream error:', err);
  scheduleReconnect();
});

stream.on('end', () => {
  // server closed the stream — reconnect if unexpected
});

// Clean up on unmount
return () => stream.cancel();
```

| Pattern | Direction | Use Case |
|---|---|---|
| Unary | Client → Server (once) | Standard CRUD requests |
| Server streaming | Server → Client (many) | Live feeds, stock updates |
| Client streaming | Client → Server (many) | File uploads, telemetry |
| Bidirectional | Both (many) | Chat, collaborative editing |

### When to Use gRPC vs REST in React Native

| Factor | gRPC | REST/JSON |
|---|---|---|
| Payload size matters | Strongly preferred | Acceptable with gzip |
| Real-time streaming | Native support | Requires SSE or WebSocket |
| Team familiarity | Steep learning curve | Universal |
| Browser compatibility | Requires grpc-web proxy | Native |
| Tooling maturity in RN | Limited (use `grpc-web`) | Excellent |
| Schema enforcement | Compile-time (.proto) | Runtime (Zod, yup) |

**Recommendation**: use gRPC between backend microservices where payload size and throughput matter most. For React Native, prefer REST or GraphQL unless you control the full stack and need streaming or extreme payload efficiency.

---

## SSE vs WebSocket Trade-offs

### SSE for Read-Only Push

Server-Sent Events (SSE) use a plain HTTP connection the server keeps open, pushing text events. The browser (and React Native) handle reconnection automatically.

Advantages over WebSocket for read-only streams:
- Single HTTP/2 connection — multiplexed with other requests
- Automatic reconnection built into the `EventSource` protocol
- Works through HTTP proxies and firewalls that block WebSocket upgrades
- Lower server resource cost (no protocol upgrade handshake)

### EventSource API in React Native

React Native does not ship a native `EventSource`. Use the `react-native-sse` package or a polyfill.

```ts
import EventSource from 'react-native-sse';

function useLivePrice(productId: string) {
  const [price, setPrice] = useState<number | null>(null);

  useEffect(() => {
    const es = new EventSource(
      `${API_BASE}/products/${productId}/price-stream`,
      { headers: { Authorization: `Bearer ${getToken()}` } }
    );

    es.addEventListener('price-update', (event: MessageEvent) => {
      const { price } = JSON.parse(event.data);
      setPrice(price);
    });

    es.addEventListener('error', () => {
      // EventSource retries automatically after 3s by default
      // Server controls retry interval via `retry: <ms>` in the event stream
    });

    return () => es.close();
  }, [productId]);

  return price;
}
```

### Code Example: SSE vs WebSocket

```ts
// SSE — server pushes, client reads only
const es = new EventSource('/api/notifications/stream');
es.onmessage = event => handleNotification(JSON.parse(event.data));
// reconnects automatically on drop

// WebSocket — bidirectional, client also sends
const ws = new WebSocket('wss://api.example.com/ws');
ws.onopen = () => ws.send(JSON.stringify({ type: 'subscribe', topic: 'notifications' }));
ws.onmessage = event => handleNotification(JSON.parse(event.data));
ws.onclose = () => scheduleReconnect(); // must implement manually
```

### Decision Table

| Factor | SSE | WebSocket |
|---|---|---|
| Data direction | Server → Client only | Bidirectional |
| Protocol | HTTP/1.1 or HTTP/2 | Separate WS protocol |
| Auto-reconnect | Yes (built-in) | No (manual) |
| Proxy / firewall support | Excellent | Sometimes blocked |
| Max connections (HTTP/1.1) | 6 per domain | Unlimited |
| Max connections (HTTP/2) | Unlimited (multiplexed) | Unlimited |
| Binary data | No (text only) | Yes |
| Overhead per message | Low | Low |
| Server resource cost | Lower | Higher |
| **Best for** | Notifications, live feeds, dashboards | Chat, multiplayer, collaborative editing |

**Rule**: default to SSE for any read-only server push. Only upgrade to WebSocket when the client must also send frequent messages.

---

## Background Sync Patterns

### Android WorkManager Queue Patterns

WorkManager schedules deferrable background work that survives process death and device restart.

```ts
// Using @voximplant/react-native-background-fetch or
// direct native module — example uses react-native-background-fetch

import BackgroundFetch from 'react-native-background-fetch';

// Register background task (call once on app start)
BackgroundFetch.configure(
  {
    minimumFetchInterval: 15, // minutes — Android minimum is 15
    stopOnTerminate: false,
    startOnBoot: true,
    requiredNetworkType: BackgroundFetch.NETWORK_TYPE_ANY,
  },
  async taskId => {
    await syncPendingUploads();
    BackgroundFetch.finish(taskId); // MUST call finish or OS kills the app
  },
  taskId => {
    // timeout — finish immediately
    BackgroundFetch.finish(taskId);
  }
);
```

For fine-grained WorkManager control (constraints, tags, chaining), write a native module or use `@notifee/react-native` background handlers.

### iOS BackgroundTasks Framework

```ts
// iOS BGProcessingTask — for longer sync tasks (up to 30s)
// Register in AppDelegate.m:
// BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.app.sync", ...)

// From JS, schedule via BackgroundFetch (wraps BGAppRefreshTask):
BackgroundFetch.scheduleTask({
  taskId: 'com.app.sync',
  delay: 0,                         // run as soon as possible
  periodic: false,                  // one-shot
  requiresNetworkConnectivity: true,
  requiresCharging: false,
});
```

iOS restricts background execution aggressively. The OS decides when to actually run the task based on battery, usage patterns, and device state — do not rely on exact timing.

### Sync Tag Deduplication

When multiple offline mutations target the same resource, deduplicate before syncing to avoid redundant requests.

```ts
type PendingSync = {
  tag: string;       // unique key, e.g. `post:${id}:like`
  payload: unknown;
  timestamp: number;
};

function enqueueSyncTask(tag: string, payload: unknown) {
  const existing = syncQueue.find(t => t.tag === tag);
  if (existing) {
    // replace the stale entry — only the latest state matters
    Object.assign(existing, { payload, timestamp: Date.now() });
  } else {
    syncQueue.push({ tag, payload, timestamp: Date.now() });
  }
  persistQueue(syncQueue);
}

// Result: liking and unliking the same post while offline = 1 sync operation, not 2
```

### Exponential Backoff for Sync Retries

```ts
async function syncWithBackoff(
  task: () => Promise<void>,
  maxAttempts = 5,
  baseDelay = 1_000
): Promise<void> {
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      await task();
      return; // success
    } catch (err) {
      if (attempt === maxAttempts - 1) throw err;

      const delay = Math.min(baseDelay * 2 ** attempt, 30_000);
      const jitter = Math.random() * 0.3 * delay; // ±30% jitter
      await new Promise(resolve => setTimeout(resolve, delay + jitter));
    }
  }
}
// Delays: ~1s, ~2s, ~4s, ~8s, ~16s (capped at 30s)
// Jitter prevents thundering herd when many devices reconnect simultaneously
```

### Background Sync Queue

```ts
// lib/sync-queue.ts
import { MMKV } from 'react-native-mmkv';

const storage = new MMKV({ id: 'sync-queue' });
const QUEUE_KEY = 'pending_tasks';

type SyncTask = {
  tag: string;
  url: string;
  method: 'POST' | 'PUT' | 'PATCH' | 'DELETE';
  body: unknown;
  attempts: number;
};

export function enqueue(task: Omit<SyncTask, 'attempts'>) {
  const queue = getQueue();
  const idx = queue.findIndex(t => t.tag === task.tag);
  const entry: SyncTask = { ...task, attempts: 0 };
  if (idx >= 0) queue[idx] = entry; else queue.push(entry);
  storage.set(QUEUE_KEY, JSON.stringify(queue));
}

export function getQueue(): SyncTask[] {
  const raw = storage.getString(QUEUE_KEY);
  return raw ? JSON.parse(raw) : [];
}

export async function flushQueue() {
  const queue = getQueue();
  const remaining: SyncTask[] = [];

  for (const task of queue) {
    try {
      await fetch(task.url, {
        method: task.method,
        body: JSON.stringify(task.body),
        headers: { 'Content-Type': 'application/json' },
      });
    } catch {
      if (task.attempts < 5) {
        remaining.push({ ...task, attempts: task.attempts + 1 });
      }
      // drop after 5 failures — surface error to user
    }
  }

  storage.set(QUEUE_KEY, JSON.stringify(remaining));
}
```

Wire `flushQueue` to the TanStack Query `onlineManager` listener so it runs automatically when connectivity restores.

---

## HTTP/2 & Network Optimization

### HTTP/2 Multiplexing Benefits in React Native

HTTP/1.1 opens one connection per request (browsers cap at 6 per domain). HTTP/2 multiplexes all requests over a single TCP connection with no head-of-line blocking at the application layer.

| Metric | HTTP/1.1 | HTTP/2 |
|---|---|---|
| Connections per domain | 6 | 1 (multiplexed) |
| Header compression | None | HPACK (60–90% reduction) |
| Request prioritization | No | Yes |
| Server push | No | Yes |
| Typical latency reduction | — | 20–40% on mobile |

React Native's `fetch` and `XMLHttpRequest` use the platform's native network stack (NSURLSession on iOS, OkHttp on Android), both of which support HTTP/2 automatically when the server advertises it via ALPN. No code changes needed — ensure your API server has HTTP/2 enabled.

### Certificate Pinning Performance Impact

Certificate pinning adds a hash comparison per TLS handshake (negligible CPU cost, ~0.1 ms). The real cost is **deployment risk**: a pinned certificate that expires or rotates without an app update breaks all network calls.

```ts
// Using react-native-ssl-pinning
import { fetch as pinnedFetch } from 'react-native-ssl-pinning';

const response = await pinnedFetch('https://api.example.com/data', {
  method: 'GET',
  sslPinning: {
    certs: ['cert_sha256_hash_here'], // SHA-256 of the server's certificate
  },
});
```

Mitigation strategy: pin to the **intermediate CA certificate**, not the leaf. Intermediate CAs rotate less frequently. Ship two hashes (current + backup) to enable rotation without a forced update.

### DNS Prefetching Strategies

DNS resolution on mobile networks adds 50–300 ms on the first request to a new host. Warm up DNS before the user navigates.

```ts
// Android: use OkHttp's DNS prefetch via a native module
// iOS: NSURLSession warms DNS automatically after first request

// App-level: make a cheap HEAD request to critical domains on app start
async function warmupDNS(hosts: string[]) {
  await Promise.allSettled(
    hosts.map(host =>
      fetch(`https://${host}/health`, { method: 'HEAD' }).catch(() => {})
    )
  );
}

// Call in app root, before user reaches any screen that needs the API
warmupDNS(['api.example.com', 'cdn.example.com', 'images.example.com']);
```

### Connection Pooling

Both NSURLSession (iOS) and OkHttp (Android) maintain a connection pool by default. Keep connections alive by:

- Using the same base URL for all API requests (no per-request base URL switching)
- Setting `Connection: keep-alive` (default in HTTP/1.1 and HTTP/2)
- Avoiding unnecessary TLS renegotiation (reuse the same `fetch` instance / Axios instance)

```ts
// Good — single Axios instance, reuses connection pool
const apiClient = axios.create({ baseURL: process.env.EXPO_PUBLIC_API_URL });

// Bad — new instance per request discards pooled connections
function fetchSomething() {
  return axios.create({ baseURL: '...' }).get('/endpoint');
}
```

### Request Prioritization

On congested mobile networks, request order matters. Fetch critical data first; defer analytics and telemetry.

```ts
// Priority 1 — above-the-fold content, blocks render
const { data: feed } = useQuery({ queryKey: ['feed'], queryFn: fetchFeed });

// Priority 2 — secondary content, load after feed
const { data: recommendations } = useQuery({
  queryKey: ['recommendations'],
  queryFn: fetchRecommendations,
  enabled: !!feed, // don't start until critical data is loaded
});

// Priority 3 — analytics, fire and forget, never block UI
useEffect(() => {
  if (feed) {
    // defer with low priority
    requestIdleCallback(() => logFeedImpression(feed));
  }
}, [feed]);
```

---

## Pagination Performance

### Cursor vs Offset Pagination

| Factor | Offset (`LIMIT n OFFSET k`) | Cursor (keyset) |
|---|---|---|
| DB fetch complexity | O(n) — scans skipped rows | O(1) — seeks directly to position |
| Stable across concurrent writes | No — inserts shift rows | Yes — anchored to a value |
| Duplicates / skips on mutation | Yes | No |
| Random page jump support | Yes | No (forward/back only) |
| Implementation complexity | Simple | Moderate |
| Performance at page 1,000 | Slow (skip 20,000 rows) | Fast (index seek) |

Offset pagination becomes unacceptably slow beyond a few hundred pages. Cursor pagination scales to millions of rows with constant fetch time.

### Keyset Pagination Pattern

Cursor-based pagination anchors the next page to the last seen value of an indexed column (typically `createdAt` + `id` for tie-breaking).

```ts
// Backend: NestJS + MongoDB example
async function getPaginatedPosts(cursor?: string, limit = 20) {
  const filter = cursor
    ? {
        $or: [
          { createdAt: { $lt: new Date(cursor.split('_')[0]) } },
          {
            createdAt: new Date(cursor.split('_')[0]),
            _id: { $lt: cursor.split('_')[1] },
          },
        ],
      }
    : {};

  const posts = await PostModel.find(filter)
    .sort({ createdAt: -1, _id: -1 }) // compound index required
    .limit(limit + 1); // fetch one extra to know if there's a next page

  const hasMore = posts.length > limit;
  const page = hasMore ? posts.slice(0, limit) : posts;
  const lastItem = page.at(-1);

  return {
    items: page,
    nextCursor: hasMore
      ? `${lastItem!.createdAt.toISOString()}_${lastItem!._id}`
      : null,
  };
}
```

Required index:

```ts
// Compound index matches sort order exactly
PostSchema.index({ createdAt: -1, _id: -1 });
```

### Optimized Cursor Pagination with TanStack Query

```ts
// features/feed/hooks/use-feed.ts
import { useInfiniteQuery } from '@tanstack/react-query';
import { feedKeys } from '../query-keys';
import { fetchFeed } from '../api';

export function useFeed(filters: FeedFilters) {
  return useInfiniteQuery({
    queryKey: feedKeys.list(filters),
    queryFn: ({ pageParam }) =>
      fetchFeed({ cursor: pageParam as string | undefined, ...filters }),
    initialPageParam: undefined as string | undefined,
    getNextPageParam: lastPage => lastPage.nextCursor ?? undefined,
    // Keep prior pages in cache for back-navigation without refetch
    staleTime: 1000 * 60 * 2, // 2 minutes
    // Limit memory: only keep the last 5 pages in cache
    maxPages: 5,
  });
}

// features/feed/screens/feed-screen.tsx
export function FeedScreen() {
  const { data, fetchNextPage, hasNextPage, isFetchingNextPage } = useFeed({});

  const items = useMemo(
    () => data?.pages.flatMap(page => page.items) ?? [],
    [data]
  );

  const onEndReached = useCallback(() => {
    if (hasNextPage && !isFetchingNextPage) fetchNextPage();
  }, [hasNextPage, isFetchingNextPage, fetchNextPage]);

  return (
    <FlashList
      data={items}
      estimatedItemSize={120}
      keyExtractor={item => item.id}
      renderItem={({ item }) => <FeedCard post={item} />}
      onEndReached={onEndReached}
      onEndReachedThreshold={0.5}
      ListFooterComponent={isFetchingNextPage ? <LoadingSpinner /> : null}
    />
  );
}
```

`maxPages: 5` caps the in-memory list at 100 items (5 pages × 20 items). When the user scrolls forward, the oldest pages are evicted. This prevents unbounded memory growth on long scroll sessions.
