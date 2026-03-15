# Input Components

A collection of input components: basic inputs, password inputs, number inputs with formatting, and input groups with addons.

---

## Installation

```typescript
import { Input, PasswordInput, NumberInput, InputGroup } from '@ginstudio/shadcn-ui-pro';
```

---

## Basic Input

Standard input supporting all native HTML input types.

```tsx
<Input type="text" placeholder="Enter your name" />
<Input type="email" placeholder="Enter your email" />
<Input type="number" placeholder="Enter amount" />
```

### Input States

```tsx
<Input placeholder="Disabled input" disabled />
<Input value="Readonly value" readOnly />
<Input placeholder="With default" defaultValue="Hello World" />
```

| State | When to use |
|---|---|
| `disabled` | Prevent interaction while maintaining visibility |
| `readOnly` | Display values that shouldn't be modified |
| `defaultValue` | Set an initial uncontrolled value |

---

## PasswordInput

Password input with built-in show/hide toggle.

```tsx
<PasswordInput placeholder="Enter your password" />
<PasswordInput placeholder="Disabled" disabled />
```

---

## NumberInput

Enhanced numeric input with increment/decrement buttons and thousand separator formatting.

```tsx
// Basic with buttons
<NumberInput value={1000} onChange={setValue} />

// Without buttons
<NumberInput value={1000} showButtons={false} />

// With constraints
<NumberInput min={0} max={100} step={5} />

// Different separators
<NumberInput thousandSeparator="." /> // 1.000.000
<NumberInput thousandSeparator="," /> // 1,000,000
<NumberInput thousandSeparator="none" /> // 1000000
```

| Prop | Description |
|---|---|
| `showButtons` | Display increment/decrement controls (default: `true`) |
| `min` / `max` / `step` | Value constraints and increment size |
| `thousandSeparator` | Format large numbers: `','`, `'.'`, or `'none'` |

---

## InputGroup — Inline Addons

Enhance inputs with icons, text, or buttons at the start or end.

```typescript
import {
  InputGroup,
  InputGroupAddon,
  InputGroupInput,
  InputGroupText
} from '@ginstudio/shadcn-ui-pro';
```

```tsx
// Icon at start
<InputGroup>
  <InputGroupAddon align="inline-start">
    <Mail />
  </InputGroupAddon>
  <InputGroupInput placeholder="Email address" />
</InputGroup>

// Text at end
<InputGroup>
  <InputGroupInput type="number" placeholder="Price" />
  <InputGroupAddon align="inline-end">
    <InputGroupText>.00</InputGroupText>
  </InputGroupAddon>
</InputGroup>
```

| `align` value | Position |
|---|---|
| `inline-start` | Beginning of input (icons, prefixes) |
| `inline-end` | End of input (suffixes, units) |

---

## InputGroup — With Buttons

```typescript
import {
  InputGroup,
  InputGroupAddon,
  InputGroupButton,
  InputGroupInput
} from '@ginstudio/shadcn-ui-pro';
```

```tsx
<InputGroup>
  <InputGroupAddon align="inline-start">
    <Search />
  </InputGroupAddon>
  <InputGroupInput placeholder="Search..." />
  <InputGroupAddon align="inline-end">
    <InputGroupButton>Search</InputGroupButton>
  </InputGroupAddon>
</InputGroup>
```

---

## InputGroup — Multiple Addons

```tsx
<InputGroup>
  <InputGroupAddon align="inline-start">
    <InputGroupText>https://</InputGroupText>
  </InputGroupAddon>
  <InputGroupInput placeholder="example.com" />
  <InputGroupAddon align="inline-end">
    <InputGroupText>/path</InputGroupText>
  </InputGroupAddon>
</InputGroup>

<InputGroup>
  <InputGroupAddon align="inline-start">
    <Phone />
    <InputGroupText>+84</InputGroupText>
  </InputGroupAddon>
  <InputGroupInput placeholder="Phone number" />
</InputGroup>
```

---

## Custom Variants (Factory Pattern)

Use `createInput()` to create an `Input` with custom variant definitions:

```typescript
import { createInput, DEFAULT_INPUT_CONFIG } from '@ginstudio/shadcn-ui-pro';

// Create custom Input with your project's variants
const { Input } = createInput({
  inputSize: {
    sm: 'h-8 px-2 py-1 text-xs',
    md: 'h-10 px-3 py-2 text-sm',
    lg: 'h-12 px-4 py-3 text-base',
  },
  inputVariant: {
    default: '',
    error: 'border-red-500 focus-visible:ring-red-500',
    warning: 'border-yellow-500 focus-visible:ring-yellow-500',
  },
  defaultInputSize: 'md',
  defaultInputVariant: 'default',
});

// Extend defaults with spread
const { Input: ExtendedInput } = createInput({
  inputVariant: {
    ...DEFAULT_INPUT_CONFIG.inputVariant,
    info: 'border-blue-500 focus-visible:ring-blue-500',
  },
});
```

---

## Props

```typescript
interface InputProps extends Omit<React.ComponentProps<'input'>, 'size'> {
  type?: 'text' | 'email' | 'password' | 'number' | 'tel' | 'url' | 'search' | 'date';
  placeholder?: string;
  disabled?: boolean;
  readOnly?: boolean;
  value?: string | number;
  defaultValue?: string | number;
  onChange?: (e: ChangeEvent<HTMLInputElement>) => void;
  className?: string;
}

interface PasswordInputProps extends Omit<InputProps, 'type'> {}

interface NumberInputProps {
  value?: number;
  defaultValue?: number;
  onChange?: (value: number | undefined) => void;
  min?: number;
  max?: number;
  step?: number;
  showButtons?: boolean;
  thousandSeparator?: ',' | '.' | 'none';
  disabled?: boolean;
  placeholder?: string;
  className?: string;
}

interface InputGroupProps {
  children: React.ReactNode;
  className?: string;
}

interface InputGroupAddonProps {
  align: 'inline-start' | 'inline-end';
  children: React.ReactNode;
}
```

---

## Best Practices

```tsx
// ✅ CORRECT - Controlled with label
<div>
  <label htmlFor="email">Email</label>
  <Input
    id="email"
    type="email"
    value={email}
    onChange={(e) => setEmail(e.target.value)}
    placeholder="you@example.com"
  />
</div>

// ❌ WRONG - No label, uncontrolled
<Input type="email" placeholder="Email" />
```

- Always provide meaningful placeholder text or labels
- Use appropriate `type` for better mobile keyboard support
- Prefer controlled inputs (`value` + `onChange`) for form state management
- Use `InputGroup` for contextual enhancements, not as a replacement for labels
- Avoid `inline-start` addons for required form fields — use proper labels instead
