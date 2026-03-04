# Tutorial: Create a New Skill

A skill is a `SKILL.md` file (plus optional supporting files) that teaches Claude a reusable workflow, domain knowledge, or set of instructions. Claude auto-invokes skills when relevant, or users trigger them with `/skill-name`.

---

## Step 1: Understand the Structure

```
.claude/skills/<skill-name>/       ← project-level (committed to git)
~/.claude/skills/<skill-name>/     ← personal (all projects)
ginstudio-skills/skills/<name>/    ← this repo's plugin skills
  ├── SKILL.md                     ← REQUIRED: instructions + frontmatter
  ├── docs/                        ← optional: reference docs loaded on demand
  │   └── reference.md
  ├── scripts/                     ← optional: executable helpers
  │   └── helper.sh
  └── evals/
      └── evals.json               ← optional: test cases
```

Keep `SKILL.md` under 500 lines. Move detailed references to `docs/` files and link to them.

---

## Step 2: Write SKILL.md

Every skill needs two parts: **YAML frontmatter** (configuration) and **markdown content** (instructions).

### Full Frontmatter Reference

```yaml
---
name: my-skill                    # Becomes the /slash-command. Lowercase, hyphens only.
description: |                    # CRITICAL: Claude reads this to decide when to use the skill.
  **Short bold summary**: One sentence description.
  - MANDATORY TRIGGERS: keyword1, keyword2, phrase one, phrase two
  - Use this skill when... (describe context, not just keywords)

# Optional fields:
disable-model-invocation: true    # Only YOU can invoke (not Claude). Use for /deploy, /commit.
user-invocable: false             # Only CLAUDE can invoke (hide from / menu). Use for background knowledge.
allowed-tools: Read, Grep, Glob   # Tools auto-approved when this skill is active.
model: sonnet                     # Force a model: sonnet | opus | haiku
context: fork                     # Run in isolated subagent context (won't see conversation history)
agent: Explore                    # Which agent type when context: fork. Built-ins: Explore, Plan, general-purpose
argument-hint: "[topic]"          # Shown in autocomplete. Example: "[issue-number] [format]"
---
```

### Invocation Control Matrix

| Frontmatter | You can invoke | Claude can invoke | When loaded |
|-------------|---------------|-------------------|-------------|
| (default) | ✅ | ✅ | Description always in context, full skill loads on invocation |
| `disable-model-invocation: true` | ✅ | ❌ | Description NOT in context, loads only when you invoke |
| `user-invocable: false` | ❌ | ✅ | Description always in context, full skill loads on invocation |

---

## Step 3: Write the Instructions

After the frontmatter, write clear markdown instructions. Think about what type of skill this is:

### Type A: Task Skill (do-this workflow)

For repeatable procedures — code review, deployment, PR creation:

```markdown
---
name: create-pr
description: Create a pull request with proper format. MANDATORY TRIGGERS: create PR, open PR, make PR.
disable-model-invocation: true
allowed-tools: Bash(gh *)
---

# Create Pull Request

1. Run `git status` and `git diff main...HEAD` to understand changes
2. Write a clear PR title (under 70 chars, imperative mood)
3. Create PR body with Summary + Test Plan sections
4. Run: `gh pr create --title "..." --body "..."`
5. Return the PR URL
```

### Type B: Knowledge Skill (apply-these-rules)

For domain knowledge Claude should apply inline (not a task to run):

```markdown
---
name: api-conventions
description: API design patterns for this codebase. Apply when writing API endpoints.
user-invocable: false
---

# API Conventions

When writing API endpoints in this project:
- Use RESTful naming: GET /users/:id, POST /users, PATCH /users/:id
- Always return { data, meta } shape for lists, { data } for single items
- Error format: { error: { code, message, details } }
- Use Zod for request validation, class-transformer for response shaping
```

### Type C: Research Skill (explore in isolation)

For research that should run in a separate context:

```markdown
---
name: deep-research
description: Thoroughly research a topic in the codebase.
context: fork
agent: Explore
---

Research "$ARGUMENTS" thoroughly:

1. Use Glob to find relevant files
2. Use Grep to search for usages
3. Read and analyze the key files
4. Return a structured summary with file:line references
```

---

## Step 4: Arguments

Skills can accept arguments via `$ARGUMENTS` (all args) or `$N` (positional):

```yaml
---
name: fix-issue
description: Fix a GitHub issue by number. MANDATORY TRIGGERS: fix issue, implement issue.
disable-model-invocation: true
argument-hint: "[issue-number]"
allowed-tools: Bash(gh *), Read, Edit, Grep
---

Fix GitHub issue #$ARGUMENTS:

1. Run `gh issue view $ARGUMENTS` to read the requirements
2. Understand what needs to be implemented
3. Find the relevant files using Grep/Glob
4. Implement the fix following project conventions
5. Write or update tests
6. Create a commit with "fix: resolve issue #$ARGUMENTS"
```

