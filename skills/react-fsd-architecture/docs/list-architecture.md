# List Architecture (scrape-video project)

> TanStack Table v8 + dialog store + bulk actions pattern for CRUD list pages.

---

## Feature Folder Structure

```
features/{domain}-list/  (e.g., list-facebook-vias/)
├── _store/
│   └── via-dialog.store.ts         ← Zustand dialog state — INSIDE the slice, not parent
├── _ui/
│   ├── {entity}-columns.tsx        ← ColumnDef[] with row actions
│   ├── data-table-bulk-actions.tsx ← Feature-level bulk action bar
│   └── delete-{entities}-multi-dialog.tsx  ← Bulk delete confirm dialog
├── edit-{entity}/
│   ├── _ui/
│   │   └── edit-{entity}-form/     ← RHF 3-layer form (see form-architecture.md)
│   └── index.tsx                   ← Edit dialog container (Layer 3)
└── index.tsx                       ← Page/feature root — table + dialogs
```

---

## Dialog Store (`_store/via-dialog.store.ts`)

Use Zustand to track which dialog is open and which row is selected. One store per feature list.

```typescript
import { create } from "zustand";

export enum ViaDialogType {
  EDIT = "edit",
  // ADD future dialogs here: DELETE_MULTI = "delete-multi"
}

interface ViaDialogState {
  open: ViaDialogType | null;
  setOpen: (type: ViaDialogType | null) => void;
  currentRow: FacebookViaRes | null;
  setCurrentRow: (row: FacebookViaRes | null) => void;
}

export const useViaDialogStore = create<ViaDialogState>((set) => ({
  open: null,
  setOpen: (type) =>
    set((state) => ({ open: state.open === type ? null : type })),
  currentRow: null,
  setCurrentRow: (row) => set({ currentRow: row }),
}));
```

**Rules:**
- Dialog open state is an enum (not boolean) — allows multiple dialogs per feature
- `setOpen` toggles: calling with the same type closes it
- `currentRow` carries the entity row that was acted on

---

## Column Definitions (`_ui/{entity}-columns.tsx`)

```typescript
import { ColumnDef } from "@tanstack/react-table";
import { Checkbox } from "@/shared/components/shadcn/checkbox";
import { useShallow } from "zustand/react/shallow";

// RowActions is a separate component so it can use hooks
function RowActions({ via }: { via: FacebookViaRes }) {
  const { deleteFacebookVia, isDeletingFacebookVia } = useDeleteFacebookVia();
  const { setOpen, setCurrentRow } = useViaDialogStore(
    useShallow((s) => ({ setOpen: s.setOpen, setCurrentRow: s.setCurrentRow }))
  );

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon">
          <MoreHorizontal className="h-4 w-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem
          onClick={() => {
            setCurrentRow(via);
            setOpen(ViaDialogType.EDIT);
          }}
        >
          <Pencil className="mr-2 h-4 w-4" /> Chỉnh sửa
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem
          className="text-destructive"
          disabled={isDeletingFacebookVia}
          onClick={() => deleteFacebookVia({ _id: via._id })}
        >
          <Trash2 className="mr-2 h-4 w-4" /> Xóa
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

export const facebookViasColumns: ColumnDef<FacebookViaRes>[] = [
  // Checkbox column — always first
  {
    id: "select",
    header: ({ table }) => (
      <Checkbox
        checked={
          table.getIsAllPageRowsSelected() ||
          (table.getIsSomePageRowsSelected() && "indeterminate")
        }
        onCheckedChange={(value) => table.toggleAllPageRowsSelected(!!value)}
        aria-label="Select all"
      />
    ),
    cell: ({ row }) => (
      <Checkbox
        checked={row.getIsSelected()}
        onCheckedChange={(value) => row.toggleSelected(!!value)}
        aria-label="Select row"
      />
    ),
    enableSorting: false,
    enableHiding: false,
    size: 40,
  },
  {
    accessorKey: "uid",
    header: "UID",
  },
  {
    id: "actions",
    cell: ({ row }) => <RowActions via={row.original} />,
    size: 40,
  },
];
```

**Rules:**
- Use `useShallow` when selecting multiple values from Zustand store (avoids unnecessary rerenders)
- `RowActions` is a named component, not an anonymous arrow function — allows hooks
- Checkbox column is always the first column with `id: "select"`

---

## Feature Root (`index.tsx`)

```typescript
export function ListFacebookVias() {
  const { facebookVias, isLoadingFacebookVias } = useGetListFacebookVias();

  // Row selection state lives here
  const [rowSelection, setRowSelection] = useState<RowSelectionState>({});

  const table = useReactTable({
    data: facebookVias ?? [],
    columns: facebookViasColumns,
    getCoreRowModel: getCoreRowModel(),
    // Row selection
    enableRowSelection: true,
    onRowSelectionChange: setRowSelection,
    state: { rowSelection },
  });

  // Dialog state from store
  const { open, currentRow, setOpen } = useViaDialogStore(
    useShallow((s) => ({ open: s.open, currentRow: s.currentRow, setOpen: s.setOpen }))
  );

  return (
    <div>
      {/* Toolbar */}
      <DataTableToolbar table={table} />

      {/* Table */}
      <DataTable table={table} isLoading={isLoadingFacebookVias}>
        {/* Bulk action floating bar */}
        <DataTableBulkActions table={table} />
      </DataTable>

      {/* Dialogs */}
      <EditFacebookViaDialog
        via={currentRow}
        open={open === ViaDialogType.EDIT}
        onOpenChange={(s) => { if (!s) setOpen(null); }}
      />
    </div>
  );
}
```

