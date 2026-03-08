# Slash Commands & Directives

## Commands (standalone /... messages)

Gửi như một message riêng biệt bắt đầu bằng `/`:

| Command | Mô tả |
|---------|-------|
| `/help` | Hiển thị help |
| `/commands` | List tất cả commands |
| `/status` | Status hiện tại: model, token usage, compactions |
| `/whoami` (hoặc `/id`) | Hiển thị sender id của bạn |
| `/new [model]` | Bắt đầu session mới (optionally switch model) |
| `/reset` | Reset session |
| `/compact [instructions]` | Compact context (tóm tắt history cũ) |
| `/stop` | Abort run hiện tại, clear queue |
| `/context [list\|detail\|json]` | Xem system prompt, workspace files, context size |
| `/skill <name> [input]` | Run skill theo tên |
| `/allowlist` | List/add/remove allowlist entries |
| `/approve <id> allow-once\|allow-always\|deny` | Resolve exec approval prompts |
| `/export-session [path]` | Export session ra HTML |
| `/send on\|off\|inherit` | Toggle reply delivery cho session hiện tại |
| `/session idle <duration\|off>` | Set inactivity auto-unfocus |

---

## Directives (inline hints)

Directives bị strip khỏi message trước khi model thấy.

**Standalone directive** (chỉ directive trong message) → persist session setting:
```
/think high
/verbose on
/model claude-opus-4-6
```

**Inline directive** (kết hợp với text) → one-time hint, không persist:
```
/think high Viết cho tôi một thuật toán sắp xếp tối ưu
```

### Danh sách Directives

| Directive | Options | Mô tả |
|-----------|---------|-------|
| `/think <level>` | `off`, `low`, `medium`, `high` | Thinking level cho reasoning models |
| `/verbose <on\|off>` | `on`, `off` | Verbose output mode |
| `/reasoning <on\|off>` | `on`, `off` | Show reasoning (nếu model hỗ trợ) |
| `/elevated <on\|off>` | `on`, `off` | Enable elevated exec mode cho session |
| `/exec <policy>` | `deny`, `allowlist`, `full` | Override exec security policy |
| `/model <model>` | model name/alias | Switch model cho session |
| `/queue <mode>` | `collect`, `steer`, `followup` | Set queue mode |

---

## Bash Command (`!`)

Nếu được enable: chạy host shell command (không qua agent):

```
! ls -la
! git status
/bash git log --oneline -10
```

> Yêu cầu `commands.bash: true` và `tools.elevated` allowlist.

---

## Config

```json5
{
  commands: {
    text: true,             // parse /... trong chat (default: true)
    native: "auto",         // register native commands trên Telegram/Discord
    nativeSkills: "auto",   // register skill commands natively
    bash: false,            // enable ! <cmd> (default: false)
    bashForegroundMs: 2000, // wait before backgrounding bash
    config: false,          // enable /config command
    debug: false,           // enable /debug command
    restart: false,         // enable /restart command
    allowFrom: {
      "*": ["YOUR_USER_ID"],          // global: chỉ bạn có thể dùng commands
      "discord": ["user:123456789"],  // override per channel
    },
    useAccessGroups: true,   // dùng channel allowlists cho command auth
  },
}
```

---

## Native Commands (Telegram & Discord)

Telegram/Discord hiển thị commands trong dropdown:

```bash
openclaw commands list               # list registered commands
openclaw commands sync               # sync với Telegram/Discord
openclaw commands sync --channel telegram
```

Để disable native commands:
```json5
{
  channels: {
    telegram: {
      commands: { native: false }
    }
  }
}
```

---

## Skill Commands

Mỗi skill có thể được gọi như slash command:
```
/skill weather Hà Nội
/skill x-tech-news
/skill openclaw-builder acp
```

Native skill commands trên Telegram:
```
/weather Hà Nội      ← nếu nativeSkills: true
```
