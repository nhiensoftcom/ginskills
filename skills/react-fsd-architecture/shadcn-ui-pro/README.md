# @ginstudio/shadcn-ui-pro — Loading Guide

This folder contains docs for building UI with the `@ginstudio/shadcn-ui-pro` component library inside a Feature-Sliced Design project.

---

## When to Load Each File

| Task / Keyword | File to Read |
|---|---|
| Build a form, form hook, Zod schema, dialog, create/edit, dialog store, dialog registry | `shadcn-ui-pro/form-guide.md` |
| CategorySelector, tree selector, category picker, hierarchical select | `shadcn-ui-pro/examples/category-selector.md` |
| Full form example, all field types, checkbox, calendar, date picker, nested fields | `shadcn-ui-pro/examples/event-form.md` |
| Installation, import paths, what components exist | `shadcn-ui-pro/form-guide.md` (Installation section) |
| BulkActions, DataTableRenderer, Pagination, Toolbar, list components | `shadcn-ui-pro/list-components.md` |
| Data list feature, table feature, list page, selection store, bulk delete, row actions | `shadcn-ui-pro/examples/list-feature.md` |
| Input, PasswordInput, NumberInput, InputGroup, input addon, input group | `shadcn-ui-pro/input-components.md` |
| Typography, H1-H6, Paragraph, Lead, Muted, Large, Small, Blockquote, Code, LongText | `shadcn-ui-pro/typography.md` |
| useDebounceValue, useDebounceCallback, debounce hooks | `shadcn-ui-pro/hooks.md` |
| Button, CopyButton, button variants, sizes, loading, asChild | `shadcn-ui-pro/button.md` |
| Badge, badge variants, shapes, sizes, notification counter | `shadcn-ui-pro/badge.md` |
| AlertDialog, alert dialog, confirm destructive action | `shadcn-ui-pro/alert-dialog.md` |

---

## AI Instructions

When the user asks about **forms**, **dialogs**, or **shadcn-ui-pro** components:

1. Read `shadcn-ui-pro/form-guide.md` first — it covers the full 8-step pattern.
2. If the task involves a **category tree / hierarchical selector**, also read `shadcn-ui-pro/examples/category-selector.md`.
3. If the task involves **multiple field types in one form** (date, select, checkbox, textarea, nested), also read `shadcn-ui-pro/examples/event-form.md`.

Never skip steps — the 8-step form pattern in `form-guide.md` must be followed in order.

---

## File Index

```
shadcn-ui-pro/
├── README.md                        ← you are here (loading guide)
├── form-guide.md                    ← core form guide: 8-step pattern + best practices
├── list-components.md               ← BulkActions, DataTableRenderer, Pagination, Toolbar
├── input-components.md              ← Input, PasswordInput, NumberInput, InputGroup
├── typography.md                    ← H1-H6, Paragraph, Lead, Muted, Large, Small, Blockquote, Code, LongText
├── hooks.md                         ← useDebounceValue, useDebounceCallback
├── button.md                        ← Button, CopyButton, variants, loading, asChild
├── badge.md                         ← Badge variants, shapes, sizes, factory pattern
├── alert-dialog.md                  ← AlertDialog for destructive confirmations
└── examples/
    ├── category-selector.md         ← CategorySelector: tree component, types, API hook
    ├── event-form.md                ← EventForm: all field types combined (calendar, category, checkbox, textarea)
    └── list-feature.md              ← Data list feature: 10-step guide, dialog registry, selection store, bulk delete
```

---

## Quick Import Reference

```typescript
// Field wrappers
import { Field, FieldGroup, FieldLabel, FieldError, FieldDescription } from '@ginstudio/shadcn-ui-pro';

// Inputs
import { Input } from '@ginstudio/shadcn-ui-pro';
import { Textarea } from '@ginstudio/shadcn-ui-pro';
import { Checkbox } from '@ginstudio/shadcn-ui-pro';

// Select
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@ginstudio/shadcn-ui-pro';

// Date picker
import { Popover, PopoverContent, PopoverTrigger } from '@ginstudio/shadcn-ui-pro';
import { Calendar } from '@ginstudio/shadcn-ui-pro';
import { Button } from '@ginstudio/shadcn-ui-pro';

// Dialog
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from '@ginstudio/shadcn-ui-pro';

// Scroll / layout
import { ScrollArea, Badge } from '@ginstudio/shadcn-ui-pro';
```
