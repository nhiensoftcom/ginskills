---
name: nestjs-architecture
description: |
  **NestJS Feature-Based Architecture**: Production patterns for organizing NestJS backends — feature modules, core infrastructure, shared utilities, guards, queues, events, error handling, and project structure.
  - MANDATORY TRIGGERS: nestjs architecture, nestjs structure, nestjs module, nestjs feature module, nestjs project structure, nestjs folder structure, nestjs organize, nestjs boilerplate, nestjs scaffold, nestjs guard, nestjs interceptor, nestjs pipe, nestjs filter, nestjs exception, nestjs queue, nestjs event, nestjs event emitter, nestjs bull, nestjs redis, nestjs config, nestjs database module, nestjs health check, nestjs rate limit, nestjs middleware, nestjs core module, nestjs shared module, nestjs dto pattern, nestjs service pattern, nestjs controller pattern, nestjs processor, nestjs decorator, nestjs graceful shutdown, nestjs swagger setup, nestjs validation, nestjs monolith
  - Use this skill whenever the user is setting up a NestJS project, creating new feature modules, organizing backend code, adding infrastructure (guards, queues, events, health checks), or reviewing NestJS architecture. Also trigger when discussing backend project structure, module boundaries, dependency injection patterns, or scaling NestJS applications.
---

# NestJS Feature-Based Architecture

Production-ready patterns for organizing NestJS backends using a feature-based modular structure. Covers project layout, core infrastructure, feature modules, shared utilities, guards, queues, events, error handling, and scaling.

## Core Mental Model

**Features are the organizing principle.** Group code by business domain (user, order, notification), not by technical layer (controllers/, services/, entities/). Each feature is a self-contained module that owns its routes, business logic, data access, DTOs, and schemas.

Key principles:
- A feature module should be deletable without breaking unrelated features
- Core infrastructure (database, cache, auth, logging) lives in `core/` — imported once at the root
- Shared utilities (decorators, pipes, DTOs) live in `shared/` — imported where needed
- Communication between features uses events, not direct service imports
- Every module explicitly declares its imports and exports

## Project Structure

```
src/
├── main.ts                          # Bootstrap, global pipes/filters/interceptors
├── app.module.ts                    # Root module — imports core + features
├── app.controller.ts                # Root health/info endpoint
├── app.service.ts                   # Root service
│
├── core/                            # Platform infrastructure (imported once)
│   ├── config/                      # Environment & app configuration
│   │   ├── env.schema.ts            # Zod/Joi validation for env vars
│   │   ├── app.config.ts            # Static app constants
│   │   ├── jwt.config.ts            # Token expiration settings
│   │   ├── cors.config.ts           # CORS origins
│   │   ├── helmet.config.ts         # Security headers
│   │   └── swagger.config.ts        # API documentation setup
│   ├── database/                    # Database connection & lifecycle
│   │   ├── database.module.ts       # Mongoose/TypeORM connection
│   │   └── database-cleanup.service.ts
│   ├── redis/                       # Cache & session management
│   │   ├── redis.module.ts          # Global Redis provider
│   │   ├── redis.service.ts         # Redis client wrapper
│   │   └── redis.constants.ts
│   ├── queue/                       # Job queue infrastructure
│   │   ├── queue.module.ts          # Bull/BullMQ configuration
│   │   ├── base-queue.service.ts    # Abstract queue service
│   │   ├── base-processor.ts        # Abstract job processor
│   │   └── queue.constants.ts       # Retry, backoff, timeout defaults
│   ├── logger/                      # Structured logging
│   │   └── logger.module.ts
│   ├── health/                      # Health check endpoints
│   │   ├── health.controller.ts     # /health endpoint
│   │   └── custom-disk.indicator.ts
│   ├── exception/                   # Global error handling
│   │   ├── http-exception.filter.ts # Global exception filter
│   │   └── app.exception.ts         # Custom exception hierarchy
│   └── scheduler/                   # Cron job registration
│       ├── scheduler.module.ts
│       └── scheduler.service.ts
│
├── features/                        # Business domain modules
│   ├── user/
│   │   ├── user.module.ts
│   │   ├── user.controller.ts
│   │   ├── user.service.ts
│   │   ├── user.event.ts            # Event listeners
│   │   ├── dto/
│   │   │   ├── create-user.dto.ts
│   │   │   └── update-user.dto.ts
│   │   ├── entities/
│   │   │   └── user.schema.ts       # Mongoose schema
│   │   ├── processors/              # Queue job handlers
│   │   │   └── user-deletion.processor.ts
│   │   └── services/                # Feature-specific sub-services
│   │       └── user-profile.service.ts
│   ├── auth/
│   ├── order/
│   ├── notification/
│   ├── media/
│   └── ...
│
├── shared/                          # Cross-feature utilities
│   ├── decorators/                  # Custom decorators
│   │   ├── pagination.decorator.ts
│   │   └── api-select.decorator.ts
│   ├── guards/                      # Reusable guards
│   │   └── rate-limit.guard.ts
│   ├── pipes/                       # Transform/validation pipes
│   │   ├── populate.pipe.ts
│   │   ├── select.pipe.ts
│   │   └── condition.pipe.ts
│   ├── dto/                         # Shared DTOs
│   │   ├── pagination.dto.ts
│   │   └── delete-response.dto.ts
│   ├── schema/                      # Shared schema mixins
│   │   ├── priority.schema.ts
│   │   └── thumbnail.schema.ts
│   ├── enum/                        # Shared enumerations
│   ├── events/                      # Domain event types
│   │   └── domain-event.ts
│   ├── utils/                       # Pure utility functions
│   ├── validators/                  # Custom class-validator rules
│   └── interfaces/                  # Shared type interfaces
│
└── types/                           # Global type declarations
```

