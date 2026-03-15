# Form Guide — React Hook Form + Zod + @ginstudio/shadcn-ui-pro

Complete guide for building forms with React Hook Form, Zod validation, and integration with dialogs. Follows the Feature-Sliced Design architecture.

---

## Installation

```typescript
import {
  Field,
  FieldGroup,
  FieldLabel,
  FieldError,
  FieldDescription,
} from '@ginstudio/shadcn-ui-pro';

import { Input } from '@ginstudio/shadcn-ui-pro';
import { Textarea } from '@ginstudio/shadcn-ui-pro';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@ginstudio/shadcn-ui-pro';
import { Popover, PopoverContent, PopoverTrigger } from '@ginstudio/shadcn-ui-pro';
import { Button } from '@ginstudio/shadcn-ui-pro';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@ginstudio/shadcn-ui-pro';
```

---

## Architecture Overview

Forms follow the Feature-Sliced Design architecture:

```
src/
├── entities/
│   └── [entity]/
│       ├── _apis/
│       │   └── get-[entity]-by-id.service.ts    # API for edit mode
│       └── _types/
│           └── [entity].type.ts                  # Types & enums
│
└── features/
    └── [feature]/
        ├── _stores/
        │   └── [feature]-dialogs-store.ts        # Dialog state management
        └── _ui/
            ├── [feature]-form/                   # Form folder
            │   ├── index.tsx                     # Form UI component
            │   └── use-[feature]-form.ts         # Form hook + schema
            ├── [feature]-dialogs.tsx             # Dialog registry
            └── create-edit-dialog.tsx            # Create/Edit dialog
```

**Naming Convention:** Form folder: `[feature]-form` (e.g., `system-prompts-form`, `user-form`)

---

## Step 1: Create Folder Structure

Create form folder inside feature `_ui` directory:

```
features/
└── system-prompt/
    └── _ui/
        └── system-prompts-form/     # ✅ [feature]-form naming
            ├── index.tsx             # Form UI component
            └── use-system-prompts-form.ts  # Hook + Schema + Types
```

---

## Step 2: Create Form Hook

**File:** `use-[feature]-form.ts`

⚠️ **STRICT ORDER:** Schema → Types → Default Values → Form ID → Hook

```typescript
import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import z from "zod";

// ⚠️ Import types/enums from entities - NEVER create redundant types
import { SystemPromptStatus } from "@/entities/system-prompt/_types/system-prompt.type";

// 1. Schema Definition
export const systemPromptFormSchema = z.object({
  name: z
    .string()
    .trim()
    .min(1, { message: "Vui lòng nhập tên prompt" }),
  status: z.nativeEnum(SystemPromptStatus),
  content: z
    .string()
    .trim()
    .min(1, { message: "Vui lòng nhập nội dung prompt" }),
});

// 2. Type Inference
export type SystemPromptFormValues = z.infer<typeof systemPromptFormSchema>;

// 3. Default Values
export const DEFAULT_SYSTEM_PROMPT_FORM_VALUES: SystemPromptFormValues = {
  name: "",
  status: SystemPromptStatus.PRIVATE,
  content: "",
};

// 4. Form ID Constant
export const SYSTEM_PROMPT_FORM_ID = "system-prompt-form";

// 5. useForm Hook
// ⚠️ REQUIRED: defaultValues MUST support Promise for edit mode
export const useSystemPromptForm = ({
  defaultValues,
}: {
  defaultValues:
    | SystemPromptFormValues
    | (() => Promise<SystemPromptFormValues>);
}) => {
  return useForm<SystemPromptFormValues>({
    defaultValues,
    resolver: zodResolver(systemPromptFormSchema),
  });
};
```

⚠️ **Critical:**
- `defaultValues` MUST support Promise — Required for edit mode (fetch from API)
- Import types/enums from entities — NEVER create redundant types
- Follow strict naming: `schema`, `type`, `DEFAULT_`, `FORM_ID`, `useHook`

---

## Step 3: Create Form UI Component

**File:** `index.tsx`

