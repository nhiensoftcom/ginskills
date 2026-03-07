# Active Life Backend - Setup & Configuration

## Project Location
```
/Users/nhiensoft/Workspace/ginstudio/active-life/be-store-active-life-global/
```

## Prerequisites
- Node.js (ES2022 compatible)
- Yarn package manager
- PostgreSQL (Supabase recommended)
- Redis (optional, for caching)

## Installation

```bash
cd be-store-active-life-global
yarn install
yarn db:generate    # Generate Prisma client
yarn dev            # Start dev server with hot-reload
```

## Environment Variables

### Required (.env)
```env
DATABASE_URL=""                      # Supabase pooler connection (for runtime)
DIRECT_URL=""                        # Direct DB connection (for migrations)
PORT=3000                            # Server port
JWT_CLIENT_ACCESS_TOKEN_SECRET=""    # JWT signing secret
JWT_CLIENT_ACCESS_EXPIRE="15d"       # Token expiry duration
```

### Supabase Connection Setup

**IMPORTANT**: Use the correct connection format for Supabase:

**Pooler URL (DATABASE_URL)** — for application runtime:
```
postgresql://postgres.[project-ref]:[password]@aws-0-[region].pooler.supabase.com:6543/postgres?pgbouncer=true
```

**Direct URL (DIRECT_URL)** — for migrations only:
```
postgresql://postgres.[project-ref]:[password]@aws-0-[region].pooler.supabase.com:5432/postgres
```

**Common Error**: "Tenant or user not found" — Make sure username is `postgres.[project-ref]` NOT just `postgres`.

### Optional Environment Variables
```env
# eTelecom
ETELECOM_URL=                        # eTelecom API base URL
AT_ETELECOM=                         # eTelecom API token

# Email
MAIL_HOST=                           # SMTP host
MAIL_PORT=                           # SMTP port
MAIL_USER=                           # SMTP username
MAIL_PASS=                           # SMTP password
MAIL_FROM=                           # Default sender

# Firebase
FIREBASE_PROJECT_ID=
FIREBASE_PRIVATE_KEY=
FIREBASE_CLIENT_EMAIL=

# Redis
REDIS_URL=                           # Redis connection URL

# MongoDB (if used)
MONGODB_URI=                         # MongoDB connection string
```

## Database Commands

```bash
# Sync schema to database (keeps existing data)
yarn db:push

# Create and run a migration (production-ready)
yarn db:migrate

# Seed database with initial data
yarn db:seed

# Open Prisma Studio (GUI for database)
yarn db:studio

# Generate Prisma client (after schema changes)
yarn db:generate

# Reset database (DESTRUCTIVE - drops all data)
yarn db:reset
```

### Migration Workflow
1. Edit `prisma/schema.prisma`
2. Run `yarn db:push` for development (quick, keeps data)
3. Run `yarn db:migrate` for production (creates migration files)
4. Commit migration files to git

## All Scripts (package.json)

```bash
yarn dev              # nest start --watch (hot-reload)
yarn build            # nest build
yarn start            # nest start
yarn start:prod       # node dist/main
yarn start:debug      # nest start --debug --watch
yarn lint             # eslint --fix
yarn format           # prettier --write
yarn test             # jest
yarn test:watch       # jest --watch
yarn test:cov         # jest --coverage
yarn test:e2e         # jest --config ./test/jest-e2e.json
```

## Configuration Files

### nest-cli.json
- Builder: TypeScript compiler
- Assets: `mail/templates` copied to dist
- Source root: `src/`

### tsconfig.json
- Target: ES2022
- Module: CommonJS
- Path alias: `@prisma/*` → `src/generated/prisma/*`
- Strict mode: Relaxed (noImplicitAny: false, strictNullChecks: false)

### .prettierrc
```json
{
  "singleQuote": true,
  "trailingComma": "all"
}
```

### .eslintrc.js
- Parser: @typescript-eslint
- Relaxed rules for rapid development

## API Documentation

Swagger UI available at: `http://localhost:3000/api`

## API Versioning

URI-based versioning:
- v1: `http://localhost:3000/api/v1/...`
- v2: `http://localhost:3000/api/v2/...`

Default version: v1 and v2 (both active)

## CORS Configuration

All origins allowed (development mode):
```typescript
app.enableCors({
  origin: true,
  methods: 'GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS',
  credentials: true,
});
```

## Rate Limiting

Global throttle: 10 requests per 60 seconds per IP.
