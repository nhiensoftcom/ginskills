# Active Life Backend - Prisma Database Schema

## Location
`prisma/schema.prisma`

## Database
PostgreSQL via Supabase with `@prisma/adapter-pg`

## Enums

```prisma
enum RewardType { POINT, VOUCHER }
enum VoucherType { PERCENT, FIXED }
enum OrderStatus {
  PENDING, PROCESSING, SHIPPED, DELIVERED, CANCELLED,
  REFUNDED, RETURN_PENDING, RETURN_RECEIVED, RETURN_REJECTED, REFUND_PENDING
}
enum PaymentMethod { CASH, TRANSFER }
enum InventoryTransactionType { IMPORT, EXPORT }
enum LogOrderType {
  CREATE, PROCESS, SHIP, DELIVER, CANCEL_CLIENT, CANCEL_STAFF,
  RETURN, RETURN_CREATE, RETURN_RECEIVE, RETURN_COMPLETE,
  REFUND, REFUND_CREATE, REFUND_COMPLETE
}
enum ProductStatus { HIDDEN, NORMAL, HIGH }
```

## Models (36 total)

### Core: Role & User (Staff)

```prisma
model Role {
  id          String   @id @default(uuid())
  name        String   @unique   // Admin, TeleSales, LiveChat, Agency
  permissions String[]
  users       User[]
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt
}

model User {
  id         String   @id @default(uuid())
  phone      String   @unique
  email      String?  @unique
  name       String
  password   String
  avatar     String?
  isBan      Boolean  @default(false)
  roleId     String
  role       Role     @relation(fields: [roleId], references: [id])
  extension  EtelecomExtension?  // 1-to-1 SIP extension
  createdAt  DateTime @default(now())
  updatedAt  DateTime @updatedAt
}
```

### Core: Client (Customer)

```prisma
model Client {
  id                    String    @id @default(uuid())
  phone                 String    @unique
  email                 String?
  name                  String
  password              String?
  avatar                String?
  dob                   DateTime?
  gender                String?
  address               String?
  province              String?
  district              String?
  ward                  String?
  point                 Int       @default(0)
  isBan                 Boolean   @default(false)
  note                  String?
  tags                  String[]
  // CRM fields
  customerSourceId      String?
  customerStatusId      String?
  customerDetailStatusId String?
  livechatStaffId       String?
  telesalesStaffId      String?
  agencyStaffId         String?
  firstCallAt           DateTime?
  lastOrderAt           DateTime?
  // Relations
  orders                Order[]
  cart                  Cart?
  vouchers              ClientVoucher[]
  bank                  ClientBank?
  spinTransactions      SpinTransaction[]
  redeemTransactions    RedeemTransaction[]
  createdAt             DateTime @default(now())
  updatedAt             DateTime @updatedAt
}
```

### CRM Lookup Tables

```prisma
model CustomerSource {
  id          String   @id @default(uuid())
  name        String   @unique
  description String?
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt
}

model CustomerStatus {
  id          String   @id @default(uuid())
  name        String   @unique
  description String?
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt
}

model CustomerDetailStatus {
  id          String   @id @default(uuid())
  name        String   @unique
  description String?
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt
}

model InteractionStatus { /* same shape */ }
model InteractionResult { /* same shape */ }
model AdsSource { /* same shape */ }
```

### Product Catalog

```prisma
model Category {
  id          String    @id @default(uuid())
  name        String
  slug        String    @unique
  image       String?
  description String?
  parentId    String?
  parent      Category?  @relation("CategoryTree", fields: [parentId], references: [id])
  children    Category[] @relation("CategoryTree")
  brands      CategoryBrand[]
  products    ProductCategory[]
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt
}

model Brand {
  id          String   @id @default(uuid())
  name        String
  slug        String   @unique
  image       String?
  description String?
  categories  CategoryBrand[]
  inventoryProducts InventoryProduct[]
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt
}

model CategoryBrand {
  id         String   @id @default(uuid())
  categoryId String
  brandId    String
  category   Category @relation(fields: [categoryId], references: [id])
  brand      Brand    @relation(fields: [brandId], references: [id])
  @@unique([categoryId, brandId])
}

model Unit {
  id           String   @id @default(uuid())
  name         String   @unique
  abbreviation String?
  createdAt    DateTime @default(now())
  updatedAt    DateTime @updatedAt
}
```

### Store Products & Combos

