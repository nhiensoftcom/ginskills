# Advanced NestJS Architecture Patterns

Detailed reference for patterns beyond the main SKILL.md. Load this when the user works on advanced infrastructure.

## Custom Decorators

### Compose Multiple Decorators

```typescript
// shared/decorators/auth.decorator.ts
import { applyDecorators, SetMetadata, UseGuards } from '@nestjs/common'
import { ApiBearerAuth, ApiUnauthorizedResponse } from '@nestjs/swagger'

export function Auth(...roles: Role[]) {
  return applyDecorators(
    SetMetadata('roles', roles),
    UseGuards(HybridAuthGuard, RolesGuard),
    ApiBearerAuth(),
    ApiUnauthorizedResponse({ description: 'Unauthorized' }),
  )
}

// Usage — single decorator replaces 4 lines
@Auth(Role.ADMIN)
@Get('admin/users')
async getAdminUsers() { ... }
```

### Current User Decorator

```typescript
// shared/decorators/current-user.decorator.ts
export const CurrentUser = createParamDecorator(
  (field: keyof UserDocument | undefined, ctx: ExecutionContext) => {
    const request = ctx.switchToHttp().getRequest()
    const user = request.user
    return field ? user?.[field] : user
  },
)

// Usage
@Get('me')
async getProfile(@CurrentUser() user: UserDocument) { ... }

@Get('me/name')
async getName(@CurrentUser('firstName') name: string) { ... }
```

### API Field Selection Decorator

```typescript
// shared/decorators/api-select.decorator.ts
export const ApiSelect = createParamDecorator(
  (data: unknown, ctx: ExecutionContext): string => {
    const request = ctx.switchToHttp().getRequest()
    return request.query.fields || ''  // 'name,email,avatar'
  },
)

// Usage in service
async findAll(fields: string) {
  const select = fields.split(',').join(' ')
  return this.userModel.find().select(select).lean()
}
```

## Interceptors

### Response Transform Interceptor

```typescript
// shared/interceptors/transform.interceptor.ts
@Injectable()
export class TransformInterceptor<T> implements NestInterceptor<T, ResponseWrapper<T>> {
  intercept(context: ExecutionContext, next: CallHandler): Observable<ResponseWrapper<T>> {
    return next.handle().pipe(
      map((data) => ({
        success: true,
        data,
        timestamp: new Date().toISOString(),
      })),
    )
  }
}
```

### Logging Interceptor

```typescript
// shared/interceptors/logging.interceptor.ts
@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  private readonly logger = new Logger('HTTP')

  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    const request = context.switchToHttp().getRequest()
    const { method, url } = request
    const start = Date.now()

    return next.handle().pipe(
      tap(() => {
        const duration = Date.now() - start
        this.logger.log(`${method} ${url} — ${duration}ms`)
      }),
    )
  }
}
```

### Cache Interceptor (Per-Route)

```typescript
// shared/interceptors/cache.interceptor.ts
@Injectable()
export class HttpCacheInterceptor extends CacheInterceptor {
  trackBy(context: ExecutionContext): string | undefined {
    const request = context.switchToHttp().getRequest()
    // Only cache GET requests for authenticated users
    if (request.method !== 'GET') return undefined
    return `${request.user?.id}:${request.url}`
  }
}

// Usage
@UseInterceptors(HttpCacheInterceptor)
@CacheTTL(300) // 5 minutes
@Get()
async findAll() { ... }
```

## Middleware Patterns

### Request Context Middleware

```typescript
// shared/middleware/request-context.middleware.ts
@Injectable()
export class RequestContextMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    // Attach unique request ID for tracing
    req['requestId'] = req.headers['x-request-id'] || randomUUID()
    res.setHeader('x-request-id', req['requestId'])

    // Attach start time for duration tracking
    req['startTime'] = Date.now()

    next()
  }
}

// Register in module
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(RequestContextMiddleware).forRoutes('*')
  }
}
```

### Conditional Middleware

```typescript
// Apply middleware only to specific routes
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer
      .apply(RawBodyMiddleware)
      .forRoutes({ path: 'webhooks/*', method: RequestMethod.POST })

    consumer
      .apply(LoggingMiddleware)
      .exclude({ path: 'health', method: RequestMethod.GET })
      .forRoutes('*')
  }
}
```

## API Versioning

### URI Versioning (Recommended)

```typescript
// main.ts
app.enableVersioning({
  type: VersioningType.URI,
  defaultVersion: '1',
  prefix: 'api/v',
})

// Controller
@Controller({ path: 'users', version: '1' })
export class UserV1Controller { ... }

@Controller({ path: 'users', version: '2' })
export class UserV2Controller { ... }

// Routes:
// GET /api/v1/users → UserV1Controller
// GET /api/v2/users → UserV2Controller
```