## Core Infrastructure

### Config: Environment Validation with Zod

Validate **all** environment variables at startup. The app should crash immediately if config is invalid — not at runtime when a feature first reads a missing var.

```typescript
// core/config/env.schema.ts
import { z } from 'zod'

export const envSchema = z.object({
  // Server
  NODE_ENV: z.enum(['development', 'staging', 'production']).default('development'),
  PORT: z.coerce.number().default(3000),

  // Database
  MONGODB_CONNECTION_STRING: z.string().url(),
  MONGODB_NAME: z.string().min(1),

  // Redis
  REDIS_HOST: z.string().default('localhost'),
  REDIS_PORT: z.coerce.number().default(6379),
  REDIS_PASSWORD: z.string().optional(),

  // JWT
  JWT_ACCESS_TOKEN_SECRET: z.string().min(32),
  JWT_REFRESH_TOKEN_SECRET: z.string().min(32),
  JWT_ACCESS_TOKEN_EXPIRY: z.string().default('15m'),
  JWT_REFRESH_TOKEN_EXPIRY: z.string().default('7d'),

  // Storage — conditional validation
  STORAGE_TYPE: z.enum(['local', 's3']).default('local'),
  AWS_S3_BUCKET: z.string().optional(),
  AWS_S3_REGION: z.string().optional(),
  AWS_ACCESS_KEY_ID: z.string().optional(),
  AWS_SECRET_ACCESS_KEY: z.string().optional(),

  // Feature flags
  SWAGGER_ENABLED: z.coerce.boolean().default(true),
  ENABLE_TERMINAL_LOGGER: z.coerce.boolean().default(true),
  ENABLE_FILE_LOGGER: z.coerce.boolean().default(false),
}).refine(
  (data) => data.STORAGE_TYPE !== 's3' || (data.AWS_S3_BUCKET && data.AWS_S3_REGION),
  { message: 'AWS_S3_BUCKET and AWS_S3_REGION required when STORAGE_TYPE=s3' },
)

export type EnvConfig = z.infer<typeof envSchema>
```

```typescript
// main.ts — validate on startup
import { envSchema } from './core/config/env.schema'

const env = envSchema.safeParse(process.env)
if (!env.success) {
  console.error('Invalid environment variables:', env.error.format())
  process.exit(1)
}
```

### Database Module

