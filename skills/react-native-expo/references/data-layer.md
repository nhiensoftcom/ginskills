# Data Layer — React Query v5 + API Client

## API Client (`@/shared/libs/api-client`)

Custom Axios wrapper with:
- **Auto token injection** via request interceptor
- **401 auto-refresh** with single-flight pattern (max 2 retries, prevents race conditions)
- **FormData fallback** to native `fetch` (Axios has RN FormData issues)
- **Credit header parsing**: Response interceptor reads `x-credits-balance` and `x-credits-used` headers
- **Custom headers**: `User-Agent`, `X-Client-Type: mobile`, `Accept-Language`
- Base URL from `EXPO_PUBLIC_API_URL` env var
- Android emulator: `localhost` auto-replaced with `10.0.2.2`

```typescript
import { client } from "@/shared/libs/api-client"

// Standard requests
const { data } = await client.get<ItemRes[]>("/api/v1/item")
const { data } = await client.post<ItemRes>("/api/v1/item", body)
const { data } = await client.patch<ItemRes>(`/api/v1/item/${id}`, body)
await client.delete(`/api/v1/item/${id}`)

// FormData (auto falls back to native fetch)
const formData = new FormData()
formData.append("file", { uri, type, name } as any)
const { data } = await client.post("/api/v1/upload", formData, {
  headers: { "X-FormData-Upload": "true" },
})
```

## Service Pattern — One Hook Per File

Each query/mutation lives in its own file under `_services/`:

```
src/models/item/_services/
  use-get-items.ts         # useInfiniteQuery
  use-get-item-detail.ts   # useQuery
  use-create-item.ts       # useMutation
  use-update-item.ts       # useMutation
  use-delete-item.ts       # useMutation
```

### Query Key Convention

Query keys are **always the API URL path string**:

```typescript
export const ITEM_INFINITE_LIST_QUERY_KEY = "/api/v1/item"
export const ITEM_DETAIL_QUERY_KEY = "/api/v1/item/detail"
export const CATEGORIES_QUERY_KEY = "/api/v1/category"
```

### useQuery Pattern

```typescript
import { useQuery } from "@tanstack/react-query"
import { client } from "@/shared/libs/api-client"

export const ITEM_DETAIL_QUERY_KEY = "/api/v1/item/detail"

export const useGetItemDetail = (id: string) => {
  return useQuery({
    queryKey: [ITEM_DETAIL_QUERY_KEY, id],
    queryFn: async () => {
      const { data } = await client.get<ItemDetailPopulated>(`/api/v1/item/${id}`)
      return data
    },
    enabled: !!id,
  })
}
```

### useInfiniteQuery Pattern

```typescript
import { useInfiniteQuery } from "@tanstack/react-query"

export const ITEM_INFINITE_LIST_QUERY_KEY = "/api/v1/item"

export const useGetItemInfiniteList = (params?: ItemListParams, opts?: { enabled?: boolean }) => {
  const limit = 20
  const query = useInfiniteQuery({
    queryKey: [ITEM_INFINITE_LIST_QUERY_KEY, limit, params],
    initialPageParam: 0,
    queryFn: async ({ pageParam }) => {
      const { data } = await client.get<PaginatedResponse<ItemRes>>(ITEM_INFINITE_LIST_QUERY_KEY, {
        params: { limit, skip: pageParam, paging_count: pageParam === 0, ...params },
      })
      return data
    },
    getNextPageParam: (lastPage, allPages) => {
      if ((lastPage?.data?.length ?? 0) < limit) return undefined
      return allPages.reduce((sum, p) => sum + (p?.data?.length ?? 0), 0)
    },
    enabled: opts?.enabled,
  })

  // Flatten pages
  const items = query.data?.pages.flatMap((p) => p.data) ?? []
  const firstMeta = query.data?.pages?.[0]?.meta

  return { items, meta: firstMeta, ...query }
}
```

Usage with FlashList + infinite scroll:
```typescript
const { items, fetchNextPage, hasNextPage, isFetchingNextPage } = useGetItemInfiniteList()
const { onEndReached } = useInfiniteScroll({ fetchNextPage, hasNextPage, isFetchingNextPage })

<FlashList
  data={items}
  renderItem={renderItem}
  estimatedItemSize={120}
  onEndReached={onEndReached}
  onEndReachedThreshold={0.5}
  ListFooterComponent={isFetchingNextPage ? <ActivityIndicator /> : null}
/>
```

### useMutation Pattern

