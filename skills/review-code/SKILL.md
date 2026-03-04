---
name: review-code
description: |
  **Code Review**: Comprehensive code review and quality analysis for fullstack monorepos (NestJS backend, Next.js frontend, React Native mobile).
  - MANDATORY TRIGGERS: code review, review code, review PR, review my code, check code quality, code audit, review this feature, review module, review service, review controller, find bugs, code smell, refactor suggestions, review backend, review frontend, review NestJS, review Next.js, lint check, architecture review, security review, performance review
  - Use this skill whenever the user wants to review, audit, or analyze code quality in any part of the project, even if they just say "review this" or "check this file". Also trigger when the user mentions improving code quality, finding issues, or wants a second pair of eyes on their implementation.
---

# Code Review Skill

Review code across fullstack monorepos with deep awareness of architecture, conventions, and tech stack. This skill understands how modern NestJS + Next.js + React Native projects are structured and what "good code" looks like — not just generic best practices.

## Project Context

Before reviewing, identify the project's structure. A typical monorepo layout:

```
project-root/
├── backend/               # NestJS backend (MongoDB, Bull, Redis)
├── frontend/              # Next.js frontend (Tailwind, Zustand, React Query)
├── mobile/                # React Native mobile app
└── shared/                # Shared libraries/packages
```

> **First step:** Read the project root to discover the actual directory names and structure. Don't assume — check what exists.

### Backend Architecture (NestJS)

Look for these path aliases in `tsconfig.json`:
- `@/*` → `src/*`
- `@shared/*` → `src/shared/*`
- `@features/*` → `src/features/*`
- `@core/*` → `src/core/*`

Module organization:
- `src/core/` — Infrastructure (config, database, logger, redis, queue, health, scheduler, exception handling)
- `src/features/` — Feature modules (each with controller, service, DTOs, entities)
- `src/shared/` — Shared utilities, DTOs, decorators, pipes, guards
- `src/types/` — Global type definitions

Common stack: MongoDB + Mongoose ODM, Bull queues, Redis caching, Pino logger, LangChain/LangGraph (AI agents), vector DBs, AWS S3

### Frontend Architecture (Next.js)

- Next.js 14/15 App Router with route groups for public and authenticated sections
- Radix UI + shadcn/ui component library
- Zustand stores for state, React Query for data fetching
- Zod validation with React Hook Form

## Review Process

When asked to review code, follow this order:

### 1. Understand Scope

Determine what the user wants reviewed:
- **Specific file(s)** — Focus review on those files, but check related imports/dependencies
- **Feature module** — Review the entire module directory (controller, service, schema, DTOs, tests)
- **PR/changeset** — Review the diff, focusing on what changed and its impact
- **General audit** — Scan for high-impact issues across the codebase

### 2. Read the Code

Read the target files thoroughly. For a NestJS module, that typically means:

```
features/<module>/
├── <module>.module.ts       # Module declaration, imports, providers
├── <module>.controller.ts   # Route handlers, decorators, swagger docs
├── <module>.service.ts      # Business logic
├── dto/                     # Request/response DTOs (class-validator)
├── entities/                # Mongoose schemas
├── interfaces/              # TypeScript interfaces
└── __tests__/               # Unit tests (if they exist)
```

For AI agent modules, also look at:
```
ai-agents/core/
├── llm/services/            # LLM provider abstraction
├── providers/               # Provider configs (OpenAI, Gemini, etc.)
├── graph/                   # LangGraph state machine
├── tools/                   # Custom agent tools
├── knowledge/               # Knowledge base (embeddings)
└── config/                  # System prompts, tool configs
```

### 3. Analyze Against These Categories

Review each piece of code against these categories, prioritized from most to least impactful:

#### Critical Issues (must fix)
- **Security vulnerabilities**: Unsanitized inputs, SQL/NoSQL injection, exposed secrets, missing auth guards, insecure token handling
- **Data loss risks**: Missing error handling that could corrupt data, race conditions in concurrent operations
- **Production crashes**: Unhandled promise rejections, undefined access without null checks

#### Architecture & Design (SOLID Principles)
- **Single Responsibility (SRP)**: Each class/function should have one reason to change. Controllers validate + delegate. Services own business logic. Schemas define data shape. If a service handles both business logic AND email sending, it violates SRP.
- **Open/Closed (OCP)**: Code should be open for extension, closed for modification. Use strategy patterns, plugin architectures, and dependency injection instead of modifying existing classes for new behavior.
- **Liskov Substitution (LSP)**: Subtypes must be substitutable for their base types. If overriding a method changes expected behavior or throws unexpected errors, it violates LSP.
- **Interface Segregation (ISP)**: Don't force classes to implement interfaces they don't use. Prefer small, focused interfaces over fat ones. A `UserService` shouldn't implement methods for unrelated domains.
- **Dependency Inversion (DIP)**: Depend on abstractions, not concretions. NestJS DI naturally supports this — services should inject interfaces/tokens, not concrete implementations directly.
- **Circular dependencies**: Watch for modules that import each other — this is a common NestJS pitfall
- **Module coupling**: Features should communicate through well-defined interfaces, not reach into each other's internals

