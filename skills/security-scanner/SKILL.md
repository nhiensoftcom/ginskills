---
name: security-scanner
description: |
  **Security Scanner**: Comprehensive security audit for fullstack monorepos — NestJS backend, Next.js frontend, and React Native mobile app. Aligned with OWASP Top 10:2025, OWASP Top 10 for LLM Apps 2025, and OWASP Mobile Top 10. Scans for vulnerabilities, secrets exposure, auth misconfigurations, injection risks, supply chain threats, LLM/AI agent risks, and platform-specific security issues.
  - MANDATORY TRIGGERS: security scan, security audit, security review, check security, vulnerability scan, find vulnerabilities, check secrets, secret leak, hardcoded password, hardcoded key, OWASP, injection, XSS, CSRF, auth security, token security, check dependencies, dependency audit, CVE, security headers, CORS check, CSP check, penetration test, pen test, security checklist, supply chain, prompt injection, LLM security
  - Use this skill whenever the user mentions anything about security, vulnerabilities, secrets, or wants to audit code for safety issues. Also trigger when the user asks about CORS, CSP headers, auth guards, token handling, API key exposure, dependency vulnerabilities, supply chain risks, prompt injection, or AI agent security — even casual mentions like "is this secure?" or "any security issues?".
---

# Security Scanner

Scan fullstack monorepos for security vulnerabilities with deep awareness of the project's architecture. Aligned with **OWASP Top 10:2025**, **OWASP Top 10 for LLM Applications 2025**, and **OWASP Mobile Top 10 2024**. This skill understands modern NestJS/Next.js/React Native security posture.

## Project Security Architecture (Current State)

### What's Already Good
- JWT with 15min access / 7d refresh tokens (`core/config/jwt.config.ts`)
- Global `ValidationPipe` with `whitelist: true` + `forbidNonWhitelisted: true`
- Mobile uses `react-native-keychain` (OS-level secure storage, not AsyncStorage)
- Single-flight token refresh pattern prevents race conditions
- Swagger protected with basic auth middleware
- HSTS enabled (1 year, preload)
- Signed httpOnly cookies for token transport

### Known Risks (Flagged)
- CSP allows `'unsafe-inline'` in both `scriptSrc` and `styleSrc`
- `connectSrc: ["'self'", 'https://*']` — too permissive
- CORS defaults to `['*']` in non-production environments
- `.env.example` may contain reusable example secrets
- `strictNullChecks: false` increases null-related vulnerability surface

## OWASP Alignment

### OWASP Top 10:2025 — Web Application Risks
Map every finding to these categories where applicable:

| ID | Category | What to Check |
|----|----------|---------------------|
| A01 | Broken Access Control | IDOR in user endpoints, auth guard gaps, RBAC bypass |
| A02 | Security Misconfiguration | CORS wildcard, CSP unsafe-inline, Helmet config |
| A03 | Software Supply Chain Failures | npm dependencies, lockfile integrity, lifecycle scripts |
| A04 | Cryptographic Failures | JWT signing, token storage, TLS configuration |
| A05 | Injection | NoSQL injection (MongoDB), XSS, command injection |
| A06 | Insecure Design | Missing rate limiting, no abuse detection on AI endpoints |
| A07 | Authentication Failures | Token handling, refresh flow, session management |
| A08 | Software/Data Integrity Failures | CI/CD pipeline, unsigned OTA updates, unverified deps |
| A09 | Security Logging & Alerting | Missing audit logs, no alerting on suspicious activity |
| A10 | Mishandling Exceptional Conditions | Uncaught errors leaking stack traces, fail-open patterns |

### OWASP Top 10 for LLM Applications 2025
The project uses LangChain + LangGraph agents with multi-provider LLMs — these risks are critical:

| ID | Category | Check |
|----|----------|-------|
| LLM01 | Prompt Injection | User input sanitized before LLM prompts? System prompts hidden? |
| LLM02 | Sensitive Info Disclosure | PII leaked in LLM responses? Conversation history access controlled? |
| LLM03 | Supply Chain | LLM package versions pinned? Model provenance verified? |
| LLM05 | Improper Output Handling | AI-generated content sanitized before rendering/storing? |
| LLM06 | Excessive Agency | LangGraph tools sandboxed? Permissions scoped to minimum? |
| LLM07 | System Prompt Leakage | System prompts retrievable by users? |
| LLM08 | Vector/Embedding Weaknesses | Qdrant access controlled? Embedding poisoning possible? |
| LLM10 | Unbounded Consumption | Token limits on AI calls? Rate limiting on AI endpoints? |

### OWASP Mobile Top 10 2024
For React Native (mobile app):

