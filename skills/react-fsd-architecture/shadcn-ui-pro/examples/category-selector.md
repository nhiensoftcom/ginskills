# CategorySelector — Hierarchical Tree Select

A reusable component for selecting from a nested category tree. Supports search, expand/collapse, path breadcrumb display, and clear selection.

---

## Types

```typescript
// entities/category/_types/category.type.ts
import { IdAndTimeStamps } from '@/shared/_types/id-and-timestamps';

export type CategoryRes = {
  name: string;
  description?: string;
  parent_id?: string;
  sub_categories?: CategoryRes[];
  level: number;
  path: string;
} & IdAndTimeStamps;

export type CategoryResWithChildren = CategoryRes & {
  sub_categories: CategoryResWithChildren[];
};
```

---

## API Hook

```typescript
// entities/category/_apis/get-list-categories.api.ts
import { useQuery } from '@tanstack/react-query';
import axiosInstance from '@/shared/_libs/axios';
import { CategoryResWithChildren } from '../_types/category.type';

export const QK_GET_LIST_CATEGORIES = '/api/v1/categories';

export const useGetListCategories = () => {
  const { data, isLoading, error, refetch } = useQuery<CategoryResWithChildren[]>({
    queryKey: [QK_GET_LIST_CATEGORIES],
    queryFn: async () => {
      const response = await axiosInstance.get<CategoryResWithChildren[]>(QK_GET_LIST_CATEGORIES, {
        params: { tree: true },
      });
      return response.data;
    },
  });

  return {
    categories: data || [],
    isLoadingCategories: isLoading,
    errorCategories: error,
    refetchCategories: refetch,
  };
};
```

---

## CategorySelector Component