### Version-Neutral Routes

```typescript
// Health check available at /health (no version prefix)
@Controller({ path: 'health', version: VERSION_NEUTRAL })
export class HealthController { ... }
```

## Testing Strategies

### Unit Test — Service

```typescript
// features/order/order.service.spec.ts
describe('OrderService', () => {
  let service: OrderService
  let model: Model<OrderDocument>

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        OrderService,
        {
          provide: getModelToken(Order.name),
          useValue: {
            find: jest.fn(),
            findOne: jest.fn(),
            create: jest.fn(),
            countDocuments: jest.fn(),
          },
        },
        {
          provide: EventEmitter2,
          useValue: { emit: jest.fn() },
        },
      ],
    }).compile()

    service = module.get(OrderService)
    model = module.get(getModelToken(Order.name))
  })

  describe('findOneOrFail', () => {
    it('should throw NotFoundException when order not found', async () => {
      jest.spyOn(model, 'findOne').mockReturnValue({
        lean: () => ({ exec: () => Promise.resolve(null) }),
      } as any)

      await expect(service.findOneOrFail('id', 'userId'))
        .rejects.toThrow(NotFoundException)
    })
  })
})
```

### Integration Test — Controller

```typescript
// features/order/order.controller.spec.ts
describe('OrderController (e2e)', () => {
  let app: INestApplication
  let mongoServer: MongoMemoryServer

  beforeAll(async () => {
    mongoServer = await MongoMemoryServer.create()

    const module = await Test.createTestingModule({
      imports: [
        MongooseModule.forRoot(mongoServer.getUri()),
        OrderModule,
      ],
    }).compile()

    app = module.createNestApplication()
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }))
    await app.init()
  })

  afterAll(async () => {
    await app.close()
    await mongoServer.stop()
  })

  it('POST /orders — should validate input', () => {
    return request(app.getHttpServer())
      .post('/orders')
      .send({ items: [] })  // empty items should fail
      .expect(422)
  })

  it('POST /orders — should create order', () => {
    return request(app.getHttpServer())
      .post('/orders')
      .send({ items: [{ productId: 'abc', quantity: 2 }] })
      .expect(201)
      .expect((res) => {
        expect(res.body.total).toBeDefined()
      })
  })
})
```

### Testing Queue Processors

```typescript
describe('OrderFulfillmentProcessor', () => {
  let processor: OrderFulfillmentProcessor

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        OrderFulfillmentProcessor,
        { provide: OrderService, useValue: { findById: jest.fn(), updateStatus: jest.fn() } },
        { provide: NotificationService, useValue: { send: jest.fn() } },
      ],
    }).compile()

    processor = module.get(OrderFulfillmentProcessor)
  })

  it('should process fulfillment job', async () => {
    const mockJob = { data: { orderId: '123' }, progress: jest.fn() } as any
    const result = await processor.handleFulfillment(mockJob)
    expect(result.status).toBe('confirmed')
    expect(mockJob.progress).toHaveBeenCalledWith(100)
  })
})
```

## Docker Setup

### Multi-Stage Dockerfile

```dockerfile
# Stage 1: Build
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts
COPY . .
RUN npm run build
RUN npm prune --production

# Stage 2: Production
FROM node:20-alpine AS production
WORKDIR /app

RUN addgroup -g 1001 -S nestjs && adduser -S nestjs -u 1001
COPY --from=builder --chown=nestjs:nestjs /app/dist ./dist
COPY --from=builder --chown=nestjs:nestjs /app/node_modules ./node_modules
COPY --from=builder --chown=nestjs:nestjs /app/package.json ./

USER nestjs
EXPOSE 3000
CMD ["node", "dist/main.js"]
```

### Docker Compose (Development)

```yaml
version: '3.8'
services:
  api:
    build: .
    ports: ['3000:3000']
    env_file: .env
    depends_on:
      mongodb:
        condition: service_healthy
      redis:
        condition: service_healthy
    volumes:
      - ./uploads:/app/uploads

  mongodb:
    image: mongo:7
    ports: ['27017:27017']
    volumes: ['mongo-data:/data/db']
    healthcheck:
      test: mongosh --eval "db.adminCommand('ping')"
      interval: 10s
      timeout: 5s
      retries: 3

  redis:
    image: redis:7-alpine
    ports: ['6379:6379']
    healthcheck:
      test: redis-cli ping
      interval: 10s
      timeout: 5s
      retries: 3

volumes:
  mongo-data:
```

## Swagger / OpenAPI Setup