**Positional args** (`$0`, `$1`, `$2` or `$ARGUMENTS[0]`, `$ARGUMENTS[1]`):

```yaml
---
name: migrate
description: Migrate a component between frameworks.
argument-hint: "[component] [from-framework] [to-framework]"
---

Migrate the $0 component from $1 to $2.
Preserve all existing behavior, props API, and tests.
```

Run as: `/migrate SearchBar React Vue`

---

## Step 5: Dynamic Context Injection

Use `!`command`` to run shell commands BEFORE Claude sees the skill content. The output replaces the placeholder inline — this is preprocessing, not something Claude executes.

```yaml
---
name: pr-review
description: Review the current pull request.
context: fork
agent: Explore
allowed-tools: Bash(gh *)
---

## Pull Request Context
- Diff: !`gh pr diff`
- Comments: !`gh pr view --comments`
- Changed files: !`gh pr diff --name-only`
- CI status: !`gh pr checks`

## Your Task
Review this pull request. Focus on:
1. Correctness — does it do what the description says?
2. Code quality — follows project conventions?
3. Tests — are they sufficient?
4. Security — any vulnerabilities?

Provide structured feedback grouped by severity.
```

Other useful shell injections:
```bash
!`cat package.json | jq '.version'`          # Project version
!`git log --oneline -10`                      # Recent commits
!`git diff --stat HEAD~1`                     # Last change summary
!`node --version && npm --version`            # Environment info
```

---

## Step 6: Supporting Files

For complex skills, split content into multiple files. Reference them from `SKILL.md`:

**SKILL.md:**
```markdown
## Additional Resources

Read these files when you need deeper detail:
- `docs/api-reference.md` — Full API parameter reference (read when generating API calls)
- `docs/examples.md` — Real-world examples (read when unsure about format)
- `scripts/validate.sh` — Run this to validate generated output
```

**docs/api-reference.md** (only loaded when Claude needs it, keeps SKILL.md lean):
```markdown
# API Parameter Reference
## POST /api/v1/jobs/createTask
...detailed params...
```

---

## Step 7: Evals (Optional but Recommended)

Add test cases to verify the skill works correctly:

**evals/evals.json:**
```json
[
  {
    "prompt": "Review my recent code changes",
    "expected_skill": "review-code",
    "notes": "Should trigger on code review requests"
  },
  {
    "prompt": "/my-skill some-argument",
    "expected_behavior": "Describes what the skill should do with this input"
  }
]
```

---

## Complete Example: The `ai-asset-generator` Pattern

This project's `ai-asset-generator` skill shows the best-in-class pattern:

```
ai-asset-generator/
├── SKILL.md           ← Overview, quick start, key patterns (under 300 lines)
├── docs/
│   ├── gen-image.md   ← Full API reference for image generation
│   ├── genvideo.md    ← Full API reference for video generation
│   └── remove-background.md
├── lib/               ← Shared JS libraries (not loaded, executed)
│   ├── kie-client.mjs
│   └── bg-remove.mjs
└── scripts/
    └── scaffold-generator.mjs
```

Key design decisions:
1. **SKILL.md stays lean** — overview, patterns, entry points only
2. **Docs are lazy-loaded** — Claude reads them when it needs specific API details
3. **Scripts do the heavy work** — Claude orchestrates, scripts execute
4. **Clear output destinations** — explicit about where generated files go

---

## Checklist Before Publishing

- [ ] `name` is lowercase with hyphens only (no spaces, no underscores)
- [ ] `description` contains trigger keywords users would naturally say
- [ ] SKILL.md is under 500 lines (move extras to `docs/`)
- [ ] References to supporting files are explicit ("read `docs/api.md` when you need X")
- [ ] If side effects: `disable-model-invocation: true` is set
- [ ] If background knowledge: `user-invocable: false` is set
- [ ] Tested with `/skill-name` directly
- [ ] Tested that Claude auto-invokes it with natural language

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Description too vague | Add specific trigger phrases, use MANDATORY TRIGGERS format |
| Skill too large (>500 lines) | Split into SKILL.md + docs/*.md |
| Forgot `disable-model-invocation: true` | Claude will run deploys automatically! |
| No `$ARGUMENTS` but users pass args | Args get appended as `ARGUMENTS: value` at end — works but not ideal |
| Using `context: fork` for knowledge skills | Fork = isolated subagent, won't see conversation. Use only for task skills |
| Hardcoded paths | Use script to detect paths dynamically, or use relative paths |
