# Data List Feature — 10-Step Guide

A complete guide for building a data list feature following the feature-based architecture with Dialog Registry pattern.

---

## Components Overview

| Component | Chức năng |
|---|---|
| Toolbar | Search, filters, actions |
| DataTableRenderer | Table, loading, empty, mobile cards |
| Pagination | Page navigation |
| BulkActions | Bulk operations (fixed bottom bar) |
| ProductDialogs | Dialog registry (add, edit, delete, view) |

---

## Folder Structure

```
features/product/
├── _store/
│   └── product-dialog.store.ts    # Dialog state (enum + store)
├── _ui/
│   ├── product-dialogs.tsx        # Dialog registry
│   ├── product-add-dialog.tsx     # Add dialog
│   ├── product-edit-dialog.tsx    # Edit dialog
│   └── product-delete-dialog.tsx  # Delete dialog (ConfirmDialog)
│
├── list-products/
│   ├── index.tsx                  # Main table
│   ├── products-columns.tsx       # Column definitions
│   ├── products-toolbar.tsx       # Toolbar wrapper
│   ├── products-bulk-actions.tsx  # Bulk actions wrapper
│   ├── product-row-actions.tsx    # Row action dropdown
│   └── product-mobile-card.tsx    # Mobile card

entities/product/
├── _apis/
│   ├── get-list-products.api.ts
│   ├── create-product.api.ts
│   ├── update-product.api.ts
│   ├── delete-product.api.ts
│   └── bulk-delete-products.api.ts
└── _types/
    └── product.type.ts
```

---

## Step 1: Dialog Store with Enum

Create a store with an enum defining dialog types. `open` tracks which dialog is currently open, and `currentProductId` tracks the item being edited/deleted.

```typescript
// features/product/_store/product-dialog.store.ts

import { create } from 'zustand';

export enum ProductDialogType {
  ADD = 'add',
  EDIT = 'edit',
  DELETE = 'delete',
  BULK_DELETE = 'bulk_delete',
  VIEW = 'view',
}

type ProductDialogState = {
  open: ProductDialogType | null;
  setOpen: (type: ProductDialogType | null) => void;
  currentProductId: string | null;
  setCurrentProductId: (id: string | null) => void;
};

export const useProductDialogStore = create<ProductDialogState>((set) => ({
  open: null,
  setOpen: (type) =>
    set((state) => ({
      // Toggle: if same type, close; else open new type
      open: state.open === type ? null : type,
    })),
  currentProductId: null,
  setCurrentProductId: (id) => set({ currentProductId: id }),
}));
```

---

## Step 2: Dialog Registry Component

Create a component that registers all dialogs. This component renders at route scope (page or layout).

```tsx
// features/product/_ui/product-dialogs.tsx

'use client';

import { useShallow } from 'zustand/react/shallow';
import {
  useProductDialogStore,
  ProductDialogType,
} from '../_store/product-dialog.store';
import { ProductAddDialog } from './product-add-dialog';
import { ProductEditDialog } from './product-edit-dialog';
import { ProductDeleteDialog } from './product-delete-dialog';
import { ProductBulkDeleteDialog } from './product-bulk-delete-dialog';

export function ProductDialogs() {
  const { open, setOpen, currentProductId, setCurrentProductId } =
    useProductDialogStore(
      useShallow((state) => ({
        open: state.open,
        setOpen: state.setOpen,
        currentProductId: state.currentProductId,
        setCurrentProductId: state.setCurrentProductId,
      })),
    );

  const handleClose = (type: ProductDialogType) => {
    setOpen(type);
    // Clear current ID after animation
    setTimeout(() => {
      setCurrentProductId(null);
    }, 300);
  };

  return (
    <>
      {/* Add Dialog - no product ID needed */}
      <ProductAddDialog
        open={open === ProductDialogType.ADD}
        onOpenChange={() => handleClose(ProductDialogType.ADD)}
      />

      {/* Edit/Delete/View require currentProductId */}
      {currentProductId && (
        <>
          <ProductEditDialog
            key={`edit-${currentProductId}`}
            productId={currentProductId}
            open={open === ProductDialogType.EDIT}
            onOpenChange={() => handleClose(ProductDialogType.EDIT)}
          />

          <ProductDeleteDialog
            key={`delete-${currentProductId}`}
            productId={currentProductId}
            open={open === ProductDialogType.DELETE}
            onOpenChange={() => handleClose(ProductDialogType.DELETE)}
          />
        </>
      )}

      {/* Bulk Delete - uses selection store, not currentProductId */}
      <ProductBulkDeleteDialog
        open={open === ProductDialogType.BULK_DELETE}
        onOpenChange={() => handleClose(ProductDialogType.BULK_DELETE)}
      />
    </>
  );
}
```

