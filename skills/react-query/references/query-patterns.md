# Advanced React Query Patterns

Detailed reference for advanced patterns beyond the main SKILL.md. Load this when the user is working on specific advanced scenarios.

## Parallel Queries

### Independent queries in a component

Simply call multiple `useQuery` hooks — React Query fetches them in parallel:

```typescript
const { data: users } = useUsers()
const { data: projects } = useProjects()
const { data: notifications } = useNotifications()
// All three fire simultaneously
```

### Dynamic parallel queries with `useQueries`

When the number of queries is dynamic (e.g., fetch details for a list of IDs):

```typescript
const todoQueries = useQueries({
  queries: todoIds.map(id => ({
    queryKey: todoKeys.detail(id),
    queryFn: () => fetchTodoById(id),
    staleTime: 1000 * 60 * 5,
  })),
})

const allLoaded = todoQueries.every(q => q.isSuccess)
const allData = todoQueries.map(q => q.data).filter(Boolean)
```

### Combine results with `combine`

```typescript
const todoQueries = useQueries({
  queries: todoIds.map(id => ({
    queryKey: todoKeys.detail(id),
    queryFn: () => fetchTodoById(id),
  })),
  combine: (results) => ({
    data: results.map(r => r.data).filter(Boolean),
    isLoading: results.some(r => r.isLoading),
    isError: results.some(r => r.isError),
  }),
})
```

## Polling / Auto-Refetch

### Interval-based polling

```typescript
const { data } = useQuery({
  queryKey: ['job-status', jobId],
  queryFn: () => fetchJobStatus(jobId),
  refetchInterval: 3000,  // poll every 3 seconds
  refetchIntervalInBackground: false,  // stop when tab is hidden
})
```

### Conditional polling (stop when done)

```typescript
const { data } = useQuery({
  queryKey: ['job-status', jobId],
  queryFn: () => fetchJobStatus(jobId),
  refetchInterval: (query) => {
    return query.state.data?.status === 'completed' ? false : 3000
  },
})
```

## Pagination

### Basic pagination with placeholderData

```typescript
import { keepPreviousData } from '@tanstack/react-query'

const [page, setPage] = useState(1)

const { data, isPlaceholderData } = useQuery({
  queryKey: ['todos', page],
  queryFn: () => fetchTodos(page),
  placeholderData: keepPreviousData,  // keep showing old data while new page loads
})

<Button
  disabled={isPlaceholderData || !data?.hasNextPage}
  onPress={() => setPage(p => p + 1)}
/>
```

### Prefetch next page

```typescript
useEffect(() => {
  if (data?.hasNextPage) {
    queryClient.prefetchQuery({
      queryKey: ['todos', page + 1],
      queryFn: () => fetchTodos(page + 1),
    })
  }
}, [data, page])
```

## Cursor-Based Infinite Queries

### Bi-directional infinite query

```typescript
const {
  data,
  fetchNextPage,
  fetchPreviousPage,
  hasNextPage,
  hasPreviousPage,
} = useInfiniteQuery({
  queryKey: ['messages', chatId],
  queryFn: ({ pageParam }) => fetchMessages(chatId, pageParam),
  initialPageParam: { cursor: undefined, direction: 'forward' },
  getNextPageParam: (lastPage) =>
    lastPage.nextCursor ? { cursor: lastPage.nextCursor, direction: 'forward' } : undefined,
  getPreviousPageParam: (firstPage) =>
    firstPage.prevCursor ? { cursor: firstPage.prevCursor, direction: 'backward' } : undefined,
  maxPages: 20,  // limit stored pages
})
```

## SSR / Hydration (Next.js)

### Prefetch on server, hydrate on client

```typescript
// app/todos/page.tsx (Server Component)
import { dehydrate, HydrationBoundary, QueryClient } from '@tanstack/react-query'

export default async function TodosPage() {
  const queryClient = new QueryClient()

  await queryClient.prefetchQuery({
    queryKey: todoKeys.lists(),
    queryFn: fetchTodos,
  })

  return (
    <HydrationBoundary state={dehydrate(queryClient)}>
      <TodoList />
    </HydrationBoundary>
  )
}

// components/TodoList.tsx (Client Component)
'use client'

export function TodoList() {
  // This will use the prefetched data — no loading state on first render
  const { data } = useTodos()
  return <div>{data?.map(todo => ...)}</div>
}
```