```tsx
"use client";

import React from "react";
import { Controller, UseFormReturn } from "react-hook-form";
import {
  Field,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@ginstudio/shadcn-ui-pro";
import { Input } from "@ginstudio/shadcn-ui-pro";
import { Textarea } from "@ginstudio/shadcn-ui-pro";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@ginstudio/shadcn-ui-pro";

import { SystemPromptStatus } from "@/entities/system-prompt/_types/system-prompt.type";
import { SystemPromptFormValues } from "./use-system-prompts-form";

// Props Pattern: formId, form, onSubmit, isSubmitting
type SystemPromptFormProps = {
  formId: string;
  form: UseFormReturn<SystemPromptFormValues>;
  onSubmit: (data: SystemPromptFormValues) => void;
  isSubmitting: boolean;
};

export default function SystemPromptsForm({
  formId,
  form,
  onSubmit,
  isSubmitting,
}: SystemPromptFormProps) {
  return (
    <form
      id={formId}
      onSubmit={form.handleSubmit(onSubmit)}
      className="space-y-4"
    >
      {/* Text Input */}
      <FieldGroup>
        <Controller
          name="name"
          control={form.control}
          render={({ field, fieldState }) => (
            <Field data-invalid={fieldState.invalid}>
              <FieldLabel htmlFor={formId + "-name"}>
                Tên prompt <span className="text-destructive">*</span>
              </FieldLabel>
              <Input
                {...field}
                value={field.value ?? ""}
                id={formId + "-name"}
                aria-invalid={fieldState.invalid}
                placeholder="Nhập tên prompt"
                autoComplete="off"
              />
              {fieldState.invalid && <FieldError errors={[fieldState.error]} />}
            </Field>
          )}
        />
      </FieldGroup>

      {/* Select Field */}
      <FieldGroup>
        <Controller
          name="status"
          control={form.control}
          render={({ field, fieldState }) => (
            <Field data-invalid={fieldState.invalid}>
              <FieldLabel>
                Trạng thái <span className="text-destructive">*</span>
              </FieldLabel>
              <Select
                value={field.value ?? SystemPromptStatus.PRIVATE}
                onValueChange={field.onChange}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Chọn trạng thái" />
                </SelectTrigger>
                <SelectContent>
                  {Object.values(SystemPromptStatus).map((status) => (
                    <SelectItem key={status} value={status}>
                      {status === SystemPromptStatus.PUBLIC
                        ? "Công khai"
                        : "Riêng tư"}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {fieldState.invalid && <FieldError errors={[fieldState.error]} />}
            </Field>
          )}
        />
      </FieldGroup>

      {/* Textarea */}
      <FieldGroup>
        <Controller
          name="content"
          control={form.control}
          render={({ field, fieldState }) => (
            <Field data-invalid={fieldState.invalid}>
              <FieldLabel htmlFor={formId + "-content"}>
                Nội dung prompt <span className="text-destructive">*</span>
              </FieldLabel>
              <Textarea
                {...field}
                value={field.value ?? ""}
                id={formId + "-content"}
                aria-invalid={fieldState.invalid}
                placeholder="Nhập nội dung prompt"
                autoComplete="off"
                rows={6}
              />
              {fieldState.invalid && <FieldError errors={[fieldState.error]} />}
            </Field>
          )}
        />
      </FieldGroup>
    </form>
  );
}
```

**Form UI Rules:**
- Props pattern: `formId`, `form`, `onSubmit`, `isSubmitting`
- Use `Controller` from react-hook-form for all fields
- ID pattern: `{formId}-{fieldName}` for unique IDs
- Error: `{fieldState.invalid && <FieldError errors={[fieldState.error]} />}`

---

## Form with Popover (Calendar, Color Picker, etc.)

Use `Popover` for date pickers, color pickers, or any popup selections:

```tsx
import { Popover, PopoverContent, PopoverTrigger } from "@ginstudio/shadcn-ui-pro";
import { Calendar } from "@ginstudio/shadcn-ui-pro";
import { Button } from "@ginstudio/shadcn-ui-pro";
import { CalendarIcon } from "lucide-react";
import { format } from "date-fns";

// Inside form component
<FieldGroup>
  <Controller
    name="dueDate"
    control={form.control}
    render={({ field, fieldState }) => (
      <Field data-invalid={fieldState.invalid}>
        <FieldLabel>Ngày hết hạn</FieldLabel>
        <Popover>
          <PopoverTrigger asChild>
            <Button
              variant="outline"
              className="w-full justify-start text-left font-normal"
            >
              <CalendarIcon className="mr-2 h-4 w-4" />
              {field.value ? format(field.value, "dd/MM/yyyy") : "Chọn ngày"}
            </Button>
          </PopoverTrigger>
          <PopoverContent className="w-auto p-0" align="start">
            <Calendar
              mode="single"
              selected={field.value}
              onSelect={field.onChange}
              initialFocus
            />
          </PopoverContent>
        </Popover>
        {fieldState.invalid && <FieldError errors={[fieldState.error]} />}
      </Field>
    )}
  />
</FieldGroup>
```

---

## Step 4: Create API Service for Edit Mode

**File:** `entities/[entity]/_apis/get-[entity]-by-id.service.ts`

