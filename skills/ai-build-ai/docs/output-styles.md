# Tutorial: Output Styles

Output styles modify how Claude Code communicates — changing its tone, verbosity, and teaching style. Unlike CLAUDE.md (which adds project instructions as a user message), output styles replace sections of Claude's default **system prompt**.

---

## Step 1: The Three Built-in Styles

| Style | Behavior |
|-------|----------|
| `default` | Standard Claude Code — efficient software engineering mode |
| `explanatory` | Adds **Insights** between actions: explains implementation choices, patterns, and the "why" behind decisions |
| `learning` | Collaborative mode: shares Insights AND asks you to write small code pieces. Adds `TODO(human)` markers in code for you to fill in |

```bash
/output-style                  # Opens selection menu
/output-style explanatory      # Switch to explanatory style
/output-style learning         # Collaborative learning mode
/output-style default          # Reset to standard mode
```

---

## Step 2: How Output Styles Differ from Other Mechanisms

| Mechanism | What it does | Always active? | Modifies system prompt? |
|-----------|-------------|----------------|------------------------|
| **Output Style** | Changes Claude's tone/teaching mode | Yes (once set) | Replaces sections of it |
| **CLAUDE.md** | Adds project instructions | Yes (loaded at start) | No — added as a user message |
| **Skill** | Runs a specific workflow on demand | No — invoked manually | No |
| **Subagent** | Specialized sub-task in its own context | No — delegated task | Agent has its own system prompt |
| `--append-system-prompt` | Appends text to system prompt | Yes (per session only) | Appends to it |

**Key distinction:** Output styles and `--append-system-prompt` both modify the system prompt. Output styles are **saved persistently per project**; `--append-system-prompt` applies only for that CLI session.

---

## Step 3: Create a Custom Output Style

**Locations:**
```
~/.claude/output-styles/<name>.md      ← Personal (available in all projects)
.claude/output-styles/<name>.md        ← Project-level (commit to share with team)
```

**File format:**

```markdown
---
name: Pair Programmer
description: Collaborative pair programmer — asks questions, challenges assumptions, proposes alternatives
keep-coding-instructions: false
---

You are a collaborative pair programmer. When working with the user:

1. Before implementing, briefly restate the problem to confirm understanding
2. When you see multiple valid approaches, name them and explain trade-offs (2-3 sentences each)
3. After implementing, call out any edge cases or assumptions the user should review
4. If something looks fragile nearby (not just what you changed), mention it as a side note

Be concise. Don't lecture — be a peer.
```

### Frontmatter Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Display name shown in `/output-style` menu |
| `description` | string | Brief description shown in the menu |
| `keep-coding-instructions` | boolean | Retain Claude Code's built-in coding instructions (tests, commit messages, etc.). Default: `false` |

---

## Step 4: `keep-coding-instructions` Explained

**`false` (default):** Your style content is the primary behavior guide. Claude's built-in "always verify builds", "run tests" guidance is removed.
- Best for: tone/communication styles, teaching modes, domain personas

**`true`:** Your instructions are added on top of Claude's coding discipline.
- Best for: adding personality or specific rules while keeping rigorous coding behavior

---

## Step 5: Where Styles Are Saved

When you run `/output-style explanatory`, it saves to:

```json
// .claude/settings.local.json (gitignored — personal only)
{
  "outputStyle": "explanatory"
}
```

**To share a style with your team:**
1. Put the style file in `.claude/output-styles/<name>.md` (commit to git)
2. Set the default in `.claude/settings.json` (commit to git):

```json
{
  "outputStyle": "your-style-name"
}
```

**To keep it personal (gitignored):**
```json
// .claude/settings.local.json
{
  "outputStyle": "your-style-name"
}
```

---

## Example Custom Styles

### Security-Focused

```markdown
---
name: Security Reviewer
description: Always considers security implications in every implementation
keep-coding-instructions: true
---

Always apply a security lens to every change:
- Before implementing: identify any attack surface the change introduces
- During implementation: follow OWASP Top 10 guidelines by default
- After implementing: call out any security assumptions or risks to verify

Flag CRITICAL issues immediately. Mention WARNINGS as concise side notes.
```

### Concise Mode

```markdown
---
name: Concise
description: Ultra-brief responses — code only, minimal explanation
keep-coding-instructions: true
---

Be extremely concise:
- Show code changes directly, no preamble
- One sentence summary max after a change (skip if obvious)
- No "Here's what I did" or "I've implemented..." openers
- Only explain if something non-obvious was done
```

### Mentor Mode

```markdown
---
name: Mentor
description: Teaches while coding — explains patterns, suggests alternatives, builds understanding
keep-coding-instructions: false
---

You are a senior engineer mentoring a junior developer. For every meaningful change:

1. Explain the "why" behind the approach you chose
2. Name the pattern being used (e.g., "this is the Repository pattern")
3. Mention one alternative and why you didn't use it here
4. Point out one thing they should watch for or test

Use analogies when helpful. Assume they're smart but inexperienced with this specific area.
```

### Domain Expert

```markdown
---
name: NestJS Expert
description: Responds as a NestJS/TypeScript expert with opinionated guidance
keep-coding-instructions: true
---

You are a NestJS expert. Apply these defaults to every suggestion:

- Prefer decorators and class-based patterns (NestJS idioms)
- Always use dependency injection — never instantiate services directly
- Validate inputs with class-validator DTOs, never raw objects
- Controllers are thin — all logic lives in services
- Use Guards for auth, Interceptors for cross-cutting concerns, Pipes for transformation

Call out when code deviates from these patterns and why it matters.
```

---

## Quick Reference

```bash
/output-style                    # Open style picker
/output-style explanatory        # Switch to explanatory (shows Insights)
/output-style learning           # Learning mode (you write some code too)
/output-style default            # Reset to standard

# Custom styles are referenced by filename (without .md)
/output-style my-custom-style
```

**File locations:**
```
~/.claude/output-styles/        ← Personal styles (all projects)
.claude/output-styles/          ← Project styles (commit to git to share)
```
