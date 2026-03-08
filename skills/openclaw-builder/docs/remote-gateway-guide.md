# Remote Gateway & Tailscale

## Các cách expose Gateway

| Cách | Use case | Security |
|------|----------|---------|
| `bind: "loopback"` (default) | Local only | ✅ Safest |
| `bind: "lan"` | Local network | ⚠️ Cần auth |
| Tailscale Serve | Tailnet devices | ✅ HTTPS + Tailnet-only |
| Tailscale Funnel | Public internet | ⚠️ Cần password |
| Reverse proxy (nginx/caddy) | VPS hosting | ⚠️ Cần HTTPS + auth |

---

## Tailscale

### Tailnet-only (Serve) — Khuyến nghị

```json5
{
  gateway: {
    bind: "loopback",
    tailscale: { mode: "serve" },
    auth: {
      mode: "token",
      token: "your-gateway-token",
      allowTailscale: true,   // trust Tailscale identity headers
    },
  },
}
```

Truy cập: `https://<machine>.tailnet-name.ts.net/`

### Public Internet (Funnel)

```json5
{
  gateway: {
    bind: "loopback",
    tailscale: {
      mode: "funnel",
      // Cần shared password khi public
    },
    auth: {
      mode: "password",
      password: "strong-shared-password",
    },
  },
}
```

### Bind trực tiếp Tailnet IP (không Serve)

```json5
{
  gateway: {
    bind: "tailnet",
    auth: { mode: "token", token: "your-token" },
  },
}
```

Truy cập từ device khác trong Tailnet: `http://<tailscale-ip>:18789/`

---

## Remote Gateway Setup (truy cập từ nơi khác)

Khi Gateway chạy trên server/VPS, CLI local có thể connect:

```bash
# Set remote gateway
openclaw config set gateway.remote.url "wss://your-gateway-host:18789"
openclaw config set gateway.remote.token "your-gateway-token"

# Verify
openclaw status
openclaw gateway status --remote
```

Hoặc dùng env vars:
```bash
export OPENCLAW_GATEWAY_URL="wss://your-gateway-host:18789"
export OPENCLAW_GATEWAY_TOKEN="your-token"
```

---

## Docker on VPS

```bash
# Clone và setup
git clone https://github.com/openclaw/openclaw
cd openclaw
./docker-setup.sh

# Với environment vars
OPENCLAW_IMAGE=ghcr.io/openclaw/openclaw:latest \
OPENCLAW_SANDBOX=1 \
./docker-setup.sh
```

**docker-compose.yml tối thiểu:**
```yaml
services:
  openclaw:
    image: ghcr.io/openclaw/openclaw:latest
    volumes:
      - ~/.openclaw:/home/node/.openclaw
    ports:
      - "127.0.0.1:18789:18789"   # loopback only
    environment:
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
    restart: unless-stopped
```

---

## VPS Providers

Deploy guide có sẵn cho:
- DigitalOcean
- Hetzner
- Fly.io
- Render
- Railway
- Northflank
- Oracle Cloud (free tier)
- GCP
- Ansible (infra as code)

```bash
# Fetch specific VPS guide
python3 skills/skills/openclaw-builder/scripts/fetch-docs.py install/docker
python3 skills/skills/openclaw-builder/scripts/fetch-docs.py install/digitalocean
python3 skills/skills/openclaw-builder/scripts/fetch-docs.py install/hetzner
```

---

## Nginx Reverse Proxy (VPS)

```nginx
server {
    listen 443 ssl;
    server_name gateway.yourdomain.com;

    ssl_certificate     /etc/ssl/certs/gateway.crt;
    ssl_certificate_key /etc/ssl/private/gateway.key;

    location / {
        proxy_pass http://127.0.0.1:18789;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 86400;
    }
}
```

---

## Nodes (Remote Devices)

Nodes là companion app / headless agents kết nối vào Gateway:

```bash
openclaw nodes list                  # list connected nodes
openclaw devices list                # list paired devices
openclaw devices approve <requestId> # approve node pairing
```

Pair node qua Telegram:
```
/pair             ← gửi trong Telegram, bot reply setup code
# → Paste code vào iOS app → Settings → Gateway
/pair approve     ← approve trong Telegram
```

Node capabilities: camera, screen, location, notifications, exec on device.
