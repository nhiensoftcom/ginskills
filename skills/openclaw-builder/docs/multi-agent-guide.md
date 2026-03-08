# Multi-Agent Setup in OpenClaw

## Khái niệm cơ bản

Mỗi **agent** là một "bộ não" hoàn toàn cô lập với:
- **Workspace** riêng — AGENTS.md, SOUL.md, USER.md, persona
- **agentDir** riêng — auth profiles, model registry, per-agent config
- **Session store** riêng — `~/.openclaw/agents/<agentId>/sessions`
- **Skills** riêng — `<workspace>/skills/` (+ shared từ `~/.openclaw/skills`)

> ⚠️ **Không bao giờ** reuse `agentDir` giữa 2 agents — sẽ gây auth/session collision.

---

## Single Agent (Default)

Khi không cấu hình gì, OpenClaw chạy 1 agent mặc định:
- `agentId` = `main`
- Sessions keyed as `agent:main:<mainKey>`
- Workspace = `~/.openclaw/workspace`

---

## Thêm Agent Mới

### Cách 1: Dùng wizard (khuyến nghị)

```bash
openclaw agents add coding     # tạo agent "coding"
openclaw agents add social     # tạo agent "social"
openclaw agents list --bindings  # verify
```

Wizard tự tạo workspace, agentDir, và hỏi bạn setup bindings.

### Cách 2: Cấu hình thủ công

```json5
// ~/.openclaw/openclaw.json
{
  agents: {
    list: [
      {
        id: "main",
        default: true,                          // fallback agent
        name: "Personal",
        workspace: "~/.openclaw/workspace-main",
        agentDir: "~/.openclaw/agents/main/agent",
      },
      {
        id: "coding",
        name: "Coding Agent",
        workspace: "~/.openclaw/workspace-coding",
        agentDir: "~/.openclaw/agents/coding/agent",
        model: "anthropic/claude-opus-4-6",    // per-agent model override
      },
      {
        id: "social",
        name: "Social Bot",
        workspace: "~/.openclaw/workspace-social",
        agentDir: "~/.openclaw/agents/social/agent",
        model: "anthropic/claude-sonnet-4-6",
      },
    ],
  },
}
```

---

## Bindings — Routing Messages đến Agents

Bindings quyết định message nào đến agent nào. **Most-specific wins** (thứ tự ưu tiên):

1. `peer` match — exact DM/group id (ưu tiên cao nhất)
2. `parentPeer` — thread inheritance
3. `guildId + roles` — Discord role routing
4. `guildId` — Discord server
5. `teamId` — Slack workspace
6. `accountId` — specific channel account
7. `channel` + `accountId: "*"` — channel-wide fallback
8. Default agent (first in list hoặc `default: true`)

```json5
{
  bindings: [
    // Peer-specific (highest priority)
    {
      agentId: "opus",
      match: { channel: "whatsapp", peer: { kind: "direct", id: "+84901234567" } },
    },
    // Account-specific
    { agentId: "coding", match: { channel: "telegram", accountId: "coding-bot" } },
    // Channel-wide fallback
    { agentId: "main", match: { channel: "whatsapp" } },
  ],
}
```

> Nếu nhiều bindings match cùng tier → binding đầu tiên trong config thắng.

---

## Ví dụ Thực Tế

### 1. Telegram — 2 bots, 2 agents

Tạo 2 bot khác nhau qua @BotFather, mỗi bot map 1 agent:

```json5
{
  agents: {
    list: [
      { id: "main", workspace: "~/.openclaw/workspace-main" },
      { id: "alerts", workspace: "~/.openclaw/workspace-alerts" },
    ],
  },
  bindings: [
    { agentId: "main", match: { channel: "telegram", accountId: "default" } },
    { agentId: "alerts", match: { channel: "telegram", accountId: "alerts-bot" } },
  ],
  channels: {
    telegram: {
      accounts: {
        default: {
          botToken: "111111:MAIN_TOKEN",
          dmPolicy: "pairing",
        },
        "alerts-bot": {
          botToken: "222222:ALERTS_TOKEN",
          dmPolicy: "allowlist",
          allowFrom: ["123456789"],   // your chat id
        },
      },
    },
  },
}
```

### 2. WhatsApp — 2 số điện thoại, 2 agents

```bash
# Link từng số riêng
openclaw channels login --channel whatsapp --account personal
openclaw channels login --channel whatsapp --account biz
```

```json5
{
  agents: {
    list: [
      { id: "home", default: true, workspace: "~/.openclaw/workspace-home" },
      { id: "work", workspace: "~/.openclaw/workspace-work" },
    ],
  },
  bindings: [
    { agentId: "home", match: { channel: "whatsapp", accountId: "personal" } },
    { agentId: "work", match: { channel: "whatsapp", accountId: "biz" } },
    // Route 1 group từ số personal → work agent
    {
      agentId: "work",
      match: {
        channel: "whatsapp",
        accountId: "personal",
        peer: { kind: "group", id: "120363xxx@g.us" },
      },
    },
  ],
  channels: {
    whatsapp: {
      accounts: {
        personal: {},   // authDir auto: ~/.openclaw/credentials/whatsapp/personal
        biz: {},        // authDir auto: ~/.openclaw/credentials/whatsapp/biz
      },
    },
  },
}
```

