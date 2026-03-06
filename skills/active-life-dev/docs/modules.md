# Active Life Backend - All Modules Reference

## Module List (23 total)

### Core Business Modules

#### 1. Auth Module (`src/auth/`)
- **Controller**: `AuthController` — Login, register, token refresh
- **Service**: `AuthService` — JWT signing, password hashing, validation
- **Strategies**: `JwtStrategy` (staff), `JwtClientStrategy` (customer)
- **Guard**: `JwtAuthGuard` — Global auth guard, checks @Public, checks isBan
- **DTOs**:
  - `UserLoginDto` — { phone, password }
  - `ClientLoginDto` — { phone, password }
  - `ClientRegisterDto` — { phone, password, name }
  - `ClientZaloLoginDto` — Zalo OAuth login
  - `UserRegisterDto` — Staff registration (admin only)
  - `AdminUpdateUserDto` — Admin updates user profile

#### 2. Product Module (`src/product/`)
- **Controller**: `ProductController` — CRUD products, combo management
- **Service**: `ProductService` — Product operations, combo logic, slug generation
- **DTOs**:
  - `CreateProductDto` — { name, description, images, categoryIds, brandId, unitId, status }
  - `UpdateProductDto` — Partial of create
  - `CreateProductComboDto` — { name, price, comparePrice, items[] }
  - `UpdateProductComboDto` — Partial of combo create
  - `AddComboToProductDto` — Add combo to product
  - `AddComboGiftDto` — Add gift items to combo
  - `ComboItemDto` — { inventoryProductId, quantity }

#### 3. Order Module (`src/order/`)
- **Controller**: `OrderController` — Create, process, ship, deliver, cancel, refund, return
- **Service**: `OrderService` — Order lifecycle, inventory deduction, status flow
- **DTOs**:
  - `CreateOrderDto` — Customer creates order
  - `StaffCreateOrderDto` — Staff creates order on behalf
  - `CreateOrderItemDto` — { productId, comboId, quantity }
  - `UpdateOrderStatusDto` — Change order status
  - `UpdateOrderFlowDto` — Process order through stages
  - `CancelOrderDto` — { reason }
  - `ProcessOrderDto` — Process with lot selection
  - `ProcessOrderItemLotDto` — Assign inventory lots to items
  - `RefundOrderDto` — Initiate refund
  - `RefundRequestDto`, `CreateRefundRequestDto`, `CompleteRefundRequestDto` — Refund workflow
  - `ReturnRequestDto`, `CreateReturnRequestDto`, `CompleteReturnRequestDto` — Return workflow
  - `OrderRequestDto` — Query/filter orders

#### 4. Inventory Module (`src/inventory/`)
- **Controller**: `InventoryController` — Import/export sessions
- **Service**: `InventoryService` — Session management, transaction creation
- **DTOs**:
  - `CreateInventorySessionDto` — { type, items[], note }
  - `CreateInventoryItemDto` — { inventoryProductId, quantity, expiryDate, lotNumber }

#### 5. Inventory Product Module (`src/inventory-product/`)
- **Controller**: `InventoryProductController` — Warehouse product CRUD
- **Service**: `InventoryProductService` — Stock tracking, valid items
- **DTOs**:
  - `CreateInventoryProductDto` — { name, sku, unitId, brandId }
  - `UpdateInventoryProductDto` — Partial update
  - `GetValidItemsDto` — Filter non-expired items

#### 6. Category Module (`src/category/`)
- **Controller**: `CategoryController` — Hierarchical category CRUD
- **Service**: `CategoryService` — Recursive queries, slug generation
- **DTOs**:
  - `CreateCategoryDto` — { name, parentId?, image?, description? }
  - `UpdateCategoryDto` — Partial update

#### 7. Brand Module (`src/brand/`)
- **Controller**: `BrandController` — Brand CRUD
- **Service**: `BrandService` — Brand operations
- **DTOs**:
  - `CreateBrandDto` — { name, image?, description? }
  - `UpdateBrandDto` — Partial update

