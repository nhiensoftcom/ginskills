# FSD Advanced Patterns

Detailed reference for advanced Feature-Sliced Design patterns. The main SKILL.md covers the core methodology — this file provides composition patterns, state management integration, testing strategy, and real-world edge cases.

## Composition Patterns

### How layers compose together

The key to FSD is **composition at higher layers**. Lower layers are independent; higher layers wire them together.

```
Page composes → Widgets + Features + Entities
Widget composes → Features + Entities
Feature uses → Entities + Shared
Entity uses → Shared only
```

### Example: Product page composition

```typescript
// pages/product-detail/ui/ProductDetailPage.tsx
import { ProductInfo } from '@/widgets/product-info'
import { AddToCart } from '@/features/add-to-cart'
import { ProductReviews } from '@/widgets/product-reviews'
import { RecommendedProducts } from '@/widgets/recommended-products'

export const ProductDetailPage = ({ id }: { id: string }) => (
  <div>
    <ProductInfo productId={id} />
    <AddToCart productId={id} />
    <ProductReviews productId={id} />
    <RecommendedProducts productId={id} />
  </div>
)
```

```typescript
// widgets/product-info/ui/ProductInfo.tsx
import { ProductCard } from '@/entities/product'
import { FavoriteButton } from '@/features/toggle-favorite'
import { ShareButton } from '@/features/share-product'

export const ProductInfo = ({ productId }: { productId: string }) => {
  // Widget composes entity UI with feature actions
  return (
    <ProductCard id={productId}>
      <FavoriteButton productId={productId} />
      <ShareButton productId={productId} />
    </ProductCard>
  )
}
```

### Render props / slots pattern

When an entity needs feature-level actions but can't import features (wrong direction), use composition via props:

```typescript
// entities/todo/ui/TodoCard.tsx
interface TodoCardProps {
  todo: Todo
  actions?: React.ReactNode  // slot for feature-level actions
}

export const TodoCard = ({ todo, actions }: TodoCardProps) => (
  <div>
    <h3>{todo.title}</h3>
    <p>{todo.description}</p>
    {actions && <div className="actions">{actions}</div>}
  </div>
)
```

```typescript
// widgets/todo-list/ui/TodoList.tsx — composes entity + features
import { TodoCard } from '@/entities/todo'
import { ToggleButton } from '@/features/toggle-todo'
import { DeleteButton } from '@/features/delete-todo'

export const TodoList = ({ todos }: { todos: Todo[] }) => (
  <ul>
    {todos.map(todo => (
      <TodoCard
        key={todo.id}
        todo={todo}
        actions={
          <>
            <ToggleButton todoId={todo.id} />
            <DeleteButton todoId={todo.id} />
          </>
        }
      />
    ))}
  </ul>
)
```

## State Management Integration

### Zustand with FSD

Each entity/feature owns its own store:

```typescript
// entities/user/model/user.store.ts
import { create } from 'zustand'
import type { User } from './user.types'

interface UserStore {
  user: User | null
  setUser: (user: User) => void
  clear: () => void
}

export const useUserStore = create<UserStore>((set) => ({
  user: null,
  setUser: (user) => set({ user }),
  clear: () => set({ user: null }),
}))
```

```typescript
// entities/user/index.ts
export { useUserStore } from './model/user.store'
export type { User } from './model/user.types'
export { UserAvatar } from './ui/UserAvatar'
```

### React Query with FSD

Query hooks live in the entity/feature that owns the data:

```typescript
// entities/product/api/product.api.ts
import { apiClient } from '@/shared/api'
import type { Product } from '../model/product.types'

export const productApi = {
  getAll: (filters?: ProductFilters) =>
    apiClient.get<Product[]>('/products', { params: filters }),
  getById: (id: string) =>
    apiClient.get<Product>(`/products/${id}`),
}
```