### 3. WhatsApp — 1 số, split DM theo người gửi

```json5
{
  agents: {
    list: [
      { id: "alex", workspace: "~/.openclaw/workspace-alex" },
      { id: "mia", workspace: "~/.openclaw/workspace-mia" },
    ],
  },
  bindings: [
    { agentId: "alex", match: { channel: "whatsapp", peer: { kind: "direct", id: "+15551230001" } } },
    { agentId: "mia", match: { channel: "whatsapp", peer: { kind: "direct", id: "+15551230002" } } },
  ],
  channels: {
    whatsapp: {
      dmPolicy: "allowlist",
      allowFrom: ["+15551230001", "+15551230002"],
    },
  },
}
```

> Reply vẫn đến từ cùng 1 số WhatsApp — chỉ "bộ nhớ/brain" khác nhau per người.

### 4. Discord — 2 bots per agent

```json5
{
  agents: {
    list: [
      { id: "main", workspace: "~/.openclaw/workspace-main" },
      { id: "coding", workspace: "~/.openclaw/workspace-coding" },
    ],
  },
  bindings: [
    { agentId: "main", match: { channel: "discord", accountId: "default" } },
    { agentId: "coding", match: { channel: "discord", accountId: "coding" } },
  ],
  channels: {
    discord: {
      accounts: {
        default: {
          token: "DISCORD_BOT_TOKEN_MAIN",
          guilds: {
            "SERVER_ID": {
              channels: {
                "GENERAL_CHANNEL_ID": { allow: true, requireMention: false },
              },
            },
          },
        },
        coding: {
          token: "DISCORD_BOT_TOKEN_CODING",
          guilds: {
            "SERVER_ID": {
              channels: {
                "DEV_CHANNEL_ID": { allow: true, requireMention: false },
              },
            },
          },
        },
      },
    },
  },
}
```

### 5. Channel split — WhatsApp fast, Telegram deep work

```json5
{
  agents: {
    list: [
      {
        id: "chat",
        name: "Everyday",
        workspace: "~/.openclaw/workspace-chat",
        model: "anthropic/claude-sonnet-4-6",
      },
      {
        id: "opus",
        name: "Deep Work",
        workspace: "~/.openclaw/workspace-opus",
        model: "anthropic/claude-opus-4-6",
      },
    ],
  },
  bindings: [
    // Peer-specific (thêm trước — ưu tiên cao hơn channel-wide)
    { agentId: "opus", match: { channel: "whatsapp", peer: { kind: "direct", id: "+84901234567" } } },
    // Channel-wide fallback
    { agentId: "chat", match: { channel: "whatsapp" } },
    { agentId: "opus", match: { channel: "telegram" } },
  ],
}
```

### 6. Family agent — sandboxed, giới hạn tools

```json5
{
  agents: {
    list: [
      {
        id: "family",
        name: "Family Bot",
        workspace: "~/.openclaw/workspace-family",
        sandbox: {
          mode: "all",        // luôn sandbox
          scope: "agent",     // 1 container per agent
        },
        tools: {
          allow: ["read", "exec"],
          deny: ["write", "edit", "apply_patch", "browser"],
        },
        groupChat: {
          mentionPatterns: ["@family", "@familybot"],
        },
      },
    ],
  },
  bindings: [
    {
      agentId: "family",
      match: { channel: "whatsapp", peer: { kind: "group", id: "120363xxx@g.us" } },
    },
  ],
}
```

---

## Per-Agent Heartbeat

Chỉ agents có `heartbeat` block mới chạy heartbeat:

```json5
{
  agents: {
    defaults: {
      heartbeat: { every: "30m", target: "last" },
    },
    list: [
      { id: "main", default: true },
      {
        id: "ops",
        heartbeat: {
          every: "1h",
          target: "telegram",
          to: "YOUR_CHAT_ID",
          accountId: "ops-bot",
          prompt: "Read HEARTBEAT.md. Reply HEARTBEAT_OK if nothing to do.",
        },
      },
    ],
  },
}
```

---

## Verify & Debug

```bash
openclaw gateway restart              # apply config
openclaw agents list --bindings       # verify agents + routes
openclaw channels status --probe      # check all channels connected
openclaw doctor                       # diagnose issues
```

---

## Paths Reference

| Item | Path |
|------|------|
| Config | `~/.openclaw/openclaw.json` |
| Workspace | `~/.openclaw/workspace-<agentId>` |
| Agent state | `~/.openclaw/agents/<agentId>/agent` |
| Auth profiles | `~/.openclaw/agents/<agentId>/agent/auth-profiles.json` |
| Sessions | `~/.openclaw/agents/<agentId>/sessions` |
| Shared skills | `~/.openclaw/skills/` |
| Per-agent skills | `<workspace>/skills/` |
| WhatsApp creds | `~/.openclaw/credentials/whatsapp/<accountId>` |

---

## Lưu ý Quan Trọng

- **Auth profiles** là per-agent — không tự share. Muốn share: copy `auth-profiles.json` sang agent kia
- **`tools.elevated`** là global, không config per-agent được
- **DM security**: nếu nhiều người DM cùng 1 agent → set `session.dmScope: "per-channel-peer"` để isolate sessions
- **Peer bindings phải đặt TRƯỚC channel-wide bindings** trong config (first match wins)
