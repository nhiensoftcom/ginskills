# Tutorial: CLAUDE.md & Memory

Claude starts every session fresh with no memory of previous conversations. Two mechanisms carry knowledge across sessions: **CLAUDE.md files** (instructions you write) and **auto memory** (notes Claude writes itself).

---

## Step 1: Understand the Two Systems

| | CLAUDE.md files | Auto memory |
|--|----------------|-------------|
| **Who writes** | You | Claude |
| **Contains** | Instructions, rules, context | Learnings, patterns, discoveries |
| **Scope** | Project, user, or org-wide | Per working tree (git repo) |
| **Loaded** | Every session, fully | First 200 lines of `MEMORY.md` |
| **Use for** | Coding standards, workflows, architecture | Build commands, debugging insights, preferences |

---

## Step 2: Where CLAUDE.md Files Live

```
/Library/Application Support/ClaudeCode/CLAUDE.md   ← macOS org-wide (managed, can't be excluded)
/etc/claude-code/CLAUDE.md                           ← Linux org-wide (managed)
~/.claude/CLAUDE.md                                  ← Your personal preferences (all projects)
./CLAUDE.md  or  ./.claude/CLAUDE.md                 ← Project-level (commit to git)
./CLAUDE.local.md                                    ← Project-local, gitignored (your personal project prefs)
```

**Loading order:** more specific wins over broader.
- Organization-wide → user → project → local
- When files conflict, the more specific one applies

**How they load at startup:**
- Claude walks UP the directory tree from your cwd and loads all CLAUDE.md files it finds
- CLAUDE.md files in **subdirectories** load on-demand when Claude reads files in those directories
- This means a monorepo can have `frontend/CLAUDE.md`, `backend/CLAUDE.md`, etc.

---

## Step 3: Create a Project CLAUDE.md

```bash
# Quick start: let Claude generate it from your codebase
/init

# Or create manually:
touch CLAUDE.md
```

**Good CLAUDE.md content:**

```markdown
# Project Instructions

## Tech Stack
- Backend: NestJS + MongoDB + Redis
- Frontend: Next.js 15 App Router + Tailwind + shadcn/ui
- Mobile: React Native + Expo
- Testing: Jest + Supertest

## Build & Test Commands
- Install: `bun install`
- Backend dev: `cd backend && bun run dev`
- Frontend dev: `cd frontend && bun run dev`
- Tests: `bun test` (run before any commit)
- Lint: `bun run lint`

## Architecture Decisions
- Use `@features/` path alias for feature modules (backend)
- API responses always return `{ data, meta }` for lists, `{ data }` for single items
- Errors use `{ error: { code, message, details } }` format
- All new endpoints need Swagger `@ApiOperation()` decorators

## Code Style
- TypeScript strict mode — no `any`, use `unknown` + type guards
- Prefer early returns over nested if/else
- Functions > 30 lines should be split
- Test files co-located in `__tests__/` next to source

## Workflows
- PRs need: tests pass, no lint errors, Swagger docs updated
- Commit format: `type(scope): description` (feat/fix/refactor/docs/test/chore)
```

**Size target:** under 200 lines. Longer files consume more context and reduce adherence.

---

## Step 4: Import Other Files

Use `@path/to/file` syntax to import content into CLAUDE.md:

```markdown
# Project Context
See @README.md for project overview.
Available commands: @package.json

# Git workflow
@docs/git-workflow.md

# API conventions
@docs/api-standards.md
```

- Both relative and absolute paths work
- Imports are expanded at launch into context
- Max import depth: 5 hops
- First time Claude sees an import, it shows an approval dialog

For personal per-project preferences not committed to git, use `CLAUDE.local.md` (auto-gitignored):
```markdown
# My local settings
My sandbox URL: http://localhost:3001
My test user: testuser@example.com
```

---

## Step 5: Path-Specific Rules with `.claude/rules/`

For large projects, organize instructions into files that load **only when relevant**:

