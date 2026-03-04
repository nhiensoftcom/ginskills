---
name: react-query
description: |
  **TanStack React Query Best Practices**: Comprehensive guide for writing production-quality React Query code — query keys, mutations, caching, optimistic updates, infinite queries, error handling, and project structure.
  - MANDATORY TRIGGERS: react query, tanstack query, useQuery, useMutation, useInfiniteQuery, query key, query cache, staleTime, gcTime, invalidateQueries, prefetch, optimistic update, server state, data fetching hook, react query pattern, query factory
  - Use this skill whenever the user is writing, reviewing, or debugging React Query / TanStack Query code. Also trigger when discussing data fetching architecture, server state management, cache invalidation, or query performance in React/React Native apps.
---

# TanStack React Query — Best Practices & Patterns

Production-ready patterns for TanStack Query (React Query) v5+. Covers query keys, mutations, caching strategy, optimistic updates, infinite queries, error handling, testing, and project structure.

## Core Mental Model

**Server state ≠ Client state.** Server data is owned by the backend — your frontend merely displays the most recent version. React Query is an async state manager for server state, not a replacement for Zustand/Redux (which handle client state).

Key implications:
- Don't copy query data into local state (`useState`) — you'll lose background updates
- Don't duplicate query state into Redux/Context — React Query already tracks loading, error, data
- Treat query data as a **cache** that stays in sync with the server, not a local store you manually manage

## Query Key Design

Query keys are the foundation of React Query's cache. Get them right and everything else falls into place.

### Rules

1. **Always use arrays**: `['todos']` not `'todos'`
2. **Include all dependencies**: If the `queryFn` uses a parameter, that parameter belongs in the key
3. **Order from general to specific**: `['todos', 'list', { filters }]` not `[{ filters }, 'list', 'todos']`
4. **Keys are deterministically serialized**: `{ a: 1, b: 2 }` equals `{ b: 2, a: 1 }` in query keys

### Query Key Factory Pattern

Create one factory per feature/entity. This is the single most impactful pattern for maintainable React Query code.

```typescript
// keys/todo.keys.ts
export const todoKeys = {
  all:     ['todos'] as const,
  lists:   ()        => [...todoKeys.all, 'list'] as const,
  list:    (filters: TodoFilters) => [...todoKeys.lists(), filters] as const,
  details: ()        => [...todoKeys.all, 'detail'] as const,
  detail:  (id: number) => [...todoKeys.details(), id] as const,
}
```

Usage:
```typescript
// Fetch filtered list
useQuery({ queryKey: todoKeys.list({ status: 'done' }), queryFn: ... })

// Fetch single item
useQuery({ queryKey: todoKeys.detail(5), queryFn: ... })

// Invalidate all todos (lists + details)
queryClient.invalidateQueries({ queryKey: todoKeys.all })

// Invalidate only lists (not details)
queryClient.invalidateQueries({ queryKey: todoKeys.lists() })

// Invalidate one specific list
queryClient.invalidateQueries({ queryKey: todoKeys.list({ status: 'done' }) })
```

### Co-location

Keep query keys, hooks, and `queryFn` together per feature — not in a global `queryKeys.ts`:

```
src/
├── features/
│   ├── todos/
│   │   ├── todo.keys.ts        # query key factory
│   │   ├── todo.queries.ts     # useQuery hooks
│   │   ├── todo.mutations.ts   # useMutation hooks
│   │   └── todo.types.ts       # types
│   └── users/
│       ├── user.keys.ts
│       ├── user.queries.ts
│       └── user.mutations.ts
```

Or if using a `_services` pattern (common in React Native projects):

```
src/
├── models/
│   ├── todo/
│   │   ├── _services/
│   │   │   ├── get-todos.service.ts
│   │   │   ├── create-todo.service.ts
│   │   │   └── delete-todo.service.ts
│   │   ├── _types/
│   │   │   └── todo.types.ts
│   │   └── todo.keys.ts
```

## Custom Hooks — Always Wrap

**Never use `useQuery` / `useMutation` directly in components.** Always wrap in a custom hook.

### Why