```typescript
import { useQuery, useMutation } from "@tanstack/react-query";
import { ApiError } from "@/shared/types/api.error";
import { SystemPromptRes } from "../_types/system-prompt.type";
import axiosInstance from "@/shared/libs/axios";

export const QK_GET_PERSONAL_PROMPT_BY_ID = "/api/v1/system-prompts";

export const useGetPersonalPromptById = ({ _id }: { _id?: string }) => {
  const { data, isLoading, error, refetch } = useQuery<
    SystemPromptRes,
    ApiError
  >({
    queryKey: [QK_GET_PERSONAL_PROMPT_BY_ID, _id],
    queryFn: async () => {
      const response = await axiosInstance.get<SystemPromptRes>(
        `${QK_GET_PERSONAL_PROMPT_BY_ID}/${_id}`
      );
      return response.data;
    },
    enabled: !!_id,
  });

  // ⚠️ REQUIRED: mutateAsync for form async defaultValues
  const { mutateAsync, isPending } = useMutation<
    SystemPromptRes,
    ApiError,
    void
  >({
    mutationFn: async () => {
      if (!_id) throw new Error("ID is required");
      const response = await axiosInstance.get<SystemPromptRes>(
        `${QK_GET_PERSONAL_PROMPT_BY_ID}/${_id}`
      );
      return response.data;
    },
  });

  return {
    personalPromptById: data,
    isLoadingPersonalPromptById: isLoading || isPending,
    errorPersonalPromptById: error,
    refetchPersonalPromptById: refetch,
    getPersonalPromptByIdManual: mutateAsync,  // ⚠️ Used in form defaultValues
  };
};
```

---

## Step 5: Create/Edit Dialog

**File:** `features/[feature]/_ui/create-edit-dialog.tsx`

```tsx
"use client";

import { Button } from "@ginstudio/shadcn-ui-pro";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@ginstudio/shadcn-ui-pro";
import { Loader2 } from "lucide-react";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";

import SystemPromptsForm from "../system-prompts-form";
import {
  DEFAULT_SYSTEM_PROMPT_FORM_VALUES,
  SYSTEM_PROMPT_FORM_ID,
  SystemPromptFormValues,
  useSystemPromptForm,
} from "../system-prompts-form/use-system-prompts-form";
import { SystemPromptRes } from "@/entities/system-prompt/_types/system-prompt.type";
import { useCreateNewSystemPrompt } from "@/entities/system-prompt/_apis/create-new-system-prompt.service";
import { useUpdatePersonalPrompt } from "@/entities/system-prompt/_apis/update-personal-prompt.service";
import { QK_GET_PERSONAL_LIST_PROMPTS } from "@/entities/system-prompt/_apis/get-personal-list-prompts.service";
import { useGetPersonalPromptById } from "@/entities/system-prompt/_apis/get-personal-prompt-by-id.service";

export default function SystemPromptCreateEditDialog({
  open,
  currentRow,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  currentRow?: SystemPromptRes;
}) {
  const isEdit = !!currentRow;
  const queryClient = useQueryClient();

  const { createNewSystemPrompt, isCreatingNewSystemPrompt } =
    useCreateNewSystemPrompt();
  const { updatePersonalPrompt, isUpdatingPersonalPrompt } =
    useUpdatePersonalPrompt({ _id: currentRow?._id ?? "" });
  const { getPersonalPromptByIdManual, isLoadingPersonalPromptById } =
    useGetPersonalPromptById({ _id: currentRow?._id });

  // ⚠️ Async defaultValues pattern for edit mode
  const form = useSystemPromptForm({
    defaultValues: async () => {
      if (isEdit && currentRow) {
        const promptData = await getPersonalPromptByIdManual();
        if (promptData) {
          return {
            name: promptData.name,
            status: promptData.status,
            content: promptData.content,
          } as SystemPromptFormValues;
        }
      }
      return DEFAULT_SYSTEM_PROMPT_FORM_VALUES;
    },
  });

  const onSubmit = (data: SystemPromptFormValues) => {
    const payload = {
      name: data.name,
      status: data.status,
      content: data.content,
    };

    if (isEdit && currentRow) {
      updatePersonalPrompt(payload, {
        onSuccess: () => {
          toast.success("Cập nhật prompt thành công");
          queryClient.invalidateQueries({
            queryKey: [QK_GET_PERSONAL_LIST_PROMPTS],
          });
          onOpenChange(false);
        },
        onError: (e) => {
          if (e.error_code === "system_prompt_name_already_exists") {
            form.setError("name", { message: "Tên prompt đã tồn tại" });
            form.setFocus("name");
            return;
          }
          toast.error("Cập nhật prompt thất bại");
        },
      });
    } else {
      createNewSystemPrompt(payload, {
        onSuccess: () => {
          toast.success("Tạo prompt thành công");
          queryClient.invalidateQueries({
            queryKey: [QK_GET_PERSONAL_LIST_PROMPTS],
          });
          onOpenChange(false);
          form.reset();
        },
        onError: (e) => {
          if (e.response?.data?.error_code === "system_prompt_name_already_exists") {
            form.setError("name", { message: "Tên prompt đã tồn tại" });
            form.setFocus("name");
            return;
          }
          toast.error("Tạo prompt thất bại");
        },
      });
    }
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(state) => {
        if (!state) form.reset();
        onOpenChange(state);
      }}
    >
      <DialogContent aria-describedby={SYSTEM_PROMPT_FORM_ID}>
        <DialogHeader className="text-start">
          <DialogTitle>{isEdit ? "Cập nhật" : "Tạo"} prompt</DialogTitle>
        </DialogHeader>
        <DialogDescription>
          {isEdit ? "Cập nhật thông tin" : "Tạo mới"} system prompt
        </DialogDescription>

        <SystemPromptsForm
          form={form}
          onSubmit={onSubmit}
          formId={SYSTEM_PROMPT_FORM_ID}
          isSubmitting={isCreatingNewSystemPrompt || isUpdatingPersonalPrompt}
        />

        <DialogFooter className="shrink-0 bg-background">
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
            Hủy
          </Button>
          <Button
            type="submit"
            form={SYSTEM_PROMPT_FORM_ID}
            disabled={
              isLoadingPersonalPromptById ||
              isCreatingNewSystemPrompt ||
              isUpdatingPersonalPrompt
            }
          >
            {isEdit ? "Cập nhật" : "Tạo"}
            {(isCreatingNewSystemPrompt || isUpdatingPersonalPrompt) && (
              <Loader2 className="w-4 h-4 animate-spin" />
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
```

