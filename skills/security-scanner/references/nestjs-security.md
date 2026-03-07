# NestJS Backend Security Checklist

Deep-dive security checklist for the NestJS backend. Read this when scanning the backend.

## Table of Contents
1. [Authentication & JWT](#authentication--jwt)
2. [Authorization & RBAC](#authorization--rbac)
3. [Input Validation & Injection](#input-validation--injection)
4. [Rate Limiting & DoS](#rate-limiting--dos)
5. [File Upload](#file-upload)
6. [Error Handling & Info Disclosure](#error-handling--info-disclosure)
7. [Database Security](#database-security)
8. [Cache & Session Security](#cache--session-security)
9. [Third-Party API Security](#third-party-api-security)
10. [LLM/AI Agent Security](#llmai-agent-security)

---

## Authentication & JWT

### Token Configuration
- File: `core/config/jwt.config.ts`
- Access token: 15min expiry (good)
- Refresh token: 7d / 30d with "remember me"

### Checklist
- [ ] JWT secret loaded from env, not hardcoded
- [ ] Token expiration enforced (`ignoreExpiration: false`)
- [ ] Refresh token rotation on use (old token invalidated)
- [ ] Refresh token stored server-side (Redis/DB) for revocation
- [ ] Logout invalidates refresh token
- [ ] Token extraction order: Bearer header → signed cookie → regular cookie
- [ ] No token in URL query parameters
- [ ] JWE (encrypted JWT) considered for sensitive claims

### Common Vulnerabilities
```typescript
// BAD: JWT algorithm confusion
jwt.verify(token, secret) // No algorithm specified — attacker could use 'none'

// GOOD: Specify algorithm
jwt.verify(token, secret, { algorithms: ['HS256'] })
```

## Authorization & RBAC

### Checklist
- [ ] All endpoints have `@UseGuards(JwtAuthGuard)` unless intentionally public
- [ ] Public endpoints documented with `@Public()` decorator
- [ ] Role guard (`roles.guard.ts`) checks resource ownership, not just role
- [ ] Admin bypass is restricted to verified admin accounts
- [ ] No horizontal privilege escalation (user A accessing user B's data)
- [ ] Bulk endpoints check ownership for each item

### IDOR Check Pattern
```typescript
// BAD: No ownership check
@Get(':id')
findOne(@Param('id') id: string) {
  return this.service.findById(id); // Any user can access any record
}

// GOOD: Ownership check
@Get(':id')
findOne(@Param('id') id: string, @CurrentUser() user: User) {
  return this.service.findByIdAndUser(id, user._id);
}
```

## Input Validation & Injection

### Global Validation (already configured in main.ts)
- `whitelist: true` — strips unknown properties
- `forbidNonWhitelisted: true` — rejects unknown properties
- `transform: true` — auto-transforms types

### NoSQL Injection Checklist
- [ ] No raw `$where` queries with user input
- [ ] No `$regex` with unescaped user input
- [ ] No `JSON.parse()` of user input used directly in queries
- [ ] Mongoose `.lean()` used where possible (prevents prototype pollution)
- [ ] ObjectId params validated with `@IsMongoId()`

```typescript
// BAD: NoSQL injection possible
const users = await this.userModel.find({ name: req.body.name });
// If req.body.name = { "$gt": "" }, returns all users

// GOOD: Validate type first
@IsString() name: string; // class-validator ensures string type
```

### Prototype Pollution
- [ ] No `Object.assign()` or spread with unchecked user input into query objects
- [ ] `JSON.parse()` outputs validated before use

## Rate Limiting & DoS

### Checklist
- [ ] Rate limiting on auth endpoints (login, register, forgot-password)
- [ ] Rate limiting on API endpoints (especially AI/LLM which are expensive)
- [ ] File upload size limits configured
- [ ] Request body size limit set
- [ ] Pagination enforced (no unbounded `find()`)
- [ ] Bull queue jobs have timeout limits
- [ ] LLM API calls have timeout and token limits

### Implementation
```typescript
// NestJS throttler
@Throttle({ default: { limit: 5, ttl: 60000 } })
@Post('login')
login() { ... }
```

## File Upload

### Checklist
- [ ] File type validated (not just extension — check magic bytes)
- [ ] File size limited
- [ ] Uploaded files stored outside webroot (S3, not `/public`)
- [ ] Filenames sanitized (no path traversal `../`)
- [ ] Image files re-encoded to strip EXIF/metadata
- [ ] No server-side file execution possible

## Error Handling & Info Disclosure

### Checklist
- [ ] Production mode strips stack traces (`HttpExceptionFilter`)
- [ ] No internal paths leaked in error messages
- [ ] No database error details in API responses
- [ ] No technology fingerprinting (remove `X-Powered-By`)
- [ ] Mongoose validation errors don't expose schema structure

```typescript
// BAD: Leaks internal details
catch (error) {
  throw new InternalServerErrorException(error.message);
}

// GOOD: Generic message, log details internally
catch (error) {
  this.logger.error('Operation failed', error.stack);
  throw new InternalServerErrorException('An unexpected error occurred');
}
```

## Database Security

### MongoDB Checklist
- [ ] Connection string uses authentication
- [ ] TLS/SSL enabled for database connections
- [ ] Database user has minimal required permissions
- [ ] Indexes exist on fields used in auth queries (email, userId)
- [ ] No `$where` or `$expr` with user-controlled input
- [ ] Backup encryption enabled

## Cache & Session Security

### Redis Checklist
- [ ] Redis requires authentication (`REDIS_PASSWORD`)
- [ ] Redis connection uses TLS in production
- [ ] Cache keys don't contain sensitive data
- [ ] Cache invalidation on permission changes
- [ ] Session data encrypted at rest

## Third-Party API Security

### Checklist
- [ ] All API keys loaded from environment variables
- [ ] API keys have minimal required permissions/scopes
- [ ] Webhook endpoints validate request signatures
- [ ] External API responses validated before use
- [ ] Timeout configured for all HTTP clients
- [ ] Circuit breaker on external service calls

### Known External Services
Check for these common integrations:
- Image generation APIs — API key management
- LLM providers (OpenAI, Google/Vertex AI, Anthropic) — API keys
- Cloud storage (AWS S3, GCS) — credentials and IAM
- Vector databases (Qdrant, Pinecone, Weaviate) — access control
- Payment processors — webhook signature verification

## LLM/AI Agent Security (OWASP LLM Top 10:2025)

This project uses LangChain + LangGraph with multi-provider LLMs (OpenAI, Gemini, Vertex AI) and Qdrant vector DB. AI agent security is a critical surface.

### Prompt Injection (LLM01) — #1 Risk
- [ ] User input sanitized before inclusion in LLM prompts
- [ ] System prompts not exposed to users (check for leakage via prompt tricks)
- [ ] Tool calls validated and sandboxed
- [ ] LLM output not trusted for authorization decisions
- [ ] Rate limiting on AI endpoints (expensive operations)
- [ ] Multi-modal inputs (images) checked for embedded prompt injections
- [ ] Indirect injection: external documents processed by RAG checked for injected instructions

**Mitigation reality check:** Prompt injection cannot be fully prevented with current LLM architecture. Focus on containment — least privilege, output validation, logging, and separating instructions from data.

### Sensitive Information Disclosure (LLM02)
- [ ] PII not sent to external LLM providers unnecessarily
- [ ] Conversation history access restricted to conversation owner
- [ ] Knowledge base doesn't contain user PII
- [ ] LLM responses sanitized before storing/displaying
- [ ] Model responses don't echo back system prompts or internal config

### Improper Output Handling (LLM05)
- [ ] AI-generated HTML/markdown sanitized before frontend rendering
- [ ] AI-suggested actions validated before execution
- [ ] No `dangerouslySetInnerHTML` with raw AI output
- [ ] URLs in AI responses validated (no `javascript:` links)

### Excessive Agency (LLM06)
- [ ] LangGraph tools scoped to minimum required permissions
- [ ] Agent can't access resources outside current user's scope
- [ ] Human-in-the-loop for destructive or irreversible actions
- [ ] Tool execution timeouts prevent runaway agents
- [ ] Cross-agent trust: agents can't escalate each other's permissions

### System Prompt Leakage (LLM07)
- [ ] System prompts not retrievable via "ignore previous instructions" attacks
- [ ] No system prompt content in error messages
- [ ] Prompt templates don't contain sensitive business logic that would be harmful if exposed

### Vector/Embedding Weaknesses (LLM08)
- [ ] Qdrant vector DB requires authentication
- [ ] Access to knowledge base restricted by user/tenant
- [ ] Embedding poisoning: can users inject malicious content into the knowledge base?
- [ ] Retrieval results validated before inclusion in prompts

### Unbounded Consumption (LLM10)
- [ ] Max token limits on LLM API calls
- [ ] Rate limiting per user on AI endpoints
- [ ] Timeout on LangGraph agent execution
- [ ] Cost alerting for LLM provider API usage
- [ ] Queue-based processing with bounded concurrency for AI jobs

### Tool Execution
- [ ] LangGraph tools have input validation
- [ ] Tools can't access resources outside their scope
- [ ] Tool errors don't leak internal state
- [ ] Tool call chains have maximum depth limit

## Known NestJS Vulnerabilities

### CVE-2025-54782 — RCE in @nestjs/devtools-integration
- **Affected:** `@nestjs/devtools-integration` ≤ 0.2.0
- **Impact:** Remote code execution on developer machines via unsafe `vm.runInNewContext()` + missing CORS
- **Fix:** Upgrade to ≥ 0.2.1
- [ ] Check if `@nestjs/devtools-integration` is in dependencies and version is ≥ 0.2.1

## Security Logging & Alerting (OWASP A09:2025)

- [ ] Auth events logged (login success/failure, token refresh, logout)
- [ ] Admin actions logged with actor + target + timestamp
- [ ] Failed access control attempts logged and alerted
- [ ] Rate limit violations logged
- [ ] Suspicious AI usage patterns detected (repeated prompt injection attempts)
- [ ] Logs don't contain PII or secrets (sanitize before logging)
- [ ] Log aggregation configured (Pino → structured JSON → log service)