| ID | Category | Check |
|----|----------|-------|
| M1 | Improper Credential Usage | Keychain used? No hardcoded credentials? |
| M2 | Inadequate Supply Chain | Third-party SDK audit? Dependency scanning? |
| M3 | Insecure Auth/AuthZ | Token rotation? Biometric for sensitive actions? |
| M4 | Insufficient Input/Output Validation | Deep link params validated? WebView input sanitized? |
| M5 | Insecure Communication | Certificate pinning? No cleartext traffic? |
| M8 | Security Misconfiguration | Debug flags stripped? ProGuard enabled? |
| M9 | Insecure Data Storage | AsyncStorage audit? Sensitive data encrypted? |
| M10 | Insufficient Cryptography | Proper key management? Strong algorithms? |

## Scan Process

When asked to scan, follow this order. Adapt scope based on what the user asks — they might want a full audit or just one area.

### 1. Determine Scope

Ask (or infer) what they want scanned:
- **Full audit** — All platforms, all categories
- **Backend only** — NestJS auth, injection, config, dependencies
- **Frontend only** — Next.js XSS, auth, API routes
- **Mobile only** — React Native storage, certificate pinning, deep links
- **Specific area** — Just auth, just secrets, just dependencies, etc.

### 2. Run Automated Checks

Use the scripts in `scripts/` to get quick automated results first:

```bash
# Full security scan (all platforms)
./scripts/security-scan.sh all

# Platform-specific
./scripts/security-scan.sh backend
./scripts/security-scan.sh frontend
./scripts/security-scan.sh mobile
```

The script checks for: hardcoded secrets, `any` type abuse, console.log of sensitive data, missing auth guards, unsafe eval, dependency vulnerabilities, and more.

#### Deep Credential Scanning

For comprehensive credential and API key leak detection, use the dedicated credential scanner:

```bash
# Scan entire project for leaked credentials (100+ patterns)
./scripts/credential-scanner.sh /path/to/project

# Scan with JSON output for CI/CD integration
./scripts/credential-scanner.sh /path/to/project --format json --output report.json

# Scan only critical/high severity
./scripts/credential-scanner.sh /path/to/project --severity high

# Scan specific category (cloud, payment, ai, vcs, etc.)
./scripts/credential-scanner.sh /path/to/project --category cloud

# Skip git history scanning (faster)
./scripts/credential-scanner.sh /path/to/project --no-git-history

# Run the test suite to validate all patterns
./scripts/test-secret-detection.sh
```

The credential scanner uses a **multi-pass engine**:
1. **Direct pattern matching** — 100+ provider-specific regex patterns (AWS, GCP, Stripe, GitHub, OpenAI, etc.)
2. **Contextual pattern matching** — patterns that need surrounding context to reduce false positives
3. **Entropy analysis** — Shannon entropy calculation on matched strings to distinguish real secrets from placeholders
4. **File-based checks** — `.env` files, `.pem` keys, `credentials.json`, Docker/CI configs
5. **Git history scanning** — finds secrets ever committed then deleted

All patterns are defined in `scripts/secret-patterns.sh` (sourceable pattern database).
Test coverage is in `scripts/test-fixtures.sh` + `scripts/test-secret-detection.sh`.

### 3. Manual Review by Category

After automated checks, do targeted manual review based on findings.

#### Category 1: Secrets & Credentials (CRITICAL)

Scan for leaked secrets, hardcoded keys, and exposed credentials. **Use `credential-scanner.sh` for comprehensive automated detection.**

```bash
# Run the dedicated credential scanner first
./scripts/credential-scanner.sh /path/to/project --format json --output cred-report.json
```

The credential scanner covers **100+ patterns** across these provider categories:

| Category | Patterns | Examples |
|----------|----------|----------|
| **Cloud** | AWS, GCP, Azure | `AKIA...`, `AIza...`, Azure connection strings |
| **Payment** | Stripe, Square, PayPal | `sk_live_...`, `sq0atp-...` |
| **AI/ML** | OpenAI, Anthropic, HuggingFace | `sk-proj-...`, `sk-ant-...`, `hf_...` |
| **VCS/CI** | GitHub, GitLab, CircleCI | `ghp_...`, `glpat-...`, `github_pat_...` |
| **Communication** | Slack, Discord, Twilio, SendGrid | `xoxb-...`, `SG....`, `AC...` |
| **Database** | MongoDB, PostgreSQL, MySQL, Redis | Connection strings with embedded passwords |
| **Infrastructure** | Cloudflare, DigitalOcean, Vercel, Fly.io | `dop_v1_...`, `fo1_...` |
| **Crypto** | RSA, EC, OpenSSH, PGP private keys | `-----BEGIN ... PRIVATE KEY-----` |
| **Auth** | Firebase, Supabase, Auth0, Clerk | FCM keys, JWT tokens |
| **Registry** | NPM, PyPI, RubyGems | `npm_...`, `pypi-...` |
| **SaaS** | Linear, Notion, Doppler, PlanetScale | `lin_api_...`, `secret_...`, `dp.pt....` |
| **Shopify** | Access, custom app, shared secret | `shpat_...`, `shpca_...` |
| **Generic** | Passwords, secrets, tokens, Bearer, Basic | Entropy-based detection |