#### 8. Voucher Module (`src/voucher/`)
- **Controller**: `VoucherController` — Voucher CRUD, redemption
- **Service**: `VoucherService` — Voucher lifecycle, usage tracking
- **DTOs**:
  - `CreateVoucherDto` — { code, type, value, minOrder, maxDiscount, expiryDate, quantity }
  - `UpdateVoucherDto` — Partial update
  - `RedeemVoucherDto` — { code, orderId }

#### 9. Client Module (`src/client/`)
- **Controller**: `ClientController` — Customer CRUD, self-update
- **Service**: `ClientService` — Customer management, assignment
- **DTOs**:
  - `CreateClientDto` — { phone, name, email?, address? }
  - `UpdateClientDto` — Staff updates client
  - `UpdateClientSelfDto` — Client updates own profile
  - `UpdateBankInfoDto` — { bankName, accountNumber, accountHolder }

#### 10. Cart Module (`src/cart/`)
- **Controller**: `CartController` — Add, update, remove items, checkout
- **Service**: `CartService` — Cart operations, checkout flow
- **DTOs**:
  - `AddToCartDto` — { productId, comboId, quantity }
  - `UpdateCartItemDto` — { quantity }
  - `CheckoutDto` — { voucherCode?, paymentMethod, shippingAddress }

#### 11. User Module (`src/user/`)
- **Controller**: `UserController` — Staff profile management
- **Service**: `UserService` — Staff CRUD
- **DTOs**:
  - `UpdateUserDto` — Update staff profile
  - `UpdatePasswordDto` — { oldPassword, newPassword }

#### 12. Role Module (`src/role/`)
- **Controller**: `RoleController` — Role CRUD (Admin only)
- **Service**: `RoleService` — Role management
- **No DTOs** — Uses inline types

### CRM / Lookup Modules

#### 13. Customer Source (`src/customer-source/`)
- Lookup table for where customers come from (Facebook, Zalo, Walk-in, etc.)
- **DTO**: `CreateCustomerSourceDto` — { name, description? }

#### 14. Customer Status (`src/customer-status/`)
- Lookup table for customer lifecycle status (New, Active, Inactive, etc.)
- **DTO**: `CreateCustomerStatusDto` — { name, description? }

#### 15. Customer Detail Status (`src/customer-detail-status/`)
- Granular customer status (Interested, Following Up, Purchased, etc.)
- **DTO**: `CreateCustomerDetailStatusDto` — { name, description? }

#### 16. Interaction Status (`src/interaction-status/`)
- Call/chat interaction statuses (Connected, No Answer, Busy, etc.)
- **DTO**: `CreateInteractionStatusDto` — { name, description? }

#### 17. Interaction Result (`src/interaction-result/`)
- Outcomes of customer interactions (Interested, Not Interested, Callback, etc.)
- **DTO**: `CreateInteractionResultDto` — { name, description? }

#### 18. Interaction Type (`src/interaction-type/`)
- Types of interactions (Phone Call, Zalo Chat, In-store, etc.)
- **DTO**: `CreateInteractionTypeDto` — { name, description? }

### Utility Modules

#### 19. Unit Module (`src/unit/`)
- Units of measurement (kg, liter, box, piece, etc.)
- **DTOs**: `CreateUnitDto`, `UpdateUnitDto` — { name, abbreviation? }

#### 20. Report Module (`src/report/`)
- Business analytics and reporting
- **No DTOs** — Query params based

#### 21. Seed Module (`src/seed/`)
- Database seeding for development/staging
- **No DTOs** — Hardcoded seed data

#### 22. Etelecom Module (`src/etelecom/`)
- SIP phone system integration for call center
- **DTOs**:
  - `CreateEtelecomExtensionDto` — { extensionNumber, extensionPassword, tenantId, tenantDomain }
  - `LinkStaffExtensionDto` — { userId, extensionId }
  - `WebhookBodyDto` — Incoming call webhook data

---

## Module Import Pattern

All modules are imported in `src/app.module.ts`:

```typescript
@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    ThrottlerModule.forRoot([{ ttl: 60000, limit: 10 }]),
    // ... all feature modules
    AuthModule,
    ProductModule,
    OrderModule,
    // etc.
  ],
})
export class AppModule {}
```