- Single place to change the query key, queryFn, or options
- Consumers don't need to know API details
- Easy to add `select`, `enabled`, `staleTime` per use-case
- Testable in isolation

### Query Hook Pattern

```typescript
// todo.queries.ts
import { useQuery } from '@tanstack/react-query'
import { todoKeys } from './todo.keys'
import { fetchTodos, fetchTodoById } from './todo.api'
import type { TodoFilters } from './todo.types'

export const useTodos = (filters: TodoFilters) => {
  return useQuery({
    queryKey: todoKeys.list(filters),
    queryFn: () => fetchTodos(filters),
  })
}

export const useTodo = (id: number) => {
  return useQuery({
    queryKey: todoKeys.detail(id),
    queryFn: () => fetchTodoById(id),
    enabled: !!id,  // don't fetch if id is falsy
  })
}
```

### Mutation Hook Pattern

```typescript
// todo.mutations.ts
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { todoKeys } from './todo.keys'
import { createTodo, updateTodo, deleteTodo } from './todo.api'

export const useCreateTodo = () => {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: createTodo,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: todoKeys.lists() })
    },
  })
}

export const useUpdateTodo = () => {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: updateTodo,
    onSuccess: (data, variables) => {
      // Update the detail cache directly
      queryClient.setQueryData(todoKeys.detail(variables.id), data)
      // Invalidate lists so they refetch
      queryClient.invalidateQueries({ queryKey: todoKeys.lists() })
    },
  })
}

export const useDeleteTodo = () => {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: deleteTodo,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: todoKeys.lists() })
    },
  })
}
```

### Adding Optimistic Updates to Mutation Services

For mutations where instant UI feedback matters (toggle, delete, reorder), add optimistic updates **inside the mutation hook** — not in the component. This keeps the optimistic logic co-located with the mutation and reusable across all consumers.

**Basic mutation** (wait for server) vs **Optimistic mutation** (update immediately, rollback on error):

```typescript
// todo.mutations.ts — optimistic version

export const useToggleTodo = () => {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (todo: Todo) => updateTodo({ ...todo, completed: !todo.completed }),

    // Step 1: Optimistically update cache BEFORE the API call
    onMutate: async (todo) => {
      // Cancel in-flight refetches so they don't overwrite our optimistic update
      await queryClient.cancelQueries({ queryKey: todoKeys.detail(todo.id) })
      await queryClient.cancelQueries({ queryKey: todoKeys.lists() })

      // Snapshot current cache for rollback
      const previousTodo = queryClient.getQueryData<Todo>(todoKeys.detail(todo.id))
      const previousList = queryClient.getQueryData<Todo[]>(todoKeys.lists())

      // Write optimistic data to cache — UI updates instantly
      const optimistic = { ...todo, completed: !todo.completed }
      queryClient.setQueryData(todoKeys.detail(todo.id), optimistic)
      queryClient.setQueryData<Todo[]>(todoKeys.lists(), (old) =>
        old?.map(t => t.id === todo.id ? optimistic : t)
      )

      // Return rollback context
      return { previousTodo, previousList }
    },

    // Step 2: Rollback on error
    onError: (_err, todo, context) => {
      if (context?.previousTodo) {
        queryClient.setQueryData(todoKeys.detail(todo.id), context.previousTodo)
      }
      if (context?.previousList) {
        queryClient.setQueryData(todoKeys.lists(), context.previousList)
      }
    },

    // Step 3: Always refetch after mutation settles to ensure server truth
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: todoKeys.all })
    },
  })
}

// Optimistic delete — remove from list immediately
export const useDeleteTodoOptimistic = () => {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: deleteTodo,
    onMutate: async (todoId: number) => {
      await queryClient.cancelQueries({ queryKey: todoKeys.lists() })
      const previousList = queryClient.getQueryData<Todo[]>(todoKeys.lists())

      // Remove from cache immediately
      queryClient.setQueryData<Todo[]>(todoKeys.lists(), (old) =>
        old?.filter(t => t.id !== todoId)
      )

      return { previousList }
    },
    onError: (_err, _todoId, context) => {
      if (context?.previousList) {
        queryClient.setQueryData(todoKeys.lists(), context.previousList)
      }
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: todoKeys.lists() })
    },
  })
}
```