```typescript
// core/database/database.module.ts
import { Module, Logger } from '@nestjs/common'
import { MongooseModule } from '@nestjs/mongoose'
import { ConfigService } from '@nestjs/config'
import mongoose from 'mongoose'

@Module({
  imports: [
    MongooseModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => {
        const logger = new Logger('Database')

        mongoose.connection.on('connecting', () => logger.log('Connecting to MongoDB...'))
        mongoose.connection.on('connected', () => logger.log('MongoDB connected'))
        mongoose.connection.on('error', (err) => logger.error('MongoDB error:', err))
        mongoose.connection.on('disconnected', () => logger.warn('MongoDB disconnected'))
        mongoose.connection.on('reconnected', () => logger.log('MongoDB reconnected'))

        return {
          uri: config.get('MONGODB_CONNECTION_STRING'),
          dbName: config.get('MONGODB_NAME'),
          maxPoolSize: 10,
          minPoolSize: 2,
          serverSelectionTimeoutMS: 5000,
          socketTimeoutMS: 45000,
        }
      },
    }),
  ],
})
export class DatabaseModule {}
```

### Global Exception Filter

```typescript
// core/exception/app.exception.ts
export class AppException extends Error {
  constructor(
    public readonly errorCode: string,
    public readonly statusCode: number,
    message: string,
    public readonly details?: Record<string, any>,
  ) {
    super(message)
  }

  static from(error: unknown): AppException {
    if (error instanceof AppException) return error
    if (error instanceof HttpException) {
      return new AppException('HTTP_ERROR', error.getStatus(), error.message)
    }
    return new AppException('INTERNAL_ERROR', 500, 'An unexpected error occurred')
  }
}

export class UnauthorizedException extends AppException {
  constructor(message = 'Unauthorized') {
    super('UNAUTHORIZED', 401, message)
  }
}

export class NotFoundException extends AppException {
  constructor(entity: string, id?: string) {
    super('NOT_FOUND', 404, id ? `${entity} with id ${id} not found` : `${entity} not found`)
  }
}

export class ValidationException extends AppException {
  constructor(details: Record<string, any>) {
    super('VALIDATION_ERROR', 422, 'Validation failed', details)
  }
}
```

```typescript
// core/exception/http-exception.filter.ts
@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger('ExceptionFilter')

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp()
    const response = ctx.getResponse<Response>()
    const request = ctx.getRequest<Request>()

    const appException = AppException.from(exception)
    const isProd = process.env.NODE_ENV === 'production'

    this.logger.error(`[${appException.errorCode}] ${appException.message}`, {
      path: request.url,
      method: request.method,
      ...(isProd ? {} : { stack: (exception as Error)?.stack }),
    })

    response.status(appException.statusCode).json({
      error_code: appException.errorCode,
      message: appException.message,
      details: appException.details,
      ...(isProd ? {} : { stack: (exception as Error)?.stack }),
    })
  }
}
```

### Queue Infrastructure

```typescript
// core/queue/queue.constants.ts
export const QUEUE_DEFAULTS = {
  attempts: 3,
  backoff: { type: 'exponential' as const, delay: 2000 },
  timeout: 30_000,
  removeOnComplete: { count: 100 },
  removeOnFail: { count: 500 },
}
```

```typescript
// core/queue/base-queue.service.ts
import { Queue, Job } from 'bull'

export abstract class BaseQueueService {
  private dedupeCache = new Map<string, number>()

  constructor(protected readonly queue: Queue) {}

  async addJob<T>(name: string, data: T, opts?: { dedupeKey?: string; dedupeTtl?: number }) {
    // Deduplication — prevent identical jobs within TTL window
    if (opts?.dedupeKey) {
      const lastRun = this.dedupeCache.get(opts.dedupeKey)
      const ttl = opts.dedupeTtl ?? 60_000
      if (lastRun && Date.now() - lastRun < ttl) return null
      this.dedupeCache.set(opts.dedupeKey, Date.now())
    }

    return this.queue.add(name, data, {
      ...QUEUE_DEFAULTS,
    })
  }

  async getJobStatus(jobId: string) {
    const job = await this.queue.getJob(jobId)
    if (!job) return null
    const state = await job.getState()
    return { id: job.id, state, data: job.data, progress: job.progress() }
  }

  async getMetrics() {
    const [completed, failed, waiting, active] = await Promise.all([
      this.queue.getCompletedCount(),
      this.queue.getFailedCount(),
      this.queue.getWaitingCount(),
      this.queue.getActiveCount(),
    ])
    return { completed, failed, waiting, active }
  }

  async gracefulShutdown(timeoutMs = 30_000) {
    await this.queue.pause(true)
    const start = Date.now()
    while (Date.now() - start < timeoutMs) {
      const active = await this.queue.getActiveCount()
      if (active === 0) break
      await new Promise((r) => setTimeout(r, 1000))
    }
    await this.queue.close()
  }
}
```