**Additional manual checks:**
- Secrets in `.env.example` that look real (not placeholder-ish)
- Secrets logged to console or error responses
- Secrets in URL query parameters
- Secrets in frontend bundles (`NEXT_PUBLIC_*`, `EXPO_PUBLIC_*`)
- Check git history for deleted secret files: `git log --all --diff-filter=D -- "*.env" "*.pem" "*.key"`

#### Category 2: Authentication & Authorization

**Backend (NestJS):**
- Are all non-public endpoints guarded with `@UseGuards(JwtAuthGuard)`?
- Do user-specific queries filter by `userId` from `@CurrentUser()`?
- Can users access/modify other users' data? (IDOR)
- Is the admin bypass in `roles.guard.ts` properly restricted?
- Are refresh tokens properly invalidated on logout?
- Token expiration: are access/refresh token lifetimes enforced?

**Frontend (Next.js):**
- Are API routes in `src/app/api/` checking auth before processing?
- Are tokens stored in httpOnly cookies (not localStorage)?
- Is there CSRF protection on state-changing requests?

**Mobile (React Native):**
- Tokens stored in Keychain/Keystore via `react-native-keychain`? (currently yes)
- Is biometric auth implemented for sensitive actions?
- Are deep link handlers validating the source?

Read `references/auth-security.md` for detailed checklist.

#### Category 3: Injection Attacks

**NoSQL Injection (MongoDB):**
- Are Mongoose queries using user input directly in `$where`, `$regex`, or `$expr`?
- Is `JSON.parse()` used on user input without validation?
- Does `forbidNonWhitelisted: true` catch all inputs? (check file uploads, query params)

**XSS:**
- Is user-generated content rendered with `dangerouslySetInnerHTML`?
- Are Markdown/rich text inputs sanitized before storage and display?
- Do AI-generated responses get sanitized before rendering?

**Command Injection:**
- Does any code use `exec()`, `spawn()`, or `eval()` with user input?
- Playwright scraper — is the URL validated before navigation?

#### Category 4: Security Headers & CORS

**Current config** (`core/config/helmet.config.ts` and `cors.config.ts`):

Check these against best practices:
- CSP should NOT have `'unsafe-inline'` (currently does)
- `connectSrc` should list specific domains, not `https://*`
- CORS should not default to `['*']` even in development
- X-Frame-Options: should be `DENY` or `SAMEORIGIN`
- Referrer-Policy: should be `strict-origin-when-cross-origin`

Read `references/headers-checklist.md` for the full checklist.

#### Category 5: Dependencies & Supply Chain (OWASP A03:2025)

This is newly elevated in OWASP 2025. Treat supply chain as a first-class risk.

```bash
# Vulnerability scan
cd <backend-dir> && npm audit
cd <frontend-dir> && npm audit
cd <mobile-dir> && npm audit

# Verify package signatures (npm 9+)
npm audit signatures

# Check for lifecycle scripts that download code
./scripts/security-scan.sh supply-chain
```

**What to check:**
- Known CVEs in dependencies (`npm audit`)
- Lockfile integrity — are lockfiles committed? (`pnpm-lock.yaml`, `package-lock.json`)
- Lifecycle scripts — `preinstall`/`postinstall` that download or execute code
- Typosquatting — dependency names close to popular packages
- Dependency signature verification (`npm audit signatures`)
- SBOM generation for compliance (`npm sbom --sbom-format cyclonedx`)
- NestJS-specific: **CVE-2025-54782** — RCE in `@nestjs/devtools-integration` ≤0.2.0 (unsafe `vm.runInNewContext` + missing CORS). Verify version ≥0.2.1

**Supply chain attack awareness:**
- The Sept 2025 "Shai-Hulud" attack compromised 18 popular npm packages (chalk, debug, etc.)
- Always disable lifecycle scripts by default: `npm config set ignore-scripts true`
- Use `--ignore-scripts` in CI/CD and explicitly allow-list needed scripts

#### Category 6: LLM/AI Agent Security (OWASP LLM Top 10)

The project has LangChain + LangGraph agents, multi-provider LLMs, and Qdrant vector DB. This category is critical.

