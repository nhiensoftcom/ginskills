# Entity Conventions (scrape-video project)

> Applies to `src/entities/` in **desktop app** and **web UI** — same pattern in both.

---

## Folder Structure

```
entities/{entity-name}/
├── _apis/          ← ONE file per operation (never combine)
├── _types/         ← {entity}.type.ts — response shapes only
├── _utils/         ← pure helpers, label mappers
└── _repositories/  ← SQLite only (desktop local entities)
```

Multi-word names: always full `kebab-case` — never abbreviate:
```
entities/personal-access-token/   ✅
entities/pat/                     ❌
```

---

## `_apis/` — One File Per Operation (CRITICAL)

### File naming

```
[verb]-[entity].api.ts         ← React Query hooks (useQuery / useMutation)
[verb]-[entity]-manual.ts      ← Imperative / callback-based fetch (no .api.ts suffix)
```

### Verb prefix table

| Operation | File prefix | Example |
|-----------|-------------|---------|
| Fetch list | `get-list-` | `get-list-facebook-vias.api.ts` |
| Fetch single (imperative) | `get-{entity}-manual.ts` | `get-facebook-via-manual.ts` |
| Create | `add-` or `create-` | `add-user.api.ts` |
| Update (partial) | `update-` | `update-facebook-via.api.ts` |
| Delete single | `delete-` | `delete-facebook-via.api.ts` |
| Delete all | `delete-all-` | `delete-all-facebook-vias.api.ts` |
| Batch operation | `batch-[verb]-` | `batch-delete-facebook-vias.api.ts` |
| Custom action | `[action]-` | `revoke-access-token.api.ts` |

---

## Return Value Naming (MANDATORY)

**Never return raw `{ mutate, isPending, data, isLoading }`.**

### Mutation hooks

```typescript
// Pattern: { [actionVerb][Entity]: mutateAsync, is[Verb]ing[Entity]: isPending }
return {
  deleteFacebookVia: mutateAsync,
  isDeletingFacebookVia: isPending,
}

return {
  updateFacebookVia: mutateAsync,
  isUpdatingFacebookVia: isPending,
}

return {
  batchDeleteFacebookVias: mutateAsync,
  isBatchDeletingFacebookVias: isPending,
}
```

### Query hooks

```typescript
// Pattern: { [entityOrListName]: data, isLoading[Name]: isLoading }
return {
  facebookVias: data,
  isLoadingFacebookVias: isLoading,
}
```

### Manual (imperative) hooks

```typescript
// Pattern: { get{Entity}Res, isLoadingGet{Entity}, errorGet{Entity}, mutateGet{Entity} }
return {
  getFacebookViaRes: data,
  isLoadingGetFacebookVia: isLoading,
  errorGetFacebookVia: error,
  mutateGetFacebookVia: mutate,   // caller triggers this
}
```

---

## Payload Types — Co-locate With Hook File

**Never duplicate fields from the entity type — derive with `Pick<>` / `Partial<>` / `Omit<>`.**

```typescript
// update-facebook-via.api.ts
export type UpdateFacebookViaPayload = { _id: string } & Partial<
  Pick<FacebookViaRes, "password" | "new_password" | "totp_secret" | "emails">
>;

// add-user.api.ts
export type AddUserPayload = Pick<UserRes, "name" | "email" | "roles"> & {
  password: string;
};
```

---

## QK_ Query Key Constants

Export from the **same file** as the query hook:

```typescript
// get-list-facebook-vias.api.ts
export const QK_LIST_FACEBOOK_VIAS = "list-facebook-vias";

// Other files cross-import to invalidate:
import { QK_LIST_FACEBOOK_VIAS } from "./get-list-facebook-vias.api";
onSuccess: () => {
  queryClient.invalidateQueries({ queryKey: [QK_LIST_FACEBOOK_VIAS] });
},
```

---

## Manual Fetch Hook (`get-{entity}-manual.ts`)

Imperative hook using `useState` + `useCallback`. **No `useQuery`.**

```typescript
// entities/facebook-via/_apis/get-facebook-via-manual.ts
import { useCallback, useState } from "react";
import axiosInstance from "@/shared/libs/axios";
import { FacebookViaRes } from "../_types/facebook-via.type";

export const useGetFacebookViaManual = ({ _id }: { _id?: string }) => {
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [data, setData] = useState<FacebookViaRes | null>(null);

  const mutate = useCallback(async () => {
    if (!_id) return null;
    setIsLoading(true);
    try {
      const res = await axiosInstance.get(`/api/v1/facebook-auto-post/vias/${_id}`);
      setData(res.data);
      setIsLoading(false);
      return res.data as FacebookViaRes;
    } catch (err) {
      setIsLoading(false);
      setError(err);
      return null;
    }
  }, [_id]);

  return {
    getFacebookViaRes: data,
    isLoadingGetFacebookVia: isLoading,
    errorGetFacebookVia: error,
    mutateGetFacebookVia: mutate,
  };
};
```

**Primary use case — init edit form with fresh data (no `useEffect`):**

```typescript
// In Layer 3 container:
const { mutateGetFacebookVia } = useGetFacebookViaManual({ _id: via?._id });

const form = useEditViaForm({
  defaultValues: async () => {        // RHF calls this on mount automatically
    const res = await mutateGetFacebookVia();
    return res ? mapToValues(res) : DEFAULT_EDIT_VIA_FORM_VALUES;
  },
});
// ✅ No useEffect. No form.reset(). RHF handles it.
```

---

## `_types/` — Entity Type File

One file: `{entity}.type.ts`. Response shapes only — no payload types here.

```typescript
// facebook-via.type.ts
export type ViaEmail = {
  email: string;
  password: string;
};

export type FacebookViaRes = {
  _id: string;
  uid: string;
  password: string;
  new_password: string;
  totp_secret: string;
  emails: ViaEmail[];
  user_id: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};
```

**Naming conventions:**
- Response shape → `type {Entity}Res`
- Enums → `enum {Entity}{Attribute}` with `SCREAMING_SNAKE` keys + lowercase string values

---

## `_utils/` — Label Mappers

Pure functions mapping enum → display string. Always include `default: return status;`.

```typescript
// _utils/get-user-entity-status.ts
export const getUserEntityStatus = (status: UserStatus): string => {
  switch (status) {
    case UserStatus.ACTIVE: return "Hoạt động";
    default: return status;   // ← always include for future enum values
  }
};
```

---

## Anti-Patterns

```typescript
// ❌ Multiple hooks in one file
// ❌ Payload types in _types/entity.type.ts
// ❌ import from entity folder root @/entities/user — use direct path
// ❌ Create index.ts barrel in entity folder
// ❌ useQuery + enabled: false + refetch() for imperative — use manual hook
// ❌ Return raw { mutate, isPending } — always rename to descriptive names
// ❌ useEffect to reset form after edit dialog opens — use async defaultValues
```
