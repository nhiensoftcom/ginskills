# Typography Components

A collection of typography components for consistent text styling: headings, paragraphs, and specialized text components.

---

## Installation

```typescript
import {
  H1, H2, H3, H4, H5, H6,
  Paragraph, P,
  Lead, Muted, Large, Small,
  Blockquote, Code, LongText
} from '@ginstudio/shadcn-ui-pro';
```

---

## Headings

```tsx
<H1>Page Title</H1>
<H2>Section Title</H2>
<H3>Subsection</H3>
<H4>Card Title</H4>
<H5>Small Title</H5>
<H6>Label</H6>
```

| Component | Use |
|---|---|
| `H1` | Page title — only one per page |
| `H2` | Major sections |
| `H3` | Subsections |
| `H4` / `H5` / `H6` | Card titles, labels, fine-grained hierarchy |

---

## Paragraph

```tsx
<Paragraph>Default paragraph text.</Paragraph>
<Paragraph size="sm">Small paragraph.</Paragraph>
<Paragraph size="lg">Large paragraph.</Paragraph>
<Paragraph variant="muted">Muted text for secondary content.</Paragraph>

// P is an alias
<P>Using the P alias.</P>
```

| Prop | Options |
|---|---|
| `size` | `xs` \| `sm` \| `md` (default) \| `lg` |
| `variant` | `default` \| `muted` |

---

## Lead & Muted

```tsx
<Lead>A lead paragraph for prominent introductory text.</Lead>
<Muted>Muted text for secondary information.</Muted>
```

| Component | Use |
|---|---|
| `Lead` | Prominent introductory text, larger size |
| `Muted` | Secondary information, reduced opacity |

---

## Large & Small

```tsx
<Large>Large text for emphasis</Large>
<Small>Small text for fine print</Small>
```

---

## Blockquote

```tsx
<Blockquote>
  "Design is not just what it looks like and feels like.
  Design is how it works." — Steve Jobs
</Blockquote>
```

---

## Inline Code

```tsx
<p>Run <Code>npm install</Code> to install dependencies.</p>
<p>Use the <Code>useState</Code> hook for local state.</p>
```

---

## LongText (Auto-Truncate)

Automatically truncates text and shows full content in tooltip (desktop) or popover (mobile). Useful for table cells and card descriptions.

```tsx
<div className="w-48">
  <LongText>
    This is a very long text that will be truncated automatically
  </LongText>
</div>
```

---

## Custom Variants (Factory Pattern)

```typescript
import { createTypography, DEFAULT_TYPOGRAPHY_CONFIG } from '@ginstudio/shadcn-ui-pro';

// Create custom typography with your project's styles
const { H1, H2, H3, H4, H5, H6, P, Blockquote, Code, Large, Small, Lead, Muted } = createTypography({
  h1: 'text-4xl font-black tracking-tighter',
  h2: 'text-3xl font-bold border-b-2 border-brand-500 pb-4',
  h3: 'text-2xl font-semibold text-brand-600',
  p: 'text-base leading-relaxed text-gray-700',
  muted: 'text-sm text-gray-500 italic',
});

// Extend only specific elements
const { H1: BrandH1, H2: BrandH2 } = createTypography({
  ...DEFAULT_TYPOGRAPHY_CONFIG,
  h1: 'text-5xl font-extrabold bg-gradient-to-r from-brand-500 to-brand-700 bg-clip-text text-transparent',
});

export { H1, H2, H3, H4, H5, H6, P, Blockquote, Code, Large, Small, Lead, Muted };
```

---

## Props

```typescript
// Paragraph / P
interface ParagraphProps {
  size?: 'xs' | 'sm' | 'md' | 'lg';
  variant?: 'default' | 'muted';
  children: React.ReactNode;
  className?: string;
}

// LongText
interface LongTextProps {
  children: string;
  maxLines?: number;
  className?: string;
}

// Headings, Lead, Muted, Large, Small, Blockquote, Code
// All extend React.HTMLAttributes with children + className
```

---

## Best Practices

```tsx
// ✅ CORRECT - Semantic hierarchy
<H1>Page Title</H1>
<H2>First Section</H2>
<H3>Subsection</H3>

// ❌ WRONG - Skipped H2
<H1>Page Title</H1>
<H3>Subsection</H3>
```

- Use only one `H1` per page (page title)
- Don't skip heading levels (`H1` → `H3` without `H2`)
- Use `Paragraph` for body text instead of raw `<p>` tags
- Use `Lead` for page introductions, `Muted` for captions
