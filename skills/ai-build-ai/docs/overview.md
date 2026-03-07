# AI Build AI — Overview

You are helping the user understand and use Claude Code's extensibility system. Claude Code can be extended in nine ways:

---

## The Nine Extension Types

### 1. Skills (`/ai-build-ai skill`)
**What:** Reusable prompt playbooks stored as `SKILL.md` files. Auto-invoked by Claude or triggered with `/skill-name`.
**When:** Repeatable workflows, domain knowledge, step-by-step procedures Claude should follow consistently.
**Location:** `.claude/skills/<name>/SKILL.md` (project) | `~/.claude/skills/<name>/SKILL.md` (personal)

### 2. Custom Subagents (`/ai-build-ai agent`)
**What:** Specialized AI assistants with their own context window, system prompt, tools, and permissions.
**When:** Context isolation for verbose tasks, restricted tool access, parallel workloads, domain specialists.
**Location:** `.claude/agents/<name>.md` (project) | `~/.claude/agents/<name>.md` (personal)

### 3. MCP Servers (`/ai-build-ai mcp`)
**What:** External tools and data sources connected via Model Context Protocol. Gives Claude access to GitHub, databases, Slack, APIs.
**When:** Claude needs to interact with external systems.
**Command:** `claude mcp add --transport http|sse|stdio <name> <url-or-command>`

### 4. Headless / Agent SDK (`/ai-build-ai headless`)
**What:** Running Claude programmatically from scripts, CI/CD, or the Python/TypeScript SDK.
**When:** Automation, batch processing, CI/CD integration, building apps with Claude as the AI.
**Key flag:** `claude -p "your prompt" --allowedTools "Read,Edit,Bash"`

### 5. Hooks (`/ai-build-ai hooks`)
**What:** Shell commands / HTTP endpoints / LLM prompts that fire automatically at lifecycle points (PreToolUse, PostToolUse, SessionStart, Stop, etc.).
**When:** Auto-format files on save, block dangerous commands, inject context, send notifications, enforce rules deterministically.
**Location:** `.claude/settings.json` under `"hooks"` key

### 6. Plugins (`/ai-build-ai plugins`)
**What:** Packaged bundles of skills + agents + hooks + MCP servers with a manifest (`plugin.json`), versioning, and marketplace distribution.
**When:** Sharing across teams/community, versioned releases, one-command installs.
**Structure:** `my-plugin/.claude-plugin/plugin.json` + `skills/`, `agents/`, `hooks/`, `.mcp.json`

