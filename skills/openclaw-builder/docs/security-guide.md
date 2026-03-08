# Security Hardening Guide

> ⚠️ **Personal assistant trust model**: OpenClaw không phải hostile multi-tenant security boundary. Designed cho 1 trusted operator boundary per gateway (single-user). Nếu cần multi-user isolation → dùng separate gateways + separate OS users.

---

## Quick Audit

```bash
openclaw security audit          # basic check
openclaw security audit --deep   # + live gateway probe
openclaw security audit --fix    # auto-repair khi có thể
openclaw security audit --json   # machine-readable
```

---

## Hardened Baseline (60 giây)

```json5
// ~/.openclaw/openclaw.json
{
  gateway: {
    mode: "local",
    bind: "loopback",           // chỉ local, không expose network
    auth: { mode: "token", token: "replace-with-long-random-token" },
  },
  session: {
    dmScope: "per-channel-peer",  // isolate DMs per user
  },
  tools: {
    profile: "messaging",          // minimal tool set
    deny: ["group:automation", "group:runtime", "group:fs", "sessions_spawn", "sessions_send"],
    fs: { workspaceOnly: true },
    exec: { security: "deny", ask: "always" },
    elevated: { enabled: false },
  },
  channels: {
    whatsapp: { dmPolicy: "pairing", groups: { "*": { requireMention: true } } },
    telegram: { dmPolicy: "pairing", groups: { "*": { requireMention: true } } },
  },
}
```

---

## Checklist Bảo Mật

### 01. Inbound Access — Ai có thể nhắn tin bot?

```json5
{
  channels: {
    telegram: {
      dmPolicy: "pairing",         // chỉ approve thủ công
      // dmPolicy: "allowlist",    // whitelist cụ thể
      allowFrom: ["YOUR_CHAT_ID"], // chỉ bạn
      groups: {
        "*": { requireMention: true }, // phải @mention trong group
      },
    },
  },
}
```

**DM Policy options:**
- `pairing` — user cần code approve (default, khuyến nghị)
- `allowlist` — chỉ chat_id trong `allowFrom`
- `open` — ai cũng được (nguy hiểm!)

### 02. Session Isolation — Shared inbox?

Nếu nhiều người DM cùng bot:
```json5
{
  session: {
    dmScope: "per-channel-peer",  // isolate per user
    // "per-account-channel-peer" — multi-account
  },
}
```

### 03. Tool Blast Radius — Bot có thể làm gì?

```json5
{
  tools: {
    profile: "messaging",    // chỉ messaging tools
    // profile: "minimal",  // gần như không có tools
    deny: ["exec", "write", "edit", "apply_patch", "browser"],
    elevated: { enabled: false },  // không exec trên host
    exec: {
      security: "deny",    // không exec mặc định
      ask: "always",       // luôn hỏi approve
    },
  },
}
```

### 04. Network Exposure — Gateway bind ở đâu?

```json5
{
  gateway: {
    bind: "loopback",   // chỉ 127.0.0.1 (safest)
    // bind: "lan",     // local network
    // bind: "all",     // 0.0.0.0 (nguy hiểm nếu không có auth)
    auth: {
      mode: "token",
      token: "long-random-secret-token",  // ít nhất 32 chars
    },
  },
}
```

**Public access → dùng Tailscale:**
```json5
{
  gateway: {
    bind: "loopback",
    tailscale: { mode: "serve" },  // tailnet-only, HTTPS
    // tailscale: { mode: "funnel" }, // public internet
  },
}
```

### 05. Elevated Mode — Exec trên host?

```json5
{
  tools: {
    elevated: {
      enabled: true,
      allowlist: ["ls", "git status", "npm run build"],  // chỉ specific commands
      // KHÔNG để "*" trong production
    },
  },
}
```

### 06. Browser Control

```json5
{
  browser: {
    enabled: false,           // disable nếu không cần
    // hoặc restrict:
    ssrfPolicy: {
      dangerouslyAllowPrivateNetwork: false,
      hostnameAllowlist: ["*.yourdomain.com"],
    },
    // evaluateEnabled: false,  // block arbitrary JS eval
  },
}
```

---

## Shared Multi-User Setup (Khuyến Nghị)

Nếu team chia sẻ 1 agent:

```
✅ Dùng: Separate gateway per trust boundary
✅ Dùng: Dedicated OS user + dedicated machine/VM
✅ Dùng: Business-scoped agent (không mix personal data)
✅ Dùng: per-channel-peer dmScope
❌ Tránh: Shared agent có personal credentials/files
❌ Tránh: Open DM policy với broad tool access
❌ Tránh: Mix personal + company identities trên cùng runtime
```

---

## Credential Map (Backup/Audit)

| Credential | Vị trí |
|-----------|--------|
| WhatsApp session | `~/.openclaw/credentials/whatsapp/<accountId>/creds.json` |
| DM allowlists | `~/.openclaw/credentials/<channel>-allowFrom.json` |
| API keys | config/env hoặc SecretRef |
| Exec approvals | `~/.openclaw/exec-approvals.json` |
| Paired nodes | `~/.openclaw/devices/paired.json` |

---

## Audit Checks (những gì bị kiểm tra)

- **Inbound access**: DM policies, group policies, allowlists
- **Tool blast radius**: elevated tools, open rooms, exec policy
- **Network exposure**: Gateway bind/auth, Tailscale, weak tokens
- **Browser control**: remote nodes, relay ports, remote CDP
- **Local disk**: permissions, symlinks, "synced folder" paths
- **Plugins**: extensions không có allowlist
- **Policy drift**: sandbox off nhưng docker config tồn tại, exec.host="sandbox" với sandbox mode off

---

## Secrets Management

Không hardcode credentials trong `openclaw.json`:

```json5
// env var reference (khuyến nghị)
{
  channels: {
    telegram: {
      botToken: { source: "env", provider: "default", id: "TELEGRAM_BOT_TOKEN" },
    },
  },
}

// file reference
{
  secrets: {
    providers: {
      filemain: { source: "file", path: "~/.openclaw/secrets.json", mode: "json" },
    },
  },
  channels: {
    telegram: {
      botToken: { source: "file", provider: "filemain", id: "/telegram/botToken" },
    },
  },
}
```

```bash
# Audit secrets
openclaw secrets audit --check
openclaw secrets configure
```
