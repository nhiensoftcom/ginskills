# Active Life Backend - Authentication & Authorization

## Dual JWT System

The app has two separate authentication flows:
1. **User (Staff)** — Internal employees (Admin, TeleSales, LiveChat, Agency)
2. **Client (Customer)** — End-users / shoppers

Both use JWT Bearer tokens but different strategies and payloads.

## JWT Strategies

### JwtStrategy (Staff - Default)
**File**: `src/auth/passport/jwt.strategy.ts`

```typescript
// Extracts from: Authorization: Bearer <token>
// Secret: JWT_CLIENT_ACCESS_TOKEN_SECRET
// Payload shape:
interface IJwtPayload {
  id: string;
  phone: string;
  name: string;
  role: { id: string; name: string };
  etelecom?: { extensionNumber: string; extensionPassword: string; tenantId: string; tenantDomain: string };
}
// Returns: IUser
```

### JwtClientStrategy (Customer)
**File**: `src/auth/passport/jwt-client.strategy.ts`

```typescript
// Named strategy: 'jwt-client'
// Extracts from: Authorization: Bearer <token>
// Secret: JWT_CLIENT_ACCESS_TOKEN_SECRET (same secret)
// Payload shape:
interface IJwtClientPayload {
  id: string;
  phone: string;
  name: string;
  point: number;
}
// Returns: IClient with type='client'
```

## Guards

### JwtAuthGuard (Global)
**File**: `src/auth/jwt-auth.guard.ts`
- Applied globally in `main.ts`
- Checks `@Public()` metadata — if present, skips auth
- After validation, checks `user.isBan` — returns 403 if banned
- Default: all routes require authentication

### RolesGuard
**File**: `src/core/roles.guard.ts`
- Works with `@Roles()` decorator
- Checks if authenticated user's role matches required roles
- Applied per-route, not globally

## Custom Decorators

**File**: `src/decorators/customize.ts`

```typescript
// Skip authentication for a route
@Public()

// Set custom response message (used by TransformInterceptor)
@ResponseMessage('Custom message here')

// Get current authenticated user (staff)
@User() user: IUser

// Get current authenticated client (customer)
@Client() client: IClient
```

**File**: `src/decorators/roles.decorator.ts`

```typescript
// Require specific roles
@Roles('Admin', 'TeleSales')
```

## Interfaces

**File**: `src/interface/users.interface.ts`
```typescript
interface IUser {
  id: string;
  phone: string;
  name: string;
  email?: string;
  roleName: string;
  role: { id: string; name: string };
  etelecom?: { ... };
}
```

**File**: `src/interface/client.interface.ts`
```typescript
interface IClient {
  id: string;
  phone: string;
  name: string;
  point: number;
  type: 'client';
}
```

## Auth Controller Endpoints

```
POST /api/v1/auth/login          — Staff login (phone + password)
POST /api/v1/auth/register       — Staff register (admin only)
POST /api/v1/auth/client-login   — Client login (phone + password)
POST /api/v1/auth/client-register — Client register
POST /api/v1/auth/client-zalo    — Client Zalo OAuth login
GET  /api/v1/auth/profile        — Get current user profile
GET  /api/v1/auth/client-profile — Get current client profile
```

## Role-Based Access Patterns

```typescript
// Admin only
@Roles('Admin')
@UseGuards(RolesGuard)

// Multiple roles
@Roles('Admin', 'TeleSales', 'LiveChat')
@UseGuards(RolesGuard)

// Public endpoint (no auth)
@Public()

// Client endpoint (use jwt-client guard)
@UseGuards(AuthGuard('jwt-client'))

// Staff endpoint (default - no extra decorator needed)
```

## Password Handling
- Hashing: `bcryptjs` with salt rounds
- Stored as hashed string in User.password and Client.password
- Client.password is optional (Zalo login doesn't require it)

## Token Configuration
- Secret: `JWT_CLIENT_ACCESS_TOKEN_SECRET` env var
- Expiry: `JWT_CLIENT_ACCESS_EXPIRE` env var (default: "15d")
- Algorithm: Default HS256

## Common Auth Patterns

### Protecting a staff-only endpoint
```typescript
@Controller('admin')
@ApiTags('admin')
@ApiBearerAuth()
export class AdminController {
  @Get('dashboard')
  @Roles('Admin')
  @UseGuards(RolesGuard)
  getDashboard(@User() user: IUser) {
    // user is guaranteed to be authenticated staff with Admin role
  }
}
```

### Creating a public + client endpoint
```typescript
@Controller('shop')
@ApiTags('shop')
export class ShopController {
  @Get('products')
  @Public()  // Anyone can browse
  getProducts() { }

  @Post('checkout')
  @UseGuards(AuthGuard('jwt-client'))
  checkout(@Client() client: IClient) {
    // client is guaranteed to be authenticated customer
  }
}
```
