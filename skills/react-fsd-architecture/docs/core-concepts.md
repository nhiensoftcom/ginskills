# FSD Core Concepts

Feature-Sliced Design organizes code around **business features** instead of technical layers.

Official docs: https://feature-sliced.design

## The Golden Rule

> A module in a slice can only import from slices on **layers strictly below** it.

This prevents circular dependencies and makes the codebase predictable.

---

## Layers (top → bottom)

```
src/
├── app/          ← Bootstrap, routing, providers (no slices)
├── pages/        ← Route-level screens
├── widgets/      ← Composite UI blocks reused across pages
├── features/     ← User interactions with business logic
├── entities/     ← Business domain models, API hooks, types
└── shared/       ← Utilities, UI primitives, no business logic (no slices)
```

| Layer | Purpose | Has slices? |
|-------|---------|-------------|
| **app** | Bootstrap, routing, providers | No |
| **pages** | Route screens | Yes |
| **widgets** | Large composite UI (header, sidebar) | Yes |
| **features** | User interactions (login, delete, import) | Yes |
| **entities** | Domain models, API hooks, types | Yes |
| **shared** | UI kit, API client, utils, config | No — segments directly |

**Import direction — higher can use lower, never reverse:**
```
app  →  pages  →  widgets  →  features  →  entities  →  shared
```

---

## Slices

Group code by **business meaning** — names reflect the domain, not tech:

```
✅ entities/user/       entities/order/       features/add-to-cart/
❌ features/hooks/      features/utils/       entities/api/
```

**Rules:**
- Zero coupling between slices on the same layer (except entities `@x`)
- Each slice exposes a public API (`index.ts`)
- External code imports from `index.ts` only — no deep imports

---

## Segments

Technical sub-folders within a slice:

| Segment | Contains |
|---------|----------|
| `ui` / `_ui` | Components, styles |
| `model` / `_store` | State, stores, hooks |
| `api` / `_apis` | Backend requests (one file per operation) |
| `lib` | Internal utilities for this slice |
| `config` | Constants, feature flags |
| `_types` | Type definitions |
| `_utils` | Pure helpers, label mappers |

> This project uses **underscore-prefixed** segments (`_apis`, `_types`, `_utils`, `_ui`) instead of plain `api`, `model`.

---

## Public API (`index.ts`)

```typescript
// ✅ Explicit named exports only
export { LoginForm } from './ui/LoginForm'
export { useAuth } from './model/auth.store'
export type { User } from './model/auth.types'

// ❌ Never use export *
export * from './ui'
```

> **This project does NOT use barrel `index.ts` for entities.**
> Import directly from the specific file:
> ```typescript
> // ✅
> import { useUpdateFacebookVia } from "@/entities/facebook-via/_apis/update-facebook-via.api"
> // ❌
> import { useUpdateFacebookVia } from "@/entities/facebook-via"
> ```

---

## @x Cross-Imports (entities only)

When entity B's data contains entity A's data, use `@x` notation:

```
entities/product/@x/order.ts    ← public API only for the order entity
entities/order/ui/OrderCard.tsx  ← imports from entities/product/@x/order
```

---

## Framework Adaptations

### Next.js App Router
```
src/
├── app/          ← Next.js routing (thin route files only)
├── pages/        ← FSD page UI logic
├── features/
├── entities/
└── shared/
```

### Tauri + React (this project)
```
src/
├── app/
│   ├── layouts/
│   └── routes/   ← Thin route files, import from features
├── features/     ← All business logic
├── entities/     ← Domain models, API hooks
└── shared/
```

---

## Common Mistakes

```typescript
// ❌ Entity importing from a feature (upward import)
// entities/todo/model/todo.store.ts
import { useAuth } from '@/features/authentication'  // VIOLATION

// ❌ Cross-importing slices on the same layer
import { useSearch } from '@/features/search'  // inside features/filter/ — VIOLATION

// ❌ Everything in shared
shared/hooks/   shared/helpers/   shared/utils/  // too vague

// ❌ Deep import into slice internals
import { validateEmail } from '@/features/authentication/lib/validation'
// ✅ Always through public API
import { validateEmail } from '@/features/authentication'
```
