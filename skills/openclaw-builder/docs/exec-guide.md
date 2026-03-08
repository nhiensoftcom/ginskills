# Exec Tool & Elevated Mode

## Exec Tool

Chạy shell commands trong workspace.

### Parameters

| Param | Default | Mô tả |
|-------|---------|-------|
| `command` | (required) | Shell command |
| `workdir` | cwd | Working directory |
| `env` | | Key/value env overrides |
| `yieldMs` | 10000 | Auto-background sau N ms |
| `background` | false | Background ngay lập tức |
| `timeout` | 1800s | Kill nếu quá thời gian |
| `pty` | false | Pseudo-terminal (cho TTY CLIs) |
| `host` | `sandbox` | `sandbox`, `gateway`, `node` |
| `security` | `deny` | `deny`, `allowlist`, `full` |
| `ask` | `on-miss` | `off`, `on-miss`, `always` |
| `elevated` | false | Elevated mode (gateway host) |

> ⚠️ `host` default là `sandbox`. Nếu sandbox off và `host=sandbox` → exec fail (không silently chạy trên host).

### Config

```json5
{
  tools: {
    exec: {
      host: "sandbox",          // default exec target
      security: "deny",         // deny | allowlist | full
      ask: "on-miss",           // approval prompts
      notifyOnExit: true,       // notify khi background job xong
      pathPrepend: ["~/bin"],   // prepend to PATH
      safeBins: ["cat", "grep", "jq"],  // stdin-only safe binaries (no approval needed)
    },
  },
}
```

### Exec Approvals

Khi `security=allowlist` hoặc `ask=on-miss`:

```bash
# List pending approvals
openclaw approvals list

# Approve via chat
/approve <id> allow-once
/approve <id> allow-always
/approve <id> deny

# Config file: ~/.openclaw/exec-approvals.json
```

---

## Elevated Mode

Cho phép exec chạy **trực tiếp trên host** (bypass sandbox). Cẩn thận!

### Enable

```json5
{
  tools: {
    elevated: {
      enabled: true,
      allowlist: [
        "ls",
        "git status",
        "npm run build",
        "brew update",
      ],
      // ask: "on-miss",   // prompt trước khi chạy
    },
  },
}
```

### Toggle từ Chat

```
/elevated on     ← enable cho session hiện tại (cần allowlist)
/elevated off    ← disable
```

### Bash Command (`!`)

Khi `commands.bash: true`, chạy host shell trực tiếp:
```
! ls -la
! git log --oneline -5
/bash npm run test
```

---

## Security Model

```
exec tool call
  ↓
Tool Policy (allow/deny list)
  ↓
Exec Policy (security: deny/allowlist/full)
  ↓
Approval Gate (ask: off/on-miss/always)
  ↓
↓ sandbox mode ON?
    YES → chạy trong Docker container
    NO  → chạy trên gateway host
          ↑ elevated=true? → cũng chạy trên host, bypass sandbox check
```

### Tool Profiles

```json5
{
  tools: {
    profile: "messaging",  // chỉ messaging tools — safest
    // profile: "minimal", // gần như không có tools
    // profile: "default", // standard tools (exec sandbox)
    // profile: "full",    // tất cả tools (nguy hiểm)
  },
}
```

### Per-Agent Tools

```json5
{
  agents: {
    list: [
      {
        id: "main",
        tools: {
          profile: "default",
          allow: ["read", "write", "exec"],
          deny: ["browser", "elevated"],
        },
      },
      {
        id: "readonly",
        tools: {
          deny: ["exec", "write", "edit", "apply_patch", "browser"],
        },
      },
    ],
  },
}
```

---

## Background Exec

```python
# Chạy lâu → background sau 10s
exec(command="npm run build", yieldMs=10000)

# Background ngay
exec(command="./long-script.sh", background=True)

# Theo dõi process
process(action="list")
process(action="poll", sessionId="abc", timeout=30000)
process(action="log", sessionId="abc", limit=100)
process(action="kill", sessionId="abc")
process(action="send-keys", sessionId="abc", keys=["Enter"])
```

---

## PTY Mode

Dùng cho CLIs cần TTY (coding agents, interactive tools):

```python
exec(command="claude code", pty=True)
exec(command="vim file.txt", pty=True)
```

---

## Node Exec (Remote Device)

```python
# Exec trên paired node (iPhone, Mac khác...)
exec(command="ls ~/Downloads", host="node", node="iphone")
exec(command="screencapture /tmp/shot.png", host="node")
```
