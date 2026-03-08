# Webhooks & External Triggers

## Overview

Gateway có thể nhận HTTP webhook từ external services (GitHub, Gmail, Zapier...) và trigger agent turn.

---

## Enable

```json5
// ~/.openclaw/openclaw.json
{
  hooks: {
    enabled: true,
    token: "your-shared-secret",      // bắt buộc
    path: "/hooks",                   // default: /hooks
    allowedAgentIds: ["main", "hooks"], // optional: restrict agent routing
    defaultSessionKey: "hook:ingress",
    allowRequestSessionKey: false,    // default: không cho caller set session key
  },
}
```

---

## Auth (mọi request phải có token)

```bash
# Recommended
Authorization: Bearer <token>
x-openclaw-token: <token>

# KHÔNG dùng query string (?token=... → rejected)
```

---

## Endpoints

### POST /hooks/wake

Wake agent lên check something — runs trong main session:

```bash
curl -X POST http://127.0.0.1:18789/hooks/wake \
  -H 'Authorization: Bearer SECRET' \
  -H 'Content-Type: application/json' \
  -d '{"text":"New email received","mode":"now"}'
```

**Payload:**
```json
{
  "text": "New email received",    // required — mô tả event
  "mode": "now"                    // "now" (default) hoặc "next-heartbeat"
}
```

### POST /hooks/agent

Chạy isolated agent turn với prompt riêng:

```bash
curl -X POST http://127.0.0.1:18789/hooks/agent \
  -H 'x-openclaw-token: SECRET' \
  -H 'Content-Type: application/json' \
  -d '{
    "message": "Summarize the latest emails and reply to urgent ones",
    "name": "Gmail",
    "agentId": "main",
    "deliver": true,
    "channel": "telegram",
    "to": "YOUR_CHAT_ID",
    "model": "anthropic/claude-sonnet-4-6",
    "wakeMode": "now",
    "timeoutSeconds": 120
  }'
```

**Payload fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `message` | ✅ | Prompt cho agent |
| `name` | | Label (e.g. "GitHub") — xuất hiện trong session summary |
| `agentId` | | Route đến agent cụ thể (default: main) |
| `deliver` | | Gửi response ra channel (default: true) |
| `channel` | | `last`, `telegram`, `discord`, `whatsapp`, `slack`, `signal` |
| `to` | | Chat ID / phone number của recipient |
| `model` | | Override model cho run này |
| `thinking` | | `low`, `medium`, `high` |
| `wakeMode` | | `now` hoặc `next-heartbeat` |
| `timeoutSeconds` | | Max thời gian chạy (seconds) |

---

## Custom Hook Mappings

Map custom endpoint path → action + transform:

```json5
{
  hooks: {
    enabled: true,
    token: "${OPENCLAW_HOOKS_TOKEN}",
    presets: ["gmail"],           // built-in Gmail mapping
    mappings: {
      "github": {
        match: { source: "github" },
        action: "agent",
        agentId: "main",
        message: "New GitHub event: {{payload.action}} on {{payload.repository.name}}",
        deliver: true,
        channel: "telegram",
        to: "YOUR_CHAT_ID",
      },
    },
    transformsDir: "~/.openclaw/hooks/transforms",  // custom JS/TS transforms
  },
}
```

---

## Ví dụ Thực Tế

### GitHub webhook → Telegram

```json5
{
  hooks: {
    enabled: true,
    token: "HOOKS_SECRET",
    mappings: {
      github: {
        action: "agent",
        message: "GitHub event: summarize and notify if urgent",
        deliver: true,
        channel: "telegram",
        to: "123456789",
      }
    }
  }
}
```

```bash
# GitHub → Settings → Webhooks → Add webhook
# Payload URL: https://your-gateway/hooks/github
# Secret: HOOKS_SECRET
# Content type: application/json
```

### Gmail watch (built-in)

```bash
openclaw webhooks gmail setup
openclaw webhooks gmail run
```

---

## Security

```json5
{
  hooks: {
    token: "${OPENCLAW_HOOKS_TOKEN}",           // dùng env var, không hardcode
    allowedAgentIds: ["main"],                  // restrict agent routing
    allowRequestSessionKey: false,              // không cho caller set session key
    allowedSessionKeyPrefixes: ["hook:"],       // restrict session key prefixes
  }
}
```

- Repeated auth failures → rate-limited per client IP
- Keep webhooks behind loopback / Tailscale / trusted reverse proxy
- Dùng dedicated hook token, không reuse gateway auth token
