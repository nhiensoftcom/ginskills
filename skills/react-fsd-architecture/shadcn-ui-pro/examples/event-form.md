# EventForm — All Field Types Combined

A complete form example demonstrating every common field type: text input, category tree selector, date picker (Calendar + Popover), textarea, and checkbox. Use this as a reference when building forms with multiple mixed field types.

---

## Form Hook + Schema

```typescript
// features/event/_ui/event-form/use-event-form.ts
import { zodResolver } from '@hookform/resolvers/zod';
import { useForm } from 'react-hook-form';
import { z } from 'zod';

export const eventFormSchema = z.object({
  title: z.string().min(1, 'Vui lòng nhập tiêu đề'),
  category_id: z.string().min(1, 'Vui lòng chọn danh mục'),
  description: z.string().optional(),
  date: z.date().optional(),
  is_public: z.boolean(),
});

export type EventFormValues = z.infer<typeof eventFormSchema>;

export const DEFAULT_EVENT_FORM_VALUES: EventFormValues = {
  title: '',
  category_id: '',
  description: '',
  is_public: false,
};

export const EVENT_FORM_ID = 'event-form';

export const useEventForm = ({
  defaultValues,
}: {
  defaultValues: EventFormValues | (() => Promise<EventFormValues>);
}) => {
  return useForm<EventFormValues>({
    defaultValues,
    resolver: zodResolver(eventFormSchema),
  });
};
```

---

## Form UI — All Field Types

```tsx
// features/event/_ui/event-form/index.tsx
'use client';

import { Controller, UseFormReturn } from 'react-hook-form';
import {
  Field,
  FieldError,
  FieldGroup,
  FieldLabel,
  FieldDescription,
  Input,
  Textarea,
  Checkbox,
  Button,
  Popover,
  PopoverContent,
  PopoverTrigger,
  Calendar,
} from '@ginstudio/shadcn-ui-pro';
import { CalendarIcon } from 'lucide-react';
import { format } from 'date-fns';
import { useGetListCategories } from '@/entities/category/_apis/get-list-categories.api';
import { CategorySelector } from '@/shared/_components/form/category-selector';
import { EventFormValues, EVENT_FORM_ID } from './use-event-form';

type EventFormProps = {
  formId: string;
  form: UseFormReturn<EventFormValues>;
  onSubmit: (data: EventFormValues) => void;
};

export default function EventForm({ formId, form, onSubmit }: EventFormProps) {
  const { categories, isLoadingCategories } = useGetListCategories();

  return (
    <form id={formId} onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">

      {/* TEXT INPUT */}
      <FieldGroup>
        <Controller
          name="title"
          control={form.control}
          render={({ field, fieldState }) => (
            <Field data-invalid={fieldState.invalid}>
              <FieldLabel htmlFor={formId + '-title'}>
                Tiêu đề <span className="text-destructive">*</span>
              </FieldLabel>
              <Input {...field} id={formId + '-title'} placeholder="Nhập tiêu đề" />
              {fieldState.invalid && <FieldError errors={[fieldState.error]} />}
            </Field>
          )}
        />
      </FieldGroup>

      {/* CATEGORY TREE SELECTOR */}
      <FieldGroup>
        <Controller
          name="category_id"
          control={form.control}
          render={({ field, fieldState }) => (
            <Field data-invalid={fieldState.invalid}>
              <FieldLabel>
                Danh mục <span className="text-destructive">*</span>
              </FieldLabel>
              <CategorySelector
                categories={categories}
                value={field.value || null}
                onChange={(value) => field.onChange(value || '')}
                placeholder={isLoadingCategories ? 'Đang tải...' : 'Chọn danh mục'}
                disabled={isLoadingCategories}
                isLoading={isLoadingCategories}
              />
              <FieldDescription>Chọn danh mục từ cây phân cấp</FieldDescription>
              {fieldState.invalid && <FieldError errors={[fieldState.error]} />}
            </Field>
          )}
        />
      </FieldGroup>

      {/* DATE PICKER — Calendar inside Popover */}
      <FieldGroup>
        <Controller
          name="date"
          control={form.control}
          render={({ field, fieldState }) => (
            <Field data-invalid={fieldState.invalid}>
              <FieldLabel>Ngày diễn ra</FieldLabel>
              <Popover>
                <PopoverTrigger asChild>
                  <Button variant="outline" className="w-full justify-start text-left font-normal">
                    <CalendarIcon className="mr-2 h-4 w-4" />
                    {field.value ? format(field.value, 'dd/MM/yyyy') : 'Chọn ngày'}
                  </Button>
                </PopoverTrigger>
                <PopoverContent className="w-auto p-0" align="start">
                  <Calendar mode="single" selected={field.value} onSelect={field.onChange} />
                </PopoverContent>
              </Popover>
              {fieldState.invalid && <FieldError errors={[fieldState.error]} />}
            </Field>
          )}
        />
      </FieldGroup>

      {/* TEXTAREA */}
      <FieldGroup>
        <Controller
          name="description"
          control={form.control}
          render={({ field }) => (
            <Field>
              <FieldLabel htmlFor={formId + '-description'}>Mô tả</FieldLabel>
              <Textarea {...field} id={formId + '-description'} placeholder="Nhập mô tả" rows={3} />
              <FieldDescription>Mô tả ngắn gọn về sự kiện (tùy chọn)</FieldDescription>
            </Field>
          )}
        />
      </FieldGroup>

      {/* CHECKBOX — horizontal orientation */}
      <FieldGroup>
        <Controller
          name="is_public"
          control={form.control}
          render={({ field }) => (
            <Field orientation="horizontal">
              <Checkbox
                id={formId + '-is_public'}
                checked={field.value}
                onCheckedChange={field.onChange}
              />
              <FieldLabel htmlFor={formId + '-is_public'}>Công khai sự kiện</FieldLabel>
            </Field>
          )}
        />
      </FieldGroup>

    </form>
  );
}
```

---

## Field Type Quick Reference

| Field Type | Component | Notes |
|---|---|---|
| Text input | `<Input {...field} />` | Always spread `{...field}`, add `value={field.value ?? ""}` |
| Textarea | `<Textarea {...field} rows={N} />` | Same as Input pattern |
| Select (enum) | `<Select value={...} onValueChange={field.onChange}>` | Use `onValueChange` not `onChange` |
| Date picker | `<Popover>` + `<Calendar mode="single" onSelect={field.onChange}>` | `field.value` is a `Date` object |
| Category tree | `<CategorySelector value={field.value \|\| null} onChange={...}>` | Convert null → empty string for zod |
| Checkbox | `<Checkbox checked={field.value} onCheckedChange={field.onChange}>` | Use `onCheckedChange` not `onChange` |
| Checkbox + label | `<Field orientation="horizontal">` | Horizontal layout for inline label |
