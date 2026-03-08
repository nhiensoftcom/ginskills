# Gateway Configuration Cheatsheet

## File Location

```
~/.openclaw/openclaw.json   (JSON5 format — comments + trailing commas OK)
```

## Edit Config

```bash
openclaw configure          # interactive wizard
openclaw config get <path>  # read a value
openclaw config set agents.defaults.heartbeat.every "1h"
openclaw config unset tools.web.search.apiKey
openclaw doctor             # validate + diagnose issues
openclaw doctor --fix       # auto-repair
```

Or edit file directly — Gateway hot-reloads on file change.

## Starter Config

```json5
{
  identity: {
    name: "MyAgent",
    emoji: "🤖",
  },
  agents: {
    defaults: {
      workspace: "~/.openclaw/workspace",
      model: { primary: "anthropic/claude-sonnet-4-6" },
      heartbeat: {
        every: "30m",
        target: "last",
        lightContext: true,
        activeHours: { start: "08:00", end: "23:00" },
      },
    },
  },
  channels: {
    telegram: {
      botToken: "YOUR_BOT_TOKEN",
      dmPolicy: "allowlist",
      allowFrom: ["YOUR_CHAT_ID"],
    },
  },
  skills: {
    load: {
      extraDirs: ["~/path/to/your/skills"],
    },
  },
}
```

## Key Config Sections

### agents.defaults

```json5
{
  agents: {
    defaults: {
      workspace: "~/.openclaw/workspace",
      model: {
        primary: "anthropic/claude-sonnet-4-6",
        fallback: ["openai/gpt-4o"],
      },
      heartbeat: { every: "30m", target: "last" },
      sandbox: { mode: "off" },
    },
  },
}
```

### channels

```json5
{
  channels: {
    telegram: {
      botToken: "TOKEN",
      dmPolicy: "allowlist",          // allowlist | paired | open
      allowFrom: ["CHAT_ID"],
      groups: {
        "*": { requireMention: true } // require @bot mention in groups
      },
    },
    discord: {
      botToken: "TOKEN",
      guildIds: ["SERVER_ID"],
    },
    whatsapp: {
      allowFrom: ["+84901234567"],
    },
  },
}
```

### skills

```json5
{
  skills: {
    load: {
      extraDirs: ["/path/to/skills"],
      watch: true,
    },
    entries: {
      "my-skill": { enabled: true },
      "unwanted-skill": { enabled: false },
    },
  },
}
```

### tools

```json5
{
  tools: {
    web: {
      search: { apiKey: "BRAVE_API_KEY" },
      fetch: { enabled: true },
    },
    exec: {
      policy: "allowlist",     // allowlist | full | deny
      applyPatch: true,
    },
    elevated: { enabled: false },
  },
}
```

### cron

```json5
{
  cron: {
    enabled: true,
    sessionRetention: "24h",
  },
}
```

### hooks

```json5
{
  hooks: {
    internal: {
      enabled: true,
      entries: {
        "session-memory": { enabled: true },
        "command-logger": { enabled: true },
      },
    },
  },
}
```

## Multi-Agent Config

```json5
{
  agents: {
    list: [
      { id: "main", default: true, workspace: "~/.openclaw/workspace-main" },
      { id: "coding", workspace: "~/.openclaw/workspace-coding" },
    ],
  },
  bindings: [
    { agentId: "coding", match: { channel: "telegram", accountId: "coding-bot" } },
  ],
  channels: {
    telegram: {
      accounts: {
        default: { botToken: "MAIN_BOT_TOKEN" },
        "coding-bot": { botToken: "CODING_BOT_TOKEN" },
      },
    },
  },
}
```

## Validation

Config is **strictly validated** — unknown keys cause Gateway to refuse start.

```bash
openclaw doctor          # check for issues
openclaw gateway status  # is gateway running?
openclaw gateway restart # apply config changes
```
