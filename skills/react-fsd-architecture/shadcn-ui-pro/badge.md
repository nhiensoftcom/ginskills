# Badge

Displays a small label or status indicator with support for sizes, shapes, icons, and color variants.

---

## Installation

```typescript
import { Badge } from '@ginstudio/shadcn-ui-pro';
```

---

## Variants

```tsx
<Badge variant="default">Default</Badge>
<Badge variant="secondary">Secondary</Badge>
<Badge variant="destructive">Destructive</Badge>
<Badge variant="outline">Outline</Badge>
<Badge variant="success">Success</Badge>
<Badge variant="warning">Warning</Badge>
<Badge variant="info">Info</Badge>
```

| Variant | Use |
|---|---|
| `default` | Primary badge style |
| `secondary` | Less prominent badge |
| `destructive` | Error or danger states |
| `outline` | Minimal, bordered style |
| `success` | Success or completed states |
| `warning` | Warning or pending states |
| `info` | Informational states |

---

## Sizes

Three size options: `sm` (20px), `default` (24px), and `lg` (28px).

```tsx
<Badge size="sm">Small</Badge>
<Badge size="default">Default</Badge>
<Badge size="lg">Large</Badge>
```

---

## Shapes

```tsx
<Badge shape="default">Default</Badge>
<Badge shape="pill">Pill</Badge>
<Badge shape="circle">5</Badge>
```

| Shape | Use |
|---|---|
| `default` | Rounded corners (`rounded-md`) |
| `pill` | Fully rounded pill-style |
| `circle` | Perfect circle for notification counters |

---

## With Icons

Icons are automatically sized based on the badge size.

```tsx
import { Check, ArrowRight, Loader2 } from 'lucide-react';

<Badge leftIcon={<Check />}>Verified</Badge>
<Badge rightIcon={<ArrowRight />}>Next</Badge>
<Badge leftIcon={<Loader2 className="animate-spin" />}>Loading</Badge>
```

---

## Notification Counters

```tsx
<Badge shape="circle" variant="destructive">5</Badge>
<Badge shape="circle" size="lg">99</Badge>
<Badge shape="circle" variant="success">
  <Check className="size-3" />
</Badge>
```

---

## Composition with asChild

```tsx
<Badge asChild>
  <a href="/docs">Documentation</a>
</Badge>

<Badge asChild variant="outline">
  <Link href="/pricing">Learn More</Link>
</Badge>
```

---

## Custom Variants (Factory Pattern)

### Full customization

```typescript
import { createBadge } from '@ginstudio/shadcn-ui-pro';

const { Badge } = createBadge({
  variant: {
    default: 'border-transparent bg-brand-500 text-white shadow hover:bg-brand-600',
    premium: 'border-transparent bg-gradient-to-r from-amber-500 to-orange-500 text-white shadow',
    ghost: 'border-transparent bg-transparent text-foreground hover:bg-muted',
  },
  size: {
    xs: 'h-4 px-1 text-[9px] [&>svg]:size-2.5',
    sm: 'h-5 px-1.5 text-[10px] [&>svg]:size-3',
    default: 'h-6 px-2.5 text-xs [&>svg]:size-3.5',
    lg: 'h-7 px-3 text-sm [&>svg]:size-4',
    xl: 'h-8 px-4 text-base [&>svg]:size-5',
  },
  defaultVariant: 'default',
  defaultSize: 'default',
});
```

### Extending default variants

```typescript
import { createBadge, DEFAULT_BADGE_CONFIG } from '@ginstudio/shadcn-ui-pro';

const { Badge } = createBadge({
  variant: {
    ...DEFAULT_BADGE_CONFIG.variant,
    brand: 'border-transparent bg-brand-500 text-white shadow hover:bg-brand-600',
    premium: 'border-transparent bg-gradient-to-r from-purple-500 to-pink-500 text-white',
  },
});
```

### Custom variants only (createBadgeVariants)

```typescript
import { createBadgeVariants, cn } from '@ginstudio/shadcn-ui-pro';

const customBadgeVariants = createBadgeVariants({
  variant: {
    active: 'bg-emerald-500 text-white animate-pulse',
    inactive: 'bg-gray-300 text-gray-600',
  },
});

<span className={cn(customBadgeVariants({ variant: 'active' }))}>
  Online
</span>
```

---

## Props

```typescript
interface BadgeProps {
  variant?: 'default' | 'secondary' | 'destructive' | 'outline' | 'success' | 'warning' | 'info';
  size?: 'sm' | 'default' | 'lg';
  shape?: 'default' | 'pill' | 'circle';
  asChild?: boolean;
  leftIcon?: React.ReactNode;
  rightIcon?: React.ReactNode;
  children?: React.ReactNode;
  className?: string;
}

interface BadgeVariantConfig {
  base?: string;
  variant?: Record<string, string>;
  size?: Record<string, string>;
  shape?: Record<string, string>;
  compoundVariants?: Array<{ shape?: string; size?: string; class: string }>;
  defaultVariant?: string;
  defaultSize?: string;
  defaultShape?: string;
}
```
