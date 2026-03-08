# Sandboxing — Docker Isolation

## Overview

OpenClaw có thể chạy tools bên trong **Docker containers** để giảm rủi ro khi agent làm điều gì đó sai.

- Gateway vẫn chạy trên host
- Tool execution (exec/read/write/edit...) chạy trong sandbox container
- Không phải security boundary hoàn hảo, nhưng giới hạn filesystem và process access

---

## Setup (1 lần)

```bash
# Build sandbox image (cơ bản)
scripts/sandbox-setup.sh

# Build image đầy đủ hơn (curl, jq, nodejs, python3, git)
scripts/sandbox-common-setup.sh

# Build sandbox browser image (nếu cần browser trong sandbox)
scripts/sandbox-browser-setup.sh
```

---

## Config

```json5
{
  agents: {
    defaults: {
      sandbox: {
        mode: "non-main",          // "off" | "non-main" | "all"
        scope: "session",          // "session" | "agent" | "shared"
        workspaceAccess: "none",   // "none" | "ro" | "rw"
        docker: {
          network: "none",         // default: no internet
          image: "openclaw-sandbox:bookworm-slim",
          setupCommand: "apt-get update && apt-get install -y curl",  // runs once
          binds: [
            "/home/user/source:/source:ro",
            "/var/data:/data:ro",
          ],
        },
      },
    },
  },
}
```

---

## Modes (khi nào sandbox chạy)

| Mode | Mô tả |
|------|-------|
| `off` | Không sandbox — tools chạy trên host |
| `non-main` | Sandbox non-main sessions (groups, cron, webhooks); main session trên host |
| `all` | Tất cả sessions đều sandbox |

> `non-main` dựa trên `session.mainKey` (default "main"), không phải agent id.
> Group/channel sessions được coi là non-main → bị sandbox.

---

## Scope (bao nhiêu containers)

| Scope | Mô tả |
|-------|-------|
| `session` | 1 container per session (default) |
| `agent` | 1 container per agent — share giữa sessions của cùng agent |
| `shared` | 1 container shared tất cả sandboxed sessions |

---

## Workspace Access (sandbox thấy gì)

| workspaceAccess | Mô tả |
|-----------------|-------|
| `none` | Sandbox workspace riêng ở `~/.openclaw/sandboxes` |
| `ro` | Mount agent workspace read-only tại `/agent` |
| `rw` | Mount agent workspace read/write tại `/workspace` |

---

## Per-Agent Override

Mỗi agent có thể có sandbox config riêng:

```json5
{
  agents: {
    defaults: {
      sandbox: { mode: "off" },   // default: no sandbox
    },
    list: [
      {
        id: "main",
        sandbox: { mode: "off" },      // main agent: no sandbox
      },
      {
        id: "family",
        sandbox: {
          mode: "all",
          scope: "agent",
          workspaceAccess: "ro",
          docker: {
            setupCommand: "apt-get update && apt-get install -y python3",
            binds: ["/home/user/photos:/photos:ro"],
          },
        },
        tools: {
          allow: ["read", "exec"],
          deny: ["write", "edit", "apply_patch", "browser"],
        },
      },
    ],
  },
}
```

---

## Custom Bind Mounts

```json5
{
  agents: {
    defaults: {
      sandbox: {
        docker: {
          binds: [
            "/home/user/source:/source:ro",
            "/var/data/myapp:/data:ro",
          ],
        },
      },
    },
  },
}
```

> ⚠️ OpenClaw block mount nguy hiểm: `docker.sock`, `/etc`, `/proc`, `/sys`, `/dev`

---

## Tool Policy + Sandbox

Tool allow/deny policy áp dụng **trước** sandbox rules:

```json5
{
  agents: {
    list: [{
      id: "restricted",
      tools: {
        allow: ["read"],
        deny: ["exec", "write", "edit", "apply_patch", "browser"],
      }
    }]
  }
}
```

`tools.elevated` = escape hatch chạy exec trên **host** (bypass sandbox).

---

## setupCommand Caveats

```
✅ setupCommand chạy 1 lần sau khi container được tạo
❌ Default network = "none" → package install sẽ fail nếu không có network
❌ readOnlyRoot = true → không write được
❌ Cần root user để install packages (omit "user" field)
```

Nếu cần packages → bake vào custom image thay vì dùng setupCommand.

---

## Debug

```bash
openclaw sandbox explain    # xem effective sandbox mode, tool policy, cách fix
openclaw doctor             # diagnose issues
```

---

## Minimal Enable (recommended starting point)

```json5
{
  agents: {
    defaults: {
      sandbox: {
        mode: "non-main",
        scope: "session",
        workspaceAccess: "none",
      },
    },
  },
}
```
