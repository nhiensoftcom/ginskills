# Active Life Backend - Inventory System

## Architecture

```
InventoryProduct (warehouse item: SKU, barcode, unit, brand)
    ├──< ProductInventoryItem (individual lots with expiry dates)
    └──< InventoryTransaction (import/export records)
              └──> InventorySession (batch import/export session)
```

## Key Concept: Inventory vs Store Products

- **InventoryProduct** — Physical warehouse items (raw materials, actual stock)
- **StoreProduct** — Customer-facing products (may combine multiple inventory products via combos)
- **ProductInventoryItem** — Individual lot/batch with quantity, expiry date, lot number

**Example**:
```
InventoryProduct: "Whey Protein Gold Standard 1kg"
  ├── Lot #1: qty=50, expires=2025-06-01, remaining=45
  ├── Lot #2: qty=100, expires=2025-09-01, remaining=100
  └── Lot #3: qty=75, expires=2025-12-01, remaining=75
```

## Models

### InventoryProduct
```prisma
model InventoryProduct {
  id      String  @id @default(uuid())
  name    String
  sku     String? @unique
  barcode String?
  image   String?
  unitId  String?
  brandId String?
  // Relations
  unit    Unit?   @relation(...)
  brand   Brand?  @relation(...)
  items   ProductInventoryItem[]
  transactions InventoryTransaction[]
  comboItems   StoreProductComboItem[]
}
```

### ProductInventoryItem (Lot/Batch)
```prisma
model ProductInventoryItem {
  id                  String    @id @default(uuid())
  inventoryProductId  String
  quantity            Int       // Original imported quantity
  remainingQuantity   Int       // Current remaining
  expiryDate          DateTime?
  lotNumber           String?
  createdAt           DateTime  @default(now())
  updatedAt           DateTime  @updatedAt
}
```

### InventorySession
```prisma
model InventorySession {
  id           String                    @id @default(uuid())
  type         InventoryTransactionType  // IMPORT or EXPORT
  note         String?
  userId       String                    // Staff who created
  transactions InventoryTransaction[]
  createdAt    DateTime                  @default(now())
}
```

### InventoryTransaction
```prisma
model InventoryTransaction {
  id                  String   @id @default(uuid())
  sessionId           String
  inventoryProductId  String
  quantity            Int
  expiryDate          DateTime?
  lotNumber           String?
  orderItemId         String?   // Links to OrderItem when exporting for orders
  createdAt           DateTime  @default(now())
}
```

## Inventory Operations

### Import (Stock In)
```
POST /api/v1/inventory/import
Body: CreateInventorySessionDto {
  type: "IMPORT",
  note: "Weekly stock delivery",
  items: [
    {
      inventoryProductId: "uuid",
      quantity: 100,
      expiryDate: "2025-12-01",
      lotNumber: "LOT-2025-001"
    }
  ]
}
```

**What happens**:
1. Creates `InventorySession` (type=IMPORT)
2. For each item:
   - Creates `InventoryTransaction` record
   - Creates or updates `ProductInventoryItem` (lot)
   - Adds quantity to the lot

### Export (Stock Out - Manual)
```
POST /api/v1/inventory/export
Body: CreateInventorySessionDto {
  type: "EXPORT",
  note: "Damaged goods removal",
  items: [
    { inventoryProductId: "uuid", quantity: 5 }
  ]
}
```

### Export via Order Processing
When staff processes an order, they select specific lots:
```
PATCH /api/v1/order/:id/process
Body: {
  items: [{
    orderItemId: "order-item-uuid",
    lots: [{
      inventoryItemId: "lot-uuid",    // ProductInventoryItem
      quantity: 2
    }]
  }]
}
```

**What happens**:
1. Creates `InventorySession` (type=EXPORT)
2. For each lot selection:
   - Deducts `remainingQuantity` from `ProductInventoryItem`
   - Creates `InventoryTransaction` with `orderItemId` link
3. Order status → PROCESSING

### Inventory Reversal (Order Cancellation)
When a PROCESSING order is cancelled:
1. Finds all `InventoryTransaction` records for the order
2. Adds quantities back to `ProductInventoryItem.remainingQuantity`
3. Marks transactions as reversed

## Valid Items Query

Get non-expired inventory items with remaining stock:
```
GET /api/v1/inventory-product/:id/valid-items
```

Returns `ProductInventoryItem[]` where:
- `remainingQuantity > 0`
- `expiryDate > now()` (or no expiry date)
- Sorted by expiry date ASC (FIFO)

## Key API Endpoints

### Inventory Products (Warehouse Items)
```
GET    /api/v1/inventory-product           — List all inventory products
GET    /api/v1/inventory-product/:id       — Get with stock details
POST   /api/v1/inventory-product           — Create warehouse item
PATCH  /api/v1/inventory-product/:id       — Update warehouse item
DELETE /api/v1/inventory-product/:id       — Delete warehouse item
GET    /api/v1/inventory-product/:id/valid-items — Get non-expired lots
```

### Inventory Sessions (Import/Export)
```
GET    /api/v1/inventory                   — List sessions
GET    /api/v1/inventory/:id               — Get session with transactions
POST   /api/v1/inventory/import            — Import stock
POST   /api/v1/inventory/export            — Export stock (manual)
```

## Business Rules

1. **FIFO** — Use oldest lots first (sorted by expiry date)
2. **Expiry tracking** — Items past expiry should not be sold
3. **Lot traceability** — Every export links back to specific lots
4. **Order linking** — Export transactions link to order items for audit
5. **Reversal support** — Cancelled orders restore inventory
6. **Stock check** — Cannot export more than remaining quantity
