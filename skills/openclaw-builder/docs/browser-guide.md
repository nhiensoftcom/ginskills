# Browser Control

## Overview

OpenClaw chạy một **Chrome/Brave/Edge profile riêng biệt** cho agent — hoàn toàn tách khỏi browser cá nhân của bạn.

**2 profiles:**
- `openclaw` — managed, isolated browser (không cần extension)
- `chrome` — dùng Chrome của bạn qua extension relay (cần attach tab)

---

## Quick Start

```bash
openclaw browser status
openclaw browser start
openclaw browser open https://example.com
openclaw browser snapshot
```

---

## Config

```json5
// ~/.openclaw/openclaw.json
{
  browser: {
    enabled: true,
    defaultProfile: "openclaw",    // "openclaw" hoặc "chrome"
    headless: false,
    executablePath: "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",  // optional override
    color: "#FF4500",              // tint màu để phân biệt profiles
    profiles: {
      openclaw: { cdpPort: 18800, color: "#FF4500" },
      work:     { cdpPort: 18801, color: "#0066CC" },
      remote:   { cdpUrl: "http://10.0.0.42:9222", color: "#00AA00" },
    },
    ssrfPolicy: {
      dangerouslyAllowPrivateNetwork: true,  // default: allow private IPs
    },
  },
}
```

---

## CLI Commands

```bash
# Basics
openclaw browser status
openclaw browser start
openclaw browser stop
openclaw browser tabs
openclaw browser open https://example.com
openclaw browser close <targetId>

# Inspect
openclaw browser screenshot
openclaw browser screenshot --full-page
openclaw browser snapshot                    # AI snapshot (numeric refs)
openclaw browser snapshot --interactive      # Role snapshot (e12 refs)
openclaw browser snapshot --efficient        # compact mode
openclaw browser pdf
openclaw browser console --level error

# Navigate & act
openclaw browser navigate https://example.com
openclaw browser click 12                    # click by ref
openclaw browser click e12                   # click by role ref
openclaw browser type 23 "hello" --submit
openclaw browser press Enter
openclaw browser hover 44
openclaw browser select 9 OptionA OptionB
openclaw browser fill --fields '[{"ref":"1","type":"text","value":"Ada"}]'
openclaw browser wait --text "Done"
openclaw browser wait "#main" --url "**/dash" --load networkidle

# State & cookies
openclaw browser cookies
openclaw browser cookies set session abc123 --url "https://example.com"
openclaw browser cookies clear
openclaw browser storage local get
openclaw browser storage local set theme dark
openclaw browser set offline on
openclaw browser set device "iPhone 14"
openclaw browser set timezone Asia/Ho_Chi_Minh
openclaw browser set locale vi-VN

# Debug
openclaw browser errors --clear
openclaw browser requests --filter api --clear
openclaw browser highlight e12
openclaw browser trace start
openclaw browser trace stop
```

---

## Snapshot & Refs

**AI snapshot (default):**
```bash
openclaw browser snapshot           # returns numeric refs: 12, 23, 44
openclaw browser click 12
openclaw browser type 23 "hello"
```

**Role snapshot (interactive):**
```bash
openclaw browser snapshot --interactive    # returns role refs: e12
openclaw browser click e12
openclaw browser snapshot --labels         # + screenshot với ref labels
```

> Refs không stable sau navigation — re-run snapshot sau mỗi page load.

---

## Chrome Extension Relay (dùng Chrome cá nhân)

Cho phép agent control tab Chrome hiện tại của bạn:

```bash
# Install extension
openclaw browser extension install
# → Chrome → Extensions → Developer mode → Load unpacked → chọn path in output

# Click extension icon trên tab muốn control (badge ON)
# Sau đó dùng profile "chrome"
```

---

## Remote CDP (Browser ở máy khác)

```json5
{
  browser: {
    profiles: {
      remote: {
        cdpUrl: "http://10.0.0.42:9222",
        color: "#00AA00",
      }
    }
  }
}
```

---

## Browserless (hosted)

```json5
{
  browser: {
    enabled: true,
    defaultProfile: "browserless",
    profiles: {
      browserless: {
        cdpUrl: "https://production-sfo.browserless.io?token=YOUR_API_KEY",
        color: "#00AA00",
      }
    }
  }
}
```

---

## Sandboxed Browser

Khi agent chạy trong sandbox, browser mặc định dùng sandbox container:

```json5
{
  agents: {
    defaults: {
      sandbox: {
        mode: "all",
        browser: {
          autoStart: true,
          allowHostControl: false,       // true = cho phép dùng host browser từ sandbox
          network: "openclaw-sandbox-browser",
        }
      }
    }
  }
}
```

---

## Debug Workflow

Khi action fail ("not visible", "covered"):

```bash
1. openclaw browser snapshot --interactive
2. openclaw browser highlight e12          # visualize target
3. openclaw browser errors --clear
4. openclaw browser requests --filter api  # check API calls
5. openclaw browser trace start
   # reproduce issue
   openclaw browser trace stop            # → TRACE:/tmp/openclaw/...
```

---

## Security

- Browser control chỉ bind loopback — không expose public
- `browser act kind=evaluate` chạy arbitrary JS — disable với `browser.evaluateEnabled=false` nếu không cần
- Treat browser profile như sensitive data (có thể chứa logged-in sessions)
- Remote CDP endpoints → tunnel qua Tailscale, không expose public
