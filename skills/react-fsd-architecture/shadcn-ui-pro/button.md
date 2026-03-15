# Button Components

A versatile button component with multiple variants, sizes, states, and a copy-to-clipboard variant.

---

## Installation

```typescript
import { Button } from '@ginstudio/shadcn-ui-pro';
```

---

## Variants

```tsx
<Button variant="default">Default</Button>
<Button variant="destructive">Destructive</Button>
<Button variant="outline">Outline</Button>
<Button variant="secondary">Secondary</Button>
<Button variant="ghost">Ghost</Button>
<Button variant="link">Link</Button>
```

| Variant | Use |
|---|---|
| `default` | Primary actions (Submit, Save, Create) |
| `destructive` | Dangerous actions (Delete, Remove) |
| `outline` | Secondary actions (Cancel, Go Back) |
| `secondary` | Less prominent actions |
| `ghost` | Tertiary actions, minimal visual weight |
| `link` | Text-only, appears as a hyperlink |

---

## Sizes

```tsx
<Button size="sm">Small</Button>
<Button size="default">Default</Button>
<Button size="lg">Large</Button>
<Button size="xl">Extra Large</Button>
<Button size="icon"><Settings /></Button>
```

| Size | Use |
|---|---|
| `sm` | Compact spaces, inline with text |
| `default` | Standard for most use cases |
| `lg` | Prominent CTAs, hero sections |
| `xl` | Extra large for hero sections |
| `icon` | Icon-only buttons (toolbars, actions) |

---

## With Icons

```tsx
import { Mail, Download, Heart } from 'lucide-react';

<Button>
  <Mail /> Send Email
</Button>
<Button>
  Download <Download />
</Button>
<Button size="icon">
  <Heart />
</Button>
```

---

## Loading State

Button is automatically disabled during loading. Use `loadingText` to show progress.

```tsx
<Button isLoading>Please wait...</Button>
<Button isLoading loadingText="Saving...">Save</Button>
```

---

## Disabled

```tsx
<Button disabled>Disabled</Button>
```

---

## Form Usage

**Always specify `type` on buttons inside forms.**

```tsx
<form onSubmit={handleSubmit}>
  <input type="text" name="username" />

  {/* ✅ CORRECT: Submit button */}
  <Button type="submit">Save</Button>

  {/* ✅ CORRECT: Non-submit actions need type="button" */}
  <Button type="button" variant="outline" onClick={addField}>
    Add Field
  </Button>

  {/* ❌ WRONG: Missing type="button" will submit the form! */}
  <Button variant="destructive" onClick={clearData}>
    Clear
  </Button>
</form>
```

| `type` | Behavior |
|---|---|
| `submit` | Submits the form (default browser behavior) |
| `button` | Does NOT submit the form — use for all non-submit actions |
| `reset` | Resets form to initial values |

---

## As Child (Composition)

Apply button styles to custom elements like Next.js `Link`.

```tsx
// Renders as an <a> tag with button styles
<Button asChild>
  <Link href="/dashboard">Go to Dashboard</Link>
</Button>

// Or with a native anchor
<Button asChild variant="outline">
  <a href="/settings">Settings</a>
</Button>
```

---

## CopyButton

Specialized button for copy-to-clipboard with built-in success feedback.

```typescript
import { CopyButton } from '@ginstudio/shadcn-ui-pro';
```

```tsx
<CopyButton value="Hello, World!" />
<CopyButton value="npm install @ginstudio/shadcn-ui-pro" text="Install" />
<CopyButton value="const x = 42;" showIcon={false} text="Copy Code" />

// Icon only mode (no text)
<CopyButton value="code" text="" copiedText="" size="icon" />
```

### CopyButton Imperative API

Use `ref` to programmatically trigger copy from external events.

```tsx
import { useRef } from 'react';
import { CopyButton, type CopyButtonHandle } from '@ginstudio/shadcn-ui-pro';

function CodeViewer({ code }: { code: string }) {
  const copyButtonRef = useRef<CopyButtonHandle>(null);

  const handleDoubleClick = () => {
    copyButtonRef.current?.copy();
  };

  return (
    <div onDoubleClick={handleDoubleClick}>
      <CopyButton
        ref={copyButtonRef}
        value={code}
        text=""
        copiedText=""
        size="icon"
      />
      <pre>{code}</pre>
    </div>
  );
}

// CopyButtonHandle interface:
interface CopyButtonHandle {
  copy: () => Promise<void>;                      // Trigger copy & show success state
  setCopiedState: (copied: boolean) => void;      // Manually set state
}
```

---

## Custom Variants (Factory Pattern)

```typescript
import { createButton, DEFAULT_BUTTON_CONFIG } from '@ginstudio/shadcn-ui-pro';

// Create custom Button with your project's variants
const { Button } = createButton({
  variant: {
    primary: 'bg-blue-600 text-white hover:bg-blue-700',
    secondary: 'bg-gray-200 text-gray-800 hover:bg-gray-300',
    danger: 'bg-red-600 text-white hover:bg-red-700',
  },
  size: {
    sm: 'h-8 px-3 text-xs',
    md: 'h-10 px-4 text-sm',
    lg: 'h-12 px-6 text-base',
  },
  defaultVariant: 'primary',
  defaultSize: 'md',
});

// Extend defaults with spread
const { Button: ExtendedButton } = createButton({
  variant: {
    ...DEFAULT_BUTTON_CONFIG.variant,
    brand: 'bg-brand-500 text-white hover:bg-brand-600',
  },
});
```

---

## Props

```typescript
interface ButtonProps {
  variant?: 'default' | 'destructive' | 'outline' | 'secondary' | 'ghost' | 'link' | 'icon';
  size?: 'default' | 'sm' | 'lg' | 'xl' | 'icon';
  isLoading?: boolean;
  loadingText?: string;
  disabled?: boolean;
  asChild?: boolean;
  // ... extends HTMLButtonAttributes
}
```