```typescript
// entities/product/model/product.queries.ts
import { useQuery } from '@tanstack/react-query'
import { productApi } from '../api/product.api'

const productKeys = {
  all: ['products'] as const,
  lists: () => [...productKeys.all, 'list'] as const,
  list: (filters: ProductFilters) => [...productKeys.lists(), filters] as const,
  details: () => [...productKeys.all, 'detail'] as const,
  detail: (id: string) => [...productKeys.details(), id] as const,
}

export const useProducts = (filters?: ProductFilters) =>
  useQuery({
    queryKey: productKeys.list(filters ?? {}),
    queryFn: () => productApi.getAll(filters),
  })

export const useProduct = (id: string) =>
  useQuery({
    queryKey: productKeys.detail(id),
    queryFn: () => productApi.getById(id),
    enabled: !!id,
  })
```

```typescript
// features/add-to-cart/model/useAddToCart.ts
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { cartApi } from '@/entities/cart'

export const useAddToCart = () => {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: cartApi.addItem,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['cart'] })
    },
  })
}
```

### Redux Toolkit with FSD

Each slice in Redux maps to an FSD entity or feature:

```typescript
// entities/todo/model/todo.slice.ts
import { createSlice, createAsyncThunk } from '@reduxjs/toolkit'
import { todoApi } from '../api/todo.api'

export const fetchTodos = createAsyncThunk('todos/fetch', todoApi.getAll)

const todoSlice = createSlice({
  name: 'todos',
  initialState: { items: [], status: 'idle' },
  reducers: {},
  extraReducers: (builder) => {
    builder
      .addCase(fetchTodos.pending, (state) => { state.status = 'loading' })
      .addCase(fetchTodos.fulfilled, (state, action) => {
        state.items = action.payload
        state.status = 'idle'
      })
  },
})

export const todoReducer = todoSlice.reducer
```

Root store lives in `app/`:

```typescript
// app/store/index.ts
import { configureStore } from '@reduxjs/toolkit'
import { todoReducer } from '@/entities/todo'
import { userReducer } from '@/entities/user'

export const store = configureStore({
  reducer: {
    todos: todoReducer,
    user: userReducer,
  },
})
```

## Testing Strategy

### Where tests live

Tests live **inside their slice**, next to the code they test:

```
features/
├── authentication/
│   ├── ui/
│   │   ├── LoginForm.tsx
│   │   └── LoginForm.test.tsx    ← component test
│   ├── model/
│   │   ├── auth.store.ts
│   │   └── auth.store.test.ts   ← unit test
│   ├── api/
│   │   └── auth.api.test.ts     ← API mock test
│   └── index.ts
```

Or use a `__tests__` segment:

```
features/
├── authentication/
│   ├── ui/
│   ├── model/
│   ├── __tests__/
│   │   ├── LoginForm.test.tsx
│   │   └── auth.store.test.ts
│   └── index.ts
```

### Test isolation

Tests should import from the **public API** just like any other consumer:

```typescript
// features/authentication/__tests__/LoginForm.test.tsx
import { LoginForm } from '../index'  // or '@/features/authentication'

// NOT from internal paths
// import { LoginForm } from '../ui/LoginForm'  ← avoid
```

### Integration tests

Integration tests that span multiple slices live at the page or widget level:

```
pages/
├── home/
│   ├── ui/
│   │   └── HomePage.tsx
│   ├── __tests__/
│   │   └── HomePage.integration.test.tsx
│   └── index.ts
```

### E2E tests

E2E tests live outside the `src/` tree:

```
e2e/
├── authentication.spec.ts
├── checkout.spec.ts
└── search.spec.ts
```

## Handling Shared Types

### Types that belong in entities

```typescript
// entities/user/model/user.types.ts
export interface User {
  id: string
  name: string
  email: string
  avatar?: string
}
```

### Types that belong in shared

Only generic, non-domain types:

```typescript
// shared/types/index.ts
export interface PaginatedResponse<T> {
  items: T[]
  total: number
  page: number
  pageSize: number
}

export interface ApiError {
  message: string
  code: string
  statusCode: number
}
```

### DTO types