```typescript
import { useMutation, useQueryClient } from "@tanstack/react-query"
import { showErrorToast } from "@/shared/components/toast"
import { logEvent } from "@/shared/utils/log-event"

export const useUpdateItem = () => {
  const queryClient = useQueryClient()

  const { mutate, isPending, error } = useMutation({
    mutationFn: async ({ _id, body }: { _id: string; body: UpdateItemBody }) => {
      return (await client.patch<ItemRes>(`/api/v1/item/${_id}`, body)).data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: [ITEM_INFINITE_LIST_QUERY_KEY] })
      queryClient.invalidateQueries({ queryKey: [ITEM_DETAIL_QUERY_KEY] })
      logEvent("item_updated")
    },
    onError: () => {
      showErrorToast("Update Failed", "Could not update the item. Please try again.")
    },
  })

  return { updateItem: mutate, isUpdatingItem: isPending, updateItemError: error }
}
```

### Optimistic Updates

```typescript
export const useToggleFavorite = () => {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async (id: string) => (await client.patch(`/api/v1/item/${id}/favorite`)).data,
    onMutate: async (id) => {
      await queryClient.cancelQueries({ queryKey: [ITEM_DETAIL_QUERY_KEY, id] })
      const previous = queryClient.getQueryData([ITEM_DETAIL_QUERY_KEY, id])
      queryClient.setQueryData([ITEM_DETAIL_QUERY_KEY, id], (old: any) => ({
        ...old,
        isFavorite: !old.isFavorite,
      }))
      return { previous }
    },
    onError: (_err, id, context) => {
      queryClient.setQueryData([ITEM_DETAIL_QUERY_KEY, id], context?.previous)
    },
    onSettled: (_data, _err, id) => {
      queryClient.invalidateQueries({ queryKey: [ITEM_DETAIL_QUERY_KEY, id] })
    },
  })
}
```

### Async Service Pattern (for Zustand stores)

```typescript
// Non-hook function for use inside Zustand slices
export const getStyBalance = async (): Promise<StyBalance> => {
  const response = await client.get<StyBalance>(GET_STY_BALANCE_QUERY_KEY)
  return response.data
}
```

## Type Patterns

Types extend shared bases from `@/shared/types/`:

```typescript
import { IdRes, TimeStampRes } from "@/shared/types"

// Response type (composition pattern)
type ItemRes = {
  name: string
  image_url: string
  category_id: string
  blurhash?: string
} & IdRes & TimeStampRes
// IdRes = { _id: string }
// TimeStampRes = { created_at: string; updated_at: string }

// Populated type (nested objects expanded)
type ItemDetailPopulated = Omit<ItemRes, "styles" | "occasions"> & {
  styles: FashionStyleRes[]
  occasions: FashionOccasionRes[]
}

// Paginated response
type PaginatedResponse<T> = {
  data: T[]
  meta: PaginationMeta  // page, take, item_count, page_count, has_next_page
}
```

## React Query Provider Setup

```typescript
// src/shared/providers/react-query-provider.tsx
// - Sets online manager from expo-network (device connectivity)
// - Sets focus manager from AppState (refetch on app focus)
// - Exports queryClient singleton
```

## Token Storage (`@/shared/libs/token-storage`)

Secure JWT storage via `react-native-keychain`:

```typescript
import { storeTokens, getAccessToken, clearTokens, hasValidTokens, validateTokenIntegrity } from "@/shared/libs/token-storage"

await storeTokens({ accessToken, refreshToken })
const token = await getAccessToken()
await clearTokens()  // On sign-out
const isValid = await hasValidTokens()
```

## Best Practices

- **One query/mutation hook per file** — named `use-get-*.ts` or `use-create-*.ts`
- **Export `QUERY_KEY` constant** from every query file
- **Query key = API URL path** — always a string constant
- **Always `invalidateQueries`** in mutation `onSuccess`
- **Always `showErrorToast`** in mutation `onError`
- **Always `logEvent`** for analytics in mutation `onSuccess`
- **Use `enabled` option** to prevent queries without required params
- **Use `useInfiniteQuery`** for paginated lists, never manual page tracking
- **Flatten pages** in the hook: `data?.pages.flatMap((p) => p.data) ?? []`
- **Distinguish loading states**: `isLoading` (initial), `isFetching` (refetch), `isPending` (mutation)
- **Never import axios directly** — always use `client` from `api-client`
- **FormData uploads** need `"X-FormData-Upload": "true"` header
