# Tutorial: Create a Custom Subagent

A subagent is a specialized AI assistant that runs in its own isolated context window with a custom system prompt, specific tools, and independent permissions. When Claude encounters a matching task, it delegates to the subagent and summarizes the result.

---

## Step 1: Understand When to Use Subagents

| Use subagents for... | Use main conversation for... |
|----------------------|------------------------------|
| Verbose operations (test runs, log analysis) | Quick edits and targeted changes |
| Isolated tool access (read-only, specific commands) | Multi-step work needing conversation history |
| Parallel workloads (research multiple modules) | Iterative refinement with feedback |
| Consistent domain expertise (always-code-reviewer) | Tasks where context matters |
| Cost optimization (route cheap tasks to Haiku) | Complex reasoning chains |

**Key constraint:** Subagents cannot spawn other subagents. For nested delegation, chain from main conversation.

---

## Step 2: File Format and Location

Subagents are Markdown files with YAML frontmatter:

```
.claude/agents/<name>.md        ← Project-level (commit to git, team shares it)
~/.claude/agents/<name>.md      ← Personal (available in all projects)
```

**Important:** Subagents are loaded at session start. After adding a file manually, restart Claude Code or run `/agents` to reload without restarting.

---

## Step 3: Full Frontmatter Reference

```yaml
---
name: my-agent                  # REQUIRED. Unique, lowercase, hyphens only.
description: |                  # REQUIRED. When Claude should delegate to this agent.
  Expert [domain] specialist. Use proactively when [specific situation].
  Invoke when user [describes trigger condition].

# Tool access (pick one approach):
tools: Read, Grep, Glob, Bash   # Allowlist — only these tools
disallowedTools: Write, Edit    # Denylist — all tools except these

# Model selection:
model: haiku                    # haiku | sonnet | opus | inherit (default: inherit)

# Permissions:
permissionMode: default         # default | acceptEdits | dontAsk | bypassPermissions | plan

# Execution:
maxTurns: 20                    # Max agentic turns before stopping
background: false               # true = always run as background task
isolation: worktree             # Run in isolated git worktree (auto-cleaned up)

# Advanced:
skills:                         # Preload skill content into agent's context
  - api-conventions
  - error-handling-patterns
memory: user                    # Persistent memory: user | project | local
mcpServers:                     # MCP servers available to this agent
  - github
  - slack

# Hooks scoped to this agent's lifecycle:
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate-command.sh"
---
```

---

## Step 4: Write the System Prompt

The markdown body (after frontmatter) is the agent's complete system prompt. Unlike the main conversation, agents start fresh — they don't see conversation history.

### System Prompt Template

```markdown
You are a [role] specializing in [domain].

## Your Mission
[1-2 sentences on what this agent's primary job is]

## When Invoked
[Numbered steps describing the agent's workflow]
1. First, [do this]
2. Then, [analyze/check/validate]
3. Finally, [report/fix/summarize]

## Key Principles
- [Principle 1]: [explanation]
- [Principle 2]: [explanation]
- [Principle 3]: [explanation]

## Output Format
[Describe how to structure the response]
- Use severity levels: CRITICAL > WARNING > SUGGESTION
- Include file:line references for every finding
- End with a summary of top priorities
```

---

## Step 5: Choose the Right Model

| Model | When to Use | Cost |
|-------|-------------|------|
| `haiku` | Fast lookups, simple searches, file reading | Cheapest |
| `sonnet` | Balanced tasks — code review, analysis, fixes | Medium |
| `opus` | Complex reasoning, architecture decisions | Most expensive |
| `inherit` | Use same model as main conversation (default) | Inherits |

Route cheap tasks to Haiku to reduce cost significantly.

---

## Step 6: Control Tool Access

### Allowlist (recommended for restrictive agents)

```yaml
tools: Read, Grep, Glob, Bash
```

This agent can ONLY use Read, Grep, Glob, and Bash.

### Denylist (recommended for mostly-capable agents)

```yaml
disallowedTools: Write, Edit, NotebookEdit
```

This agent has all tools EXCEPT Write, Edit, and NotebookEdit. Good for "read-mostly but can run Bash" agents.

### Restrict which subagents THIS agent can spawn

Only relevant if this is a main-thread agent (`claude --agent`):

```yaml
tools: Agent(worker, researcher), Read, Bash
# OR: allow all subagents
tools: Agent, Read, Bash
```

### Bash command restriction (surgical control)

```yaml
tools: Bash(git *), Bash(npm test *), Read, Grep
# Only allow git commands and npm test commands
```

The space before `*` is important: `Bash(git diff *)` matches `git diff --stat` but NOT `git diff-index`.

---

## Step 7: Persistent Memory

Enable memory so the agent builds institutional knowledge across conversations:

```yaml
memory: user      # ~/.claude/agent-memory/<name>/ — cross-project
memory: project   # .claude/agent-memory/<name>/    — project-specific, committed
memory: local     # .claude/agent-memory-local/<name>/ — project-specific, gitignored
```

When memory is enabled:
- Agent gets Read, Write, Edit tools automatically (for memory files)
- Agent's system prompt includes first 200 lines of `MEMORY.md`
- Agent should curate `MEMORY.md` as it learns patterns

**System prompt addition for memory agents:**
```markdown
## Memory Instructions
After completing your work, update your agent memory with:
- New patterns or conventions you discovered
- Key file locations and their purposes
- Recurring issues and their root causes
- Architectural decisions worth remembering

Keep MEMORY.md concise. Write detailed notes in separate topic files.
```