```typescript
// core/config/swagger.config.ts
export function setupSwagger(app: INestApplication) {
  const config = new DocumentBuilder()
    .setTitle('API Documentation')
    .setVersion('1.0')
    .addBearerAuth({
      type: 'http',
      scheme: 'bearer',
      bearerFormat: 'JWT',
    })
    .build()

  const document = SwaggerModule.createDocument(app, config)
  SwaggerModule.setup('docs', app, document, {
    swaggerOptions: {
      persistAuthorization: true,
      tagsSorter: 'alpha',
      operationsSorter: 'alpha',
    },
  })
}
```

### Swagger Decorators on DTOs

```typescript
export class CreateUserDto {
  @ApiProperty({ example: 'John', description: 'First name' })
  @IsString()
  @MinLength(2)
  firstName: string

  @ApiProperty({ example: 'john@example.com' })
  @IsEmail()
  email: string

  @ApiPropertyOptional({ example: '+1234567890' })
  @IsString()
  @IsOptional()
  phone?: string
}
```

## File Upload Pattern

```typescript
// features/media/media.controller.ts
@Controller('media')
export class MediaController {
  constructor(private readonly mediaService: MediaStorageService) {}

  @Post('upload')
  @Auth(Role.USER)
  @UseInterceptors(FileInterceptor('file', {
    limits: { fileSize: 10 * 1024 * 1024 },  // 10MB
    fileFilter: (req, file, cb) => {
      const allowed = /\.(jpg|jpeg|png|webp|gif)$/i
      if (!allowed.test(file.originalname)) {
        return cb(new BadRequestException('Only image files allowed'), false)
      }
      cb(null, true)
    },
  }))
  async upload(
    @CurrentUser() user: UserDocument,
    @UploadedFile() file: Express.Multer.File,
  ) {
    return this.mediaService.upload(file, { userId: user.id })
  }
}
```

### Storage Abstraction (S3 / Local)

```typescript
// features/media/services/media-storage.service.ts
@Injectable()
export class MediaStorageService {
  private readonly strategy: StorageStrategy

  constructor(private config: ConfigService) {
    this.strategy = config.get('STORAGE_TYPE') === 's3'
      ? new S3StorageStrategy(config)
      : new LocalStorageStrategy(config)
  }

  async upload(file: Express.Multer.File, opts: UploadOpts): Promise<UploadResult> {
    return this.strategy.upload(file, opts)
  }

  async delete(key: string): Promise<void> {
    return this.strategy.delete(key)
  }
}
```

## WebSocket Gateway

```typescript
// features/chat/chat.gateway.ts
@WebSocketGateway({
  cors: { origin: '*' },
  namespace: '/chat',
})
export class ChatGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server: Server

  private readonly logger = new Logger('ChatGateway')

  handleConnection(client: Socket) {
    this.logger.log(`Client connected: ${client.id}`)
  }

  handleDisconnect(client: Socket) {
    this.logger.log(`Client disconnected: ${client.id}`)
  }

  @SubscribeMessage('message')
  handleMessage(client: Socket, payload: { room: string; content: string }) {
    this.server.to(payload.room).emit('message', {
      sender: client.id,
      content: payload.content,
      timestamp: new Date(),
    })
  }
}
```

## CI/CD Patterns

### Git Hooks (Husky + lint-staged)

```json
// package.json
{
  "lint-staged": {
    "*.ts": ["eslint --fix", "prettier --write"]
  }
}
```

```bash
# .husky/pre-commit
npx lint-staged

# .husky/commit-msg
npx commitlint --edit $1
```

### Commitlint Config

```javascript
// commitlint.config.js
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [2, 'always', [
      'feat', 'fix', 'docs', 'style', 'refactor',
      'perf', 'test', 'build', 'ci', 'chore', 'revert',
    ]],
    'subject-max-length': [2, 'always', 100],
  },
}
```

## Scaling Considerations

### Horizontal Scaling Checklist

- [ ] API layer is stateless (no in-memory sessions)
- [ ] Session/auth state stored in Redis
- [ ] File uploads go to S3 (not local disk)
- [ ] Queue workers can run as separate processes
- [ ] Database connection pool sized per instance
- [ ] Health checks return instance-specific metrics
- [ ] Graceful shutdown handles SIGTERM
- [ ] Sticky sessions disabled (or WebSocket uses Redis adapter)

### Extracting Microservices

When a feature outgrows the monolith:

1. The feature already has its own module with clear boundaries
2. Extract the module into a standalone NestJS app
3. Replace direct imports with HTTP/gRPC/message queue calls
4. Events already decouple side effects — minimal rewiring needed
5. Shared DTOs/interfaces move to a common package

This is the strength of feature-based architecture: each module is already a microservice boundary waiting to be extracted.
