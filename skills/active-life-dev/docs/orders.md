# Active Life Backend - Order System

## Order Lifecycle

```
PENDING → PROCESSING → SHIPPED → DELIVERED
    │          │           │
    ▼          ▼           ▼
CANCELLED  CANCELLED   RETURN_PENDING → RETURN_RECEIVED → DELIVERED (restocked)
                                │
                                ▼
                        RETURN_REJECTED

                        REFUND_PENDING → REFUNDED
```

## Order Statuses (OrderStatus enum)

| Status | Description | Triggered By |
|--------|------------|-------------|
| `PENDING` | New order, awaiting processing | Customer/Staff creates order |
| `PROCESSING` | Staff processing, selecting inventory lots | Staff processes order |
| `SHIPPED` | Order shipped to customer | Staff marks as shipped |
| `DELIVERED` | Customer received order | Staff confirms delivery |
| `CANCELLED` | Order cancelled | Customer or staff cancels |
| `RETURN_PENDING` | Return requested | Customer requests return |
| `RETURN_RECEIVED` | Returned items received | Staff confirms receipt |
| `RETURN_REJECTED` | Return request rejected | Staff rejects return |
| `REFUND_PENDING` | Refund in progress | Staff initiates refund |
| `REFUNDED` | Refund completed | Staff completes refund |

## Order Model

```prisma
model Order {
  id              String        @id @default(uuid())
  orderCode       String        @unique    // Human-readable code
  clientId        String
  status          OrderStatus   @default(PENDING)
  paymentMethod   PaymentMethod            // CASH or TRANSFER
  totalAmount     Float                    // Sum of items
  discountAmount  Float         @default(0) // Voucher discount
  finalAmount     Float                    // totalAmount - discountAmount + shippingFee
  shippingAddress String?
  shippingFee     Float         @default(0)
  note            String?
  voucherId       String?
  staffId         String?                  // Staff who processed
}
```

## Order Flow

### 1. Customer Creates Order
```
POST /api/v1/order (with jwt-client auth)
Body: CreateOrderDto {
  items: [{ productId, comboId, quantity }],
  paymentMethod: "CASH" | "TRANSFER",
  shippingAddress: string,
  voucherCode?: string,
  note?: string
}
```
- Validates product/combo availability
- Applies voucher if provided
- Calculates totals
- Creates Order + OrderItems
- Creates LogOrder (CREATE)

### 2. Staff Creates Order (on behalf)
```
POST /api/v1/order/staff-create (staff auth)
Body: StaffCreateOrderDto {
  clientId: string,
  items: [...],
  paymentMethod: ...,
  ...
}
```

### 3. Process Order (assign inventory)
```
PATCH /api/v1/order/:id/process (staff auth)
Body: ProcessOrderDto {
  items: [{
    orderItemId: string,
    lots: [{
      inventoryItemId: string,  // ProductInventoryItem
      quantity: number
    }]
  }]
}
```
- Staff selects specific inventory lots (FIFO by expiry)
- Deducts inventory quantities
- Creates InventoryTransactions (EXPORT type)
- Status: PENDING → PROCESSING

### 4. Ship Order
```
PATCH /api/v1/order/:id/ship (staff auth)
```
- Status: PROCESSING → SHIPPED
- Creates LogOrder (SHIP)

### 5. Deliver Order
```
PATCH /api/v1/order/:id/deliver (staff auth)
```
- Status: SHIPPED → DELIVERED
- Creates LogOrder (DELIVER)
- Awards loyalty points to client

### 6. Cancel Order
```
PATCH /api/v1/order/:id/cancel (staff or client auth)
Body: CancelOrderDto { reason: string }
```
- Status: PENDING/PROCESSING → CANCELLED
- If PROCESSING: reverses inventory deductions
- Creates LogOrder (CANCEL_CLIENT or CANCEL_STAFF)

### 7. Return Request
```
POST /api/v1/order/:id/return-request (client or staff)
Body: CreateReturnRequestDto { reason, items[] }
```
- Status: DELIVERED → RETURN_PENDING
- Creates LogOrder (RETURN_CREATE)

### 8. Complete Return
```
PATCH /api/v1/order/:id/return-complete (staff)
Body: CompleteReturnRequestDto { action: "receive" | "reject" }
```
- If receive: RETURN_PENDING → RETURN_RECEIVED, restock inventory
- If reject: RETURN_PENDING → RETURN_REJECTED

### 9. Refund Request
```
POST /api/v1/order/:id/refund-request (staff)
Body: CreateRefundRequestDto { amount, reason }
```
- Status: → REFUND_PENDING

### 10. Complete Refund
```
PATCH /api/v1/order/:id/refund-complete (staff)
```
- Status: REFUND_PENDING → REFUNDED
- Creates LogOrder (REFUND_COMPLETE)

## Audit Trail (LogOrder)

Every status change creates a log entry:
```prisma
model LogOrder {
  id        String       @id @default(uuid())
  orderId   String
  type      LogOrderType // CREATE, PROCESS, SHIP, DELIVER, CANCEL_*, RETURN_*, REFUND_*
  note      String?
  userId    String?      // Staff who made the change
  createdAt DateTime     @default(now())
}
```

## Payment Methods
- `CASH` — Cash on delivery
- `TRANSFER` — Bank transfer

## Key Business Rules
1. Only PENDING orders can be processed
2. Only PROCESSING orders can be shipped
3. Only SHIPPED orders can be delivered
4. Only PENDING/PROCESSING orders can be cancelled
5. Only DELIVERED orders can have return requests
6. Cancellation of PROCESSING orders must reverse inventory
7. Points are awarded only on DELIVERED status
8. Order code is auto-generated and unique