### Health Checks

```typescript
// core/health/health.controller.ts
@Controller('health')
export class HealthController {
  constructor(
    private health: HealthCheckService,
    private mongoose: MongooseHealthIndicator,
    private disk: DiskHealthIndicator,
    private memory: MemoryHealthIndicator,
  ) {}

  @Get()
  @HealthCheck()
  check() {
    const isProd = process.env.NODE_ENV === 'production'
    return this.health.check([
      () => this.mongoose.pingCheck('mongodb'),
      () => this.disk.checkStorage('disk', {
        path: '/',
        thresholdPercent: isProd ? 0.75 : 0.90,
      }),
      () => this.memory.checkHeap('memory_heap', 300 * 1024 * 1024),
    ])
  }
}
```

### Rate Limiting with Redis

```typescript
// shared/guards/rate-limit.guard.ts
@Injectable()
export class RateLimitGuard implements CanActivate {
  constructor(private readonly redisService: RedisService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest()
    const userId = request.user?.id ?? this.getGuestId(request)
    const key = `rate:${userId}`
    const window = 60  // seconds
    const maxRequests = 100

    // Atomic sliding window via Lua script
    const script = `
      local key = KEYS[1]
      local now = tonumber(ARGV[1])
      local window = tonumber(ARGV[2])
      local max = tonumber(ARGV[3])
      redis.call('ZREMRANGEBYSCORE', key, 0, now - window * 1000)
      local count = redis.call('ZCARD', key)
      if count >= max then return 0 end
      redis.call('ZADD', key, now, now .. ':' .. math.random())
      redis.call('EXPIRE', key, window)
      return 1
    `

    const allowed = await this.redisService.eval(script, 1, key, Date.now(), window, maxRequests)
    if (!allowed) throw new HttpException('Too Many Requests', 429)
    return true
  }

  private getGuestId(req: Request): string {
    const ip = req.ip || req.socket.remoteAddress
    const ua = req.headers['user-agent'] || ''
    return `guest:${createHash('sha256').update(`${ip}:${ua}`).digest('hex').slice(0, 16)}`
  }
}
```

## Feature Module Pattern

### Anatomy of a Feature

Every feature module follows the same structure:

```
features/order/
├── order.module.ts              # Module — imports, providers, exports
├── order.controller.ts          # HTTP routes
├── order.service.ts             # Business logic
├── order.event.ts               # Event listeners (@OnEvent)
├── dto/
│   ├── create-order.dto.ts      # Input validation
│   ├── update-order.dto.ts
│   └── order-response.dto.ts    # Output shape
├── entities/
│   └── order.schema.ts          # Mongoose schema
├── processors/
│   └── order-fulfillment.processor.ts  # Queue job handler
└── services/
    ├── order-pricing.service.ts        # Sub-service for complex logic
    └── order-notification.service.ts
```

### Module Definition

```typescript
// features/order/order.module.ts
@Module({
  imports: [
    MongooseModule.forFeature([{ name: Order.name, schema: OrderSchema }]),
    BullModule.registerQueue({ name: 'order-fulfillment' }),
    forwardRef(() => UserModule),  // circular dependency resolution
  ],
  controllers: [OrderController],
  providers: [
    OrderService,
    OrderPricingService,
    OrderNotificationService,
    OrderFulfillmentProcessor,
  ],
  exports: [OrderService],  // only export what other modules need
})
export class OrderModule {}
```

### Controller Pattern