**When to use optimistic updates in mutation services:**

| Scenario | Use optimistic? | Why |
|----------|----------------|-----|
| Toggle (like, bookmark, complete) | Yes | Instant feedback feels natural, easy to rollback |
| Delete item from list | Yes | Item disappearing immediately feels responsive |
| Reorder / drag-and-drop | Yes | Must feel instant, server confirms in background |
| Create new item | Usually no | Wait for server ID, show pending state via `mutation.isPending` |
| Payment / checkout | Never | Must confirm server success before showing result |
| File upload | No | Use `mutation.isPending` + progress indicator instead |

**Component usage is clean — no optimistic logic leaks out:**

```typescript
// Component — doesn't know about optimistic updates
const { mutate: toggleTodo } = useToggleTodo()
const { mutate: deleteTodo } = useDeleteTodoOptimistic()

<TodoItem
  onToggle={() => toggleTodo(todo)}
  onDelete={() => deleteTodo(todo.id)}
/>
```

## Caching Strategy

### staleTime vs gcTime

| Setting | Default | What it controls |
|---------|---------|-----------------|
| `staleTime` | `0` | How long data is considered "fresh". While fresh, no refetch happens — data served from cache only |
| `gcTime` | `5 min` | How long inactive (no observers) data stays in cache before garbage collection |

### Recommended Defaults

```typescript
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60,      // 1 minute — prevents redundant refetches
      gcTime: 1000 * 60 * 5,     // 5 minutes (default)
      retry: 2,                   // retry failed requests twice
      refetchOnWindowFocus: true, // keep data fresh (default)
    },
  },
})
```

### Per-Query Overrides

| Data type | staleTime | Why |
|-----------|-----------|-----|
| User profile | `5 min` | Rarely changes within a session |
| Config / feature flags | `Infinity` | Fetch once, use forever |
| Chat messages | `0` | Must always be fresh |
| Product list | `30s - 1min` | Balance freshness vs. API load |
| Dashboard analytics | `5 min` | Expensive query, acceptable staleness |

## Data Transformation with `select`

Transform or filter data **in the query hook**, not in the component:

```typescript
// Good — select runs only when data changes (referentially stable)
export const useCompletedTodos = () => {
  return useQuery({
    queryKey: todoKeys.list({ status: 'all' }),
    queryFn: () => fetchTodos({ status: 'all' }),
    select: (data) => data.filter(todo => todo.completed),
  })
}

// Bad — filtering in component runs on every render
const { data } = useTodos({ status: 'all' })
const completed = data?.filter(todo => todo.completed) // re-computed every render
```

`select` benefits:
- Only runs when `data` reference changes
- Result is memoized
- Component only re-renders when the selected result changes
- Multiple components can use the same query with different `select` functions

## Optimistic Updates

### Method 1: Via UI (simpler, preferred for single-location updates)

```typescript
const mutation = useCreateTodo()

// In JSX, show optimistic data directly from mutation state
{mutation.isPending && (
  <TodoItem todo={{ ...mutation.variables, id: 'temp' }} style={{ opacity: 0.5 }} />
)}
```

### Method 2: Via Cache (for updates visible in multiple places)

```typescript
export const useUpdateTodo = () => {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: updateTodo,
    onMutate: async (newTodo) => {
      // Cancel outgoing refetches to avoid overwriting optimistic update
      await queryClient.cancelQueries({ queryKey: todoKeys.detail(newTodo.id) })

      // Snapshot previous value for rollback
      const previous = queryClient.getQueryData(todoKeys.detail(newTodo.id))

      // Optimistically update the cache
      queryClient.setQueryData(todoKeys.detail(newTodo.id), newTodo)

      // Return context with previous value
      return { previous }
    },
    onError: (_err, newTodo, context) => {
      // Rollback on error
      if (context?.previous) {
        queryClient.setQueryData(todoKeys.detail(newTodo.id), context.previous)
      }
    },
    onSettled: (_data, _error, variables) => {
      // Refetch to ensure server truth
      queryClient.invalidateQueries({ queryKey: todoKeys.detail(variables.id) })
    },
  })
}
```