---

## Step 3: Delete Dialog with ConfirmDialog

The delete dialog uses `ConfirmDialog` with `variant="danger"`.

```tsx
// features/product/_ui/product-delete-dialog.tsx

'use client';

import { ConfirmDialog } from '@/components/ui/dialog/confirm-dialog/confirm-dialog';
import { useDeleteProduct } from '@/entities/product/_apis/delete-product.api';
import { useGetProductById } from '@/entities/product/_apis/get-product-by-id.api';

type ProductDeleteDialogProps = {
  productId: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
};

export function ProductDeleteDialog({
  productId,
  open,
  onOpenChange,
}: ProductDeleteDialogProps) {
  const { product } = useGetProductById(productId, { enabled: open });
  const { mutate: deleteProduct, isPending } = useDeleteProduct();

  const handleConfirm = () => {
    deleteProduct(productId, {
      onSuccess: () => onOpenChange(false),
    });
  };

  return (
    <ConfirmDialog
      open={open}
      onOpenChange={onOpenChange}
      variant="danger"
      title="Xóa sản phẩm"
      desc={
        <>
          Bạn có chắc chắn muốn xóa sản phẩm{' '}
          <strong>{product?.name}</strong>? Hành động này không thể hoàn tác.
        </>
      }
      requireConfirmText="XÓA"
      confirmText="Xóa vĩnh viễn"
      warningMessage="Dữ liệu sẽ bị xóa vĩnh viễn"
      handleConfirm={handleConfirm}
      isLoading={isPending}
    />
  );
}
```

---

## Step 4: Bulk Delete Dialog

Bulk delete reads selected IDs from the selection store — does not need `currentProductId`.

```tsx
// features/product/_ui/product-bulk-delete-dialog.tsx

'use client';

import { ConfirmDialog } from '@/components/ui/dialog/confirm-dialog/confirm-dialog';
import { useProductSelectionStore } from '../_store/product-selection.store';
import { useBulkDeleteProducts } from '@/entities/product/_apis/bulk-delete-products.api';

type Props = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
};

export function ProductBulkDeleteDialog({ open, onOpenChange }: Props) {
  const { selectedIds, clearSelection } = useProductSelectionStore();
  const { mutate, isPending } = useBulkDeleteProducts();

  const handleConfirm = () => {
    mutate(
      { ids: selectedIds },
      {
        onSuccess: () => {
          clearSelection();
          onOpenChange(false);
        },
      },
    );
  };

  return (
    <ConfirmDialog
      open={open}
      onOpenChange={onOpenChange}
      variant="danger"
      title="Xóa nhiều sản phẩm"
      desc={`Bạn có chắc chắn muốn xóa ${selectedIds.length} sản phẩm? Hành động này không thể hoàn tác.`}
      requireConfirmText="XÓA TẤT CẢ"
      confirmText="Xóa vĩnh viễn"
      warningMessage="Tất cả dữ liệu sẽ bị xóa vĩnh viễn"
      handleConfirm={handleConfirm}
      isLoading={isPending}
    />
  );
}
```

---

## Step 5: Row Actions (Open Dialogs)

Dropdown menu opens dialogs by setting the product ID and dialog type.

```tsx
// features/product/list-products/product-row-actions.tsx

'use client';

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Button } from '@/components/ui/button';
import { MoreHorizontal, Pencil, Trash2, Eye } from 'lucide-react';
import {
  useProductDialogStore,
  ProductDialogType,
} from '../_store/product-dialog.store';
import { ProductRes } from '@/entities/product/_types/product.type';

export function ProductRowActions({ product }: { product: ProductRes }) {
  const { setOpen, setCurrentProductId } = useProductDialogStore();

  const openDialog = (type: ProductDialogType) => {
    setCurrentProductId(product._id);
    setOpen(type);
  };

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon">
          <MoreHorizontal className="h-4 w-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem onClick={() => openDialog(ProductDialogType.VIEW)}>
          <Eye className="mr-2 h-4 w-4" />
          Xem chi tiết
        </DropdownMenuItem>
        <DropdownMenuItem onClick={() => openDialog(ProductDialogType.EDIT)}>
          <Pencil className="mr-2 h-4 w-4" />
          Chỉnh sửa
        </DropdownMenuItem>
        <DropdownMenuItem
          onClick={() => openDialog(ProductDialogType.DELETE)}
          className="text-destructive"
        >
          <Trash2 className="mr-2 h-4 w-4" />
          Xóa
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
```

---

## Step 6: Bulk Actions (Open Bulk Dialog)

Bulk actions open the bulk delete dialog.