DTOs (Data Transfer Objects) live in the `api` segment of the entity that owns them:

```typescript
// entities/product/api/product.dto.ts
export interface CreateProductDto {
  name: string
  price: number
  categoryId: string
}

export interface ProductResponseDto {
  id: string
  name: string
  price: number
  category: { id: string; name: string }
  createdAt: string
}
```

## Real-World API Integration

Concrete examples using actual Styai/EasyCloset API endpoints for a log management admin dashboard.

### Entity: `system-log`

```typescript
// entities/system-log/model/system-log.types.ts
export type LogKind = 'APPLICATION' | 'ACCESS' | 'ERROR' | 'AUDIT' | 'SECURITY'
export type LogLevel = 'DEBUG' | 'INFO' | 'WARN' | 'ERROR' | 'FATAL'

export interface SystemLog {
  id: string
  kind: LogKind
  level: LogLevel
  message: string
  source: string
  timestamp: string
  metadata?: Record<string, unknown>
}

export interface LogFile {
  filename: string
  size: number
  lastModified: string
}

export interface LogSearchParams {
  type?: LogKind
  level?: LogLevel
  startDate?: string
  endDate?: string
  keyword?: string
  page?: number
  pageSize?: number
}
```

```typescript
// entities/system-log/api/system-log.api.ts
import { apiClient } from '@/shared/api'
import type { SystemLog, LogFile, LogSearchParams } from '../model/system-log.types'
import type { PaginatedResponse } from '@/shared/types'

export const systemLogApi = {
  getTypes: () =>
    apiClient.get<string[]>('/api/v1/system/logs/types'),

  getFiles: (type: string) =>
    apiClient.get<LogFile[]>(`/api/v1/system/logs/${type}/files`),

  getContent: (type: string, filename: string, params?: { lines?: number }) =>
    apiClient.get<string[]>(`/api/v1/system/logs/${type}/${filename}`, { params }),

  search: (params: LogSearchParams) =>
    apiClient.get<PaginatedResponse<SystemLog>>('/api/v1/system/logs/search', { params }),

  download: (type: string, filename: string) =>
    apiClient.get<Blob>(`/api/v1/system/logs/${type}/${filename}/download`, {
      responseType: 'blob',
    }),
}
```

```typescript
// entities/system-log/model/system-log.queries.ts
import { useQuery } from '@tanstack/react-query'
import { systemLogApi } from '../api/system-log.api'
import type { LogSearchParams } from './system-log.types'

export const systemLogKeys = {
  all: ['system-logs'] as const,
  types: () => [...systemLogKeys.all, 'types'] as const,
  files: (type: string) => [...systemLogKeys.all, 'files', type] as const,
  content: (type: string, filename: string) =>
    [...systemLogKeys.all, 'content', type, filename] as const,
  search: (params: LogSearchParams) =>
    [...systemLogKeys.all, 'search', params] as const,
}

export const useLogTypes = () =>
  useQuery({
    queryKey: systemLogKeys.types(),
    queryFn: () => systemLogApi.getTypes(),
  })

export const useLogFiles = (type: string) =>
  useQuery({
    queryKey: systemLogKeys.files(type),
    queryFn: () => systemLogApi.getFiles(type),
    enabled: !!type,
  })

export const useLogContent = (type: string, filename: string) =>
  useQuery({
    queryKey: systemLogKeys.content(type, filename),
    queryFn: () => systemLogApi.getContent(type, filename),
    enabled: !!type && !!filename,
  })

export const useLogSearch = (params: LogSearchParams) =>
  useQuery({
    queryKey: systemLogKeys.search(params),
    queryFn: () => systemLogApi.search(params),
  })
```

```typescript
// entities/system-log/index.ts
export { LogTable } from './ui/LogTable'
export { LogLevelBadge } from './ui/LogLevelBadge'
export type { SystemLog, LogFile, LogKind, LogLevel, LogSearchParams } from './model/system-log.types'
export { useLogTypes, useLogFiles, useLogContent, useLogSearch, systemLogKeys } from './model/system-log.queries'
export { systemLogApi } from './api/system-log.api'
```