```tsx
// shared/_components/form/category-selector.tsx
'use client';

import { useState, useMemo } from 'react';
import {
  Popover,
  PopoverTrigger,
  PopoverContent,
  Button,
  Input,
  Badge,
  ScrollArea,
} from '@ginstudio/shadcn-ui-pro';
import {
  ChevronsUpDown,
  ChevronRight,
  ChevronDown,
  Search,
  X,
  Folder,
  FolderOpen,
  Check,
} from 'lucide-react';
import { cn } from '@/shared/_utils/cn';
import { CategoryResWithChildren } from '@/entities/category/_types/category.type';

interface CategoryTreeNodeProps {
  category: CategoryResWithChildren;
  level: number;
  selectedId: string | null;
  expandedIds: Set<string>;
  onSelect: (id: string) => void;
  onToggleExpand: (id: string) => void;
}

function CategoryTreeNode({
  category,
  level,
  selectedId,
  expandedIds,
  onSelect,
  onToggleExpand,
}: CategoryTreeNodeProps) {
  const hasChildren = category.sub_categories?.length > 0;
  const isExpanded = expandedIds.has(category._id);
  const isSelected = selectedId === category._id;

  return (
    <div>
      <div
        className={cn(
          'w-full flex items-center gap-2 py-2 px-2 rounded-lg text-sm cursor-pointer',
          'hover:bg-primary/10 transition-all duration-150',
          isSelected && 'bg-primary/10'
        )}
        style={{ paddingLeft: `${8 + level * 20}px` }}
        onClick={() => onSelect(category._id)}
        role="button"
        tabIndex={0}
      >
        {hasChildren ? (
          <span
            role="button"
            tabIndex={0}
            className="shrink-0 p-0.5 rounded hover:bg-muted cursor-pointer"
            onClick={(e) => {
              e.stopPropagation();
              onToggleExpand(category._id);
            }}
          >
            {isExpanded ? (
              <ChevronDown className="h-3.5 w-3.5 text-muted-foreground" />
            ) : (
              <ChevronRight className="h-3.5 w-3.5 text-muted-foreground" />
            )}
          </span>
        ) : (
          <div className="w-4" />
        )}
        {isExpanded ? (
          <FolderOpen className="h-4 w-4 text-primary shrink-0" />
        ) : (
          <Folder className="h-4 w-4 text-muted-foreground shrink-0" />
        )}
        <span className="flex-1 truncate">{category.name}</span>
        {isSelected && <Check className="h-4 w-4 text-primary shrink-0" />}
      </div>
      {hasChildren && isExpanded && (
        <div>
          {category.sub_categories.map((child) => (
            <CategoryTreeNode
              key={child._id}
              category={child}
              level={level + 1}
              selectedId={selectedId}
              expandedIds={expandedIds}
              onSelect={onSelect}
              onToggleExpand={onToggleExpand}
            />
          ))}
        </div>
      )}
    </div>
  );
}

export interface CategorySelectorProps {
  categories: CategoryResWithChildren[];
  value: string | null;
  onChange: (value: string | null) => void;
  placeholder?: string;
  disabled?: boolean;
  isLoading?: boolean;
}

export function CategorySelector({
  categories,
  value,
  onChange,
  placeholder = 'Chọn danh mục',
  disabled = false,
  isLoading = false,
}: CategorySelectorProps) {
  const [open, setOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());

  const selectedCategory = useMemo(() => {
    if (!value) return null;
    const findCategory = (
      cats: CategoryResWithChildren[],
      id: string
    ): CategoryResWithChildren | null => {
      for (const cat of cats) {
        if (cat._id === id) return cat;
        if (cat.sub_categories) {
          const found = findCategory(cat.sub_categories, id);
          if (found) return found;
        }
      }
      return null;
    };
    return findCategory(categories, value);
  }, [categories, value]);

  const getCategoryPath = useMemo(() => {
    if (!value) return '';
    const findPath = (
      cats: CategoryResWithChildren[],
      id: string,
      path: string[] = []
    ): string[] | null => {
      for (const cat of cats) {
        if (cat._id === id) return [...path, cat.name];
        if (cat.sub_categories) {
          const found = findPath(cat.sub_categories, id, [...path, cat.name]);
          if (found) return found;
        }
      }
      return null;
    };
    const path = findPath(categories, value);
    return path ? path.join(' / ') : '';
  }, [categories, value]);

  const filteredCategories = useMemo(() => {
    if (!searchQuery.trim()) return categories;
    const query = searchQuery.toLowerCase();
    const filterTree = (cats: CategoryResWithChildren[]): CategoryResWithChildren[] => {
      return cats
        .filter((cat) => {
          const matches = cat.name.toLowerCase().includes(query);
          if (cat.sub_categories?.length) {
            const filteredSubs = filterTree(cat.sub_categories);
            if (filteredSubs.length) return true;
          }
          return matches;
        })
        .map((cat) => ({
          ...cat,
          sub_categories: cat.sub_categories ? filterTree(cat.sub_categories) : [],
        }));
    };
    return filterTree(categories);
  }, [categories, searchQuery]);

  const toggleExpand = (id: string) => {
    setExpandedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const handleSelect = (id: string | null) => {
    onChange(id);
    setOpen(false);
    setSearchQuery('');
  };

  return (
    <Popover open={open} onOpenChange={setOpen} modal>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          role="combobox"
          aria-expanded={open}
          disabled={disabled || isLoading}
          className={cn(
            'w-full h-11 justify-between font-normal overflow-hidden',
            !value && 'text-muted-foreground'
          )}
        >
          {isLoading ? (
            <span>Đang tải...</span>
          ) : value ? (
            <div className="flex items-center gap-2 min-w-0 flex-1 overflow-hidden">
              <Folder className="h-4 w-4 shrink-0 text-muted-foreground" />
              <span className="truncate">{getCategoryPath || selectedCategory?.name}</span>
            </div>
          ) : (
            <span>{placeholder}</span>
          )}
          <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-[320px] p-0" align="start">
        <div className="p-2 border-b">
          <div className="relative">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Tìm kiếm danh mục..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-8 h-8"
            />
          </div>
        </div>
        <ScrollArea className="h-[280px]">
          <div className="p-1">
            <button
              type="button"
              className={cn(
                'w-full flex items-center gap-2 py-2 px-2 rounded-lg text-sm text-left',
                'hover:bg-primary/10 transition-all duration-150',
                !value && 'bg-primary/10'
              )}
              onClick={() => handleSelect(null)}
            >
              <div className="w-4" />
              <Badge variant="outline" className="text-xs font-normal">Không có</Badge>
              <span className="flex-1 text-muted-foreground">Danh mục gốc</span>
              {!value && <Check className="h-4 w-4 text-primary shrink-0" />}
            </button>
            {filteredCategories.length === 0 ? (
              <div className="py-6 text-center text-sm text-muted-foreground">
                Không tìm thấy danh mục
              </div>
            ) : (
              filteredCategories.map((category) => (
                <CategoryTreeNode
                  key={category._id}
                  category={category}
                  level={0}
                  selectedId={value}
                  expandedIds={expandedIds}
                  onSelect={handleSelect}
                  onToggleExpand={toggleExpand}
                />
              ))
            )}
          </div>
        </ScrollArea>
        {value && (
          <div className="p-2 border-t">
            <Button
              variant="ghost"
              size="sm"
              className="w-full text-muted-foreground"
              onClick={() => handleSelect(null)}
            >
              <X className="mr-2 h-4 w-4" />
              Xóa lựa chọn
            </Button>
          </div>
        )}
      </PopoverContent>
    </Popover>
  );
}
```

---

## Usage in a Form

```tsx
import { CategorySelector } from '@/shared/_components/form/category-selector';
import { useGetListCategories } from '@/entities/category/_apis/get-list-categories.api';

// Inside a Controller:
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
```