```tsx
// features/product/list-products/products-bulk-actions.tsx

'use client';

import { BulkActions } from '@/components/ui/list/bulk-actions';
import { useProductSelectionStore } from '../_store/product-selection.store';
import {
  useProductDialogStore,
  ProductDialogType,
} from '../_store/product-dialog.store';
import { Trash2, Archive, Download } from 'lucide-react';
import { toast } from 'sonner';

export function ProductsBulkActions() {
  const { selectedIds, clearSelection } = useProductSelectionStore();
  const setOpen = useProductDialogStore((s) => s.setOpen);

  return (
    <BulkActions
      selectedCount={selectedIds.length}
      selectedIds={selectedIds}
      entityName="sản phẩm"
      onClearSelection={clearSelection}
      actions={[
        {
          label: 'Export',
          icon: <Download className="h-4 w-4" />,
          onClick: () => toast.success(`Exported ${selectedIds.length} products`),
        },
        {
          label: 'Xóa',
          icon: <Trash2 className="h-4 w-4" />,
          variant: 'destructive',
          onClick: () => setOpen(ProductDialogType.BULK_DELETE),
        },
      ]}
    />
  );
}
```

---

## Step 7: Register Dialogs in Route

Dialogs are rendered at route scope (page or layout), outside the table component.

```tsx
// app/dashboard/products/page.tsx

import { ProductsTable } from '@/features/product/list-products';
import { ProductDialogs } from '@/features/product/_ui/product-dialogs';

export default function ProductsPage() {
  return (
    <>
      <ProductsTable />

      {/* Dialog Registry - at route scope */}
      <ProductDialogs />
    </>
  );
}
```

---

## Step 8: Selection Store

Store for managing row selection, shared between Table and BulkActions.

```typescript
// features/product/_store/product-selection.store.ts

import { create } from 'zustand';

type ProductSelectionStore = {
  selectedIds: string[];
  setSelectedIds: (ids: string[]) => void;
  clearSelection: () => void;
};

export const useProductSelectionStore = create<ProductSelectionStore>((set) => ({
  selectedIds: [],
  setSelectedIds: (ids) => set({ selectedIds: ids }),
  clearSelection: () => set({ selectedIds: [] }),
}));
```

---

## Step 9: Toolbar Wrapper

Wrapper component for Toolbar with search, filters, and primary action.

```tsx
// features/product/list-products/products-toolbar.tsx

'use client';

import { Toolbar } from '@/components/ui/list/toolbar';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { MultiSelect } from '@/components/ui/select/multi-select';
import {
  useProductDialogStore,
  ProductDialogType,
} from '../_store/product-dialog.store';
import { Plus, Download } from 'lucide-react';
import { ProductStatus } from '@/entities/product/_types/product.type';

type ProductsToolbarProps = {
  search: string;
  onSearchChange: (value: string) => void;
  status: string;
  onStatusChange: (value: string) => void;
  categories: string[];
  onCategoriesChange: (value: string[]) => void;
  onReset: () => void;
};

export function ProductsToolbar({
  search,
  onSearchChange,
  status,
  onStatusChange,
  categories,
  onCategoriesChange,
  onReset,
}: ProductsToolbarProps) {
  const setOpen = useProductDialogStore((s) => s.setOpen);

  // Calculate active filter count
  const filterCount =
    (status && status !== 'all' ? 1 : 0) +
    (categories.length > 0 ? 1 : 0);

  return (
    <Toolbar
      searchValue={search}
      onSearchChange={onSearchChange}
      searchPlaceholder="Tìm sản phẩm..."
      onReset={onReset}
      showReset={!!search || !!status || categories.length > 0}
      filterCount={filterCount}
      filters={
        <>
          <Select value={status} onValueChange={onStatusChange}>
            <SelectTrigger className="h-9 w-[130px]">
              <SelectValue placeholder="Trạng thái" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Tất cả</SelectItem>
              <SelectItem value={ProductStatus.ACTIVE}>Đang bán</SelectItem>
              <SelectItem value={ProductStatus.DRAFT}>Nháp</SelectItem>
              <SelectItem value={ProductStatus.ARCHIVED}>Lưu trữ</SelectItem>
            </SelectContent>
          </Select>

          <MultiSelect
            options={categoryOptions}
            value={categories}
            onChange={onCategoriesChange}
            placeholder="Danh mục"
          />
        </>
      }
      actions={[
        {
          label: 'Export',
          icon: <Download className="h-4 w-4" />,
          variant: 'outline',
          onClick: () => {/* Export logic */},
        },
      ]}
      primaryAction={{
        label: 'Thêm mới',
        icon: <Plus className="h-4 w-4" />,
        onClick: () => setOpen(ProductDialogType.ADD),
      }}
    />
  );
}
```

---

