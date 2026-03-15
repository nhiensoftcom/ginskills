# List Components — BulkActions, DataTableRenderer, Pagination, Toolbar

Reference for the four list UI components in `@/components/ui/list/`. Use these when building data list pages with search, filtering, pagination, and bulk operations.

---

## BulkActions

Fixed bottom toolbar that appears when items are selected. Supports keyboard navigation and accessibility.

### Features

- **Fixed position** — Always visible at bottom center
- **Keyboard navigation** — Arrow keys, Escape to clear
- **Responsive** — Icon-only on mobile, full labels on desktop
- **Accessible** — ARIA labels, live region announcements
- **Backdrop blur** — Glassmorphism effect

### Basic Usage

```tsx
import { BulkActions } from '@/components/ui/list/bulk-actions';

const [selectedIds, setSelectedIds] = useState<string[]>([]);

<BulkActions
  selectedCount={selectedIds.length}
  selectedIds={selectedIds}
  entityName="product"
  onClearSelection={() => setSelectedIds([])}
  actions={[
    {
      label: 'Xóa',
      icon: <Trash2 className="h-4 w-4" />,
      variant: 'destructive',
      onClick: (ids) => handleDelete(ids),
    },
    {
      label: 'Export',
      icon: <Download className="h-4 w-4" />,
      onClick: (ids) => handleExport(ids),
    },
  ]}
/>
```

### With TanStack Table

```tsx
// Get selected rows from TanStack Table
const selectedRows = table.getFilteredSelectedRowModel().rows;
const selectedIds = selectedRows.map((row) => row.original.id);

<BulkActions
  selectedCount={selectedRows.length}
  selectedIds={selectedIds}
  entityName="product"
  onClearSelection={() => table.resetRowSelection()}
  actions={[...]}
/>
```

### Props

```typescript
type BulkActionsProps = {
  selectedCount: number;
  selectedIds?: string[];
  entityName?: string;           // Default: 'item'
  actions?: BulkAction[];
  onClearSelection: () => void;
  children?: React.ReactNode;    // Custom content
  className?: string;
};

type BulkAction = {
  label: string;
  icon?: React.ReactNode;
  onClick: (selectedIds: string[]) => void;
  variant?: 'default' | 'outline' | 'ghost' | 'destructive';
  disabled?: boolean;
};
```

### Keyboard Shortcuts

| Key | Action |
|---|---|
| ← / → | Navigate between buttons |
| Escape | Clear selection |

---

## DataTableRenderer

Reusable wrapper for TanStack Table with loading state, empty state, and mobile card view.

### Features

- **Loading state** — Custom skeleton or default
- **Empty state** — Custom empty component or message
- **Mobile card view** — Automatically switches to cards on mobile
- **Flexible** — Works with any TanStack Table config

### Basic Usage

```tsx
import { DataTableRenderer } from '@/components/ui/list/data-table-renderer';
import { useReactTable, getCoreRowModel } from '@tanstack/react-table';

const table = useReactTable({
  data: products,
  columns: productColumns,
  getCoreRowModel: getCoreRowModel(),
});

<DataTableRenderer table={table} />
```

### With All Features

```tsx
<DataTableRenderer
  table={table}
  isLoading={isLoading}
  loadingSkeleton={<CustomSkeleton />}
  emptyState={
    <EmptyState
      icon={Package}
      title="Chưa có sản phẩm"
      description="Thêm sản phẩm để bắt đầu."
    />
  }
  mobileCard={(product) => <ProductCard product={product} />}
/>
```

### Props

```typescript
type DataTableRendererProps<TData> = {
  table: TanStackTable<TData>;       // TanStack Table instance
  isLoading?: boolean;               // Show loading state
  loadingSkeleton?: React.ReactNode; // Custom loading skeleton
  emptyState?: React.ReactNode;      // Custom empty state
  emptyMessage?: string;             // Default: 'Không có dữ liệu.'
  mobileCard?: (row: TData) => React.ReactNode; // Mobile card render
  className?: string;
};
```

### Mobile Card Pattern

When `mobileCard` is provided, the component automatically:

- Hides the table on mobile (`<768px`)
- Renders a list of cards instead
- Shows appropriate loading skeletons

```tsx
// Mobile card component
function ProductCard({ product }: { product: Product }) {
  return (
    <Card>
      <CardContent className="p-3">
        <h3>{product.name}</h3>
        <Badge>{product.status}</Badge>
        <p>{formatCurrency(product.price)}</p>
      </CardContent>
    </Card>
  );
}

// Usage
<DataTableRenderer
  table={table}
  mobileCard={(product) => <ProductCard product={product} />}
/>
```