## Placeholder & Initial Data

### initialData — counted as "real" data

```typescript
// Pre-fill detail from list cache
useQuery({
  queryKey: todoKeys.detail(id),
  queryFn: () => fetchTodoById(id),
  initialData: () => {
    return queryClient
      .getQueryData<Todo[]>(todoKeys.lists())
      ?.find(t => t.id === id)
  },
  initialDataUpdatedAt: () => {
    return queryClient.getQueryState(todoKeys.lists())?.dataUpdatedAt
  },
})
```

### placeholderData — shown while loading, not cached

```typescript
useQuery({
  queryKey: todoKeys.detail(id),
  queryFn: () => fetchTodoById(id),
  placeholderData: { id, title: 'Loading...', completed: false },
})
```

Key difference:
- `initialData` is persisted in cache, respects `staleTime`, counts as "real"
- `placeholderData` is temporary, always triggers a fetch, never cached

## Request Deduplication

React Query automatically dedupes identical queries. If 10 components call `useTodos()`, only one network request fires. All 10 share the same cache entry and re-render together.

This is automatic — no configuration needed. Just use the same query key.

## Retry & Backoff

```typescript
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 3,  // retry 3 times (default)
      retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30000),  // exponential backoff
    },
  },
})

// Disable retry for specific queries
useQuery({
  queryKey: ['login'],
  queryFn: login,
  retry: false,  // don't retry auth failures
})
```

## Query Cancellation

React Query automatically cancels queries when components unmount using `AbortSignal`:

```typescript
const { data } = useQuery({
  queryKey: ['todos'],
  queryFn: ({ signal }) => {
    return fetch('/api/todos', { signal }).then(r => r.json())
  },
})
```

For Axios:

```typescript
queryFn: ({ signal }) => {
  return axios.get('/api/todos', { signal }).then(r => r.data)
}
```

## Mutation Side Effects Chain

The full lifecycle of a mutation:

```
mutate() called
  → onMutate (optimistic update, return rollback context)
    → mutationFn (actual API call)
      → onSuccess / onError
        → onSettled (runs regardless of success/error)
```

### Coordinating mutation callbacks

```typescript
// Hook-level callbacks (always run)
useMutation({
  mutationFn: updateTodo,
  onSuccess: () => { /* runs for every call */ },
})

// Call-site callbacks (run for this specific call only)
mutation.mutate(data, {
  onSuccess: () => { /* runs only for this call */ },
})

// Execution order: hook onSuccess → call-site onSuccess
```

## Testing React Query

### Setup test wrapper

```typescript
const createWrapper = () => {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: {
        retry: false,  // don't retry in tests
      },
    },
  })

  return ({ children }) => (
    <QueryClientProvider client={queryClient}>
      {children}
    </QueryClientProvider>
  )
}
```

### Test a custom hook

```typescript
import { renderHook, waitFor } from '@testing-library/react'

it('fetches todos', async () => {
  const { result } = renderHook(() => useTodos(), {
    wrapper: createWrapper(),
  })

  await waitFor(() => expect(result.current.isSuccess).toBe(true))

  expect(result.current.data).toHaveLength(3)
})
```

### Mock at the network level

Prefer MSW (Mock Service Worker) over mocking `queryFn` directly — it tests the full request pipeline:

```typescript
import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

const server = setupServer(
  http.get('/api/todos', () => {
    return HttpResponse.json([
      { id: 1, title: 'Test', completed: false },
    ])
  })
)

beforeAll(() => server.listen())
afterEach(() => server.resetHandlers())
afterAll(() => server.close())
```

## Performance Optimization

### Tracked queries (v5 default)

React Query v5 tracks which fields you access from the query result. If you only use `data`, the component won't re-render when `isFetching` changes. This is automatic.

### `notifyOnChangeProps`

For fine-grained control:

```typescript
useQuery({
  queryKey: ['todos'],
  queryFn: fetchTodos,
  notifyOnChangeProps: ['data', 'error'],  // ignore isFetching changes
})
```

### `structuralSharing`

Enabled by default. React Query compares old and new data structurally and reuses unchanged references, preventing unnecessary re-renders in components that depend on specific parts of the data.

Disable only for very large datasets where comparison is expensive:

```typescript
useQuery({
  queryKey: ['huge-data'],
  queryFn: fetchHugeData,
  structuralSharing: false,
})
```