## Infinite Queries

For "load more" or infinite scroll lists:

```typescript
export const useTodoInfinite = (filters: TodoFilters) => {
  return useInfiniteQuery({
    queryKey: todoKeys.list({ ...filters, infinite: true }),
    queryFn: ({ pageParam }) => fetchTodos({ ...filters, cursor: pageParam }),
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (lastPage) => lastPage.nextCursor ?? undefined,
    // Limit stored pages to prevent memory bloat
    maxPages: 10,
  })
}

// In component
const { data, fetchNextPage, hasNextPage, isFetchingNextPage } = useTodoInfinite(filters)

const allItems = data?.pages.flatMap(page => page.items) ?? []
```

### Tips
- Use `maxPages` to cap memory usage for long lists
- `placeholderData: keepPreviousData` prevents flash of empty state during page transitions
- Prefetch the next page: `queryClient.prefetchInfiniteQuery(...)` one page ahead

## Dependent & Conditional Queries

### Sequential (dependent) queries

```typescript
const { data: user } = useUser(userId)
const { data: projects } = useQuery({
  queryKey: ['projects', user?.orgId],
  queryFn: () => fetchProjects(user!.orgId),
  enabled: !!user?.orgId,  // only run when user data is available
})
```

### Conditional (user-triggered) queries

```typescript
const [searchTerm, setSearchTerm] = useState('')

const { data } = useQuery({
  queryKey: ['search', searchTerm],
  queryFn: () => search(searchTerm),
  enabled: searchTerm.length >= 3,  // only search after 3 chars
})
```

## Prefetching

### On hover (for navigation)

```typescript
const queryClient = useQueryClient()

const prefetchTodo = (id: number) => {
  queryClient.prefetchQuery({
    queryKey: todoKeys.detail(id),
    queryFn: () => fetchTodoById(id),
    staleTime: 1000 * 60,  // don't refetch if data < 1 min old
  })
}

<Link onMouseEnter={() => prefetchTodo(todo.id)} to={`/todos/${todo.id}`}>
  {todo.title}
</Link>
```

### On screen mount (prefetch related data)

```typescript
// In a list screen, prefetch the first few detail pages
useEffect(() => {
  data?.slice(0, 3).forEach(todo => {
    queryClient.prefetchQuery({
      queryKey: todoKeys.detail(todo.id),
      queryFn: () => fetchTodoById(todo.id),
    })
  })
}, [data])
```

## Error Handling

### Per-query error handling

```typescript
const { data, error, isError } = useTodos(filters)

if (isError) return <ErrorMessage error={error} />
```

### Global error handler

```typescript
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      throwOnError: true,  // propagate to nearest Error Boundary
    },
    mutations: {
      onError: (error) => {
        toast.error(error.message)  // global toast for mutation errors
      },
    },
  },
})
```

### Error Boundary integration

```tsx
import { QueryErrorResetBoundary } from '@tanstack/react-query'
import { ErrorBoundary } from 'react-error-boundary'

<QueryErrorResetBoundary>
  {({ reset }) => (
    <ErrorBoundary onReset={reset} fallbackRender={({ resetErrorBoundary }) => (
      <View>
        <Text>Something went wrong</Text>
        <Button onPress={resetErrorBoundary} title="Try again" />
      </View>
    )}>
      <TodoList />
    </ErrorBoundary>
  )}
</QueryErrorResetBoundary>
```

## Common Anti-Patterns

### 1. Duplicating query data into Redux/Zustand

```typescript
// BAD — duplicates state, loses background sync
const { data } = useQuery({ queryKey: ['todos'], queryFn: fetchTodos })
useEffect(() => { dispatch(setTodos(data)) }, [data])

// GOOD — use query data directly
const { data: todos, isLoading } = useTodos()
```

### 2. Using `refetch()` when the key should change

