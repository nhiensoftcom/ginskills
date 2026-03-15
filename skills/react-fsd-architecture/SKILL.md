---
name: react-fsd-architecture
description: |
  **Feature-Sliced Design (FSD) Architecture**: Architectural methodology for organizing frontend projects by business features — layers, slices, segments, public APIs, and import rules.
  - MANDATORY TRIGGERS: feature sliced design, FSD, feature slice, project structure, folder structure, architecture, organize code, layers slices segments, app structure, frontend architecture, scalable structure, code organization, module structure, refactor structure
  - Use this skill whenever the user is setting up, refactoring, or discussing frontend project architecture and folder structure. Also trigger when deciding where to place new code, resolving circular dependencies, or organizing a React/React Native/Next.js project.
---

# Feature-Sliced Design (FSD)

An architectural methodology for organizing frontend projects around **business features** instead of technical layers. Works with React, React Native, Next.js, Vue, Svelte — any frontend framework.

Official docs: https://feature-sliced.design

## The Golden Rule

> **A module in a slice can only import from slices on layers strictly below.**

This single rule prevents circular dependencies, enforces clear boundaries, and makes your codebase predictable.

## The Three Levels

FSD organizes code into 3 hierarchical levels:

```
Layer  →  Slice  →  Segment
```

- **Layer**: Why the code exists (its responsibility level)
- **Slice**: What business domain it belongs to
- **Segment**: How it's technically organized

---

## Layers (7 levels, top to bottom)

Layers are ordered by responsibility. Higher layers can import from lower layers, never the reverse.

```
src/
├── app/          ← 1. App (highest — bootstrap, routing, providers)
├── processes/    ← 2. Processes (DEPRECATED — move to features or app)
├── pages/        ← 3. Pages (route-level screens)
├── widgets/      ← 4. Widgets (composite UI blocks)
├── features/     ← 5. Features (user interactions with business logic)
├── entities/     ← 6. Entities (business domain models)
└── shared/       ← 7. Shared (lowest — utilities, UI primitives, no business logic)
```

### Layer Details

| Layer | Purpose | Contains | Has slices? |
|-------|---------|----------|-------------|
| **app** | Application bootstrap | Routing, providers, global styles, entry point | No — segments directly |
| **pages** | Route screens | Page UI, data loading, error boundaries | Yes — one slice per page |
| **widgets** | Composite UI blocks | Large self-sufficient sections reused across pages | Yes |
| **features** | User interactions | Business logic actions (login, add-to-cart, search) | Yes |
| **entities** | Domain models | Data models, schemas, API functions, entity UI | Yes — one slice per entity |
| **shared** | Foundation | UI kit, API client, utils, types, config, i18n | No — segments directly |

### Import Direction

```
app  →  pages  →  widgets  →  features  →  entities  →  shared
 ↓        ↓         ↓           ↓            ↓           ↓
Can import anything below. Cannot import from above or same layer.
```

**Exceptions:**
- `app` and `shared` don't have slices — segments can reference each other freely within the layer
- `entities` can use `@x` cross-imports for entity relationships (see below)

---

## Slices

Slices group code by **business meaning**. Their names reflect your domain, not technical concepts.

### Good slice names (domain-driven)
```
entities/user/
entities/product/
entities/order/
features/authentication/
features/add-to-cart/
features/search/
pages/home/
pages/product-detail/
widgets/header/
widgets/product-card/
```

### Bad slice names (tech-driven — avoid)
```
features/hooks/         ← this is a segment name, not a slice
features/utils/         ← belongs in shared/lib
entities/api/           ← API is a segment, not an entity
```

### Slice Rules

1. **Zero coupling** between slices on the same layer — they cannot import from each other
2. **High cohesion** — everything related to one concept stays in one slice
3. **Public API required** — each slice exposes an `index.ts`, external code imports only from this file
4. **Domain naming** — names reflect what the user/business cares about

### Slice Groups

Related slices can be grouped in folders for organization, but the group folder itself cannot contain shared code:

```
entities/
├── user/              # slice
├── product/           # slice
├── @catalog/          # group folder (just for organization)
│   ├── category/      # slice
│   └── brand/         # slice
```

---

## Segments