```typescript
// features/order/order.controller.ts
@ApiTags('Orders')
@Controller('orders')
@UseGuards(HybridAuthGuard, RolesGuard)
export class OrderController {
  constructor(private readonly orderService: OrderService) {}

  @Get()
  @Auth(Role.USER)
  @ApiPagination()
  async findAll(
    @CurrentUser() user: UserDocument,
    @GetPagination() pagination: PaginationDto,
  ) {
    return this.orderService.findAll(user.id, pagination)
  }

  @Get(':id')
  @Auth(Role.USER)
  async findOne(
    @CurrentUser() user: UserDocument,
    @Param('id') id: string,
  ) {
    return this.orderService.findOneOrFail(id, user.id)
  }

  @Post()
  @Auth(Role.USER)
  async create(
    @CurrentUser() user: UserDocument,
    @Body() dto: CreateOrderDto,
  ) {
    return this.orderService.create(user.id, dto)
  }

  @Patch(':id')
  @Auth(Role.USER)
  async update(
    @Param('id') id: string,
    @CurrentUser() user: UserDocument,
    @Body() dto: UpdateOrderDto,
  ) {
    return this.orderService.update(id, user.id, dto)
  }

  @Delete(':id')
  @Auth(Role.USER)
  @HttpCode(HttpStatus.NO_CONTENT)
  async remove(
    @Param('id') id: string,
    @CurrentUser() user: UserDocument,
  ) {
    return this.orderService.remove(id, user.id)
  }
}
```

### Service Pattern

```typescript
// features/order/order.service.ts
@Injectable()
export class OrderService {
  constructor(
    @InjectModel(Order.name) private orderModel: Model<OrderDocument>,
    private readonly pricingService: OrderPricingService,
    private readonly eventEmitter: EventEmitter2,
  ) {}

  async findAll(userId: string, pagination: PaginationDto): Promise<PaginatedResponse<Order>> {
    const { skip, limit, sort } = pagination
    const filter = { userId: new Types.ObjectId(userId) }

    const [docs, totalDocs] = await Promise.all([
      this.orderModel.find(filter).sort(sort).skip(skip).limit(limit).lean().exec(),
      this.orderModel.countDocuments(filter),
    ])

    return {
      data: docs,
      meta: new PageMeta({ totalDocs, page: Math.floor(skip / limit) + 1, limit }),
    }
  }

  async findOneOrFail(id: string, userId: string): Promise<Order> {
    const order = await this.orderModel
      .findOne({ _id: id, userId: new Types.ObjectId(userId) })
      .lean()
      .exec()
    if (!order) throw new NotFoundException('Order', id)
    return order
  }

  async create(userId: string, dto: CreateOrderDto): Promise<Order> {
    const total = await this.pricingService.calculate(dto.items)
    const order = await this.orderModel.create({
      userId: new Types.ObjectId(userId),
      ...dto,
      total,
    })

    this.eventEmitter.emit('order.created', { orderId: order._id, userId })
    return order.toObject()
  }

  async remove(id: string, userId: string): Promise<void> {
    const result = await this.orderModel.deleteOne({
      _id: id,
      userId: new Types.ObjectId(userId),
    })
    if (result.deletedCount === 0) throw new NotFoundException('Order', id)
    this.eventEmitter.emit('order.deleted', { orderId: id, userId })
  }
}
```

### DTO Pattern (class-validator + class-transformer)

```typescript
// features/order/dto/create-order.dto.ts
import { IsString, IsArray, IsNumber, ValidateNested, Min, ArrayMinSize } from 'class-validator'
import { Type } from 'class-transformer'
import { ApiProperty } from '@nestjs/swagger'

class OrderItemDto {
  @ApiProperty()
  @IsString()
  productId: string

  @ApiProperty()
  @IsNumber()
  @Min(1)
  quantity: number
}

export class CreateOrderDto {
  @ApiProperty({ type: [OrderItemDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => OrderItemDto)
  items: OrderItemDto[]

  @ApiProperty({ required: false })
  @IsString()
  @IsOptional()
  note?: string
}
```

```typescript
// features/order/dto/update-order.dto.ts
import { PartialType } from '@nestjs/swagger'
import { CreateOrderDto } from './create-order.dto'

export class UpdateOrderDto extends PartialType(CreateOrderDto) {}
```

### Schema Pattern (Mongoose + NestJS)