```typescript
// BAD — refetch is imperative, creates race conditions
const [page, setPage] = useState(1)
const { data, refetch } = useQuery({
  queryKey: ['todos'],  // key doesn't include page!
  queryFn: () => fetchTodos(page),
})
const next = () => { setPage(p => p + 1); refetch() }

// GOOD — key includes page, auto-refetches on change
const { data } = useQuery({
  queryKey: ['todos', page],  // page in key
  queryFn: () => fetchTodos(page),
})
const next = () => setPage(p => p + 1)  // that's it
```

### 3. Transforming data in components with useEffect

```typescript
// BAD — extra state, extra renders, stale data risk
const { data } = useTodos()
const [filtered, setFiltered] = useState([])
useEffect(() => { setFiltered(data?.filter(t => t.done)) }, [data])

// GOOD — use select
const { data: filtered } = useTodos({ select: d => d.filter(t => t.done) })
```

### 4. Copying query data into form state incorrectly

```typescript
// BAD — form never gets server updates
const { data } = useTodo(id)
const [form, setForm] = useState(data)  // snapshot at mount time

// GOOD — use initialData or defaultValues, set staleTime: Infinity for forms
const { data } = useTodo(id)
const form = useForm({ defaultValues: data })
```

### 5. Creating QueryClient inside a component

```typescript
// BAD — new cache every render
function App() {
  const queryClient = new QueryClient()  // recreated on every render!
  return <QueryClientProvider client={queryClient}>...</QueryClientProvider>
}

// GOOD — stable instance
const queryClient = new QueryClient()
function App() {
  return <QueryClientProvider client={queryClient}>...</QueryClientProvider>
}

// GOOD (React 19 / strict mode safe)
function App() {
  const [queryClient] = useState(() => new QueryClient())
  return <QueryClientProvider client={queryClient}>...</QueryClientProvider>
}
```

### 6. Not disabling queries when parameters are missing

```typescript
// BAD — fires with undefined id, returns 404
const { data } = useQuery({
  queryKey: ['todo', id],
  queryFn: () => fetchTodo(id!),
})

// GOOD — wait for id
const { data } = useQuery({
  queryKey: ['todo', id],
  queryFn: () => fetchTodo(id!),
  enabled: !!id,
})
```

## React Native–Specific Tips

### Online status

```typescript
import NetInfo from '@react-native-community/netinfo'
import { onlineManager } from '@tanstack/react-query'

onlineManager.setEventListener((setOnline) => {
  return NetInfo.addEventListener((state) => {
    setOnline(!!state.isConnected)
  })
})
```

### App focus refetch

```typescript
import { useEffect } from 'react'
import { AppState } from 'react-native'
import { focusManager } from '@tanstack/react-query'

useEffect(() => {
  const subscription = AppState.addEventListener('change', (status) => {
    focusManager.setFocused(status === 'active')
  })
  return () => subscription.remove()
}, [])
```

### Persist cache (offline-first)

```typescript
import { createAsyncStoragePersister } from '@tanstack/query-async-storage-persister'
import AsyncStorage from '@react-native-async-storage/async-storage'
import { PersistQueryClientProvider } from '@tanstack/react-query-persist-client'

const persister = createAsyncStoragePersister({
  storage: AsyncStorage,
})

<PersistQueryClientProvider client={queryClient} persistOptions={{ persister }}>
  <App />
</PersistQueryClientProvider>
```

## Quick Reference

| Task | API |
|------|-----|
| Fetch data | `useQuery` |
| Fetch paginated/infinite | `useInfiniteQuery` |
| Create / Update / Delete | `useMutation` |
| Invalidate cache | `queryClient.invalidateQueries()` |
| Update cache directly | `queryClient.setQueryData()` |
| Prefetch | `queryClient.prefetchQuery()` |
| Cancel queries | `queryClient.cancelQueries()` |
| Check if fetching | `useIsFetching()` |
| Suspense mode | `useSuspenseQuery()` |
| Error boundaries | `<QueryErrorResetBoundary>` |

## Further Reading

For detailed reference on specific topics, see:
- `references/query-patterns.md` — Advanced patterns: parallel queries, dependent queries, pagination, polling, SSR hydration