```prisma
model StoreProduct {
  id          String   @id @default(uuid())
  name        String
  slug        String   @unique
  description String?
  images      String[]
  status      ProductStatus @default(NORMAL)
  categories  ProductCategory[]
  combos      StoreProductCombo[]
  cartItems   CartItem[]
  orderItems  OrderItem[]
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt
}

model ProductCategory {
  id         String       @id @default(uuid())
  productId  String
  categoryId String
  product    StoreProduct @relation(fields: [productId], references: [id])
  category   Category     @relation(fields: [categoryId], references: [id])
  @@unique([productId, categoryId])
}

model StoreProductCombo {
  id           String   @id @default(uuid())
  name         String
  price        Float
  comparePrice Float?
  productId    String
  product      StoreProduct @relation(fields: [productId], references: [id])
  items        StoreProductComboItem[]
  giftItems    StoreProductComboItem[] @relation("GiftItems")
  promotionHistory StoreProductComboPromotionHistory[]
  cartItems    CartItem[]
  orderItems   OrderItem[]
  createdAt    DateTime @default(now())
  updatedAt    DateTime @updatedAt
}

model StoreProductComboItem {
  id                  String   @id @default(uuid())
  comboId             String?
  giftComboId         String?
  inventoryProductId  String
  quantity            Int
  combo               StoreProductCombo? @relation(fields: [comboId], references: [id])
  giftCombo           StoreProductCombo? @relation("GiftItems", fields: [giftComboId], references: [id])
  inventoryProduct    InventoryProduct   @relation(fields: [inventoryProductId], references: [id])
}

model StoreProductComboPromotionHistory {
  id        String   @id @default(uuid())
  comboId   String
  oldPrice  Float
  newPrice  Float
  reason    String?
  combo     StoreProductCombo @relation(fields: [comboId], references: [id])
  createdAt DateTime @default(now())
}
```

### Inventory System

```prisma
model InventoryProduct {
  id         String   @id @default(uuid())
  name       String
  sku        String?  @unique
  barcode    String?
  image      String?
  unitId     String?
  brandId    String?
  unit       Unit?    @relation(fields: [unitId], references: [id])
  brand      Brand?   @relation(fields: [brandId], references: [id])
  comboItems StoreProductComboItem[]
  items      ProductInventoryItem[]
  transactions InventoryTransaction[]
  createdAt  DateTime @default(now())
  updatedAt  DateTime @updatedAt
}

model ProductInventoryItem {
  id                  String   @id @default(uuid())
  inventoryProductId  String
  quantity            Int
  remainingQuantity   Int
  expiryDate          DateTime?
  lotNumber           String?
  inventoryProduct    InventoryProduct @relation(fields: [inventoryProductId], references: [id])
  createdAt           DateTime @default(now())
  updatedAt           DateTime @updatedAt
}

model InventorySession {
  id           String   @id @default(uuid())
  type         InventoryTransactionType
  note         String?
  userId       String   // Staff who created
  transactions InventoryTransaction[]
  createdAt    DateTime @default(now())
}

model InventoryTransaction {
  id                  String   @id @default(uuid())
  sessionId           String
  inventoryProductId  String
  quantity            Int
  expiryDate          DateTime?
  lotNumber           String?
  session             InventorySession   @relation(fields: [sessionId], references: [id])
  inventoryProduct    InventoryProduct   @relation(fields: [inventoryProductId], references: [id])
  orderItemId         String?            // Links to order item when exporting
  createdAt           DateTime @default(now())
}
```

### Shopping Cart

```prisma
model Cart {
  id        String     @id @default(uuid())
  clientId  String     @unique
  client    Client     @relation(fields: [clientId], references: [id])
  items     CartItem[]
  createdAt DateTime   @default(now())
  updatedAt DateTime   @updatedAt
}

model CartItem {
  id        String            @id @default(uuid())
  cartId    String
  productId String
  comboId   String
  quantity  Int
  cart      Cart              @relation(fields: [cartId], references: [id])
  product   StoreProduct      @relation(fields: [productId], references: [id])
  combo     StoreProductCombo @relation(fields: [comboId], references: [id])
  createdAt DateTime          @default(now())
  updatedAt DateTime          @updatedAt
}
```

### Orders