```
project/
├── CLAUDE.md                    ← Loaded every session
└── .claude/
    └── rules/
        ├── api-design.md        ← Loaded every session (no paths = always)
        ├── testing.md           ← Loaded only when Claude reads test files
        └── security.md          ← Loaded only for auth module files
```

**`rules/testing.md`** (loaded always, no frontmatter):
```markdown
# Testing Conventions
- Each test file maps to one source file with `.spec.ts` extension
- Use `describe('ClassName') > it('should methodName when condition')` naming
- Mock external dependencies with Jest auto-mocking
- Always have Arrange-Act-Assert sections
```

**`rules/api-design.md`** (path-specific — only for API files):
```markdown
---
paths:
  - "src/api/**/*.ts"
  - "src/features/*/controller.ts"
---

# API Design Rules
- All endpoints must have `@ApiOperation()` and `@ApiResponse()` decorators
- Validate all inputs with class-validator DTOs
- Return 201 for POST, 200 for GET/PATCH, 204 for DELETE
- Never expose database IDs directly — use UUIDs
```

**`rules/security.md`** (multiple path patterns):
```markdown
---
paths:
  - "src/auth/**"
  - "src/features/users/**"
  - "**/*.guard.ts"
---

# Security Rules
- All auth tokens must be httpOnly cookies, never localStorage
- ALWAYS verify userId from JWT, never trust request body userId
- Rate limit all auth endpoints
- Log failed auth attempts with IP and timestamp
```

**Path patterns:**
| Pattern | Matches |
|---------|---------|
| `**/*.ts` | All TypeScript files |
| `src/**/*` | Everything under src/ |
| `*.md` | Markdown in project root |
| `src/**/*.{ts,tsx}` | TS and TSX anywhere in src/ |

Rules in `.claude/rules/` without `paths` frontmatter load every session (same as CLAUDE.md). Path-scoped rules load when Claude reads matching files.

**User-level rules** (`~/.claude/rules/`) apply to all your projects.

---

## Step 6: Auto Memory

Auto memory lets Claude build knowledge across sessions without your input.

```
~/.claude/projects/<project>/memory/
├── MEMORY.md             ← Index, first 200 lines loaded every session
├── debugging.md          ← Detailed debugging insights (loaded on demand)
├── api-patterns.md       ← API patterns discovered (loaded on demand)
└── architecture.md       ← Architecture notes (loaded on demand)
```

Auto memory is **on by default**. To toggle:
```bash
/memory               # In Claude Code — use toggle
```

Or in settings:
```json
{ "autoMemoryEnabled": false }
```

Or env var: `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`

**How it works:**
- First 200 lines of `MEMORY.md` are injected at every session start
- Claude reads topic files on demand when it needs that info
- Claude writes new learnings into appropriate topic files
- All worktrees and subdirectories of the same git repo share one memory directory
- Machine-local — not synced across machines

**What Claude saves:** build commands, test patterns, debugging insights, architectural decisions, style preferences you've corrected it on.

**Ask Claude to save something:**
```
Remember: always use bun, not npm, in this project
Remember that the API tests require a local Redis instance running on port 6379
```

**View your memory:** run `/memory` to browse and edit memory files.

---

## Step 7: Writing Effective Instructions

**Be specific:**
```markdown
✅ "Use 2-space indentation"           not   ❌ "Format code properly"
✅ "Run `bun test` before committing"  not   ❌ "Test your changes"
✅ "API handlers live in src/api/"     not   ❌ "Keep files organized"
✅ "No `any` — use `unknown` + type guards"  not  ❌ "Use TypeScript properly"
```

**Be concise:** instructions are loaded into context (consuming tokens). The more you write, the less headroom Claude has for your conversation.

**Avoid conflicts:** if two rules contradict, Claude may pick one arbitrarily. Review your CLAUDE.md files periodically.

**Keep CLAUDE.md under 200 lines.** Move detailed content to:
- `@docs/detailed-guide.md` imports
- `.claude/rules/` path-specific files
- Subdirectory CLAUDE.md files