### 7. Agent Teams (`/ai-build-ai teams`)
**What:** Multiple Claude Code instances coordinated as a team — a lead assigns tasks, teammates work independently and communicate directly.
**When:** Complex parallel work needing inter-agent discussion, competing hypothesis testing, cross-layer features.
**Enable:** `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (experimental)

### 8. CLAUDE.md & Memory (`/ai-build-ai memory`)
**What:** Persistent instructions (CLAUDE.md) and auto-learning (auto memory) that survive across sessions.
**When:** Project conventions, coding standards, architecture decisions, personal workflow preferences.
**Location:** `./CLAUDE.md`, `~/.claude/CLAUDE.md`, `.claude/rules/*.md`

### 9. Permissions (`/ai-build-ai permissions`)
**What:** Fine-grained control over which tools, files, and domains Claude can access — allow/deny/ask rules.
**When:** Restricting Claude to safe operations, CI/CD automation, enterprise policy enforcement.
**Location:** `.claude/settings.json` under `"permissions"` key

### 10. Sandbox (`/ai-build-ai sandbox`)
**What:** OS-level enforcement that restricts what bash commands (and their child processes) can read, write, or access on the network — independent of Claude's permission rules.
**When:** Extra security for untrusted scripts, preventing accidental writes to sensitive files, restricting outbound network access.
**Platform:** macOS (Seatbelt), Linux/WSL2 (bubblewrap+socat)

### 11. Checkpointing (`/ai-build-ai checkpoint`)
**What:** Automatic snapshots before every file edit. Rewind code, conversation, or both to any previous state. Fork sessions to experiment without losing work.
**When:** Recovering from mistakes, experimenting with risky changes, managing context.
**How:** `Esc+Esc` or `/rewind` to open rewind menu; `claude --continue` / `--resume` to manage sessions.

### 12. Output Styles (`/ai-build-ai output-styles`)
**What:** Modify Claude's communication style — tone, verbosity, teaching mode. Replaces sections of Claude's default system prompt.
**When:** Learning mode, pair programming style, domain expert persona, ultra-concise mode.
**Location:** `~/.claude/output-styles/` (personal) or `.claude/output-styles/` (project)

---

## Decision Table: What Should I Build?

| Goal | Build This |
|------|-----------|
| Teach Claude a repeatable workflow (code review, PR creation, deploy) | **Skill** |
| Add domain knowledge Claude should always apply | **Skill** (`user-invocable: false`) |
| Isolate verbose output from main conversation context | **Subagent** |
| Restrict tools for a specific task type | **Subagent** |
| Connect to GitHub / Slack / database / internal API | **MCP Server** |
| Build your own custom MCP server | **MCP Server** (build it with the MCP SDK) |
| Run Claude in CI/CD, scripts, or automation | **Headless / Agent SDK** |
| Build an app that uses Claude as the AI backend | **Agent SDK** (Python/TypeScript) |
| Auto-format files after every edit | **Hook** (PostToolUse) |
| Block dangerous commands deterministically | **Hook** (PreToolUse) |
| Send notifications when Claude needs input | **Hook** (Notification) |
| Enforce rules that must ALWAYS apply (not just Claude deciding) | **Hook** |
| Share extensions with your team or community | **Plugin** |
| Distribute versioned, installable extensions | **Plugin** |
| Parallel work needing teammates to discuss with each other | **Agent Teams** |
| Persist coding standards for the whole team | **CLAUDE.md** (committed) |
| Restrict what files/commands Claude can touch | **Permissions** |
| Enterprise-wide policy enforcement | **Managed Permissions** |
| Add OS-level protection for bash commands | **Sandbox** |
| Block bash from accessing secrets or network | **Sandbox** |
| Undo a mistake without losing other work | **Checkpointing** (`Esc+Esc`) |
| Change Claude's tone or teaching style | **Output Style** |
| Create a "learning mode" or "mentor mode" | **Output Style** |

---

## Quick Start

```bash
# 1. Create a skill
mkdir -p .claude/skills/my-skill
cat > .claude/skills/my-skill/SKILL.md << 'EOF'
---
name: my-skill
description: What this skill does and when to use it
---
# Instructions for Claude...
EOF

# 2. Create a subagent
mkdir -p .claude/agents
cat > .claude/agents/my-agent.md << 'EOF'
---
name: my-agent
description: When Claude should delegate to this agent
tools: Read, Grep, Glob
model: haiku
---
You are a specialized agent...
EOF

# 3. Add a hook (in .claude/settings.json)
# { "hooks": { "PostToolUse": [{ "matcher": "Edit|Write", "hooks": [{ "type": "command", "command": "..." }] }] } }

# 4. Add an MCP server
claude mcp add --transport http github https://api.githubcopilot.com/mcp/

# 5. Run Claude programmatically
claude -p "Summarize this project" --output-format json

# 6. Create CLAUDE.md
/init   # Auto-generates from codebase

# 7. Create a plugin
mkdir -p my-plugin/.claude-plugin
echo '{"name":"my-plugin","description":"...","version":"1.0.0"}' > my-plugin/.claude-plugin/plugin.json
claude --plugin-dir ./my-plugin   # Test it
```

---

## Topic Commands

| Command | Loads |
|---------|-------|
| `/ai-build-ai skill` | SKILL.md format, frontmatter, arguments, dynamic context, examples |
| `/ai-build-ai agent` | Subagent config, tools, models, memory, hooks, examples |
| `/ai-build-ai mcp` | MCP server setup + building your own MCP server |
| `/ai-build-ai headless` | `claude -p`, output formats, CI/CD, Python/TS SDK |
| `/ai-build-ai hooks` | All hook events, types, exit codes, matchers, recipes |
| `/ai-build-ai plugins` | Plugin manifest, structure, skills/agents/hooks/MCP in plugins, distribution |
| `/ai-build-ai teams` | Agent teams: enable, start, control, display modes, use cases |
| `/ai-build-ai memory` | CLAUDE.md, .claude/rules/, auto memory, imports, monorepo setup |
| `/ai-build-ai permissions` | Allow/deny rules, modes, Bash/Read/Edit/WebFetch/MCP/Agent rules |
| `/ai-build-ai sandbox` | OS-level enforcement, filesystem rules, network filtering, path prefixes |
| `/ai-build-ai checkpoint` | Rewind, fork, session management, summarize from here |
| `/ai-build-ai output-styles` | Built-in styles, custom styles, keep-coding-instructions |
| `/ai-build-ai` | This overview + decision table |
