# Active Life Backend - Vouchers & Rewards System

## Overview

Three reward mechanisms:
1. **Vouchers** — Discount codes (fixed or percentage)
2. **Spin Rewards** — Lucky wheel with points or voucher prizes
3. **Point Redemption** — Exchange loyalty points for rewards

## Vouchers

### Voucher Model
```prisma
model Voucher {
  id          String      @id @default(uuid())
  code        String      @unique     // e.g., "SUMMER2024"
  type        VoucherType             // PERCENT or FIXED
  value       Float                   // 10 (10%) or 50000 (50,000 VND)
  minOrder    Float?                  // Minimum order amount to use
  maxDiscount Float?                  // Cap for PERCENT type
  quantity    Int                     // Total vouchers available
  usedCount   Int         @default(0) // How many have been used
  expiryDate  DateTime?
  isActive    Boolean     @default(true)
}
```

### Voucher Types
- `FIXED` — Deducts fixed amount (e.g., 50,000 VND off)
- `PERCENT` — Deducts percentage (e.g., 10% off, max 100,000 VND)

### Voucher Lifecycle
```
Create → Assign to Clients → Client Uses at Checkout → Mark as Used
                                                          ↑
                                                   Deduct from order total
```

### Client Voucher Assignment
```prisma
model ClientVoucher {
  clientId  String
  voucherId String
  isUsed    Boolean  @default(false)
  usedAt    DateTime?
  @@unique([clientId, voucherId])  // One per client
}
```

### Key Endpoints
```
GET    /api/v1/voucher              — List vouchers (staff)
POST   /api/v1/voucher              — Create voucher (staff)
PATCH  /api/v1/voucher/:id          — Update voucher (staff)
DELETE /api/v1/voucher/:id          — Delete voucher (staff)
POST   /api/v1/voucher/redeem       — Redeem voucher code (client)
GET    /api/v1/voucher/my-vouchers  — Client's available vouchers
```

### Voucher Validation Rules
1. Code must be unique
2. Voucher must be active (`isActive: true`)
3. Not expired (`expiryDate > now()`)
4. Not fully used (`usedCount < quantity`)
5. Client hasn't already used it
6. Order meets minimum amount (`totalAmount >= minOrder`)

### Discount Calculation
```typescript
if (voucher.type === 'PERCENT') {
  discount = totalAmount * (voucher.value / 100);
  if (voucher.maxDiscount) {
    discount = Math.min(discount, voucher.maxDiscount);
  }
} else {
  discount = voucher.value;
}
finalAmount = totalAmount - discount + shippingFee;
```

## Spin Rewards (Lucky Wheel)

### SpinReward Model
```prisma
model SpinReward {
  id          String     @id @default(uuid())
  name        String                    // "100 Points", "10% Voucher"
  type        RewardType               // POINT or VOUCHER
  value       Float                    // Points amount or voucher value
  probability Float                    // 0-100 chance of winning
  isActive    Boolean    @default(true)
}
```

### Spin Transaction
```prisma
model SpinTransaction {
  clientId  String
  rewardId  String
  createdAt DateTime @default(now())
}
```

### Spin Logic
1. Client requests a spin (costs points or free daily)
2. Server calculates reward based on probabilities
3. If POINT reward: adds points to client
4. If VOUCHER reward: creates a ClientVoucher
5. Records SpinTransaction

## Point System

### How Points Are Earned
- Order delivered → Points awarded based on order amount
- Spin wheel → POINT type rewards

### Point Redemption
```prisma
model RedeemTransaction {
  clientId    String
  points      Int        // Points spent
  description String?    // What they redeemed for
  createdAt   DateTime
}
```

### Point Balance
Stored directly on `Client.point` field. Updated atomically:
```typescript
await prisma.client.update({
  where: { id: clientId },
  data: { point: { increment: pointsToAdd } },
});
```

## Integration with Orders

At checkout:
1. Client provides `voucherCode` in `CreateOrderDto`
2. Service validates voucher (active, not expired, min order, not used)
3. Calculates discount
4. Creates order with `discountAmount` and `finalAmount`
5. Marks `ClientVoucher.isUsed = true`
6. Increments `Voucher.usedCount`
