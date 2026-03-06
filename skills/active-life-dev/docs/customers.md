# Active Life Backend - Customer Management (CRM)

## Overview

The CRM system tracks customers through their lifecycle with:
- Source tracking (where they came from)
- Status management (lifecycle stage)
- Staff assignment (who manages them)
- Interaction tracking (calls, chats, visits)
- Bank information (for refunds)

## Client Model (Customer)

```prisma
model Client {
  id                    String    @id @default(uuid())
  phone                 String    @unique
  email                 String?
  name                  String
  password              String?   // Optional (Zalo login doesn't need it)
  avatar                String?
  dob                   DateTime?
  gender                String?

  // Address
  address               String?
  province              String?
  district              String?
  ward                  String?

  // Loyalty
  point                 Int       @default(0)

  // Status
  isBan                 Boolean   @default(false)
  note                  String?
  tags                  String[]

  // CRM Assignment
  customerSourceId      String?   // Where they came from
  customerStatusId      String?   // Lifecycle status
  customerDetailStatusId String?  // Detailed status
  livechatStaffId       String?   // Assigned LiveChat staff
  telesalesStaffId      String?   // Assigned TeleSales staff
  agencyStaffId         String?   // Assigned Agency staff

  // Lifecycle Dates
  firstCallAt           DateTime? // First phone call
  lastOrderAt           DateTime? // Most recent order

  // Relations
  orders                Order[]
  cart                  Cart?
  vouchers              ClientVoucher[]
  bank                  ClientBank?
  spinTransactions      SpinTransaction[]
  redeemTransactions    RedeemTransaction[]
}
```

## CRM Lookup Tables

### Customer Source
Where the customer came from:
```
Examples: Facebook, Zalo, Website, Walk-in, Referral, Google Ads, TikTok
```

### Customer Status
Lifecycle stage:
```
Examples: New, Contacted, Active, Inactive, Lost, VIP
```

### Customer Detail Status
Granular status within lifecycle:
```
Examples: Interested, Following Up, Purchased, Repeat Customer, Churned
```

### Interaction Status
Call/chat connection status:
```
Examples: Connected, No Answer, Busy, Voicemail, Line Disconnected
```

### Interaction Result
Outcome of interaction:
```
Examples: Interested, Not Interested, Callback Requested, Order Placed, Info Sent
```

### Interaction Type
How the interaction happened:
```
Examples: Phone Call, Zalo Message, In-Store Visit, Email, Facebook Message
```

All lookup tables follow the same pattern:
```prisma
model CustomerSource {
  id          String   @id @default(uuid())
  name        String   @unique
  description String?
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt
}
```

## Staff Assignment

Customers can be assigned to three types of staff:
- **LiveChat Staff** — Handles online chat support
- **TeleSales Staff** — Handles phone sales
- **Agency Staff** — Handles agency/partner relationships

Each is a reference to User (staff) by ID.

## Bank Information

For refund processing:
```prisma
model ClientBank {
  id            String @id @default(uuid())
  clientId      String @unique  // 1-to-1
  bankName      String
  accountNumber String
  accountHolder String
}
```

## Key API Endpoints

### Client Management
```
GET    /api/v1/client              — List clients (staff, paginated, filterable)
GET    /api/v1/client/:id          — Get client detail (staff)
POST   /api/v1/client              — Create client (staff)
PATCH  /api/v1/client/:id          — Update client (staff)
DELETE /api/v1/client/:id          — Delete client (staff)
```

### Client Self-Service
```
GET    /api/v1/client/profile      — Get own profile (client auth)
PATCH  /api/v1/client/self-update  — Update own profile (client auth)
PATCH  /api/v1/client/bank-info    — Update bank info (client auth)
```

### Lookup Tables (all follow same pattern)
```
GET    /api/v1/customer-source     — List sources
POST   /api/v1/customer-source     — Create source (staff)
PATCH  /api/v1/customer-source/:id — Update source (staff)
DELETE /api/v1/customer-source/:id — Delete source (staff)

# Same pattern for:
# /api/v1/customer-status
# /api/v1/customer-detail-status
# /api/v1/interaction-status
# /api/v1/interaction-result
# /api/v1/interaction-type
```

## Client Filtering (Staff View)

Staff can filter clients by:
- `customerSourceId` — Filter by source
- `customerStatusId` — Filter by lifecycle status
- `customerDetailStatusId` — Filter by detail status
- `livechatStaffId` — Filter by assigned LiveChat staff
- `telesalesStaffId` — Filter by assigned TeleSales staff
- `agencyStaffId` — Filter by assigned agency
- `search` — Search by name or phone
- `tags` — Filter by tags
- `isBan` — Filter banned/active

## Ads Source

Tracking advertising campaign sources:
```prisma
model AdsSource {
  id          String   @id @default(uuid())
  name        String   @unique
  description String?
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt
}
```

## Customer Lifecycle Flow

```
New Customer Registration
    │
    ▼
Source Assigned (Facebook, Zalo, etc.)
    │
    ▼
Status: "New" → Staff Assigned (TeleSales/LiveChat)
    │
    ▼
First Contact (firstCallAt recorded)
    │
    ▼
Interactions Tracked (calls, chats)
    │
    ▼
Status Updates (Interested → Following Up → Active)
    │
    ▼
First Order (lastOrderAt recorded)
    │
    ▼
Repeat Customer → VIP
```
