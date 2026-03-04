# NestJS Patterns — Backend Review Reference

Quick reference for reviewing NestJS backend code.

## Table of Contents
1. [Module Structure](#module-structure)
2. [Controller Conventions](#controller-conventions)
3. [Service Patterns](#service-patterns)
4. [Schema / Entity Patterns](#schema--entity-patterns)
5. [DTO Validation](#dto-validation)
6. [Error Handling](#error-handling)
7. [Auth & Guards](#auth--guards)
8. [AI Agent Patterns](#ai-agent-patterns)

---

## Module Structure

Every feature module follows this layout:
```
features/<name>/
├── <name>.module.ts         # @Module declaration
├── <name>.controller.ts     # HTTP routes
├── <name>.service.ts        # Business logic
├── dto/                     # class-validator DTOs
├── entities/                # Mongoose schemas
├── interfaces/              # TypeScript interfaces
└── __tests__/               # Jest tests (when they exist)
```

Module registration in `app.module.ts` — all feature modules are imported at the root level.

## Controller Conventions

```typescript
@Controller('items')
@ApiTags('Items')
@UseGuards(JwtAuthGuard)            // Protect all routes
export class ItemController {
  constructor(private readonly itemService: ItemService) {}

  @Post()
  @ApiOperation({ summary: 'Create item' })
  create(@Body() dto: CreateItemDto, @CurrentUser() user: User) {
    return this.itemService.create(dto, user);
  }
}
```

Review checklist:
- Controllers should be thin — validate input, delegate to service, return response (SRP)
- No business logic, DB calls, or side effects in controllers (separation of concerns)
- Use `@ApiTags` and `@ApiOperation` for Swagger docs
- Use `@UseGuards(JwtAuthGuard)` for protected routes
- Use `@CurrentUser()` decorator (from shared) to get authenticated user
- Use proper HTTP methods and status codes
- Controller methods should be <15 lines — if longer, logic belongs in the service
- Avoid catch blocks in controllers — let exception filters handle errors

## Service Patterns

```typescript
@Injectable()
export class ItemService {
  constructor(
    @InjectModel(Item.name) private itemModel: Model<ItemDocument>,
    private readonly mediaService: MediaService,
  ) {}

  async create(dto: CreateItemDto, user: User): Promise<Item> {
    // Business logic here
  }
}
```

Review checklist:
- Services own business logic, not controllers (SRP)
- Inject dependencies through constructor (DIP) — never use `new` for services or `moduleRef.get()`
- Use proper Mongoose model injection
- Return typed responses — avoid `any`, use explicit return types on public methods
- Handle errors with NestJS exceptions (`NotFoundException`, `BadRequestException`, etc.)
- Keep services focused: <200 lines, <10 public methods. Split if growing beyond this (SRP)
- Use early returns / guard clauses instead of deep nesting
- Extract repeated query patterns to private helper methods (DRY)
- Prefer composition over inheritance — inject other services rather than extending base classes
- Avoid side effects in methods that read data (query methods shouldn't mutate state)

## Schema / Entity Patterns

```typescript
@Schema({ timestamps: true, collection: 'items' })
export class Item {
  @Prop({ required: true })
  name: string;

  @Prop({ type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true })
  userId: mongoose.Types.ObjectId;

  @Prop({ type: [String], default: [] })
  tags: string[];
}
```

Review checklist:
- Use `{ timestamps: true }` for automatic createdAt/updatedAt
- Add `required: true` on non-optional fields
- Add `index: true` on fields used in queries
- Use `ref` for cross-document references
- Specify `collection` name explicitly

## DTO Validation

```typescript
export class CreateItemDto {
  @IsString()
  @IsNotEmpty()
  name: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  tags?: string[];
}
```

Review checklist:
- All input DTOs should use class-validator decorators
- Mark optional fields with `@IsOptional()`
- Use `@Transform()` for sanitization when needed
- Separate Create, Update, and Query DTOs

## Error Handling

The project should use a global `HttpExceptionFilter` in `core/exception/`.

In services, throw typed NestJS exceptions:
```typescript
throw new NotFoundException('Item not found');
throw new BadRequestException('Invalid input');
throw new UnauthorizedException('Not authorized');
throw new ConflictException('Item already exists');
```

Review checklist:
- Never swallow errors silently (empty catch blocks) — this is a CRITICAL code smell
- Use typed exceptions, not generic `Error` — exception type communicates intent
- Log errors before throwing when there's useful context
- Handle async errors — all async functions should have try/catch or let exceptions propagate meaningfully
- **Fail fast**: Validate inputs at the boundary (controller/DTO), don't check deep in business logic
- **Consistent strategy per layer**: Controllers use HTTP exceptions, services use domain exceptions, repositories propagate DB errors
- Avoid `try/catch` around every line — wrap logical units, not individual statements
- Include actionable context in error messages: `Item ${id} not found` not just `Not found`

## Auth & Guards

- `JwtAuthGuard` — Standard JWT Bearer token guard
- `@CurrentUser()` — Extracts user from JWT payload
- Role-based guards for admin/privileged operations

Review checklist:
- All non-public endpoints should have `@UseGuards(JwtAuthGuard)`
- User-specific queries should filter by `userId` from `@CurrentUser()`
- No endpoints should expose other users' data without admin check

## AI Agent Patterns

AI agent modules have their own internal architecture:

```
ai-agents/core/
├── llm/services/              # Abstraction layer for all LLM calls
├── providers/                 # Provider configs (OpenAI, Gemini, Vertex AI)
├── graph/                     # LangGraph state machine
├── tools/                     # Custom tools the agent can call
├── knowledge/                 # Knowledge base (embeddings → vector DB)
└── config/                    # System prompts, tool configs
```

Review checklist:
- LLM calls should go through the abstraction layer, not direct SDK calls
- New tools should follow the existing pattern (DynamicStructuredTool)
- System prompts should use reusable sections from config
- Token limits and timeouts should be configured, not hardcoded
- Retry logic should use circuit breakers
