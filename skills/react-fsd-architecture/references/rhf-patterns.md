# React Hook Form Patterns (scrape-video project)

## 3-Layer Form Pattern

Every form in this codebase is split into exactly 3 layers:

```
_ui/{feature}-form/
├── use-{feature}-form.ts   ← Layer 1: Zod schema + useForm hook
└── index.tsx               ← Layer 2: Dumb form component (Controller only, NO API calls)
{feature-container}.tsx     ← Layer 3: Container (mutations, submit logic, dialog)
```

---

## Layer 1 — Schema + Hook (`use-{feature}-form.ts`)

```typescript
import { z } from "zod";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";

export const mySchema = z.object({
  name: z.string().min(1, "Required"),
  email: z.string().email(),
});

export type MyFormValues = z.infer<typeof mySchema>;

export const MY_FORM_ID = "my-form";

export const DEFAULT_MY_FORM_VALUES: MyFormValues = {
  name: "",
  email: "",
};

// Accept defaultValues as a value OR async function (for edit forms that fetch from API)
export function useMyForm({
  defaultValues,
}: {
  defaultValues: MyFormValues | (() => Promise<MyFormValues>);
}) {
  return useForm<MyFormValues>({
    resolver: zodResolver(mySchema),
    defaultValues,
  });
}
```

**Rules:**
- Always export `FORM_ID`, `DEFAULT_VALUES`, and the hook from this file
- Use `z.infer<typeof schema>` for the type (never manually type form values)
- Accept `defaultValues` as `T | (() => Promise<T>)` — RHF natively supports async defaultValues

---

## Layer 2 — Form Component (`index.tsx`)

```typescript
import { Controller, UseFormReturn } from "react-hook-form";
import { Field, FieldError, FieldGroup, FieldLabel } from "@/shared/components/shadcn/field";
import { Input } from "@/shared/components/shadcn/input";
import { MY_FORM_ID, MyFormValues } from "./use-my-form";

export default function MyForm({
  formId = MY_FORM_ID,
  form,
  onSubmit,
}: {
  formId?: string;
  form: UseFormReturn<MyFormValues>;
  onSubmit: (data: MyFormValues) => void;
}) {
  return (
    <form id={formId} onSubmit={form.handleSubmit(onSubmit)}>
      <Controller
        name="name"
        control={form.control}
        render={({ field, fieldState }) => (
          <Field data-invalid={fieldState.invalid}>
            <FieldLabel>Name</FieldLabel>
            <Input {...field} />
            {fieldState.invalid && <FieldError errors={[fieldState.error]} />}
          </Field>
        )}
      />
    </form>
  );
}
```

**Rules:**
- Never call API or useMutation in Layer 2 — only props and Controller
- The submit button lives OUTSIDE this component (in Layer 3), connected via `form={FORM_ID}`
- Always use `Controller` for custom inputs (never `register` for non-native inputs)

---

## Layer 3 — Container (Dialog / Page)

```typescript
import { useUpdateFacebookVia } from "@/entities/facebook-via/_apis/update-facebook-via.api";
import { useGetFacebookViaManual } from "@/entities/facebook-via/_apis/get-facebook-via-manual";
import {
  DEFAULT_EDIT_VIA_FORM_VALUES,
  EDIT_VIA_FORM_ID,
  EditViaFormValues,
  useEditViaForm,
} from "./_ui/edit-via-form/use-edit-via-form";

export function EditFacebookViaDialog({ via, open, onOpenChange }) {
  const { updateFacebookVia } = useUpdateFacebookVia();
  const { mutateGetFacebookVia } = useGetFacebookViaManual({ _id: via?._id });

  // ✅ Async defaultValues — RHF fetches on mount, no useEffect needed
  const form = useEditViaForm({
    defaultValues: async () => {
      const res = await mutateGetFacebookVia();
      if (res) {
        return { password: res.password, new_password: res.new_password, ... };
      }
      return DEFAULT_EDIT_VIA_FORM_VALUES;
    },
  });

  const onSubmit = (data: EditViaFormValues) => {
    toast.promise(updateFacebookVia({ _id: via._id, ...data }), {
      loading: "Saving...",
      success: () => { onOpenChange(false); return "Saved"; },
      error: "Error saving",
    });
  };

  return (
    <Dialog open={open} onOpenChange={(s) => { if (!s) form.reset(); onOpenChange(s); }}>
      <DialogContent>
        <EditViaForm formId={EDIT_VIA_FORM_ID} form={form} onSubmit={onSubmit} />
        <DialogFooter>
          {/* Submit button outside the form, linked via form={FORM_ID} */}
          <Button type="submit" form={EDIT_VIA_FORM_ID}>Save</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
```

---

## Manual API Hook — init form without useEffect

Use this pattern for edit dialogs that need fresh server data. Lives in `entities/{entity}/_apis/get-{entity}-manual.ts`.

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
    mutateGetFacebookVia: mutate,
  };
};
```

**Why manual instead of `useQuery + enabled: false + refetch()`:**
- Manual hooks are imperative — call exactly when you want
- Can be awaited inside `defaultValues: async () => { ... }`
- No React Query cache pollution for one-shot form init fetches
- Return naming: `{ get{Entity}Res, isLoadingGet{Entity}, errorGet{Entity}, mutateGet{Entity} }`

---

## Dynamic Arrays — useFieldArray

```typescript
import { useFieldArray } from "react-hook-form";

const { fields, append, remove } = useFieldArray({
  control: form.control,
  name: "emails",
});

// Append an empty item
append({ email: "", password: "" });

// Remove by index
remove(index);

// Render
{fields.map((fieldItem, index) => (
  <div key={fieldItem.id}>
    <Controller name={`emails.${index}.email`} control={form.control} render={...} />
    <Controller name={`emails.${index}.password`} control={form.control} render={...} />
    <button onClick={() => remove(index)}>Remove</button>
  </div>
))}
```

---

## Anti-patterns

```typescript
// ❌ useEffect to reset form — use async defaultValues instead
useEffect(() => {
  if (via && open) form.reset({ password: via.password, ... });
}, [via, open]);

// ✅ RHF async defaultValues — called on mount automatically
const form = useEditViaForm({
  defaultValues: async () => {
    const res = await mutateGetFacebookVia();
    return res ? mapToFormValues(res) : DEFAULT_VALUES;
  },
});

// ❌ Calling API inside form component (Layer 2)
function MyForm() {
  const { mutate } = useMutation(...); // ← WRONG, belongs in Layer 3
}

// ❌ z.input<> when schema has no .transform()
type Values = z.input<typeof schema>; // use z.infer<> instead

// ❌ Submit button inside form — breaks external trigger pattern
<form>
  <button type="submit">Submit</button> {/* ← move to dialog footer */}
</form>
```