---

## Step 6: Create Dialog Store

**File:** `features/[feature]/_stores/[feature]-dialogs-store.ts`

```typescript
import { create } from 'zustand';
import { SystemPromptRes } from "@/entities/system-prompt/_types/system-prompt.type";

export enum SystemPromptsDialogType {
  CREATE = 'create',
  EDIT = 'edit',
  DELETE_BATCH = 'delete-batch',
  DELETE_ALL = 'delete-all',
}

type SystemPromptsDialogState = {
  open: SystemPromptsDialogType | null;
  setOpen: (type: SystemPromptsDialogType | null) => void;
  currentRow: SystemPromptRes | null;
  setCurrentRow: (row: SystemPromptRes | null) => void;
  selectedRows: SystemPromptRes[];
  setSelectedRows: (rows: SystemPromptRes[]) => void;
  onBatchDeleteSuccess: (() => void) | null;
  setOnBatchDeleteSuccess: (fn: (() => void) | null) => void;
  onDeleteAllSuccess: (() => void) | null;
  setOnDeleteAllSuccess: (fn: (() => void) | null) => void;
};

export const useSystemPromptsDialogStore = create<SystemPromptsDialogState>((set) => ({
  open: null,
  setOpen: (type) => set((state) => ({
    open: state.open === type ? null : type,  // Toggle behavior
  })),
  currentRow: null,
  setCurrentRow: (row) => set({ currentRow: row }),
  selectedRows: [],
  setSelectedRows: (rows) => set({ selectedRows: rows }),
  onBatchDeleteSuccess: null,
  setOnBatchDeleteSuccess: (fn) => set({ onBatchDeleteSuccess: fn }),
  onDeleteAllSuccess: null,
  setOnDeleteAllSuccess: (fn) => set({ onDeleteAllSuccess: fn }),
}));
```

---

## Step 7: Create Dialog Registry

**File:** `features/[feature]/_ui/[feature]-dialogs.tsx`