---

## Pagination

Simple pagination component with page navigation and page size selector.

### Installation

```typescript
import { Pagination } from '@ginstudio/shadcn-ui-pro';
```

### Basic Usage

```tsx
const [currentPage, setCurrentPage] = useState(1);
const [pageSize, setPageSize] = useState(10);
const totalItems = 100;
const totalPages = Math.ceil(totalItems / pageSize);

<Pagination
  currentPage={currentPage}
  totalPages={totalPages}
  pageSize={pageSize}
  onPageChange={setCurrentPage}
  onPageSizeChange={setPageSize}
/>
```

### Without Page Size Selector

Omit `onPageSizeChange` to hide the page size selector:

```tsx
<Pagination
  currentPage={currentPage}
  totalPages={10}
  pageSize={10}
  onPageChange={setCurrentPage}
/>
```

### With TanStack Table

```tsx
const table = useReactTable({ ... });

<Pagination
  currentPage={table.getState().pagination.pageIndex + 1}
  totalPages={table.getPageCount()}
  pageSize={table.getState().pagination.pageSize}
  onPageChange={(page) => table.setPageIndex(page - 1)}
  onPageSizeChange={(size) => table.setPageSize(size)}
/>
```

### Props

```typescript
type PaginationProps = {
  currentPage: number;           // Trang hiện tại (1-indexed)
  totalPages: number;            // Tổng số trang
  pageSize: number;              // Số item mỗi trang
  pageSizeOptions?: number[];    // Mặc định: [10, 20, 30, 40, 50, 100]
  onPageChange: (page: number) => void;
  onPageSizeChange?: (pageSize: number) => void;
  className?: string;
};
```

---

## Toolbar

Smart responsive toolbar with search, filters, and actions. Automatically optimized for mobile.

### Features

- **Collapsible search** — On mobile, search shows as icon and expands on click
- **Smart actions** — Secondary actions collapse to dropdown menu on mobile
- **Primary action** — Always visible, icon-only on mobile
- **Flexible filters** — Pass any filter components via `filters` prop

### Basic Usage

```tsx
import { Toolbar } from '@/components/ui/list/toolbar';

const [search, setSearch] = useState('');

<Toolbar
  searchValue={search}
  onSearchChange={setSearch}
  searchPlaceholder="Tìm kiếm..."
  onReset={() => setSearch('')}
/>
```

### With Filters

```tsx
<Toolbar
  searchValue={search}
  onSearchChange={setSearch}
  filters={
    <>
      <Select value={status} onValueChange={setStatus}>
        <SelectTrigger className="h-9 w-[120px]">
          <SelectValue placeholder="Trạng thái" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">Tất cả</SelectItem>
          <SelectItem value="active">Hoạt động</SelectItem>
        </SelectContent>
      </Select>
    </>
  }
/>
```

### With Actions (Smart Mobile)

`actions` array for secondary actions — automatically collapses to a dropdown on mobile. `primaryAction` for the main action — always visible, icon-only on mobile.

```tsx
<Toolbar
  searchValue={search}
  onSearchChange={setSearch}
  actions={[
    { label: 'Export', icon: <Download className="h-4 w-4" />, variant: 'outline' },
    { label: 'Print', icon: <Printer className="h-4 w-4" />, variant: 'outline' },
  ]}
  primaryAction={{
    label: 'Thêm mới',
    icon: <Plus className="h-4 w-4" />,
    onClick: handleAdd,
  }}
/>
```

### Props

```typescript
type ToolbarProps = {
  searchValue?: string;
  onSearchChange?: (value: string) => void;
  searchPlaceholder?: string;
  onReset?: () => void;
  showReset?: boolean;
  filters?: React.ReactNode;
  filterCount?: number; // Badge on mobile filter button
  actions?: ToolbarAction[];
  primaryAction?: ToolbarAction;
  className?: string;
};

type ToolbarAction = {
  label: string;
  icon?: React.ReactNode;
  onClick?: () => void;
  variant?: 'default' | 'outline' | 'ghost' | 'destructive';
};
```

### Responsive Behavior

| Feature | Mobile (<640px) | Desktop (≥640px) |
|---|---|---|
| Search | Icon → expands on click | Full input visible |
| Actions | Dropdown menu (⋮) | Individual buttons |
| Primary Action | Icon only | Icon + label |
| Filters | Always visible | Always visible |