---

## Step 7b: Loading CLAUDE.md from Additional Directories

By default, CLAUDE.md files are only loaded from the project directory and its parents. To also load from directories added via `--add-dir`:

```bash
CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1 claude
```

Or add permanently in `.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD": "1"
  }
}
```

This is useful in monorepos where shared libraries live in sibling directories: `--add-dir ../shared-lib` will then also pick up `../shared-lib/CLAUDE.md`.

---

## Step 7c: What to Put in CLAUDE.md (and What Not To)

**Include:**
- Bash commands Claude can't guess (build, test, deploy commands)
- Code style rules that differ from language defaults
- Test runners and how to run specific test suites
- Repo etiquette (branch naming, PR conventions, commit format)
- Architectural decisions specific to this project
- Dev environment quirks (required env vars, local setup steps)
- Common gotchas and non-obvious behaviors

**Exclude:**
- Things Claude can infer from code (obvious patterns, standard conventions)
- Standard language/framework conventions
- Detailed API docs (link to them instead with `@path/to/docs`)
- Frequently-changing information (put that in docs, link via `@`)
- Long tutorials or explanations (move to `.claude/rules/` or `docs/`)
- File-by-file descriptions of the entire codebase
- Self-evident practices like "write clean code"

**For critical rules that must always apply**, use emphasis:
```markdown
IMPORTANT: Never commit directly to main — always create a PR.
YOU MUST run `bun test` before committing. Failing tests block PRs.
```

---

## Step 8: Managing in Monorepos

In a monorepo with other teams' CLAUDE.md files, exclude irrelevant ones:

**`.claude/settings.local.json`:**
```json
{
  "claudeMdExcludes": [
    "**/other-team/CLAUDE.md",
    "**/legacy-service/.claude/rules/**"
  ]
}
```

Patterns use glob syntax matched against absolute file paths. Managed policy CLAUDE.md files (org-wide) cannot be excluded.

**Monorepo structure with per-package CLAUDE.md:**
```
monorepo/
├── CLAUDE.md                    ← Loaded for all work in this repo
├── backend/
│   └── CLAUDE.md                ← Loaded when Claude reads backend files
├── frontend/
│   └── CLAUDE.md                ← Loaded when Claude reads frontend files
└── mobile/
    └── CLAUDE.md                ← Loaded when Claude reads mobile files
```

---

## Step 9: Subagent Memory

Agents can maintain their own persistent memory. See [create-agent.md](create-agent.md) — the `memory` frontmatter field.

When `memory` is set on an agent:
- Agent gets its own memory directory
- First 200 lines of that agent's `MEMORY.md` loaded at agent startup
- Agent proactively updates its memory as it works

---

## Quick Reference

```bash
# Generate CLAUDE.md from your codebase
/init

# View all loaded CLAUDE.md files and memory
/memory

# Ask Claude to remember something persistently
"Remember: always use bun not npm"
"Add this to CLAUDE.md: API endpoints must return { data, meta } format"

# Check what CLAUDE.md files are loaded in current session
/memory   ← Lists all loaded files

# Share project instructions with team
git add CLAUDE.md .claude/rules/  # Commit these
git add CLAUDE.local.md           # DON'T commit this (gitignored)

# Org-wide instructions (requires admin)
# macOS: /Library/Application Support/ClaudeCode/CLAUDE.md
# Linux: /etc/claude-code/CLAUDE.md
```

**Location decision guide:**

| Where | Use when |
|-------|----------|
| `CLAUDE.md` (project root) | Team-shared: architecture, coding standards, workflows |
| `.claude/rules/*.md` | Topic-specific or path-scoped rules |
| `~/.claude/CLAUDE.md` | Personal preferences across all projects |
| `CLAUDE.local.md` | Your personal project-specific prefs (not shared) |
| Auto memory | Things Claude learns from your corrections |
