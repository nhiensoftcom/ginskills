# Anti-Patterns (react-fsd-architecture)

> Consolidated "never do" list across all layers. Each entry explains why.

---

## FSD Layer Violations

```typescript
// ❌ Entity importing from a feature (upward import)
// entities/todo/model/todo.store.ts
import { useAuth } from '@/features/authentication'  // VIOLATION

// ❌ Cross-importing slices on the same layer
import { useSearch } from '@/features/search'  // inside features/filter/ — VIOLATION

// ❌ Deep import into slice internals
import { validateEmail } from '@/features/authentication/lib/validation'
// ✅ Always through public API:
import { validateEmail } from '@/features/authentication'

// ❌ Everything in shared (dumping ground)
shared/hooks/   shared/helpers/   shared/utils/  // too vague — put domain code in entities/features
```

---

## Entity Conventions

```typescript
// ❌ Multiple hooks in one file
// get-list-facebook-vias.api.ts also exports useDeleteFacebookVia — WRONG

// ❌ Payload types in _types/entity.type.ts
// types file is for response shapes only, not mutation payloads

// ❌ import from entity folder root
import { useUpdateFacebookVia } from "@/entities/facebook-via"  // ❌ — no barrel index
// ✅ Direct path:
import { useUpdateFacebookVia } from "@/entities/facebook-via/_apis/update-facebook-via.api"

// ❌ Return raw { mutate, isPending } — always rename to descriptive names
return { mutate, isPending };
// ✅
return { deleteFacebookVia: mutateAsync, isDeletingFacebookVia: isPending };

// ❌ useQuery + enabled: false + refetch() for imperative fetch
const { refetch } = useQuery({ enabled: false });
// ✅ Use manual hook (useState + useCallback)

// ❌ Manually re-declaring fields that already exist in the entity type
export type UpdateFacebookViaPayload = {
  password: string;        // ← duplicated from FacebookViaRes
  new_password: string;    // ← duplicated from FacebookViaRes
};
// ✅ Derive with Pick/Partial:
export type UpdateFacebookViaPayload = { _id: string } & Partial<
  Pick<FacebookViaRes, "password" | "new_password" | "totp_secret" | "emails">
>;
```

---

## Form Patterns

```typescript
// ❌ useEffect to reset form when dialog opens
useEffect(() => {
  if (via && open) form.reset({ password: via.password });
}, [via, open, form]);
// ✅ Async defaultValues — RHF handles it automatically:
const form = useEditViaForm({
  defaultValues: async () => {
    const res = await mutateGetFacebookVia();
    return res ? mapToValues(res) : DEFAULT_VALUES;
  },
});

// ❌ API calls inside Layer 2 (form component)
function EditViaForm() {
  const { mutate } = useMutation(...); // ← belongs in Layer 3
}

// ❌ z.input<> when schema has no .transform()
type Values = z.input<typeof schema>; // ← use z.infer<>

// ❌ Submit button inside the form element
<form><button type="submit">Save</button></form>
// ✅ Button in DialogFooter linked via form={FORM_ID}

// ❌ Hardcoded default values inline in useForm call (not exported)
useForm({ defaultValues: { password: "", emails: [] } });
// ✅ Export DEFAULT_VALUES constant so Layer 3 can use as fallback
```

---

## List / Table Patterns

```typescript
// ❌ Dialog store at parent feature folder level
// features/facebook-auto-post/_store/via-dialog.store.ts  ← WRONG
// ✅ Store inside the slice that owns it:
// features/facebook-auto-post/list-facebook-vias/_store/via-dialog.store.ts

// ❌ Boolean per-dialog state — doesn't scale
const [isEditOpen, setIsEditOpen] = useState(false);
const [isDeleteOpen, setIsDeleteOpen] = useState(false);
// ✅ Enum-based dialog store with ViaDialogType enum

// ❌ Row selection state in global Zustand store
// ✅ Local useState<RowSelectionState>({}) in the feature root

// ❌ Anonymous arrow function as ColumnDef cell (can't use hooks)
cell: ({ row }) => {
  const { deleteFacebookVia } = useDeleteFacebookVia(); // ← breaks rules of hooks
}
// ✅ Named component: function RowActions({ via }) { const ... }

// ❌ Selecting multiple Zustand values without useShallow
const { open, currentRow } = useViaDialogStore(); // re-renders on any change
// ✅ useViaDialogStore(useShallow((s) => ({ open: s.open, currentRow: s.currentRow })))

// ❌ Missing data-state on table rows — selection highlight doesn't appear
<TableRow key={row.id}>
// ✅ <TableRow data-state={row.getIsSelected() && "selected"}>
```

---

## NestJS / Backend (DTO Patterns)

```typescript
// ❌ Manually re-declaring fields from a parent DTO
export class UpdateViaDto {
  @IsString() password?: string;
  @IsString() new_password?: string;
  @IsString() totp_secret?: string;
  // ← duplicating validation decorators already in ImportViaItemDto
}
// ✅ Derive with PartialType/OmitType:
export class UpdateViaDto extends PartialType(
  OmitType(ImportViaItemDto, ['uid'] as const)
) {}
```

---

## General

```typescript
// ❌ console.log anywhere in the codebase
console.log("debug");
// ✅ Logger.info/error/warn/debug (desktop) or Pino logger (backend)

// ❌ Hardcoded color values
style={{ color: "#ff0000" }}
// ✅ CSS variable tokens: className="text-destructive"

// ❌ Creating index.ts barrel in entity folder
// entities/facebook-via/index.ts  ← don't create this
// ✅ Import directly from specific file paths
```
