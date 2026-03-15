# Form Architecture (scrape-video project)

> 3-layer React Hook Form pattern with Zod, async defaultValues, and manual API init.

---

## The 3-Layer Rule

Every form is split into exactly 3 layers. No exceptions.

```
_ui/{feature}-form/
├── use-{feature}-form.ts   ← Layer 1: Zod schema + useForm hook
└── index.tsx               ← Layer 2: Dumb form component (no API calls)
{container}.tsx             ← Layer 3: Container (mutations + submit + dialog)
```

---

## Layer 1 — Schema + Hook (`use-{feature}-form.ts`)

```typescript
import { z } from "zod";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";

const editViaSchema = z.object({
  password: z.string().min(1, "Required"),
  new_password: z.string(),
  totp_secret: z.string(),
  emails: z.array(
    z.object({ email: z.string().email(), password: z.string() })
  ),
});

export type EditViaFormValues = z.infer<typeof editViaSchema>;

export const EDIT_VIA_FORM_ID = "edit-via-form";

export const DEFAULT_EDIT_VIA_FORM_VALUES: EditViaFormValues = {
  password: "",
  new_password: "",
  totp_secret: "",
  emails: [],
};

// Accept defaultValues as a value OR async function
// (for edit forms that need to fetch fresh data from the server)
export function useEditViaForm({
  defaultValues,
}: {
  defaultValues: EditViaFormValues | (() => Promise<EditViaFormValues>);
}) {
  return useForm<EditViaFormValues>({
    resolver: zodResolver(editViaSchema),
    defaultValues,
  });
}
```

**Rules:**
- Always export `FORM_ID`, `DEFAULT_VALUES`, and the hook
- Use `z.infer<typeof schema>` for the type — never manually type form values
- Accept `defaultValues: T | (() => Promise<T>)` — RHF natively supports async init

---

## Layer 2 — Form Component (`index.tsx`)

```typescript
import { Controller, UseFormReturn } from "react-hook-form";
import { Field, FieldError, FieldGroup, FieldLabel } from "@/shared/components/shadcn/field";
import { Input } from "@/shared/components/shadcn/input";
import { EDIT_VIA_FORM_ID, EditViaFormValues } from "./use-edit-via-form";

export default function EditViaForm({
  formId = EDIT_VIA_FORM_ID,
  form,
  onSubmit,
}: {
  formId?: string;
  form: UseFormReturn<EditViaFormValues>;
  onSubmit: (data: EditViaFormValues) => void;
}) {
  return (
    <form id={formId} onSubmit={form.handleSubmit(onSubmit)}>
      <Controller
        name="password"
        control={form.control}
        render={({ field, fieldState }) => (
          <Field data-invalid={fieldState.invalid}>
            <FieldLabel>Password</FieldLabel>
            <Input type="password" {...field} />
            {fieldState.invalid && <FieldError errors={[fieldState.error]} />}
          </Field>
        )}
      />
    </form>
  );
}
```

**Rules:**
- Never call API or useMutation in Layer 2 — only props + Controller
- Submit button lives OUTSIDE this component (in Layer 3), linked via `form={FORM_ID}`
- Always use `Controller` for custom/shadcn inputs; `register` only for plain native inputs

---

## Layer 3 — Container (Dialog)

```typescript
import { useUpdateFacebookVia } from "@/entities/facebook-via/_apis/update-facebook-via.api";
import { useGetFacebookViaManual } from "@/entities/facebook-via/_apis/get-facebook-via-manual";
import {
  DEFAULT_EDIT_VIA_FORM_VALUES,
  EDIT_VIA_FORM_ID,
  EditViaFormValues,
  useEditViaForm,
} from "./_ui/edit-via-form/use-edit-via-form";
import EditViaForm from "./_ui/edit-via-form";

interface Props {
  via: FacebookViaRes | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function EditFacebookViaDialog({ via, open, onOpenChange }: Props) {
  const { updateFacebookVia, isUpdatingFacebookVia } = useUpdateFacebookVia();
  const { mutateGetFacebookVia } = useGetFacebookViaManual({ _id: via?._id });

  // ✅ Async defaultValues — RHF fetches on mount automatically, no useEffect needed
  const form = useEditViaForm({
    defaultValues: async () => {
      const res = await mutateGetFacebookVia();
      if (res) {
        return {
          password: res.password ?? "",
          new_password: res.new_password ?? "",
          totp_secret: res.totp_secret ?? "",
          emails: res.emails ?? [],
        };
      }
      return DEFAULT_EDIT_VIA_FORM_VALUES;
    },
  });

  const onSubmit = (data: EditViaFormValues) => {
    if (!via) return;
    toast.promise(updateFacebookVia({ _id: via._id, ...data }), {
      loading: "Đang cập nhật...",
      success: () => { onOpenChange(false); return "Đã cập nhật"; },
      error: "Lỗi khi cập nhật",
    });
  };

  return (
    <Dialog open={open} onOpenChange={(s) => { if (!s) form.reset(); onOpenChange(s); }}>
      <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Chỉnh sửa Via</DialogTitle>
        </DialogHeader>
        <EditViaForm formId={EDIT_VIA_FORM_ID} form={form} onSubmit={onSubmit} />
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Đóng</Button>
          {/* Submit button outside <form> tag, linked via form= attribute */}
          <Button type="submit" form={EDIT_VIA_FORM_ID} disabled={isUpdatingFacebookVia}>
            {isUpdatingFacebookVia ? "Đang lưu..." : "Lưu"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
```

