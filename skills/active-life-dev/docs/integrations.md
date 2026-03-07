# Active Life Backend - External Integrations

## 1. eTelecom (SIP Phone System)

### Purpose
Call center integration for TeleSales and LiveChat staff. Staff members are assigned SIP extensions to make/receive calls.

### Models
- `EtelecomExtension` — SIP extension config (extensionNumber, password, tenantId, tenantDomain)
- `OmiCall` — Call log records (callId, direction, fromNumber, toNumber, status, duration, recordingUrl)

### Module: `src/etelecom/`
- **Controller**: Extension management, webhook receiver
- **Service**: Create extensions, link to staff, process webhooks

### Key Endpoints
```
POST /api/v1/etelecom/extension      — Create SIP extension
POST /api/v1/etelecom/link-staff     — Link staff to extension
POST /api/v1/etelecom/webhook        — Receive call events (Public)
GET  /api/v1/etelecom/calls          — List call logs
```

### JWT Integration
Staff JWT payload includes eTelecom data:
```typescript
{
  etelecom: {
    extensionNumber: string;
    extensionPassword: string;
    tenantId: string;
    tenantDomain: string;
  }
}
```

### Environment Variables
```
ETELECOM_URL=           # eTelecom API base URL
AT_ETELECOM=            # eTelecom API token
```

---

## 2. Firebase

### Dependencies
```json
"firebase": "^11.4.0",
"firebase-admin": "^12.6.0"
```

### Usage
- Push notifications to mobile clients
- Possible auth integration for social login
- Firebase Admin SDK for server-side operations

### Configuration
Firebase config expected via environment variables or service account JSON.

---

## 3. Redis (IORedis)

### Dependencies
```json
"@nestjs-modules/ioredis": "^2.0.2",
"ioredis": "^5.8.2"
```

### Usage
- Session caching
- Rate limiting support
- Temporary data storage
- Queue management (potential)

### Setup in AppModule
```typescript
import { RedisModule } from '@nestjs-modules/ioredis';

RedisModule.forRoot({
  type: 'single',
  url: process.env.REDIS_URL,
})
```

---

## 4. Email (Nodemailer)

### Dependencies
```json
"@nestjs-modules/mailer": "^1.6.1",
"nodemailer": "^6.9.14"
```

### Usage
- Transactional emails (order confirmation, password reset)
- Templates in `views/mail/templates/` directory
- EJS template engine

### Setup
```typescript
import { MailerModule } from '@nestjs-modules/mailer';

MailerModule.forRoot({
  transport: {
    host: process.env.MAIL_HOST,
    port: process.env.MAIL_PORT,
    auth: {
      user: process.env.MAIL_USER,
      pass: process.env.MAIL_PASS,
    },
  },
  defaults: {
    from: process.env.MAIL_FROM,
  },
  template: {
    dir: join(__dirname, '..', 'views', 'mail', 'templates'),
    adapter: new EjsAdapter(),
  },
})
```

---

## 5. Mongoose (MongoDB - Secondary)

### Dependencies
```json
"@nestjs/mongoose": "^10.0.0",
"mongoose": "^8.5.0",
"mongoose-delete": "^1.0.2"
```

### Usage
- Secondary database for specific use cases
- Soft delete support via mongoose-delete plugin
- NOT the primary database (Prisma/PostgreSQL is primary)

### Note
Some models may use MongoDB for flexible schema requirements or legacy data. Check individual modules for MongoDB vs Prisma usage.

---

## 6. Swagger / OpenAPI

### Dependency
```json
"@nestjs/swagger": "^7.0.0"
```

### Access
Available at `/api` endpoint in development.

### Usage in Controllers
```typescript
@ApiTags('products')
@ApiBearerAuth()
@Controller('product')
export class ProductController {
  @Post()
  @ApiOperation({ summary: 'Create a new product' })
  @ApiResponse({ status: 201, description: 'Product created' })
  create(@Body() dto: CreateProductDto) { }
}
```

---

## 7. Rate Limiting (Throttler)

### Dependency
```json
"@nestjs/throttler": "^6.0.0"
```

### Configuration
```typescript
ThrottlerModule.forRoot([{
  ttl: 60000,   // 60 seconds window
  limit: 10,    // Max 10 requests per window
}])
```

Global rate limiting applied to all endpoints.

---

## Integration Architecture

```
                    ┌─────────────┐
                    │   Clients   │
                    │ (Mobile/Web)│
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │   NestJS    │
                    │   API       │
                    └──────┬──────┘
                           │
           ┌───────┬───────┼───────┬────────┐
           │       │       │       │        │
      ┌────▼──┐ ┌──▼───┐ ┌▼────┐ ┌▼─────┐ ┌▼────────┐
      │Supabase│ │Redis │ │Email│ │Firebase│ │eTelecom │
      │  PG   │ │Cache │ │SMTP │ │ Push  │ │  SIP    │
      └───────┘ └──────┘ └─────┘ └──────┘ └─────────┘
```