#### Clean Code & Design Principles
- **DRY (Don't Repeat Yourself)**: Every piece of knowledge should have a single, unambiguous representation. Flag duplicated logic across services, repeated validation patterns, copy-pasted query builders, and similar DTO structures that could share a base class.
- **KISS (Keep It Simple, Stupid)**: Prefer simple, readable solutions over clever ones. Flag over-engineered abstractions, unnecessary design patterns, and complex generics when a simple function would suffice.
- **YAGNI (You Ain't Gonna Need It)**: Flag speculative features, unused abstractions, premature optimizations, and configuration for scenarios that don't exist yet. Code should solve today's problems, not tomorrow's hypotheticals.
- **Meaningful naming**: Variables, functions, and classes should reveal intent. `processData()` is bad — `calculateMonthlyRevenue()` is good. Avoid abbreviations, single-letter variables (except loop counters), and names that require comments to explain.
- **Function size**: Functions should do one thing well. Flag functions longer than ~30 lines or with more than 3 levels of nesting. If you need comments to separate sections within a function, it should be split.
- **Parameter count**: Functions with more than 3 parameters should use an options object or DTO. Long parameter lists are a code smell indicating the function does too much.
- **Magic numbers/strings**: Hardcoded values should be extracted to named constants. `if (status === 3)` is unreadable — `if (status === OrderStatus.SHIPPED)` is clear.
- **Comments**: Code should be self-documenting. Comments should explain *why*, not *what*. Flag commented-out code (delete it — git has history), TODO comments without tickets, and comments that restate the code.

#### Code Smells to Flag
- **God classes/services**: Classes with too many responsibilities (>10 public methods, >200 lines). Split by domain concern.
- **Feature envy**: A method that uses more data from another class than its own. Move the method to where the data lives.
- **Shotgun surgery**: A single change requires editing many unrelated files. Indicates poor encapsulation — related logic is scattered.
- **Primitive obsession**: Using primitives (string, number) where a value object or enum would be clearer. E.g., passing `userId: string` everywhere instead of a typed `UserId`.
- **Long chains**: `user.getProfile().getAddress().getCity()` — violates Law of Demeter. Provide direct accessors.
- **Boolean blindness**: Functions with boolean parameters like `createUser(data, true, false)`. Use options objects or separate methods.
- **Dead code**: Unreachable code, unused imports, unexported functions that nothing calls. Remove it.
- **Inconsistent error handling**: Some functions throw, some return null, some return error objects. Pick one pattern per layer and stick with it.

#### Code Quality
- **TypeScript discipline**: Flag excessive `any` usage — encourage proper typing especially in DTOs, service return types, and public interfaces. Use `unknown` instead of `any` when the type is truly unknown, then narrow with type guards.
- **Error handling**: Are errors caught and handled meaningfully? Or silently swallowed? Are appropriate HTTP exceptions thrown? Follow the "fail fast" principle — detect and report errors as early as possible.
- **Immutability**: Prefer `const` over `let`, `readonly` properties, and immutable data patterns. Mutations make code harder to reason about and can cause subtle bugs.
- **Early returns**: Prefer guard clauses and early returns over deeply nested if/else chains. Flatten the happy path.
- **Duplication**: Identify repeated patterns that could be extracted to shared utilities, base classes, or generic helpers.

#### Performance
- **Database queries**: Missing indexes, N+1 query patterns, unbounded finds without pagination
- **Memory leaks**: Event listeners not cleaned up, streams not closed, Bull job processors not handling failures
- **Caching**: Is Redis caching used appropriately? Are cache keys consistent and invalidated correctly?
- **LLM usage**: Are token limits respected? Are retries and circuit breakers in place for AI provider calls?
- **Premature optimization vs. real bottlenecks**: Don't optimize code that isn't slow. But DO flag obvious O(n²) patterns, unnecessary database round-trips, and missing pagination on list endpoints.

#### Testing
- **Test coverage**: Does the code have tests? Are edge cases covered?
- **Test quality**: Are tests actually testing behavior (not just implementation details)? Each test should have a clear arrange-act-assert structure.
- **Mocking**: Are external dependencies properly mocked? Avoid mocking everything — test real behavior where possible.
- **Test naming**: Test names should describe the scenario and expected outcome: `should return 404 when item not found`, not `test1` or `createItem test`.
- **Test independence**: Tests should not depend on execution order or shared mutable state.

### 4. Present Findings

Structure the review as a conversation, not a laundry list. Group findings by severity and explain the reasoning behind each suggestion. For every issue raised, provide a concrete fix or improvement.

Use this format for each finding:

```
**[SEVERITY] Short description**
File: path/to/file.ts:L42

What's happening: [explain the current code]
Why it matters: [explain the impact]
Suggested fix: [show the improved code]
```

Severity levels:
- `CRITICAL` — Security, data loss, crashes
- `WARNING` — Architecture issues, performance problems, missing error handling
- `SUGGESTION` — Code quality improvements, better patterns, readability
- `NITPICK` — Style, naming, minor cleanup (only include if the user wants thorough review)

### 5. Summarize

End with a brief summary:
- Overall health assessment (1-2 sentences)
- Top 3 priorities if there are many findings
- Any patterns that suggest systemic issues worth addressing project-wide

## Patterns to Watch For

These are common patterns and anti-patterns in NestJS/Next.js projects that deserve extra attention:

### Mongoose Schema Issues
- Missing `@Prop({ required: true })` on fields that shouldn't be null
- No `@Index()` decorators on fields used in queries
- Schema defaults that could cause silent data issues
- Using `Record<string, any>` instead of proper sub-document schemas

### NestJS Guards & Decorators
- Auth guards should be applied consistently (check for `@UseGuards()`)
- Custom decorators in shared modules should be used instead of reinventing
- Check that `@ApiTags()`, `@ApiOperation()` are present for Swagger docs

### AI Agent Specific
- LLM provider calls should use the abstraction layer, not direct SDK calls
- Tool definitions should follow the existing patterns
- System prompts should use reusable prompt section templates
- Knowledge base queries should go through dedicated services

### Common Anti-Patterns (All Layers)
- **Service locator**: Using `moduleRef.get()` or `app.get()` to grab services instead of proper constructor injection — breaks DI and makes testing harder
- **Anemic domain models**: DTOs/entities with only data and no behavior, while services contain all logic — consider if some logic belongs closer to the data
- **Catch-all error handlers**: `catch (e) { console.log(e) }` — silently swallowing errors. Errors should be logged with context and re-thrown or handled meaningfully
- **Barrel file bloat**: `index.ts` files that re-export everything from a module, causing circular dependencies and slow builds — only export the public API
- **Copy-paste inheritance**: Identical code blocks across services with minor tweaks — extract to a shared base class, generic utility, or composition pattern
- **Hardcoded configuration**: URLs, timeouts, limits, feature flags embedded in code instead of environment/config — use NestJS ConfigService or Next.js env
- **Tight coupling to external services**: Direct SDK calls scattered through business logic — wrap external services in an abstraction layer for testability and swappability

### Frontend (Next.js) Patterns
- Server components vs client components — `"use client"` should only be where needed
- API calls should go through the service layer, not directly in components
- Zustand stores should be small and focused, not god-stores
- React Query keys should follow a consistent namespace pattern

## Automated Scripts

The `scripts/` directory contains helper scripts for automated checks. These auto-detect project directories from the repository root.

### `scripts/run-review.sh` — Lint + Test Runner
Runs ESLint, TypeScript type-check, and test suites. Produces a JSON report.
```bash
./scripts/run-review.sh backend          # lint + test backend
./scripts/run-review.sh frontend         # lint + type-check + test frontend
./scripts/run-review.sh all              # both
./scripts/run-review.sh backend --fix    # auto-fix lint issues
```

### `scripts/check-module.sh` — Single Module Health Check
Quick structural audit of a NestJS feature module — checks for module/controller/service files, DTOs, schemas, tests, Swagger docs, auth guards, and `any` usage.
```bash
./scripts/check-module.sh item
./scripts/check-module.sh auth
```

### `scripts/scan-codebase.sh` — Full Codebase Scanner
Scans the entire monorepo for code quality indicators: `any` counts, TODO/FIXME, console.log usage, modules without tests, modules without Swagger docs, and the most any-heavy files.
```bash
./scripts/scan-codebase.sh
```

### `scripts/detect-duplicates.sh` — Duplicate Code Detector
Finds DRY violations using pure bash + awk (no npm deps). Detects identical functions, similar file structures, repeated code blocks, copy-paste import patterns, and duplicate string literals. Outputs structured JSON for AI parsing.
```bash
./scripts/detect-duplicates.sh                    # scan all projects
./scripts/detect-duplicates.sh backend            # scan backend only
./scripts/detect-duplicates.sh frontend           # scan frontend only
./scripts/detect-duplicates.sh mobile             # scan mobile only
./scripts/detect-duplicates.sh --min-lines 3      # minimum duplicate block size (default: 5)
./scripts/detect-duplicates.sh --min-repeats 2    # minimum string repetitions (default: 3)
```

**Finding types:** `identical_function`, `similar_files`, `repeated_block`, `duplicate_imports`, `duplicate_string`

### `scripts/deep-scan.sh` — Clean Code Violations Scanner
Detects code smells, anti-patterns, SOLID violations, and bloaters. Pure bash — no npm install needed. Outputs structured JSON grouped by category and severity.
```bash
./scripts/deep-scan.sh                            # scan all projects
./scripts/deep-scan.sh backend                    # scan backend only
./scripts/deep-scan.sh frontend                   # scan frontend only
./scripts/deep-scan.sh mobile                     # scan mobile only
./scripts/deep-scan.sh --category bloaters        # only bloater checks
./scripts/deep-scan.sh --category solid           # only SOLID violations
./scripts/deep-scan.sh --category smells          # only code smells
./scripts/deep-scan.sh --category naming          # only naming issues
./scripts/deep-scan.sh --severity critical        # only critical issues
./scripts/deep-scan.sh --summary                  # summary counts only
./scripts/deep-scan.sh --max-func-lines 50        # custom thresholds
```

**Categories & rules detected:**
- **Bloaters:** long files (>300 lines), long functions (>30 lines), too many parameters (>3), deep nesting (>3 levels), classes with >10 methods
- **SOLID:** fat controllers (DB in controllers), too many dependencies (>5), service locator (`moduleRef.get()`), manual instantiation (`new Service()`)
- **Smells:** empty catch blocks, console.log in production, magic numbers, hardcoded URLs/emails, `as any`, boolean params, TODO without ticket, commented-out code
- **Naming:** single-letter variables, generic names (`data`, `result`, `temp`, `info`, `item`)

**Exit codes:** 0 = clean, 1 = warnings found, 2 = critical issues found

### `scripts/dep-check.sh` — Dependency & Import Analyzer
Detects circular dependencies, unused exports, orphan files, and import boundary violations. Pure bash — no npm deps.
```bash
./scripts/dep-check.sh                            # scan all projects
./scripts/dep-check.sh backend                    # scan backend only
./scripts/dep-check.sh --check circular           # only circular dependency detection
./scripts/dep-check.sh --check unused             # only unused exports
./scripts/dep-check.sh --check orphans            # only orphan files (never imported)
./scripts/dep-check.sh --check boundaries         # only import boundary violations
./scripts/dep-check.sh --summary                  # summary counts only
```

**Check types:**
- **Circular:** mutual imports (A<->B), self-imports, cross-feature imports in NestJS modules
- **Unused:** exported symbols never imported by any other file
- **Orphans:** files never imported by anything (potential dead code)
- **Boundaries:** cross-project imports, test utilities in production, deep relative imports (4+ levels)

**Exit codes:** 0 = clean, 1 = issues found, 2 = critical issues (cross-project imports)

### `scripts/format-check.sh` — Format & Style Consistency Checker
Detects config drift, import ordering violations, file naming issues, and inconsistent patterns across the monorepo.
```bash
./scripts/format-check.sh                         # scan all projects
./scripts/format-check.sh backend                 # scan backend only
./scripts/format-check.sh --check configs         # only config drift detection
./scripts/format-check.sh --check imports         # only import ordering
./scripts/format-check.sh --check naming          # only file naming conventions
./scripts/format-check.sh --check patterns        # only pattern consistency
./scripts/format-check.sh --summary               # summary counts only
```

**Check types:**
- **Configs:** ESLint format drift (legacy vs flat), Prettier inconsistencies (quotes, semi, width), TypeScript strict mode, missing configs
- **Imports:** external-after-relative ordering, wildcard imports (tree-shaking impact)
- **Naming:** camelCase files, PascalCase non-components, special characters, mixed test conventions (.spec vs .test)
- **Patterns:** mixed export styles, mixed async patterns (.then vs await), console.log over logger, string concatenation over templates

## References

For deeper review of specific areas, read these files:

**Architecture patterns (in `references/`):**
- `references/clean-code-principles.md` — SOLID, DRY, KISS, YAGNI with practical TypeScript examples, code smells catalog, anti-patterns, and refactoring recipes
- `references/nestjs-patterns.md` — NestJS module structure, controller/service conventions, Mongoose schemas, DTOs, error handling, auth guards, AI agent patterns
- `references/frontend-patterns.md` — Next.js App Router, component patterns, Zustand state, React Query data fetching, form handling, Tailwind styling

Read these reference files when doing an in-depth review of a specific area.