Segments are the lowest level — they group code by **technical purpose** within a slice.

### Standard Segment Names

| Segment | Contains | Example files |
|---------|----------|---------------|
| `ui` | Components, styles, formatters | `ProductCard.tsx`, `ProductCard.styles.ts` |
| `model` | State, business logic, types, hooks | `useProduct.ts`, `product.store.ts`, `product.types.ts` |
| `api` | Backend interactions, request functions | `product.api.ts`, `product.dto.ts` |
| `lib` | Internal utilities for this slice | `formatPrice.ts`, `validateSku.ts` |
| `config` | Constants, feature flags | `product.config.ts` |

**Additional custom segments** are allowed (especially in `app` and `shared`):
- `i18n` — translations
- `router` — routing config
- `assets` — images, icons for this slice

### Not every slice needs all segments

Start with `ui` and `model`. Add `api`, `lib`, `config` only when needed:

```
features/
├── authentication/
│   ├── ui/
│   │   └── LoginForm.tsx
│   ├── model/
│   │   ├── auth.store.ts
│   │   └── auth.types.ts
│   ├── api/
│   │   └── auth.api.ts
│   └── index.ts          ← public API
│
├── search/
│   ├── ui/
│   │   └── SearchBar.tsx
│   ├── model/
│   │   └── useSearch.ts
│   └── index.ts          ← public API (no api/ or lib/ needed)
```

---

## Public API (index.ts)

Every slice **must** have an `index.ts` that explicitly re-exports what's public.

### Rules

1. **Explicit named exports** — never use `export *`
2. **Only export what consumers need** — components, types, hooks, constants
3. **Keep internals private** — helper functions, internal components, implementation details stay unexported
4. **External code must import from the index** — never deep-import into a slice

### Pattern

```typescript
// features/authentication/index.ts

// UI
export { LoginForm } from './ui/LoginForm'
export { SignUpForm } from './ui/SignUpForm'

// Model (hooks, types)
export { useAuth } from './model/auth.store'
export type { User, AuthState } from './model/auth.types'

// API (if consumers need direct access)
export { loginApi, registerApi } from './api/auth.api'
```

### Import Rules

```typescript
// GOOD — import from public API
import { LoginForm, useAuth } from '@/features/authentication'

// BAD — deep import into slice internals
import { LoginForm } from '@/features/authentication/ui/LoginForm'
import { validateEmail } from '@/features/authentication/lib/validation'
```

### Shared Layer Public API

Since `shared` has no slices, each **segment** gets its own public API:

```typescript
// shared/ui/index.ts
export { Button } from './Button'
export { Input } from './Input'
export { Modal } from './Modal'

// shared/api/index.ts
export { apiClient } from './client'
export type { ApiError } from './types'

// shared/lib/index.ts
export { formatDate, formatCurrency } from './formatters'
```

```typescript
// Consumer imports by segment
import { Button, Input } from '@/shared/ui'
import { apiClient } from '@/shared/api'
import { formatDate } from '@/shared/lib'
```

---

## Cross-Imports (@x Notation)

Slices on the same layer normally cannot import from each other. The one exception is **entities** that have relationships.

### When to use

When entity B's data contains entity A's data (e.g., Order contains Product), use the `@x` notation:

```
entities/
├── product/
│   ├── @x/
│   │   └── order.ts      ← public API specifically for the order entity
│   ├── ui/
│   ├── model/
│   └── index.ts
├── order/
│   ├── ui/
│   │   └── OrderCard.tsx  ← can import from entities/product/@x/order
│   ├── model/
│   └── index.ts
```

```typescript
// entities/product/@x/order.ts
// Only export what the order entity needs
export { ProductPreview } from '../ui/ProductPreview'
export type { ProductSummary } from '../model/product.types'
```

### Rules for @x

- Only use on the **entities** layer
- Keep cross-imports **minimal** — only what's truly needed
- All layers above entities still have cross-imports **forbidden**
- `@x` files are explicit — they document the coupling between entities

---

## Path Aliases

Set up TypeScript path aliases to match the layers:

```json
// tsconfig.json
{
  "compilerOptions": {
    "paths": {
      "@/*": ["./src/*"],
      "@/app/*": ["./src/app/*"],
      "@/pages/*": ["./src/pages/*"],
      "@/widgets/*": ["./src/widgets/*"],
      "@/features/*": ["./src/features/*"],
      "@/entities/*": ["./src/entities/*"],
      "@/shared/*": ["./src/shared/*"]
    }
  }
}
```

---

## Framework-Specific Patterns

### Next.js (App Router)

Next.js App Router has its own `app/` directory for routes. Combine with FSD:

```
src/
├── app/                    ← Next.js App Router (routing + layouts)
│   ├── layout.tsx
│   ├── page.tsx            → imports from @/pages/home
│   ├── products/
│   │   └── [id]/
│   │       └── page.tsx    → imports from @/pages/product-detail
│   └── providers.tsx
├── pages/                  ← FSD pages layer (page UI logic)
│   ├── home/
│   └── product-detail/
├── widgets/
├── features/
├── entities/
└── shared/
```

The Next.js `app/` directory handles routing. FSD `pages/` holds the actual page UI and logic. Next.js route files are thin wrappers:

```typescript
// src/app/products/[id]/page.tsx
import { ProductDetailPage } from '@/pages/product-detail'

export default function Page({ params }: { params: { id: string } }) {
  return <ProductDetailPage id={params.id} />
}
```

### React Native (Expo Router)

Same principle — Expo Router's `app/` directory handles navigation, FSD handles architecture:

```
src/
├── app/                    ← Expo Router (file-based routing)
│   ├── (tabs)/
│   │   ├── index.tsx       → imports from @/pages/home
│   │   ├── profile.tsx     → imports from @/pages/profile
│   │   └── _layout.tsx
│   └── _layout.tsx
├── pages/                  ← FSD pages layer
│   ├── home/
│   └── profile/
├── widgets/
├── features/
├── entities/
└── shared/
```

### Plain React (Vite / CRA)

FSD `app/` layer handles routing directly:

```
src/
├── app/
│   ├── App.tsx
│   ├── providers/
│   ├── router/
│   └── styles/
├── pages/
├── widgets/
├── features/
├── entities/
└── shared/
```

---

## Complete Example

A todo app structured with FSD:

```
src/
├── app/
│   ├── providers/
│   │   ├── QueryProvider.tsx
│   │   └── ThemeProvider.tsx
│   ├── router/
│   │   └── index.tsx
│   ├── styles/
│   │   └── global.css
│   └── index.tsx
│
├── pages/
│   ├── home/
│   │   ├── ui/
│   │   │   └── HomePage.tsx
│   │   └── index.ts
│   └── settings/
│       ├── ui/
│       │   └── SettingsPage.tsx
│       └── index.ts
│
├── widgets/
│   ├── todo-list/
│   │   ├── ui/
│   │   │   └── TodoList.tsx
│   │   └── index.ts
│   └── header/
│       ├── ui/
│       │   └── Header.tsx
│       └── index.ts
│
├── features/
│   ├── create-todo/
│   │   ├── ui/
│   │   │   └── CreateTodoForm.tsx
│   │   ├── model/
│   │   │   └── useCreateTodo.ts
│   │   ├── api/
│   │   │   └── createTodo.api.ts
│   │   └── index.ts
│   ├── toggle-todo/
│   │   ├── ui/
│   │   │   └── ToggleButton.tsx
│   │   ├── model/
│   │   │   └── useToggleTodo.ts
│   │   └── index.ts
│   └── delete-todo/
│       ├── ui/
│       │   └── DeleteButton.tsx
│       ├── model/
│       │   └── useDeleteTodo.ts
│       └── index.ts
│
├── entities/
│   └── todo/
│       ├── ui/
│       │   ├── TodoCard.tsx
│       │   └── TodoStatus.tsx
│       ├── model/
│       │   ├── todo.types.ts
│       │   └── todo.store.ts
│       ├── api/
│       │   └── todo.api.ts
│       └── index.ts
│
└── shared/
    ├── ui/
    │   ├── Button.tsx
    │   ├── Input.tsx
    │   ├── Modal.tsx
    │   └── index.ts
    ├── api/
    │   ├── client.ts
    │   └── index.ts
    ├── lib/
    │   ├── formatDate.ts
    │   └── index.ts
    ├── config/
    │   ├── env.ts
    │   └── index.ts
    └── types/
        └── index.ts
```