```typescript
// features/order/entities/order.schema.ts
@Schema({
  timestamps: true,
  toJSON: { virtuals: true },
  toObject: { virtuals: true },
})
export class Order {
  @Prop({ type: Types.ObjectId, ref: 'User', required: true, index: true })
  userId: Types.ObjectId

  @Prop({
    type: [{
      productId: { type: Types.ObjectId, ref: 'Product', required: true },
      quantity: { type: Number, required: true, min: 1 },
      price: { type: Number, required: true },
    }],
    required: true,
  })
  items: Array<{ productId: Types.ObjectId; quantity: number; price: number }>

  @Prop({ required: true })
  total: number

  @Prop({ type: String, enum: ['pending', 'confirmed', 'shipped', 'delivered', 'cancelled'], default: 'pending', index: true })
  status: string

  @Prop()
  note?: string
}

export type OrderDocument = HydratedDocument<Order>
export const OrderSchema = SchemaFactory.createForClass(Order)

// Compound indexes
OrderSchema.index({ userId: 1, status: 1, createdAt: -1 })
OrderSchema.index({ status: 1, createdAt: -1 })
```

## Event-Driven Communication

### Domain Events

Features communicate through events — never import another feature's service directly for side effects.

```typescript
// shared/events/domain-event.ts
export enum DomainEvent {
  // Entity lifecycle
  ORDER_CREATED = 'order.created',
  ORDER_DELETED = 'order.deleted',
  USER_DELETED = 'user.deleted',

  // Cascade cleanup
  CATEGORY_DELETED = 'category.deleted',

  // Async processing
  VECTOR_SYNC_REQUIRED = 'vector.sync.required',
  NOTIFICATION_SEND = 'notification.send',
}
```

```typescript
// features/order/order.event.ts
@Injectable()
export class OrderEventListener {
  constructor(
    @InjectModel(Order.name) private orderModel: Model<OrderDocument>,
  ) {}

  @OnEvent(DomainEvent.USER_DELETED, { promisify: true })
  async handleUserDeleted(payload: { userId: string }) {
    await this.orderModel.deleteMany({ userId: new Types.ObjectId(payload.userId) })
  }
}
```

### When to Use Events vs Direct Imports

| Scenario | Approach | Why |
|----------|----------|-----|
| Feature A reacts to Feature B's action | **Event** | No coupling, Feature B doesn't know about A |
| Cascading delete (user deleted → delete orders) | **Event** | Each feature owns its cleanup |
| Need return value from another service | **Direct import** | Events are fire-and-forget |
| Shared read-only data (lookup, validation) | **Direct import** (export service) | Simple dependency |
| Async processing (send email, generate image) | **Event → Queue** | Decouple + retry |

## Queue Processing

### Processor Pattern

```typescript
// features/order/processors/order-fulfillment.processor.ts
@Processor('order-fulfillment')
export class OrderFulfillmentProcessor extends BaseProcessor {
  constructor(
    private readonly orderService: OrderService,
    private readonly notificationService: NotificationService,
  ) {
    super()
  }

  @Process('fulfill')
  async handleFulfillment(job: Job<{ orderId: string }>) {
    const { orderId } = job.data
    this.logger.log(`Processing order fulfillment: ${orderId}`)

    await job.progress(10)
    const order = await this.orderService.findById(orderId)

    await job.progress(50)
    await this.orderService.updateStatus(orderId, 'confirmed')

    await job.progress(90)
    await this.notificationService.send(order.userId, 'Order confirmed')

    await job.progress(100)
    return { orderId, status: 'confirmed' }
  }
}
```

### Dispatching Jobs

```typescript
// In service — dispatch async work to queue
async create(userId: string, dto: CreateOrderDto): Promise<Order> {
  const order = await this.orderModel.create({ userId, ...dto })

  await this.orderQueueService.addJob('fulfill', { orderId: order._id.toString() }, {
    dedupeKey: `fulfill:${order._id}`,
    dedupeTtl: 60_000,
  })

  return order.toObject()
}
```

## Shared Infrastructure

### Pagination Decorator + DTO