```prisma
model Order {
  id              String        @id @default(uuid())
  orderCode       String        @unique
  clientId        String
  status          OrderStatus   @default(PENDING)
  paymentMethod   PaymentMethod
  totalAmount     Float
  discountAmount  Float         @default(0)
  finalAmount     Float
  shippingAddress String?
  shippingFee     Float         @default(0)
  note            String?
  voucherId       String?
  staffId         String?       // Staff who processed
  client          Client        @relation(fields: [clientId], references: [id])
  items           OrderItem[]
  logs            LogOrder[]
  createdAt       DateTime      @default(now())
  updatedAt       DateTime      @updatedAt
}

model OrderItem {
  id        String            @id @default(uuid())
  orderId   String
  productId String
  comboId   String
  quantity  Int
  price     Float
  order     Order             @relation(fields: [orderId], references: [id])
  product   StoreProduct      @relation(fields: [productId], references: [id])
  combo     StoreProductCombo @relation(fields: [comboId], references: [id])
  createdAt DateTime          @default(now())
}

model LogOrder {
  id        String       @id @default(uuid())
  orderId   String
  type      LogOrderType
  note      String?
  userId    String?      // Staff who made the change
  order     Order        @relation(fields: [orderId], references: [id])
  createdAt DateTime     @default(now())
}
```

### Vouchers & Rewards

```prisma
model Voucher {
  id          String      @id @default(uuid())
  code        String      @unique
  type        VoucherType
  value       Float       // Percentage or fixed amount
  minOrder    Float?      // Minimum order to use
  maxDiscount Float?      // Max discount (for PERCENT type)
  quantity    Int         // Total available
  usedCount   Int         @default(0)
  expiryDate  DateTime?
  isActive    Boolean     @default(true)
  clients     ClientVoucher[]
  createdAt   DateTime    @default(now())
  updatedAt   DateTime    @updatedAt
}

model ClientVoucher {
  id        String   @id @default(uuid())
  clientId  String
  voucherId String
  isUsed    Boolean  @default(false)
  usedAt    DateTime?
  client    Client   @relation(fields: [clientId], references: [id])
  voucher   Voucher  @relation(fields: [voucherId], references: [id])
  @@unique([clientId, voucherId])
}

model SpinReward {
  id          String     @id @default(uuid())
  name        String
  type        RewardType
  value       Float      // Points or voucher value
  probability Float      // 0-100 chance
  isActive    Boolean    @default(true)
  transactions SpinTransaction[]
  createdAt   DateTime   @default(now())
  updatedAt   DateTime   @updatedAt
}

model SpinTransaction {
  id        String     @id @default(uuid())
  clientId  String
  rewardId  String
  client    Client     @relation(fields: [clientId], references: [id])
  reward    SpinReward @relation(fields: [rewardId], references: [id])
  createdAt DateTime   @default(now())
}

model RedeemTransaction {
  id          String   @id @default(uuid())
  clientId    String
  points      Int
  description String?
  client      Client   @relation(fields: [clientId], references: [id])
  createdAt   DateTime @default(now())
}
```

### eTelecom Integration

```prisma
model EtelecomExtension {
  id                String   @id @default(uuid())
  extensionNumber   String   @unique
  extensionPassword String
  tenantId          String?
  tenantDomain      String?
  userId            String?  @unique  // 1-to-1 with User
  user              User?    @relation(fields: [userId], references: [id])
  createdAt         DateTime @default(now())
  updatedAt         DateTime @updatedAt
}

model OmiCall {
  id            String   @id @default(uuid())
  callId        String   @unique
  direction     String   // inbound/outbound
  fromNumber    String
  toNumber      String
  status        String   // answered, missed, busy
  duration      Int?     // seconds
  recordingUrl  String?
  responseData  Json?
  userId        String?  // Staff who handled
  createdAt     DateTime @default(now())
  updatedAt     DateTime @updatedAt
}
```

### Other

```prisma
model ClientBank {
  id            String   @id @default(uuid())
  clientId      String   @unique
  bankName      String
  accountNumber String
  accountHolder String
  client        Client   @relation(fields: [clientId], references: [id])
  createdAt     DateTime @default(now())
  updatedAt     DateTime @updatedAt
}
```

## Key Relationships Diagram

```
Role ──< User ──? EtelecomExtension
              └──< OmiCall

Client ──? Cart ──< CartItem ──> StoreProduct + StoreProductCombo
       ──< Order ──< OrderItem ──> StoreProduct + StoreProductCombo
       │         └──< LogOrder
       ──< ClientVoucher ──> Voucher
       ──? ClientBank
       ──< SpinTransaction ──> SpinReward
       ──< RedeemTransaction

Category (self-ref tree) ──< CategoryBrand ──> Brand
                         ──< ProductCategory ──> StoreProduct

StoreProduct ──< StoreProductCombo ──< StoreProductComboItem ──> InventoryProduct
                                   ──< StoreProductComboPromotionHistory

InventoryProduct ──< ProductInventoryItem (lots with expiry)
                 ──< InventoryTransaction ──> InventorySession
```