---

## Step 8: Preload Skills

Give the agent domain knowledge by preloading skill content:

```yaml
skills:
  - api-conventions
  - error-handling-patterns
  - nestjs-architecture
```

The **full content** of each skill is injected at startup — not just descriptions. Use this to give an agent specialized context without bloating its system prompt manually.

---

## Step 9: Define Agent Hooks

Hooks run shell commands at specific lifecycle points:

```yaml
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate-bash.sh"
  PostToolUse:
    - matcher: "Edit|Write"
      hooks:
        - type: command
          command: "npm run lint --silent"
  Stop:
    - hooks:
        - type: command
          command: "./scripts/cleanup.sh"
```

Hook commands receive JSON via stdin with tool details. Exit code 2 blocks the tool call. `Stop` hooks become `SubagentStop` automatically.

---

## Complete Examples

### Example 1: Read-Only Code Reviewer

```markdown
---
name: code-reviewer
description: Expert code review specialist. Use proactively after code changes. Analyze quality, security, and best practices without modifying files.
tools: Read, Grep, Glob, Bash
model: sonnet
memory: project
---

You are a senior code reviewer with expertise in TypeScript, NestJS, and React Native.

## Workflow
1. Run `git diff HEAD~1` to see recent changes
2. Identify modified files and their purpose
3. Read the changed files completely
4. Review against: security, SOLID principles, error handling, TypeScript discipline, performance, test coverage

## Review Format
For each issue:
```
**[SEVERITY] Short description**
File: path/to/file.ts:L42
Problem: What's wrong and why it matters
Fix: Concrete improved code
```

Severity: CRITICAL (security/data loss) > WARNING (architecture) > SUGGESTION (quality) > NITPICK (style)

## Memory Instructions
Update memory with recurring patterns, common anti-patterns found, and architectural decisions.
```

### Example 2: Test Runner and Fixer

```markdown
---
name: test-fixer
description: Run failing tests, diagnose root causes, and implement fixes. Use when tests fail or before committing code.
tools: Read, Edit, Bash, Grep, Glob
model: sonnet
---

You are a testing expert. Your job is to find failing tests, understand why they fail, and fix them.

## Workflow
1. Run the test suite: `npm test -- --passWithNoTests 2>&1 | head -200`
2. Identify failing tests and their error messages
3. Find the source code causing failures
4. Implement minimal fixes — don't change behavior, fix the bug
5. Run tests again to confirm fixes
6. Report what was fixed and why

## Principles
- Fix root causes, not symptoms
- Keep test assertions intact — if the test expectation is wrong, flag it but don't delete
- One fix per problem — don't refactor surrounding code
- Run tests after each fix to catch regressions early
```

### Example 3: Database Query Validator (with Hook)

```markdown
---
name: db-analyst
description: Execute read-only database queries to answer questions about data. Never modifies data.
tools: Bash
model: haiku
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: ".claude/agents/scripts/validate-readonly.sh"
---

You are a database analyst with read-only access.

When asked about data, write and execute SELECT queries. Present results clearly with context and key insights.

You cannot INSERT, UPDATE, DELETE, DROP, or modify any data. If asked, explain that you have read-only access and suggest the appropriate team contact for data modifications.
```

And the validation script:
```bash
#!/bin/bash
# .claude/agents/scripts/validate-readonly.sh
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
if echo "$CMD" | grep -iE '\b(INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|TRUNCATE|REPLACE)\b' > /dev/null 2>&1; then
  echo "Blocked: Only SELECT queries allowed." >&2
  exit 2
fi
exit 0
```

### Example 4: Background File Processor

```markdown
---
name: file-processor
description: Process large files or run batch operations in the background. Use for operations that produce verbose output.
tools: Read, Write, Bash, Glob
background: true
model: haiku
---

You are a file processing agent. Execute the requested batch operation efficiently.

Report only the summary when complete:
- How many files processed
- How many succeeded / failed
- Any errors encountered
- Output location
```

---

## Step 10: CLI-Defined Agents (Session-Only)

For quick testing or one-off automation, define agents via CLI without creating a file:

```bash
claude --agents '{
  "code-reviewer": {
    "description": "Expert code reviewer. Use proactively after code changes.",
    "prompt": "You are a senior code reviewer. Focus on quality, security, and best practices.",
    "tools": ["Read", "Grep", "Glob", "Bash"],
    "model": "sonnet"
  }
}'
```

Fields in CLI JSON: `description`, `prompt`, `tools`, `disallowedTools`, `model`, `permissionMode`, `maxTurns`, `skills`, `memory`, `hooks`, `mcpServers`.

---

## Managing Agents

```bash
# Interactive agent manager
/agents

# List all configured agents (CLI)
claude agents

# Ask Claude to use a specific agent
"Use the code-reviewer agent to review the auth module"
"Have the test-fixer agent look at the failing tests"
```

---

## Checklist Before Publishing

- [ ] `name` is lowercase, hyphens only
- [ ] `description` says "Use proactively when..." so Claude knows to auto-delegate
- [ ] Tools are restricted to minimum needed (principle of least privilege)
- [ ] Model is right-sized (haiku for simple, sonnet for complex)
- [ ] System prompt describes workflow step-by-step
- [ ] System prompt describes output format clearly
- [ ] Tested via `/agents` interface
- [ ] Memory enabled if the agent should learn across sessions
- [ ] Hooks added if tool validation is needed
