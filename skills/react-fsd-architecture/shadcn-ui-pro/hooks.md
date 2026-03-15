# Hooks

A collection of utility hooks for optimizing performance.

---

## useDebounceValue

Delays the update of a value until a specified time has passed without changes. Perfect for search inputs, form validation, and reducing API calls.

```typescript
import { useDebounceValue } from '@ginstudio/shadcn-ui-pro';
```

```tsx
function SearchComponent() {
  const [searchTerm, setSearchTerm] = useState('');
  const [debouncedSearch] = useDebounceValue(searchTerm, 500);

  useEffect(() => {
    // Only called 500ms after user stops typing
    fetchSearchResults(debouncedSearch);
  }, [debouncedSearch]);

  return (
    <input
      value={searchTerm}
      onChange={(e) => setSearchTerm(e.target.value)}
      placeholder="Search..."
    />
  );
}
```

---

## useDebounceCallback

Returns a debounced version of a callback function. Useful for button clicks, form submissions, and preventing double-actions.

```typescript
import { useDebounceCallback } from '@ginstudio/shadcn-ui-pro';
```

```tsx
function SubmitButton() {
  const handleSubmit = useDebounceCallback((data) => {
    // Only executed 300ms after the last call
    api.submit(data);
  }, 300);

  return (
    <button onClick={() => handleSubmit(formData)}>
      Submit
    </button>
  );
}
```

---

## Props

| Name | Type | Default | Description |
|---|---|---|---|
| `value` | `T` | — | The value to debounce (`useDebounceValue`) |
| `callback` | `(...args) => void` | — | The callback to debounce (`useDebounceCallback`) |
| `delay` | `number` | `500` | Delay in milliseconds before update |
| `options.leading` | `boolean` | `false` | If `true`, updates on the leading edge (immediately) |
| `options.trailing` | `boolean` | `true` | If `true`, updates on the trailing edge (after delay) |
| `options.maxWait` | `number` | — | Maximum time the callback can be delayed before forced execution |

---

## Different Delay Values

```tsx
// Fast debounce (200ms) - for real-time filtering
const [fastValue] = useDebounceValue(input, 200);

// Standard debounce (500ms) - for search/API calls
const [standardValue] = useDebounceValue(input, 500);

// Slow debounce (1000ms) - for expensive operations
const [slowValue] = useDebounceValue(input, 1000);
```
