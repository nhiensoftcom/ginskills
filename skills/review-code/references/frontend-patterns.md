# Frontend Patterns — Next.js Review Reference

Quick reference for reviewing Next.js frontend code.

## Table of Contents
1. [App Router Structure](#app-router-structure)
2. [Component Patterns](#component-patterns)
3. [State Management](#state-management)
4. [Data Fetching](#data-fetching)
5. [Form Handling](#form-handling)
6. [Styling](#styling)

---

## App Router Structure

```
src/app/
├── api/                 # Next.js API routes (server functions)
├── (public)/            # Public pages (landing, marketing)
├── (dashboard)/         # Authenticated pages
├── layout.tsx           # Root layout
└── page.tsx             # Home page
```

Review checklist:
- Route groups should have their own layouts
- Authenticated routes should check session in layout/middleware
- API routes should validate inputs and handle errors

## Component Patterns

```
src/
├── shared/components/    # Reusable UI (buttons, modals, cards)
├── features/             # Feature-specific components
├── components/           # Global components (navbar, sidebar)
└── entities/             # Domain model components
```

Review checklist:
- Use `"use client"` only where React hooks or browser APIs are needed
- Prefer server components for data fetching and static content
- Keep components focused — one component, one responsibility (SRP). If a component does too many things, split it
- Props should be typed with TypeScript interfaces, not `any`
- Components should be <150 lines of JSX. Split larger ones into sub-components
- Extract reusable logic into custom hooks (DRY) — if 2+ components share the same state/effect pattern, make a hook
- Prefer composition over prop drilling — use context, Zustand, or render props for deeply shared state
- Avoid `useEffect` for derived state — compute values directly or use `useMemo`
- Name components and hooks descriptively: `useItemFilters` not `useData`, `OrderSummaryCard` not `Card2`

## State Management

**Zustand** for client-side state:
```typescript
import { create } from 'zustand';

interface ItemStore {
  items: Item[];
  addItem: (item: Item) => void;
}

export const useItemStore = create<ItemStore>((set) => ({
  items: [],
  addItem: (item) => set((state) => ({ items: [...state.items, item] })),
}));
```

Review checklist:
- Stores should be small and focused (one per domain) — SRP for state (ISP)
- Avoid god-stores that manage everything — split by feature/concern
- Use selectors to prevent unnecessary rerenders
- Don't duplicate server state in Zustand — that's what React Query is for (single source of truth / DRY)
- Keep store actions simple — complex business logic belongs in services, not stores
- Avoid derived state in stores — compute it in components or with selectors (KISS)

## Data Fetching

**React Query** for server state:
```typescript
import { useQuery } from '@tanstack/react-query';
import { itemService } from '@/shared/services';

function useItems() {
  return useQuery({
    queryKey: ['items'],
    queryFn: () => itemService.getAll(),
  });
}
```

Review checklist:
- Query keys should follow a consistent namespace: `['items']`, `['items', id]`, `['items', { filter }]` — use query key factories (DRY)
- API calls should go through the service layer, not directly in components (separation of concerns)
- Handle loading, error, and empty states — never show a blank screen
- Use `useMutation` for writes, not manual state updates
- Invalidate relevant queries after mutations
- Extract query hooks into dedicated files (e.g., `useItems.ts`) — don't inline `useQuery` calls throughout components (DRY)
- Set appropriate `staleTime` / `gcTime` — don't refetch data that rarely changes on every mount (KISS)

## Form Handling

**React Hook Form + Zod**:
```typescript
const schema = z.object({
  name: z.string().min(1, 'Required'),
  category: z.enum(['tops', 'bottoms', 'shoes']),
});

type FormData = z.infer<typeof schema>;

function ItemForm() {
  const { register, handleSubmit } = useForm<FormData>({
    resolver: zodResolver(schema),
  });
}
```

Review checklist:
- Use Zod schemas for validation (matches backend DTOs)
- Derive TypeScript types from Zod schemas with `z.infer`
- Handle form submission errors and show to user
- Disable submit button during loading

## Styling

**Tailwind CSS + shadcn/ui (Radix)**:

Review checklist:
- Use Tailwind utility classes, not custom CSS (unless truly necessary)
- shadcn/ui components should be used for standard UI elements — don't reinvent existing components (DRY)
- Responsive design: mobile-first (`sm:`, `md:`, `lg:` breakpoints)
- Dark mode: use `dark:` variants where appropriate
- Avoid inline styles
- Extract repeated class combinations into reusable components, not utility strings (KISS)
- Use design tokens / CSS variables for colors, spacing — don't hardcode hex values throughout (DRY, maintainability)