## Real-World Example: Admin Dashboard

An admin dashboard with log management, login history, and client log ingestion — based on actual Styai/EasyCloset API endpoints.

```
src/
├── app/
│   ├── providers/
│   ├── router/
│   └── index.tsx
│
├── pages/
│   ├── @admin/                        ← slice group for admin-only pages
│   │   ├── log-management/
│   │   │   ├── ui/
│   │   │   │   └── LogManagementPage.tsx
│   │   │   └── index.ts
│   │   └── dashboard/
│   │       ├── ui/
│   │       │   └── DashboardPage.tsx
│   │       └── index.ts
│   └── @user/                         ← slice group for user-facing pages
│       └── login-history/
│           ├── ui/
│           │   └── LoginHistoryPage.tsx
│           └── index.ts
│
├── widgets/
│   └── log-viewer/                    ← composes search + table + download
│       ├── ui/
│       │   └── LogViewer.tsx
│       └── index.ts
│
├── features/
│   ├── search-logs/                   ← search form with filters
│   │   ├── ui/
│   │   │   └── LogSearchForm.tsx
│   │   ├── model/
│   │   │   └── useLogSearch.ts
│   │   └── index.ts
│   └── download-log-file/             ← file download action
│       ├── ui/
│       │   └── DownloadLogButton.tsx
│       ├── model/
│       │   └── useDownloadLog.ts
│       └── index.ts
│
├── entities/
│   ├── system-log/                    ← GET /api/v1/system/logs/*
│   │   ├── ui/
│   │   │   ├── LogTable.tsx
│   │   │   └── LogLevelBadge.tsx
│   │   ├── model/
│   │   │   ├── system-log.types.ts
│   │   │   └── system-log.queries.ts
│   │   ├── api/
│   │   │   └── system-log.api.ts
│   │   └── index.ts
│   └── login-history/                 ← GET /api/v1/user/login-history
│       ├── ui/
│       │   └── LoginHistoryTable.tsx
│       ├── model/
│       │   ├── login-history.types.ts
│       │   └── login-history.queries.ts
│       ├── api/
│       │   └── login-history.api.ts
│       └── index.ts
│
└── shared/
    ├── ui/
    ├── api/
    │   └── client.ts
    ├── lib/
    │   ├── client-logger.ts           ← POST /api/v1/logs/ingest
    │   └── index.ts
    └── config/
```

**Key patterns:**
- `@admin/` and `@user/` slice groups organize pages by role without adding shared code
- `system-log` entity owns API types/hooks matching the backend response shape
- `client-logger` lives in `shared/lib` — it has no domain UI, just a fire-and-forget service
- The `log-viewer` widget composes `search-logs` + `system-log` table + `download-log-file`

---

## Common Mistakes & Anti-Patterns

### 1. Importing from a higher layer

```typescript
// BAD — entity importing from a feature (higher layer)
// entities/todo/model/todo.store.ts
import { useAuth } from '@/features/authentication'  // ← VIOLATION

// GOOD — pass auth data as props/params from the page or widget
```

### 2. Cross-importing slices on the same layer (except entities @x)

```typescript
// BAD — one feature importing another feature
import { useSearch } from '@/features/search'  // inside features/filter/

// GOOD — compose in a widget or page that imports both features
```

### 3. Putting everything in shared

```typescript
// BAD — shared becomes a dumping ground
shared/
├── components/     ← too vague
├── helpers/        ← what kind of helpers?
├── hooks/          ← for what domain?
└── utils/          ← everything goes here

// GOOD — shared has clear segments, domain logic goes in entities/features
shared/
├── ui/             ← only generic UI primitives (Button, Input, Modal)
├── api/            ← only the API client
├── lib/            ← only pure utility functions
└── config/         ← only environment/app config
```

### 4. Skipping the public API

```typescript
// BAD — deep importing into slice internals
import { validateEmail } from '@/features/authentication/lib/validation'

// GOOD — export through index.ts if it's meant to be public
import { validateEmail } from '@/features/authentication'
```

### 5. Using `export *` in index.ts

