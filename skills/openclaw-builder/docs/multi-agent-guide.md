# Multi-Agent Setup in OpenClaw

## What Is an "Agent"?

An agent is a fully isolated brain with its own:
- **Workspace** — files, AGENTS.md, SOUL.md, USER.md, persona
- **State directory** (`agentDir`) — auth profiles, model registry, per-agent config
- **Session store** — chat history under `~/.openclaw/agents/<agentId>/sessions`
- **Skills** — via workspace `skills/` folder (shared skills from `~/.openclaw/skills`)

## Quick Start

```bash
# Add new agents via wizard
openclaw agents add coding
openclaw agents add social

# Verify agents and bindings
openclaw agents list --bindings
```

## Config Structure

```json5
// ~/.openclaw/openclaw.json
{
  agents: {
    list: [
      { id: "main", workspace: "~/.openclaw/workspace-main" },
      { id: "coding", workspace: "~/.openclaw/workspace-coding" },
      { id: "social", workspace: "~/.openclaw/workspace-social" },
    ]
  },
  bindings: [
    // Route Telegram bot 1 → coding agent
    { agentId: "coding", match: { channel: "telegram", accountId: "coding-bot" } },
    // Route Telegram bot 2 → social agent
    { agentId: "social", match: { channel: "telegram", accountId: "social-bot" } },
    // Route specific WhatsApp DM → coding agent
    { agentId: "coding", match: { channel: "whatsapp", peer: { kind: "direct", id: "+84901234567" } } },
  ]
}
```

## Routing Rules (Most-Specific Wins)

1. `peer` match — exact DM/group/channel id
2. `parentPeer` — thread inheritance
3. `guildId + roles` — Discord role routing
4. `guildId` — Discord server
5. `teamId` — Slack workspace
6. `accountId` — specific channel account
7. `channel` match with `accountId: "*"` — channel-wide fallback
8. Default agent (first in list or `agents.list[].default: true`)

## Multiple Channels per Agent

Each agent can have multiple channel accounts:

```bash
# Login WhatsApp for specific agent account
openclaw channels login --channel whatsapp --account work

# Login Telegram (just configure multiple bots in config)
```

## Restart & Verify

```bash
openclaw gateway restart
openclaw agents list --bindings
openclaw channels status --probe
```

## Paths Reference

| Item | Path |
|------|------|
| Config | `~/.openclaw/openclaw.json` |
| State dir | `~/.openclaw/` |
| Workspace | `~/.openclaw/workspace-<agentId>` |
| Agent dir | `~/.openclaw/agents/<agentId>/agent` |
| Sessions | `~/.openclaw/agents/<agentId>/sessions` |
| Shared skills | `~/.openclaw/skills/` |
| Per-agent skills | `<workspace>/skills/` |

## Notes

- Never reuse `agentDir` across agents (causes auth/session collisions)
- Auth profiles are per-agent — not shared automatically
- For shared credentials: copy `auth-profiles.json` to the other agent's `agentDir`
