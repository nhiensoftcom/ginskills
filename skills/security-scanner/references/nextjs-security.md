# Next.js Frontend Security Checklist

Deep-dive security checklist for the Next.js frontend. Read this when scanning the frontend.

## Table of Contents
1. [Server/Client Boundary](#serverclient-boundary)
2. [API Routes](#api-routes)
3. [Authentication & Session](#authentication--session)
4. [XSS Prevention](#xss-prevention)
5. [Environment Variables](#environment-variables)
6. [Middleware & Headers](#middleware--headers)
7. [Dependencies](#dependencies)

---

## Server/Client Boundary

Next.js 15 App Router has a critical server/client boundary. Mistakes here cause security issues.

### Checklist
- [ ] Server Components don't pass secrets to Client Components via props
- [ ] `"use client"` files don't import server-only modules
- [ ] Server Actions validate input (they're public HTTP endpoints!)
- [ ] No `process.env.SECRET_*` accessed in client components
- [ ] `server-only` package used to prevent accidental client imports

### Dangerous Pattern
```typescript
// BAD: Server component passes secret to client
// page.tsx (Server Component)
export default function Page() {
  return <ClientComponent apiKey={process.env.SECRET_API_KEY} />;
  // Secret ends up in client bundle!
}

// GOOD: Server component uses secret server-side only
export default async function Page() {
  const data = await fetchWithSecret(process.env.SECRET_API_KEY);
  return <ClientComponent data={data} />;
}
```

## API Routes

### Location: `src/app/api/`

### Checklist
- [ ] All API routes check authentication before processing
- [ ] Input validated with Zod or similar
- [ ] Error responses don't leak internal details
- [ ] Rate limiting on sensitive endpoints
- [ ] CORS headers set correctly (or inherited from middleware)
- [ ] No secrets returned in API responses
- [ ] POST/PUT/DELETE routes check CSRF token

### Current Pattern
```typescript
// src/app/api/me/route.ts — proxies to backend
// Check: Is auth token validated before proxying?
// Check: Are error responses generic?
```

## Authentication & Session

### Checklist
- [ ] JWT stored in httpOnly cookie (not localStorage)
- [ ] Cookie has `Secure` flag (HTTPS only)
- [ ] Cookie has `SameSite=Strict` or `SameSite=Lax`
- [ ] Cookie `Path` is restricted (not `/`)
- [ ] Token refresh handled transparently
- [ ] Logout clears all auth cookies
- [ ] CSRF protection on state-changing requests
- [ ] Session timeout after inactivity

### Token Storage Safety
```typescript
// BAD: Token in localStorage (XSS accessible)
localStorage.setItem('token', jwt);

// BAD: Token in client-side state (lost on refresh, XSS accessible)
const [token, setToken] = useState(jwt);

// GOOD: httpOnly cookie (not accessible via JavaScript)
// Set by backend, sent automatically by browser
```

## XSS Prevention

### Checklist
- [ ] No `dangerouslySetInnerHTML` with user content
- [ ] Markdown rendering sanitized (DOMPurify or similar)
- [ ] AI-generated content sanitized before display
- [ ] SVG uploads sanitized (can contain inline scripts)
- [ ] URL parameters not reflected in HTML without encoding
- [ ] Rich text editor output sanitized

### React's Built-in Protection
React auto-escapes JSX expressions, but these bypass it:
```typescript
// DANGEROUS: Direct HTML insertion
<div dangerouslySetInnerHTML={{ __html: userContent }} />

// DANGEROUS: javascript: URLs
<a href={userProvidedUrl}>Click</a>  // href="javascript:alert(1)"

// SAFE: React auto-escapes
<div>{userContent}</div>  // HTML entities escaped
```

### AI Content Rendering
```typescript
// When displaying AI stylist responses:
// 1. Sanitize HTML if rendering as rich text
// 2. Strip script tags, event handlers
// 3. Validate URLs in generated content
```

## Environment Variables

### Next.js Rules
- `NEXT_PUBLIC_*` — bundled into client JavaScript (NEVER put secrets here)
- All other env vars — server-only

### Checklist
- [ ] No secrets in `NEXT_PUBLIC_*` variables
- [ ] `.env.local` in `.gitignore`
- [ ] `NEXT_PUBLIC_*` values are safe to expose (API URLs, feature flags)
- [ ] Server-side env vars not accessed in `"use client"` files
- [ ] `.env.example` doesn't contain real values

### Verify
```bash
# Find all NEXT_PUBLIC_ usages
grep -rn "NEXT_PUBLIC_" src/ --include="*.ts" --include="*.tsx"
# Verify none contain sensitive data
```

## Middleware & Headers

### Checklist
- [ ] Security headers set in `middleware.ts` or `next.config.js`
- [ ] `Content-Security-Policy` configured
- [ ] `X-Frame-Options: DENY` (prevent clickjacking)
- [ ] `X-Content-Type-Options: nosniff`
- [ ] `Referrer-Policy: strict-origin-when-cross-origin`
- [ ] Auth middleware protects `(dashboard)` route group

### next.config.js Headers
```javascript
// Verify these are set:
const securityHeaders = [
  { key: 'X-DNS-Prefetch-Control', value: 'on' },
  { key: 'X-Frame-Options', value: 'DENY' },
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
];
```

## Dependencies & Supply Chain (OWASP A03:2025)

### Dependency Vulnerability Scanning
- [ ] `npm audit` shows no critical/high vulnerabilities
- [ ] `npm audit signatures` — verify package signatures (npm 9+)
- [ ] Dependencies pinned (lock file committed and reviewed on changes)
- [ ] No `eval()` or `Function()` in dependencies
- [ ] shadcn/ui components from trusted source
- [ ] Image optimization libraries up to date (sharp, next/image)

### Supply Chain Hardening
- [ ] No `preinstall`/`postinstall` scripts that download or execute code
- [ ] Lifecycle scripts disabled by default (`npm config set ignore-scripts true`)
- [ ] `package-lock.json` committed and integrity verified on CI
- [ ] No typosquatted dependencies (verify package names match intended)
- [ ] Dependabot or Snyk configured for automatic vulnerability alerts
- [ ] SBOM generated for compliance audits (`npm sbom --sbom-format cyclonedx`)

### Regular Audit
```bash
cd <frontend-dir>
npm audit --production    # production deps only
npm audit fix             # auto-fix where possible
npm audit signatures      # verify package signatures
```

### AI-Generated Code Warning
If using AI coding assistants (Copilot, Claude, Cursor), review generated code for:
- [ ] Hardcoded secrets or placeholder credentials
- [ ] Insecure patterns (eval, innerHTML, unsafe-inline)
- [ ] Outdated API usage from training data
- [ ] Missing input validation or error handling

## Mishandling Exceptional Conditions (OWASP A10:2025)

New in OWASP 2025 — how the frontend handles edge cases:
- [ ] API error responses don't expose stack traces to users
- [ ] Auth token refresh failure redirects to login (doesn't fail-open)
- [ ] Network failures show user-friendly errors (no raw error objects)
- [ ] Server Action errors handled gracefully (no unhandled promise rejections)
- [ ] Image/asset loading failures have fallback UI
- [ ] Rate limit responses (429) handled with retry logic, not crashes