### Feature: `search-logs`

```typescript
// features/search-logs/model/useLogSearchForm.ts
import { useState, useCallback } from 'react'
import type { LogKind, LogLevel, LogSearchParams } from '@/entities/system-log'

export const useLogSearchForm = () => {
  const [filters, setFilters] = useState<LogSearchParams>({})

  const updateFilter = useCallback(<K extends keyof LogSearchParams>(
    key: K,
    value: LogSearchParams[K],
  ) => {
    setFilters(prev => ({ ...prev, [key]: value }))
  }, [])

  const resetFilters = useCallback(() => setFilters({}), [])

  return { filters, updateFilter, resetFilters }
}
```

```typescript
// features/search-logs/ui/LogSearchForm.tsx
import { useLogTypes } from '@/entities/system-log'
import type { LogKind, LogLevel, LogSearchParams } from '@/entities/system-log'
import { Input, Select, Button } from '@/shared/ui'

interface LogSearchFormProps {
  filters: LogSearchParams
  onFilterChange: <K extends keyof LogSearchParams>(key: K, value: LogSearchParams[K]) => void
  onReset: () => void
}

export const LogSearchForm = ({ filters, onFilterChange, onReset }: LogSearchFormProps) => {
  const { data: logTypes } = useLogTypes()

  return (
    <form className="flex gap-3 items-end flex-wrap">
      <Select
        label="Type"
        value={filters.type ?? ''}
        onChange={(v) => onFilterChange('type', v as LogKind)}
        options={logTypes?.map(t => ({ label: t, value: t })) ?? []}
      />
      <Select
        label="Level"
        value={filters.level ?? ''}
        onChange={(v) => onFilterChange('level', v as LogLevel)}
        options={['DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'].map(l => ({ label: l, value: l }))}
      />
      <Input
        label="From"
        type="date"
        value={filters.startDate ?? ''}
        onChange={(v) => onFilterChange('startDate', v)}
      />
      <Input
        label="To"
        type="date"
        value={filters.endDate ?? ''}
        onChange={(v) => onFilterChange('endDate', v)}
      />
      <Input
        label="Keyword"
        value={filters.keyword ?? ''}
        onChange={(v) => onFilterChange('keyword', v)}
        placeholder="Search log messages..."
      />
      <Button variant="ghost" onClick={onReset}>Reset</Button>
    </form>
  )
}
```

```typescript
// features/search-logs/index.ts
export { LogSearchForm } from './ui/LogSearchForm'
export { useLogSearchForm } from './model/useLogSearchForm'
```

### Feature: `download-log-file`

```typescript
// features/download-log-file/model/useDownloadLog.ts
import { useMutation } from '@tanstack/react-query'
import { systemLogApi } from '@/entities/system-log'

export const useDownloadLog = () =>
  useMutation({
    mutationFn: ({ type, filename }: { type: string; filename: string }) =>
      systemLogApi.download(type, filename),
    onSuccess: (blob, { filename }) => {
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = filename
      a.click()
      URL.revokeObjectURL(url)
    },
  })
```

```typescript
// features/download-log-file/ui/DownloadLogButton.tsx
import { Button } from '@/shared/ui'
import { useDownloadLog } from '../model/useDownloadLog'

interface DownloadLogButtonProps {
  type: string
  filename: string
}

export const DownloadLogButton = ({ type, filename }: DownloadLogButtonProps) => {
  const { mutate, isPending } = useDownloadLog()

  return (
    <Button
      variant="ghost"
      size="sm"
      disabled={isPending}
      onClick={() => mutate({ type, filename })}
    >
      {isPending ? 'Downloading...' : 'Download'}
    </Button>
  )
}
```

```typescript
// features/download-log-file/index.ts
export { DownloadLogButton } from './ui/DownloadLogButton'
export { useDownloadLog } from './model/useDownloadLog'
```