**Prompt Injection (LLM01):**
- Is user input concatenated directly into LLM prompts?
- Are system prompts retrievable via conversation manipulation?
- Check `features/ai-agents/` for prompt construction patterns
- Multi-modal inputs (images) can contain hidden prompts

**Output Handling (LLM05):**
- Are AI-generated responses sanitized before rendering in frontend/mobile?
- Can AI output contain executable HTML/JS/markdown that bypasses sanitization?
- Are AI-suggested actions validated before execution?

**Excessive Agency (LLM06):**
- What tools can LangGraph agents call? Are they scoped to minimum permissions?
- Can agents access/modify resources beyond the current user's scope?
- Is there human-in-the-loop for destructive agent actions?

**Vector DB Security (LLM08):**
- Is Qdrant access authenticated?
- Can users poison the fashion knowledge base via injected content?
- Are embeddings isolated per tenant?

**Resource Limits (LLM10):**
- Token limits on LLM API calls?
- Rate limiting on AI chat endpoints?
- Timeout on LangGraph agent execution?

Read `references/nestjs-security.md` → "LLM/AI Agent Security" for detailed checklist.

#### Category 7: Platform-Specific

Read the platform-specific references for deeper checks:
- `references/nestjs-security.md` — Backend: auth, injection, rate limiting, error handling, LLM security
- `references/react-native-security.md` — Mobile: OWASP Mobile Top 10, secure storage, cert pinning, binary protection
- `references/nextjs-security.md` — Frontend: server/client boundary, API routes, CSP, dependency safety

#### Category 8: Exceptional Conditions (OWASP A10:2025)

New in OWASP 2025 — check how the app handles edge cases:
- Do uncaught exceptions expose stack traces in production?
- Do auth failures fail-open (grant access) instead of fail-closed (deny)?
- Are Bull queue job failures handled gracefully without data loss?
- Do LLM API timeouts fall back safely (no infinite retries, no credential exposure)?
- Are MongoDB connection failures handled without crashing the process?

### 4. Report Findings

Structure the report by severity:

```
🔴 CRITICAL — Exploitable now, data at risk
🟠 HIGH — Significant risk, should fix before next release
🟡 MEDIUM — Defense-in-depth improvement
🟢 LOW — Best practice recommendation
ℹ️ INFO — Observation, no action needed
```

For each finding:
```
**[SEVERITY] Title**
Location: file:line
Impact: What an attacker could do
Evidence: The vulnerable code
Fix: Concrete remediation with code example
```

### 5. Provide Fix Priority

End with a prioritized action list:
1. Critical fixes (do today)
2. High fixes (this sprint)
3. Medium fixes (next sprint)
4. Low/info (backlog)

## Recommended Tools Integration

For CI/CD pipeline integration, recommend these tools:

| Tool | Type | Use Case |
|------|------|----------|
| **Semgrep** | SAST | Custom rules for NestJS/Next.js patterns, free for open source |
| **npm audit** | SCA | Built-in dependency vulnerability scanning |
| **Socket.dev** | SCA+ | Detects malicious packages, supply chain attacks |
| **OWASP ZAP** | DAST | Runtime API scanning in staging |
| **SonarQube** | SAST | Continuous code quality + security |
| **Snyk** | SCA | Dependency monitoring with auto-fix PRs |
| **Gitleaks** | Secrets | Pre-commit hook for secret detection |

**AI-generated code note:** If the team uses AI coding assistants (Copilot, Claude, etc.), treat AI-generated code with the same scrutiny as external dependencies. Studies show ~40% of AI-generated security-sensitive code contains vulnerabilities.

## References

Platform-specific deep-dive checklists — read these when scanning a specific area:

- `references/nestjs-security.md` — Backend: auth guards, injection, rate limiting, file upload, error handling, LLM/AI agent security
- `references/react-native-security.md` — Mobile: OWASP Mobile Top 10, secure storage, certificate pinning, binary protection, deep links
- `references/nextjs-security.md` — Frontend: server/client boundary, API routes, middleware auth, env vars, CSP, dependency supply chain

**External references:**
- [OWASP Top 10:2025](https://owasp.org/Top10/2025/)
- [OWASP Top 10 for LLM Applications 2025](https://genai.owasp.org/llm-top-10/)
- [OWASP Mobile Top 10](https://owasp.org/www-project-mobile-top-10/)
- [NPM Security Cheat Sheet (OWASP)](https://cheatsheetseries.owasp.org/cheatsheets/NPM_Security_Cheat_Sheet.html)
- [NestJS Security Best Practices](https://dev.to/drbenzene/best-security-implementation-practices-in-nestjs-a-comprehensive-guide-2p88)
