---
name: react-fsd-architecture
description: |
  **Feature-Sliced Design (FSD) Architecture**: Architectural methodology for organizing frontend projects by business features — layers, slices, segments, public APIs, and import rules.
  - MANDATORY TRIGGERS: feature sliced design, FSD, feature slice, project structure, folder structure, architecture, organize code, layers slices segments, app structure, frontend architecture, scalable structure, code organization, module structure, refactor structure, react hook form, form pattern, edit dialog, manual api, useGetManual, defaultValues async, tanstack table, list, bulk actions, dialog store, row selection, column definition, anti-pattern
  - Use this skill whenever the user is setting up, refactoring, or discussing frontend project architecture and folder structure. Also trigger when deciding where to place new code, resolving circular dependencies, or organizing a React/React Native/Next.js project.
---

# Feature-Sliced Design (FSD) — react-fsd-architecture

## How to load docs

Load only what you need — saves tokens. Use the routing script:

```
!`bash ginskills/skills/react-fsd-architecture/scripts/load-docs.sh <topic>`
```

| Topic arg | What it covers |
|-----------|---------------|
| `core` | FSD layers, slices, segments, import rules, public API |
| `entity` | Entity folder structure, API hook naming, payload types, manual hooks, QK_ constants |
| `form` | 3-layer RHF pattern, Zod schemas, async defaultValues, useFieldArray |
| `list` | TanStack Table v8, dialog store, bulk actions, column defs, row selection |
| `anti` | Consolidated anti-patterns — all "never do" rules |
| `all` | Load everything |

**Examples:**

```bash
# Need to know where to put a new API hook?
bash ginskills/skills/react-fsd-architecture/scripts/load-docs.sh entity

# Building a new edit dialog with form?
bash ginskills/skills/react-fsd-architecture/scripts/load-docs.sh form

# Setting up a new list page with TanStack Table?
bash ginskills/skills/react-fsd-architecture/scripts/load-docs.sh list

# Checking FSD import rules?
bash ginskills/skills/react-fsd-architecture/scripts/load-docs.sh core
```

---

## Project-Specific Overrides (scrape-video)

This project **deviates** from standard FSD in a few ways — always prefer these:

1. **No barrel `index.ts` for entities** — import directly from the file:
   ```typescript
   // ✅
   import { useUpdateFacebookVia } from "@/entities/facebook-via/_apis/update-facebook-via.api";
   // ❌ No index.ts barrel
   ```

2. **Underscore-prefixed segments** (`_apis`, `_types`, `_utils`, `_ui`, `_store`) instead of plain `api`, `model`

3. **One file per API operation** — `get-list-X.api.ts`, `add-X.api.ts`, `update-X.api.ts` (never combine)

4. **Payload types co-located** with the hook file (never in `_types/`)

5. **Manual imperative hooks** for form init — never `useQuery + enabled: false + refetch()`

6. **Enum dialog store** per feature list — never boolean `isOpen` per dialog