```tsx
"use client";

import { useShallow } from "zustand/react/shallow";
import {
  SystemPromptsDialogType,
  useSystemPromptsDialogStore,
} from "../../_stores/system-prompts-dialogs-store";
import SystemPromptCreateEditDialog from "./create-edit-dialog";
import { SystemPromptDeleteBatchDialog } from "./delete-batch-dialog";
import { SystemPromptDeleteAllDialog } from "./delete-all-dialog";

export function SystemPromptsDialogs() {
  const {
    open,
    setOpen,
    currentRow,
    setCurrentRow,
    selectedRows,
    onBatchDeleteSuccess,
    onDeleteAllSuccess,
  } = useSystemPromptsDialogStore(
    useShallow((state) => ({
      open: state.open,
      setOpen: state.setOpen,
      currentRow: state.currentRow,
      setCurrentRow: state.setCurrentRow,
      selectedRows: state.selectedRows,
      onBatchDeleteSuccess: state.onBatchDeleteSuccess,
      onDeleteAllSuccess: state.onDeleteAllSuccess,
    }))
  );

  return (
    <>
      {/* Create Dialog (no currentRow needed) */}
      <SystemPromptCreateEditDialog
        key="system-prompt-create"
        open={open === SystemPromptsDialogType.CREATE}
        onOpenChange={() => setOpen(SystemPromptsDialogType.CREATE)}
      />

      {/* Edit Dialog (requires currentRow) */}
      {currentRow && (
        <SystemPromptCreateEditDialog
          key={`system-prompt-edit-${currentRow._id}`}
          open={open === SystemPromptsDialogType.EDIT}
          onOpenChange={() => {
            setOpen(SystemPromptsDialogType.EDIT);
            // Clear row after dialog close animation
            setTimeout(() => setCurrentRow(null), 500);
          }}
          currentRow={currentRow}
        />
      )}

      {/* Delete Batch Dialog */}
      {selectedRows.length > 0 && (
        <SystemPromptDeleteBatchDialog
          key="system-prompt-delete-batch"
          open={open === SystemPromptsDialogType.DELETE_BATCH}
          onOpenChange={() => setOpen(SystemPromptsDialogType.DELETE_BATCH)}
          selectedRows={selectedRows}
          onSuccess={onBatchDeleteSuccess ?? undefined}
        />
      )}

      {/* Delete All Dialog */}
      <SystemPromptDeleteAllDialog
        key="system-prompt-delete-all"
        open={open === SystemPromptsDialogType.DELETE_ALL}
        onOpenChange={() => setOpen(SystemPromptsDialogType.DELETE_ALL)}
        onSuccess={onDeleteAllSuccess ?? undefined}
      />
    </>
  );
}
```

**Important:**
- Use `useShallow` from `zustand/react/shallow` for performance
- Wrap edit/delete dialogs in `{currentRow && ...}`
- Use dynamic `key` with entity ID for proper remounting
- Clear `currentRow` after dialog closes (with timeout for animation)

---

## Step 8: Register Dialogs in Page

Add dialogs registry at the end of your page:

```tsx
// app/dashboard/(main)/system-prompts/page.tsx
import { SystemPromptsDialogs } from "@/features/system-prompt/_ui/system-prompts-dialogs";
import { SystemPromptsTable } from "@/features/system-prompt/_ui/system-prompts-table";

export default function SystemPromptsPage() {
  return (
    <>
      <Header>
        <h1>System Prompts</h1>
        <AddPromptButton />
      </Header>

      <Main>
        <SystemPromptsTable />
      </Main>

      {/* ⚠️ Register all dialogs at page level */}
      <SystemPromptsDialogs />
    </>
  );
}
```

---

## File Location Summary

```
src/
├── entities/
│   └── system-prompt/
│       ├── _apis/
│       │   ├── get-personal-prompt-by-id.service.ts
│       │   ├── create-new-system-prompt.service.ts
│       │   ├── update-personal-prompt.service.ts
│       │   └── get-personal-list-prompts.service.ts
│       └── _types/
│           └── system-prompt.type.ts
│
├── features/
│   └── system-prompt/
│       ├── _stores/
│       │   └── system-prompts-dialogs-store.ts
│       └── _ui/
│           ├── system-prompts-form/
│           │   ├── index.tsx
│           │   └── use-system-prompts-form.ts
│           ├── system-prompts-dialogs.tsx
│           ├── create-edit-dialog.tsx
│           ├── delete-batch-dialog.tsx
│           └── delete-all-dialog.tsx
│
└── app/
    └── dashboard/
        └── (main)/
            └── system-prompts/
                └── page.tsx
```

---

## Best Practices

- **Always support async `defaultValues`** — Required for edit mode
- **Import types from entities** — Never create redundant types
- **Use Form ID constant** — Enables form submission from external buttons
- **Follow naming conventions** — Consistent `schema`, `types`, `defaults` naming
- **Use Popover for complex selectors** — Date pickers, color pickers, etc.
- **Register dialogs at page level** — Keeps dialog logic centralized
- **Use `useShallow` for store subscriptions** — Prevents unnecessary re-renders
- **Clear `currentRow` after dialog closes** — Prevents stale data
- **Handle API errors with `form.setError`** — Show inline validation errors
