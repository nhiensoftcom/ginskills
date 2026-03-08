# Hooks — Event-Driven Automation

## What Are Hooks?

Hooks are small TypeScript scripts that run automatically when agent events fire (e.g. `/new`, session start, message received). They extend OpenClaw behavior without modifying core code.

**Two types:**
- **Hooks** (this guide) — run inside the Gateway on agent events
- **Webhooks** — external HTTP triggers (see `automation/webhook` docs)

## Bundled Hooks (Ready to Enable)

```bash
openclaw hooks list          # see all available hooks
openclaw hooks list --eligible
openclaw hooks enable <name>
```

| Hook | Event | What it does |
|------|-------|-------------|
| `session-memory` | `/new` | Saves session context to `memory/YYYY-MM-DD-slug.md` |
| `bootstrap-extra-files` | `agent:bootstrap` | Injects extra workspace files (e.g. monorepo `AGENTS.md`) |
| `command-logger` | all commands | Logs commands to `~/.openclaw/logs/commands.log` |
| `boot-md` | `gateway:startup` | Runs `BOOT.md` when gateway starts |

## Creating a Custom Hook

### 1. Create directory

```bash
mkdir -p ~/.openclaw/hooks/my-hook
```

### 2. Create HOOK.md

```markdown
---
name: my-hook
description: "Does something on /new"
metadata: { "openclaw": { "emoji": "🎯", "events": ["command:new"] } }
---

# My Hook
Runs when user sends /new.
```

### 3. Create handler.ts

```typescript
const handler = async (event) => {
  if (event.type !== "command" || event.action !== "new") return;
  
  console.log("[my-hook] /new triggered!");
  event.messages.push("✅ Hook ran successfully!");
};

export default handler;
```

### 4. Enable

```bash
openclaw hooks list        # verify it's discovered
openclaw hooks enable my-hook
# restart gateway
```

## Event Types

| Event key | Trigger |
|-----------|---------|
| `command:new` | User sends `/new` |
| `command:reset` | User sends `/reset` |
| `command:stop` | User sends `/stop` |
| `agent:bootstrap` | Before workspace files injected |
| `gateway:startup` | Gateway starts |
| `message:received` | Inbound message received |
| `message:sent` | Outbound message sent |
| `message:transcribed` | Audio transcription complete |
| `session:compact:before` | Before compaction |
| `session:compact:after` | After compaction |

## Handler Context

```typescript
event = {
  type: string,          // "command" | "session" | "agent" | "gateway" | "message"
  action: string,        // "new" | "reset" | "stop" | "received" | "sent" | ...
  sessionKey: string,
  timestamp: Date,
  messages: string[],    // push here to send message to user
  context: {
    workspaceDir?: string,
    // message events:
    from?: string,       // sender id
    to?: string,         // recipient
    content?: string,
    channelId?: string,
    conversationId?: string,
  }
}
```

## Config (openclaw.json)

```json5
{
  hooks: {
    internal: {
      enabled: true,
      entries: {
        "session-memory": { "enabled": true },
        "command-logger": { "enabled": false },
        "my-hook": { 
          "enabled": true,
          "env": { "MY_VAR": "value" }
        }
      },
      load: {
        extraDirs: ["/path/to/more/hooks"]
      }
    }
  }
}
```

## Best Practices

- Return early if event not relevant (`if (event.type !== ...) return;`)
- Wrap in try/catch — don't let hook errors block command processing
- Keep handlers fast — use fire-and-forget for slow operations
- Prefer specific event keys (`command:new`) over general (`command`)