## Step 10: Main Table Component

The main component only imports and composes — it contains no business logic.

```tsx
// features/product/list-products/index.tsx

'use client';

import { useState, useEffect } from 'react';
import {
  useReactTable,
  getCoreRowModel,
  getSortedRowModel,
  type SortingState,
  type RowSelectionState,
} from '@tanstack/react-table';
import { useGetListProducts } from '@/entities/product/_apis/get-list-products.api';
import { useProductSelectionStore } from '../_store/product-selection.store';
import { productColumns } from './products-columns';
import { ProductsToolbar } from './products-toolbar';
import { ProductsBulkActions } from './products-bulk-actions';
import { ProductMobileCard } from './product-mobile-card';
import { DataTableRenderer } from '@/components/ui/list/data-table-renderer';
import { Pagination } from '@/components/ui/list/pagination';
import { ProductsLoadingSkeleton } from './loading-skeleton';
import { Package } from 'lucide-react';

export function ProductsTable() {
  // Filter state
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(10);
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('');
  const [categories, setCategories] = useState<string[]>([]);
  const [sorting, setSorting] = useState<SortingState>([]);

  // Selection from store
  const { selectedIds, setSelectedIds } = useProductSelectionStore();

  // API call
  const { data, isLoading } = useGetListProducts({
    page,
    page_size: pageSize,
    search: search || undefined,
    status: status && status !== 'all' ? status : undefined,
    category_ids: categories.length > 0 ? categories : undefined,
  });

  // Reset page when filters change
  useEffect(() => {
    setPage(1);
  }, [search, status, categories]);

  // Table instance
  const table = useReactTable({
    data: data?.products ?? [],
    columns: productColumns,
    state: {
      sorting,
      rowSelection: Object.fromEntries(selectedIds.map((id) => [id, true])),
    },
    onSortingChange: setSorting,
    onRowSelectionChange: (updater) => {
      const current = Object.fromEntries(selectedIds.map((id) => [id, true]));
      const next = typeof updater === 'function' ? updater(current) : updater;
      setSelectedIds(Object.keys(next).filter((k) => next[k]));
    },
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getRowId: (row) => row._id,
    enableRowSelection: true,
    manualPagination: true,
    pageCount: data?.meta.page_count ?? 1,
  });

  const handleReset = () => {
    setSearch('');
    setStatus('');
    setCategories([]);
    setPage(1);
  };

  return (
    <div className="space-y-4">
      {/* Toolbar - search, filters, actions */}
      <ProductsToolbar
        search={search}
        onSearchChange={setSearch}
        status={status}
        onStatusChange={setStatus}
        categories={categories}
        onCategoriesChange={setCategories}
        onReset={handleReset}
      />

      {/* Table with loading, empty, mobile support */}
      <DataTableRenderer
        table={table}
        isLoading={isLoading}
        loadingSkeleton={<ProductsLoadingSkeleton />}
        emptyState={
          <div className="flex flex-col items-center py-8 text-center">
            <Package className="h-12 w-12 text-muted-foreground mb-4" />
            <h3 className="font-semibold">Chưa có sản phẩm</h3>
            <p className="text-sm text-muted-foreground">
              Thêm sản phẩm đầu tiên để bắt đầu.
            </p>
          </div>
        }
        mobileCard={(product) => <ProductMobileCard product={product} />}
      />

      {/* Pagination */}
      <Pagination
        currentPage={page}
        totalPages={data?.meta.page_count ?? 1}
        pageSize={pageSize}
        onPageChange={setPage}
        onPageSizeChange={(size) => {
          setPageSize(size);
          setPage(1);
        }}
      />

      {/* Bulk Actions - fixed bottom bar */}
      <ProductsBulkActions />
    </div>
  );
}
```

---

## Key Principles

- **Dialog Registry** — All dialogs render in one place, managed by a store
- **Enum Type** — Use enums to define dialog types, avoid magic strings
- **currentEntityId** — Store holds the ID of the entity being edited/deleted
- **Toggle Pattern** — `setOpen(type)` toggles: calling with the same type will close it
- **Route Scope** — Dialogs render at page/layout, not inside the table component
- **Cleanup** — Clear `currentEntityId` after closing the dialog

---

## Flow Diagram

```
User clicks "Xóa" in RowActions
    ↓
setCurrentProductId(product._id)
setOpen(ProductDialogType.DELETE)
    ↓
ProductDialogs sees: open === DELETE && currentProductId exists
    ↓
Renders ProductDeleteDialog with productId
    ↓
User confirms delete
    ↓
deleteProduct(productId) → onOpenChange(false)
    ↓
handleClose: setOpen(DELETE) → open = null
setTimeout: setCurrentProductId(null)
```
