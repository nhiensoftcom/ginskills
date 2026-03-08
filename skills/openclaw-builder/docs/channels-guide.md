# Channel Setup Guides

## Telegram

**Status:** Production-ready — bot DMs + groups via grammY.

### Setup (3 bước)

**1. Tạo bot token qua BotFather**
- Mở Telegram, chat với `@BotFather`
- Gửi `/newbot`, làm theo hướng dẫn, lưu token

**2. Cấu hình trong `openclaw.json`**
```json5
{
  channels: {
    telegram: {
      enabled: true,
      botToken: "123:abc",           // hoặc env TELEGRAM_BOT_TOKEN
      dmPolicy: "pairing",           // pairing | allowlist | open
      groups: {
        "*": { requireMention: true } // require @bot mention in groups
      },
    },
  },
}
```

**3. Start gateway + approve DM đầu tiên**
```bash
openclaw gateway
openclaw pairing list telegram
openclaw pairing approve telegram <CODE>   # code hết hạn sau 1h
```

### DM Policies
- `pairing` — user gửi code, bạn approve (default, khuyến nghị)
- `allowlist` — chỉ allow từ danh sách chat_id/username
- `open` — ai cũng chat được (cẩn thận!)

---

## Discord

**Status:** Ready — DMs + guild channels.

### Setup

**1. Tạo Discord Application + Bot**
- Vào [Discord Developer Portal](https://discord.com/developers/applications)
- New Application → Bot → copy Bot Token
- Enable **Message Content Intent** (bắt buộc)
- Enable **Server Members Intent** (khuyến nghị)

**2. Invite bot vào server**
- OAuth2 → URL Generator → chọn `bot` + `applications.commands`
- Permissions: `Send Messages`, `Read Message History`, `Read Messages/View Channels`
- Mở URL, chọn server

**3. Cấu hình**
```json5
{
  channels: {
    discord: {
      botToken: "YOUR_BOT_TOKEN",
      guildIds: ["YOUR_SERVER_ID"],  // optional: restrict to specific servers
      dmPolicy: "pairing",
      groups: {
        "*": { requireMention: true }
      },
    },
  },
}
```

**4. Start gateway**
```bash
openclaw gateway
openclaw pairing list discord
openclaw pairing approve discord <CODE>
```

---

## WhatsApp

**Status:** Production-ready via WhatsApp Web (Baileys).

### Setup

**1. Cấu hình policy**
```json5
{
  channels: {
    whatsapp: {
      dmPolicy: "pairing",
      allowFrom: ["+84901234567"],
    },
  },
}
```

**2. Link WhatsApp (QR code)**
```bash
openclaw channels login --channel whatsapp

# Multi-account
openclaw channels login --channel whatsapp --account work
```

**3. Start gateway**
```bash
openclaw gateway
```

---

## Multi-account (Telegram)

```json5
{
  channels: {
    telegram: {
      accounts: {
        default: { botToken: "MAIN_BOT_TOKEN" },
        "coding-bot": { botToken: "SECOND_BOT_TOKEN" },
      },
    },
  },
}
```

---

## Signal

```bash
openclaw channels login --channel signal
# Scan QR / link device như Signal Desktop
```

---

## Troubleshooting

```bash
openclaw channels status --probe   # check all channels
openclaw doctor                    # diagnose issues
openclaw pairing list              # see pending pairings
```
