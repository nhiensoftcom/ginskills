# Active Life Backend - Products & Catalog

## Product Architecture

```
Category (hierarchical tree)
    └──< CategoryBrand >── Brand
    └──< ProductCategory >── StoreProduct
                                └──< StoreProductCombo (pricing/bundle)
                                        └──< StoreProductComboItem ──> InventoryProduct
                                        └──< StoreProductComboItem (gifts) ──> InventoryProduct
```

### Key Concept: Product vs Combo vs Inventory Product

- **StoreProduct** — What customers see (name, images, description, status)
- **StoreProductCombo** — A purchasable configuration with price (e.g., "Pack of 3", "Family Bundle")
- **StoreProductComboItem** — Links combo to warehouse inventory products with quantities
- **InventoryProduct** — Actual warehouse item (SKU, barcode, unit, brand)

**Example**:
```
StoreProduct: "Whey Protein Gold Standard"
  ├── Combo: "1kg Bag" — price: 500,000 VND
  │     └── Item: InventoryProduct("WP-GS-1KG") × 1
  ├── Combo: "2kg Bag + Shaker" — price: 900,000 VND
  │     ├── Item: InventoryProduct("WP-GS-2KG") × 1
  │     └── Gift: InventoryProduct("SHAKER-01") × 1
  └── Combo: "5kg Bulk" — price: 2,000,000 VND
        └── Item: InventoryProduct("WP-GS-1KG") × 5
```

## Categories

### Hierarchical Structure (Parent-Child)
```prisma
model Category {
  id       String     @id @default(uuid())
  name     String
  slug     String     @unique
  parentId String?
  parent   Category?  @relation("CategoryTree", fields: [parentId], references: [id])
  children Category[] @relation("CategoryTree")
}
```

**Example tree**:
```
Supplements
  ├── Protein
  │     ├── Whey Protein
  │     └── Casein Protein
  ├── Pre-Workout
  └── Vitamins
Equipment
  ├── Weights
  └── Accessories
```

### Recursive Category Queries
The service uses raw SQL for recursive queries to get full category trees:
```sql
WITH RECURSIVE category_tree AS (
  SELECT * FROM "Category" WHERE "parentId" IS NULL
  UNION ALL
  SELECT c.* FROM "Category" c
  JOIN category_tree ct ON c."parentId" = ct.id
)
SELECT * FROM category_tree;
```

### Category-Brand Relationship
Many-to-many via `CategoryBrand` join table. A category can have multiple brands, and a brand can appear in multiple categories.

## Products

### StoreProduct Model
```prisma
model StoreProduct {
  id          String        @id @default(uuid())
  name        String
  slug        String        @unique
  description String?
  images      String[]                         // Array of image URLs
  status      ProductStatus @default(NORMAL)   // HIDDEN, NORMAL, HIGH
}
```

### Product Status
- `HIDDEN` — Not visible to customers
- `NORMAL` — Standard visibility
- `HIGH` — Featured/promoted product

### Creating a Product
```
POST /api/v1/product
Body: {
  name: "Whey Protein Gold Standard",
  description: "Premium whey protein...",
  images: ["url1", "url2"],
  categoryIds: ["cat-uuid-1", "cat-uuid-2"],
  status: "NORMAL"
}
```
Auto-generates slug from name (Vietnamese diacritics removed).

## Combos (Product Pricing)

### StoreProductCombo Model
```prisma
model StoreProductCombo {
  id           String  @id @default(uuid())
  name         String
  price        Float
  comparePrice Float?   // "Was" price for showing discounts
  productId    String
  items        StoreProductComboItem[]       // Regular items
  giftItems    StoreProductComboItem[]       // Gift items
}
```

### Creating a Combo
```
POST /api/v1/product/:id/combo
Body: {
  name: "1kg Bag",
  price: 500000,
  comparePrice: 600000,
  items: [
    { inventoryProductId: "inv-uuid", quantity: 1 }
  ]
}
```

### Adding Gift Items
```
POST /api/v1/product/:id/combo/:comboId/gift
Body: {
  items: [
    { inventoryProductId: "shaker-uuid", quantity: 1 }
  ]
}
```

### Promotion History
When combo price changes, a history record is created:
```prisma
model StoreProductComboPromotionHistory {
  comboId   String
  oldPrice  Float
  newPrice  Float
  reason    String?
  createdAt DateTime @default(now())
}
```

## Brands

```prisma
model Brand {
  id          String @id @default(uuid())
  name        String
  slug        String @unique
  image       String?
  description String?
}
```

## Key API Endpoints

### Products
```
GET    /api/v1/product              — List products (public, paginated)
GET    /api/v1/product/:id          — Get product detail (public)
GET    /api/v1/product/slug/:slug   — Get by slug (public)
POST   /api/v1/product              — Create product (staff)
PATCH  /api/v1/product/:id          — Update product (staff)
DELETE /api/v1/product/:id          — Delete product (staff)
```

### Combos
```
POST   /api/v1/product/:id/combo           — Add combo to product
PATCH  /api/v1/product/:id/combo/:comboId  — Update combo
DELETE /api/v1/product/:id/combo/:comboId  — Delete combo
POST   /api/v1/product/:id/combo/:comboId/gift — Add gift items
```

### Categories
```
GET    /api/v1/category             — List categories (tree structure, public)
GET    /api/v1/category/:id         — Get category with products (public)
POST   /api/v1/category             — Create category (staff)
PATCH  /api/v1/category/:id         — Update category (staff)
DELETE /api/v1/category/:id         — Delete category (staff)
```

### Brands
```
GET    /api/v1/brand                — List brands (public)
POST   /api/v1/brand                — Create brand (staff)
PATCH  /api/v1/brand/:id            — Update brand (staff)
DELETE /api/v1/brand/:id            — Delete brand (staff)
```

## Shopping Cart Integration

Cart items reference both product and combo:
```prisma
model CartItem {
  productId String
  comboId   String
  quantity  Int
}
```
Customers add combos to cart, not raw products.