```typescript
// BAD — exposes internals, breaks encapsulation
export * from './ui'
export * from './model'
export * from './api'

// GOOD — explicit named exports
export { LoginForm } from './ui/LoginForm'
export { useAuth } from './model/auth.store'
export type { User } from './model/auth.types'
```

### 6. Making features too granular or too broad

```typescript
// TOO GRANULAR — one feature per button
features/
├── click-login-button/
├── click-signup-button/
├── click-forgot-password/

// TOO BROAD — everything in one feature
features/
├── user-management/     ← contains login, signup, profile, settings...

// RIGHT — one feature per user interaction
features/
├── authentication/      ← login + signup + password reset
├── edit-profile/
├── manage-notifications/
```

### 7. Confusing widgets with features

- **Feature** = an action/interaction (add-to-cart, search, toggle-theme)
- **Widget** = a UI composition (header, sidebar, product-card-with-actions)

Widgets **compose** features and entities. Features **contain** business logic.

---

## Migration Strategy

### Incremental adoption (recommended)

1. **Start with `shared/`** — extract UI kit, API client, utils
2. **Create `entities/`** — identify your domain models (user, product, order)
3. **Create `features/`** — extract interactive behaviors from pages
4. **Create `pages/`** — thin page shells that compose widgets/features
5. **Add `widgets/` only when needed** — for reusable composite blocks

### Don't try to restructure everything at once

- Move one feature at a time
- Keep old and new structures working in parallel
- Use ESLint plugin (`eslint-plugin-boundaries` or `steiger`) to enforce rules gradually

---

## Tooling

### Linting

Use [Steiger](https://github.com/feature-sliced/steiger) — the official FSD linter:

```bash
npx steiger src/
```

Or use `eslint-plugin-boundaries` for import rule enforcement.

### ESLint Rule

Enforce the import direction rule:

```json
{
  "rules": {
    "boundaries/element-types": [2, {
      "default": "disallow",
      "rules": [
        { "from": "app", "allow": ["pages", "widgets", "features", "entities", "shared"] },
        { "from": "pages", "allow": ["widgets", "features", "entities", "shared"] },
        { "from": "widgets", "allow": ["features", "entities", "shared"] },
        { "from": "features", "allow": ["entities", "shared"] },
        { "from": "entities", "allow": ["shared"] },
        { "from": "shared", "allow": [] }
      ]
    }]
  }
}
```

## Further Reading

For detailed patterns and edge cases, see:
- `references/fsd-patterns.md` — Composition patterns, testing strategy, state management integration
- `references/project-conventions.md` — Project-specific folder structure, `_apis/`/`_types/`/`_utils/` naming, type conventions (`[Entity]Res`, `IdAndTimeStamps`), 7 coding rules

---

## @ginstudio/shadcn-ui-pro

Component library docs for building forms, dialogs, and list pages. Load with `load-docs.sh` or read directly.

| Topic | File |
|---|---|
| Forms, dialogs, Zod schema, 8-step pattern | `shadcn-ui-pro/form-guide.md` |
| CategorySelector (tree picker) | `shadcn-ui-pro/examples/category-selector.md` |
| All field types in one form (calendar, checkbox, textarea) | `shadcn-ui-pro/examples/event-form.md` |
| BulkActions, DataTableRenderer, Pagination, Toolbar | `shadcn-ui-pro/list-components.md` |
| Full data list feature (10-step guide, selection store, row actions) | `shadcn-ui-pro/examples/list-feature.md` |
| Input, PasswordInput, NumberInput, InputGroup | `shadcn-ui-pro/input-components.md` |
| Typography — H1-H6, Paragraph, Lead, Muted, LongText | `shadcn-ui-pro/typography.md` |
| useDebounceValue, useDebounceCallback | `shadcn-ui-pro/hooks.md` |
| Button, CopyButton | `shadcn-ui-pro/button.md` |
| Badge variants, shapes, sizes | `shadcn-ui-pro/badge.md` |
| AlertDialog (destructive confirmations) | `shadcn-ui-pro/alert-dialog.md` |

Quick load: `bash shadcn-ui-pro/load-docs.sh [form|input|button|badge|typography|hooks|alert-dialog|list|list-feature|category|event|all]`