### Widget: `log-viewer`

```typescript
// widgets/log-viewer/ui/LogViewer.tsx
import { LogTable, useLogSearch } from '@/entities/system-log'
import { LogSearchForm, useLogSearchForm } from '@/features/search-logs'
import { DownloadLogButton } from '@/features/download-log-file'

export const LogViewer = () => {
  const { filters, updateFilter, resetFilters } = useLogSearchForm()
  const { data, isLoading } = useLogSearch(filters)

  return (
    <div className="space-y-4">
      <LogSearchForm
        filters={filters}
        onFilterChange={updateFilter}
        onReset={resetFilters}
      />
      <LogTable
        logs={data?.items ?? []}
        isLoading={isLoading}
        actions={(log) => (
          <DownloadLogButton type={log.kind} filename={`${log.id}.log`} />
        )}
      />
    </div>
  )
}
```

```typescript
// widgets/log-viewer/index.ts
export { LogViewer } from './ui/LogViewer'
```

### Page: `log-management`

```typescript
// pages/@admin/log-management/ui/LogManagementPage.tsx
import { LogViewer } from '@/widgets/log-viewer'

export const LogManagementPage = () => (
  <div className="container mx-auto py-6">
    <h1 className="text-2xl font-bold mb-6">Log Management</h1>
    <LogViewer />
  </div>
)
```

```typescript
// pages/@admin/log-management/index.ts
export { LogManagementPage } from './ui/LogManagementPage'
```

### Shared: `client-logger`

A fire-and-forget service for sending client-side logs to `POST /api/v1/logs/ingest`:

```typescript
// shared/lib/client-logger.ts
import { apiClient } from '@/shared/api'

type ClientLogLevel = 'debug' | 'info' | 'warn' | 'error' | 'fatal'

interface ClientLogEntry {
  level: ClientLogLevel
  message: string
  context?: Record<string, unknown>
  timestamp?: string
}

const sendLog = (entry: ClientLogEntry) => {
  const payload = {
    ...entry,
    timestamp: entry.timestamp ?? new Date().toISOString(),
    userAgent: navigator.userAgent,
    url: window.location.href,
  }

  // Fire-and-forget — don't block UI on logging
  apiClient.post('/api/v1/logs/ingest', payload).catch(() => {
    // Silently fail — logging should never break the app
  })
}

export const clientLogger = {
  debug: (message: string, context?: Record<string, unknown>) =>
    sendLog({ level: 'debug', message, context }),
  info: (message: string, context?: Record<string, unknown>) =>
    sendLog({ level: 'info', message, context }),
  warn: (message: string, context?: Record<string, unknown>) =>
    sendLog({ level: 'warn', message, context }),
  error: (message: string, context?: Record<string, unknown>) =>
    sendLog({ level: 'error', message, context }),
  fatal: (message: string, context?: Record<string, unknown>) =>
    sendLog({ level: 'fatal', message, context }),
}
```

```typescript
// Usage from any layer:
import { clientLogger } from '@/shared/lib'

// In an error boundary
clientLogger.error('Unhandled render error', { component: 'App', error: err.message })

// In a feature
clientLogger.info('User completed checkout', { orderId: '123' })
```

## Monorepo / Multi-Package Patterns

For large projects, FSD layers can map to packages:

```
packages/
├── shared/           ← @myapp/shared
├── entities/         ← @myapp/entities
├── features/         ← @myapp/features
└── apps/
    ├── web/          ← uses @myapp/* packages
    └── mobile/       ← uses @myapp/* packages
```

Each package maintains the same internal FSD structure.

## When NOT to Use FSD

- **Very small projects** (< 10 components) — overhead isn't worth it
- **Prototypes / hackathons** — speed matters more than structure
- **Solo projects with no growth plan** — simpler flat structure is fine

FSD shines when:
- Multiple developers work on the same codebase
- The project will grow over months/years
- Features are added, removed, or modified frequently
- You want to prevent "spaghetti" imports as the project scales
