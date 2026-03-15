# AlertDialog

A modal dialog that requires user action before dismissal. Unlike `Dialog`, users cannot close it by clicking the overlay or pressing Escape.

---

## Installation

```typescript
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@ginstudio/shadcn-ui-pro';
```

---

## Basic Usage

```tsx
<AlertDialog>
  <AlertDialogTrigger asChild>
    <Button variant="destructive">Delete Account</Button>
  </AlertDialogTrigger>
  <AlertDialogContent>
    <AlertDialogHeader>
      <AlertDialogTitle>Are you absolutely sure?</AlertDialogTitle>
      <AlertDialogDescription>
        This action cannot be undone. This will permanently delete your
        account and remove your data from our servers.
      </AlertDialogDescription>
    </AlertDialogHeader>
    <AlertDialogFooter>
      <AlertDialogCancel>Cancel</AlertDialogCancel>
      <AlertDialogAction>Continue</AlertDialogAction>
    </AlertDialogFooter>
  </AlertDialogContent>
</AlertDialog>
```

---

## AlertDialog vs Dialog

| Use `AlertDialog` when | Use `Dialog` when |
|---|---|
| Destructive actions (delete, remove) | Forms and editing |
| User must acknowledge before proceeding | Information display |
| Irreversible operations | Optional interactions (user can dismiss) |
| User cannot dismiss without choosing | Non-critical content viewing |

---

## Controlled Usage

```tsx
const [open, setOpen] = useState(false);

<AlertDialog open={open} onOpenChange={setOpen}>
  <AlertDialogTrigger asChild>
    <Button>Delete Item</Button>
  </AlertDialogTrigger>
  <AlertDialogContent>
    <AlertDialogHeader>
      <AlertDialogTitle>Confirm Deletion</AlertDialogTitle>
      <AlertDialogDescription>
        This will permanently delete the item.
      </AlertDialogDescription>
    </AlertDialogHeader>
    <AlertDialogFooter>
      <AlertDialogCancel>Cancel</AlertDialogCancel>
      <AlertDialogAction onClick={handleDelete}>
        Delete
      </AlertDialogAction>
    </AlertDialogFooter>
  </AlertDialogContent>
</AlertDialog>
```

---

## With Async Actions

```tsx
const [open, setOpen] = useState(false);
const [loading, setLoading] = useState(false);

const handleDelete = async () => {
  setLoading(true);
  try {
    await deleteItem(itemId);
    setOpen(false);
    toast.success('Item deleted');
  } catch (error) {
    toast.error('Failed to delete');
  } finally {
    setLoading(false);
  }
};

<AlertDialog open={open} onOpenChange={setOpen}>
  <AlertDialogContent>
    <AlertDialogHeader>
      <AlertDialogTitle>Delete Item?</AlertDialogTitle>
      <AlertDialogDescription>
        This action cannot be undone.
      </AlertDialogDescription>
    </AlertDialogHeader>
    <AlertDialogFooter>
      <AlertDialogCancel disabled={loading}>Cancel</AlertDialogCancel>
      <AlertDialogAction onClick={handleDelete} disabled={loading}>
        {loading ? 'Deleting...' : 'Delete'}
      </AlertDialogAction>
    </AlertDialogFooter>
  </AlertDialogContent>
</AlertDialog>
```

---

## Props

```typescript
// AlertDialog (Root)
interface AlertDialogProps {
  open?: boolean;
  defaultOpen?: boolean;
  onOpenChange?: (open: boolean) => void;
}

// AlertDialogTrigger
interface AlertDialogTriggerProps {
  asChild?: boolean;
}

// AlertDialogContent
interface AlertDialogContentProps {
  className?: string;
  children: React.ReactNode;
}

// AlertDialogAction
interface AlertDialogActionProps {
  className?: string;
  children: React.ReactNode;
  // Uses default button variant styles
}

// AlertDialogCancel
interface AlertDialogCancelProps {
  className?: string;
  children: React.ReactNode;
  // Uses outline button variant styles
}
```

---

## Accessibility

- Focus is trapped within the dialog
- Pressing Escape does NOT close (unlike `Dialog`)
- Clicking outside does NOT dismiss
- `role="alertdialog"` — proper ARIA role announced by screen readers
- Title and description are announced automatically

## Best Practices

- Use specific action verbs: **Delete**, **Discard**, **Remove** — not generic **OK**
- Use `variant="destructive"` on `AlertDialogAction` for dangerous operations
- Always show loading state during async operations and disable buttons
- Keep the description concise — explain consequences, not mechanics