---

## Manual API Hook — Async Form Init

Use when an edit dialog needs fresh server data. File lives in `entities/{entity}/_apis/get-{entity}-manual.ts`.

**Why not `useQuery + enabled: false + refetch()`:**
- Manual hooks are imperative — called exactly when needed
- Can be `await`-ed inside `defaultValues: async () => { ... }`
- No React Query cache pollution for one-shot form init fetches

```typescript
// entities/facebook-via/_apis/get-facebook-via-manual.ts
import { useCallback, useState } from "react";
import axiosInstance from "@/shared/libs/axios";
import { FacebookViaRes } from "../_types/facebook-via.type";

export const useGetFacebookViaManual = ({ _id }: { _id?: string }) => {
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [data, setData] = useState<FacebookViaRes | null>(null);

  const mutate = useCallback(async () => {
    if (!_id) return null;
    setIsLoading(true);
    try {
      const res = await axiosInstance.get(`/api/v1/facebook-auto-post/vias/${_id}`);
      setData(res.data);
      setIsLoading(false);
      return res.data as FacebookViaRes;
    } catch (err) {
      setIsLoading(false);
      setError(err);
      return null;
    }
  }, [_id]);

  return {
    getFacebookViaRes: data,
    isLoadingGetFacebookVia: isLoading,
    errorGetFacebookVia: error,
    mutateGetFacebookVia: mutate,   // caller triggers this
  };
};
```

Return naming pattern: `{ get{Entity}Res, isLoadingGet{Entity}, errorGet{Entity}, mutateGet{Entity} }`

---

## Dynamic Arrays — useFieldArray

```typescript
import { useFieldArray } from "react-hook-form";

// Layer 2: inside form component
const { fields, append, remove } = useFieldArray({
  control: form.control,
  name: "emails",
});

// Append empty item
append({ email: "", password: "" });

// Remove by index
remove(index);

// Render
{fields.map((fieldItem, index) => (
  <div key={fieldItem.id}>
    <Controller
      name={`emails.${index}.email`}
      control={form.control}
      render={({ field }) => <Input {...field} />}
    />
    <Controller
      name={`emails.${index}.password`}
      control={form.control}
      render={({ field }) => <Input type="password" {...field} />}
    />
    <Button variant="ghost" size="icon" onClick={() => remove(index)}>
      <Trash2 className="h-4 w-4" />
    </Button>
  </div>
))}
```

---

## Anti-Patterns

```typescript
// ❌ useEffect to reset form after dialog opens
useEffect(() => {
  if (via && open) form.reset({ password: via.password });
}, [via, open]);
// ✅ Use async defaultValues — RHF calls it on mount

// ❌ Calling mutation inside Layer 2 form component
function MyForm() {
  const { mutate } = useMutation(...); // ← move to Layer 3
}

// ❌ z.input<> when schema has no .transform()
type Values = z.input<typeof schema>; // ← use z.infer<>

// ❌ Submit button inside the form element — breaks external trigger
<form><button type="submit">Submit</button></form>
// ✅ Button in DialogFooter with form={FORM_ID}

// ❌ useQuery + enabled: false + refetch() for form init
const { refetch } = useQuery({ enabled: false });
useEffect(() => { refetch(); }, [open]);
// ✅ Use manual hook with async defaultValues
```