```typescript
// shared/decorators/pagination.decorator.ts
export const GetPagination = createParamDecorator(
  (data: unknown, ctx: ExecutionContext): PaginationDto => {
    const request = ctx.switchToHttp().getRequest()
    const { skip = 0, limit = 20, sort, search } = request.query

    return {
      skip: Math.max(0, Number(skip)),
      limit: Math.min(100, Math.max(1, Number(limit))),
      sort: parseSort(sort as string),     // '-createdAt' → { createdAt: -1 }
      search: parseSearch(search as string), // 'name:john' → { name: /john/i }
    }
  },
)

function parseSort(raw?: string): Record<string, 1 | -1> {
  if (!raw) return { createdAt: -1 }
  const dir = raw.startsWith('-') ? 1 : -1  // '-' = ascending, default = descending
  const field = raw.replace(/^[+-]/, '')
  return { [field]: dir }
}
```

```typescript
// shared/dto/pagination.dto.ts
export class PageMeta {
  totalDocs: number
  page: number
  limit: number
  totalPages: number
  hasNextPage: boolean
  hasPrevPage: boolean

  constructor(opts: { totalDocs: number; page: number; limit: number }) {
    this.totalDocs = opts.totalDocs
    this.page = opts.page
    this.limit = opts.limit
    this.totalPages = Math.ceil(opts.totalDocs / opts.limit)
    this.hasNextPage = opts.page < this.totalPages
    this.hasPrevPage = opts.page > 1
  }
}

export class PaginatedResponse<T> {
  data: T[]
  meta: PageMeta
}
```

### Shared Schema Mixins

```typescript
// shared/schema/priority.schema.ts
export const PriorityMixin = {
  priority: { type: Number, default: 0, index: true },
  sortOrder: { type: Number, default: 0 },
}

// Usage in any feature schema:
@Schema({ timestamps: true })
export class Category {
  @Prop({ required: true })
  name: string

  @Prop({ default: 0, index: true })
  priority: number
}
```

## Bootstrap (main.ts)

```typescript
// main.ts
async function bootstrap() {
  // Validate environment first
  const env = envSchema.safeParse(process.env)
  if (!env.success) {
    console.error('Invalid env vars:', env.error.format())
    process.exit(1)
  }

  const app = await NestFactory.create(AppModule)

  // Global prefix
  app.setGlobalPrefix('api/v1', { exclude: ['health'] })

  // Security
  app.use(helmet(helmetConfig))
  app.enableCors(corsConfig)

  // Global pipes
  app.useGlobalPipes(new ValidationPipe({
    transform: true,
    whitelist: true,
    forbidNonWhitelisted: true,
    transformOptions: { enableImplicitConversion: true },
  }))

  // Global filters
  app.useGlobalFilters(new HttpExceptionFilter())

  // Swagger
  if (process.env.SWAGGER_ENABLED === 'true') {
    setupSwagger(app)
  }

  // Graceful shutdown
  app.enableShutdownHooks()

  await app.listen(process.env.PORT || 3000)
}

bootstrap()
```

## Root Module

```typescript
// app.module.ts
@Module({
  imports: [
    // Core infrastructure (order matters for dependencies)
    ConfigModule.forRoot({ isGlobal: true }),
    DatabaseModule,
    RedisModule,
    LoggerModule,
    HealthModule,
    QueueModule,
    SchedulerModule,
    EventEmitterModule.forRoot({ wildcard: true }),
    CacheModule.registerAsync({
      isGlobal: true,
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        store: redisStore,
        host: config.get('REDIS_HOST'),
        port: config.get('REDIS_PORT'),
        ttl: 60,
      }),
    }),

    // Feature modules
    AuthModule,
    UserModule,
    OrderModule,
    NotificationModule,
    MediaModule,
    // ... other features
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
```

## Common Anti-Patterns

### 1. Organizing by Technical Layer

```
# BAD — "technical layer" structure
src/
├── controllers/
│   ├── user.controller.ts
│   ├── order.controller.ts
│   └── product.controller.ts
├── services/
│   ├── user.service.ts
│   ├── order.service.ts
│   └── product.service.ts
├── entities/
│   ├── user.schema.ts
│   └── order.schema.ts

# GOOD — "feature-based" structure
src/features/
├── user/
│   ├── user.controller.ts
│   ├── user.service.ts
│   └── entities/user.schema.ts
├── order/
│   ├── order.controller.ts
│   ├── order.service.ts
│   └── entities/order.schema.ts
```

