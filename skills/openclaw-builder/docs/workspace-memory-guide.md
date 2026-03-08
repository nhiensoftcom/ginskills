# Workspace & Memory

## Workspace Overview

The workspace is the agent's home directory — all files, memory, and skills live here.

**Default location:** `~/.openclaw/workspace`

```json5
// Override in ~/.openclaw/openclaw.json
{
  agents: {
    defaults: {
      workspace: "~/.openclaw/workspace"
    }
  }
}
```

## Key Files in Workspace

| File | Purpose | Loaded when |
|------|---------|-------------|
| `AGENTS.md` | Operating instructions, rules, behavior | Every session |
| `SOUL.md` | Persona, tone, boundaries | Every session |
| `USER.md` | Who the user is, preferences | Every session |
| `TOOLS.md` | Tool notes, conventions | Every session |
| `IDENTITY.md` | Agent name, emoji, vibe | Every session |
| `BOOTSTRAP.md` | First-run setup ritual | Once (then delete) |
| `HEARTBEAT.md` | Heartbeat checklist | Every heartbeat |
| `MEMORY.md` | Long-term curated memory | Main session only |
| `memory/YYYY-MM-DD.md` | Daily notes | Today + yesterday |

**Rules:**
- Blank files are skipped (no token cost)
- Large files are trimmed/truncated
- Missing files get a "missing" marker (not an error)

## Memory System

OpenClaw memory = plain Markdown files. The model only "remembers" what gets written to disk.

### Two-Layer Memory

**Short-term (daily):**
```
memory/2026-03-08.md
```
- Append-only daily log
- Agent reads today + yesterday at session start
- Raw notes, what happened, context

**Long-term (curated):**
```
MEMORY.md
```
- Distilled important facts, decisions, preferences
- ⚠️ Load ONLY in private main session — never in group chats
- Agent reviews daily logs and promotes key info here

### Memory Tools

```
memory_search  — semantic search across memory files
memory_get     — read specific file/line range
```

### When to Write Memory

- Someone says "remember this" → write to `memory/YYYY-MM-DD.md`
- Important decision/preference → write to `MEMORY.md`
- Today's events → append to `memory/YYYY-MM-DD.md`
- DO NOT keep things in "mental notes" — files survive restarts, RAM doesn't

### Auto Memory Flush

Before compaction, OpenClaw automatically prompts the agent to write durable memories. Configurable:

```json5
{
  agents: {
    defaults: {
      compaction: {
        memoryFlush: {
          enabled: true,
          prompt: "Write lasting notes to memory/YYYY-MM-DD.md; reply NO_REPLY if nothing to store."
        }
      }
    }
  }
}
```

## Skills in Workspace

Skills live in `<workspace>/skills/` and take highest precedence over bundled/managed skills.

```
~/.openclaw/workspace/
├── AGENTS.md
├── SOUL.md
├── MEMORY.md
├── memory/
│   ├── 2026-03-07.md
│   └── 2026-03-08.md
└── skills/
    └── my-skill/
        └── SKILL.md
```

## Sandboxing

By default, tools run on the host. Enable Docker sandboxing for isolation:

```json5
{
  agents: {
    defaults: {
      sandbox: {
        mode: "non-main",    // sandbox non-main sessions only
        scope: "session",    // one container per session
        workspaceAccess: "rw"  // mount workspace read/write
      }
    }
  }
}
```

Modes: `"off"` | `"non-main"` | `"all"`
Scope: `"session"` | `"agent"` | `"shared"`