**`data-state` on rows** — required for selection highlight:
```typescript
// Inside DataTable's row render:
<TableRow
  key={row.id}
  data-state={row.getIsSelected() && "selected"}
>
```

---

## Bulk Actions Bar (`_ui/data-table-bulk-actions.tsx`)

Feature-level wrapper around the shared `BulkActionsToolbar`:

```typescript
import { Table } from "@tanstack/react-table";
import { BulkActionsToolbar } from "@/shared/components/data-table/bulk-actions";

interface Props {
  table: Table<FacebookViaRes>;
}

export function DataTableBulkActions({ table }: Props) {
  const [showDeleteDialog, setShowDeleteDialog] = useState(false);
  const selectedRows = table.getFilteredSelectedRowModel().rows;

  if (selectedRows.length === 0) return null;

  return (
    <>
      <BulkActionsToolbar table={table}>
        <Button
          variant="destructive"
          size="sm"
          onClick={() => setShowDeleteDialog(true)}
        >
          <Trash2 className="mr-2 h-4 w-4" />
          Xóa ({selectedRows.length})
        </Button>
      </BulkActionsToolbar>

      <DeleteFacebookViasMultiDialog
        vias={selectedRows.map((r) => r.original)}
        open={showDeleteDialog}
        onOpenChange={setShowDeleteDialog}
        onSuccess={() => table.resetRowSelection()}
      />
    </>
  );
}
```

---

## Bulk Delete Confirm Dialog (`_ui/delete-{entities}-multi-dialog.tsx`)

```typescript
interface Props {
  vias: FacebookViaRes[];
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSuccess: () => void;
}

export function DeleteFacebookViasMultiDialog({ vias, open, onOpenChange, onSuccess }: Props) {
  const { batchDeleteFacebookVias, isBatchDeletingFacebookVias } = useBatchDeleteFacebookVias();

  const handleConfirm = async () => {
    await batchDeleteFacebookVias({ ids: vias.map((v) => v._id) });
    onSuccess();
    onOpenChange(false);
  };

  return (
    <ConfirmDialog
      open={open}
      onOpenChange={onOpenChange}
      title={`Xóa ${vias.length} via?`}
      description="Hành động này không thể hoàn tác."
      confirmText="Xóa"
      confirmVariant="destructive"
      onConfirm={handleConfirm}
      isLoading={isBatchDeletingFacebookVias}
    />
  );
}
```

---

## Batch Delete API Hook (`entities/{entity}/_apis/batch-delete-{entities}.api.ts`)

```typescript
import { useMutation, useQueryClient } from "@tanstack/react-query";
import axiosInstance from "@/shared/libs/axios";
import { QK_LIST_FACEBOOK_VIAS } from "./get-list-facebook-vias.api";

export const useBatchDeleteFacebookVias = () => {
  const queryClient = useQueryClient();

  const { mutateAsync, isPending } = useMutation({
    mutationFn: async ({ ids }: { ids: string[] }) => {
      // Parallel individual deletes (no batch endpoint needed)
      await Promise.all(
        ids.map((id) =>
          axiosInstance.delete(`/api/v1/facebook-auto-post/vias/${id}`)
        )
      );
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: [QK_LIST_FACEBOOK_VIAS] });
    },
  });

  return {
    batchDeleteFacebookVias: mutateAsync,
    isBatchDeletingFacebookVias: isPending,
  };
};
```

---

## Anti-Patterns

```typescript
// ❌ Boolean dialog open state per dialog — doesn't scale
const [isEditOpen, setIsEditOpen] = useState(false);
const [isDeleteOpen, setIsDeleteOpen] = useState(false);
// ✅ Enum-based dialog store handles all dialogs per feature

// ❌ Row selection state in Zustand store
// ✅ Row selection state as local useState in the feature root

// ❌ RowActions as anonymous arrow in ColumnDef (can't use hooks)
cell: ({ row }) => {
  const { deleteFacebookVia } = useDeleteFacebookVia(); // ← breaks rules of hooks
}
// ✅ Named component: function RowActions({ via }) { ... }

// ❌ Missing useShallow when selecting multiple Zustand values
const { open, currentRow } = useViaDialogStore(); // re-renders on any state change
// ✅ useShallow((s) => ({ open: s.open, currentRow: s.currentRow }))

// ❌ Missing data-state on row — selection highlight won't show
<TableRow key={row.id}>
// ✅ <TableRow data-state={row.getIsSelected() && "selected"}>
```