### 2. God Module (Everything in AppModule)

```typescript
// BAD — all providers in root module
@Module({
  providers: [UserService, OrderService, ProductService, EmailService, ...50 more],
})
export class AppModule {}

// GOOD — each feature is its own module
@Module({
  imports: [UserModule, OrderModule, ProductModule],
})
export class AppModule {}
```

### 3. Cross-Feature Direct Service Imports for Side Effects

```typescript
// BAD — tight coupling: OrderService directly calls NotificationService
@Injectable()
export class OrderService {
  constructor(private notificationService: NotificationService) {}

  async create(dto) {
    const order = await this.orderModel.create(dto)
    await this.notificationService.sendOrderConfirmation(order)  // tight coupling
  }
}

// GOOD — emit event, let NotificationModule listen
@Injectable()
export class OrderService {
  constructor(private eventEmitter: EventEmitter2) {}

  async create(dto) {
    const order = await this.orderModel.create(dto)
    this.eventEmitter.emit('order.created', { orderId: order._id })  // decoupled
  }
}
```

### 4. No Global Exception Filter

```typescript
// BAD — try/catch in every controller method
@Get(':id')
async findOne(@Param('id') id: string) {
  try {
    return await this.service.findOne(id)
  } catch (error) {
    throw new HttpException(error.message, 500)
  }
}

// GOOD — throw domain exceptions, global filter handles formatting
@Get(':id')
async findOne(@Param('id') id: string) {
  return this.service.findOneOrFail(id)  // throws NotFoundException if missing
}
```

### 5. Business Logic in Controllers

```typescript
// BAD — controller does business logic
@Post()
async create(@Body() dto: CreateOrderDto) {
  const price = dto.items.reduce((sum, i) => sum + i.price * i.quantity, 0)
  const tax = price * 0.1
  const order = await this.orderModel.create({ ...dto, total: price + tax })
  await this.mailerService.send(...)
  return order
}

// GOOD — controller delegates to service
@Post()
async create(@Body() dto: CreateOrderDto) {
  return this.orderService.create(dto)
}
```

### 6. Missing Graceful Shutdown

```typescript
// BAD — active queue jobs lost on deploy, connections leaked

// GOOD — clean shutdown
app.enableShutdownHooks()

@Injectable()
export class AppCleanupService implements OnApplicationShutdown {
  constructor(private queueService: BaseQueueService) {}

  async onApplicationShutdown(signal: string) {
    logger.log(`Shutting down on ${signal}`)
    await this.queueService.gracefulShutdown(30_000)
    await mongoose.connection.close()
  }
}
```

## Module Dependency Rules

1. **Core modules** are `@Global()` — imported once in `AppModule`, available everywhere
2. **Feature modules** import only what they need — use `imports: [OtherModule]` and consume exported services
3. **Shared utilities** are standalone — imported directly in features that need them
4. **Circular dependencies** resolved with `forwardRef(() => ModuleA)` — keep these rare
5. **Feature-to-feature communication** prefers events over direct imports
6. **Never import a feature module just for a type** — move shared types to `shared/interfaces/`

## Quick Reference

| Task | Pattern |
|------|---------|
| New feature | Create `features/<name>/` with module, controller, service, dto/, entities/ |
| Cross-feature side effect | `EventEmitter2` + `@OnEvent()` listener |
| Async heavy work | Bull queue + processor |
| Input validation | class-validator DTOs + global `ValidationPipe` |
| Auth on route | `@Auth(Role.USER)` + `@CurrentUser()` |
| Pagination | `@GetPagination()` decorator + `PaginatedResponse<T>` |
| Error response | Throw `AppException` subclass, global filter formats it |
| Cron job | `@Cron()` in `SchedulerService` |
| Health check | Add indicator in `HealthController.check()` |
| Config value | `ConfigService.get('KEY')` — validated at startup |

## Further Reading

For detailed reference on specific topics, see:
- `references/advanced-patterns.md` — Middleware chains, custom decorators, interceptors, versioning, testing strategies, Docker setup, CI/CD patterns
