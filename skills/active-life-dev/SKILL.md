---
name: active-life-dev
description: |
  **Active Life Backend Dev Guide**: Comprehensive development guide for the Active Life Global Store NestJS backend (be-store-active-life-global). Covers architecture, modules, Prisma schema, DTOs, auth, patterns, integrations, and coding conventions.
  - MANDATORY TRIGGERS: active life, backend, be-store, nestjs, prisma, module, controller, service, dto, guard, interceptor, order, product, inventory, voucher, cart, client, auth, etelecom, category, brand, report, seed, role, user, customer source, customer status, interaction, unit, api endpoint, database schema, migration
  - Use this skill when the user asks about backend architecture, wants to create/modify modules, needs to understand the database schema, wants to follow project conventions, or is working on any feature in the be-store-active-life-global project.
argument-hint: "[module | schema | auth | patterns | integrations | setup | orders | products | inventory | vouchers | customers | all]"
user-invocable: true
disable-model-invocation: false
allowed-tools: Read, Grep, Glob, Bash, Edit, Write
---

# Active Life Backend Development Guide

You are an expert NestJS developer working on the **Active Life Global Store** backend.

## Quick Context Loading

Load the relevant documentation based on what you need:

!`bash skills/skills/active-life-dev/scripts/load-docs.sh $ARGUMENTS`

---

## Project Location

```
/Users/nhiensoft/Workspace/ginstudio/active-life/be-store-active-life-global/
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | NestJS 10.x (Express) |
| Language | TypeScript (ES2022, CommonJS) |
| Database | PostgreSQL (Supabase) |
| ORM | Prisma 7.x with @prisma/adapter-pg |
| Auth | Passport + JWT (dual: User staff + Client customer) |
| Validation | class-validator + class-transformer |
| API Docs | Swagger / OpenAPI |
| Cache | Redis (ioredis) |
| Email | Nodemailer (@nestjs-modules/mailer) |
| Notifications | Firebase Admin SDK |
| Phone | eTelecom SIP integration |
| Rate Limit | @nestjs/throttler (10 req/60s) |
| API Versioning | URI-based (v1, v2) |

## Architecture Overview

```
src/
├── app.module.ts              # Root module - imports all feature modules
├── main.ts                    # Bootstrap: guards, pipes, interceptors, CORS, Swagger
├── core/                      # Global interceptors & guards
│   ├── transform.interceptor.ts   # { statusCode, message, data } response wrapper
│   ├── logging.interceptor.ts     # Request/response logging with timing
│   ├── roles.guard.ts             # Role-based access control
│   └── query.guard.ts
├── decorators/                # @Public, @ResponseMessage, @User, @Client, @Roles
├── interface/                 # IUser, IClient, PaginateInfo
├── generated/prisma/          # Auto-generated Prisma types
└── [feature-modules]/         # 23 feature modules (see docs/modules.md)
```

## Key Patterns (MUST follow)

### 1. Module Structure
Every module follows: `module.ts` + `controller.ts` + `service.ts` + `dto/` folder.

### 2. Response Format
All responses are wrapped by TransformInterceptor:
```typescript
{ statusCode: number, message?: string, data: any }
```

### 3. Auth - Dual JWT System
- **User (staff)**: `JwtAuthGuard` (default on all routes) → `@User()` decorator
- **Client (customer)**: `jwt-client` strategy → `@Client()` decorator
- **Public routes**: `@Public()` decorator skips auth

### 4. DTO Validation
```typescript
import { IsString, IsNotEmpty, IsOptional } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class CreateXxxDto {
  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  name: string;

  @ApiProperty({ required: false })
  @IsOptional()
  @IsString()
  description?: string;
}
```

### 5. Service Pattern
```typescript
@Injectable()
export class XxxService {
  constructor(private prismaService: PrismaService) {}

  async create(dto: CreateXxxDto) {
    return this.prismaService.xxx.create({ data: dto });
  }
}
```

### 6. Error Handling
Use NestJS exceptions: `BadRequestException`, `NotFoundException`, `ForbiddenException`.

### 7. Database Commands
```bash
yarn db:push        # Sync schema (keep data)
yarn db:migrate     # Create & run migrations
yarn db:seed        # Seed database
yarn db:studio      # Prisma Studio GUI
yarn dev            # Dev with hot-reload
```

---

## Documentation Files

Load specific docs when you need deeper detail:

| Doc | Content | When to Read |
|-----|---------|-------------|
| `docs/modules.md` | All 23 modules with controllers, services, DTOs | Creating/modifying any module |
| `docs/schema.md` | Complete Prisma schema (36 models, 7 enums) | Database changes, relations, queries |
| `docs/auth.md` | JWT strategies, guards, decorators, roles | Auth changes, protected endpoints |
| `docs/patterns.md` | Coding conventions, service patterns, error handling | Writing new code |
| `docs/integrations.md` | eTelecom, Firebase, Redis, Email, Mongoose | External service work |
| `docs/setup.md` | Environment vars, Supabase config, scripts | Setup, deployment, config |
| `docs/orders.md` | Order lifecycle, statuses, refunds, returns | Order feature work |
| `docs/products.md` | Products, combos, categories, brands, inventory | Product/catalog work |
| `docs/inventory.md` | Inventory sessions, transactions, lot tracking | Inventory/warehouse work |
| `docs/vouchers.md` | Vouchers, rewards, spins, redemptions | Promotion feature work |
| `docs/customers.md` | Client management, sources, statuses, interactions | CRM feature work |

---

## Creating a New Module Checklist

1. Create folder: `src/<module-name>/`
2. Create files: `<name>.module.ts`, `<name>.controller.ts`, `<name>.service.ts`
3. Create DTOs in `dto/` subfolder with class-validator decorators
4. Add Prisma model to `prisma/schema.prisma` if new table needed
5. Run `yarn db:push` or `yarn db:migrate` to sync schema
6. Import module in `app.module.ts`
7. Add `@ApiTags('module-name')` to controller
8. Add `@ApiBearerAuth()` to protected endpoints
9. Use `@Public()` for public endpoints
10. Follow existing service patterns (PrismaService injection, async/await)
