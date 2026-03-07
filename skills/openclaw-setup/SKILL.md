---
name: openclaw-setup
description: |
  Guide for setting up, configuring, and using OpenClaw — an AI gateway for connecting LLM agents to messaging channels (Telegram, Discord, WhatsApp, Signal, etc.), automation (cron, webhooks, heartbeat), browser control, skills, and multi-agent workflows.
  - MANDATORY TRIGGERS: setup openclaw, configure openclaw, install openclaw, openclaw telegram, openclaw discord, openclaw channel, openclaw gateway, openclaw cron, openclaw webhook, openclaw heartbeat, openclaw skills, openclaw agent, openclaw browser, openclaw memory, openclaw session, how to use openclaw, openclaw config
  - Use this skill when the user wants to: install/setup OpenClaw, connect a messaging channel, configure the gateway, set up automation (cron/webhook/heartbeat), work with skills/agents, or troubleshoot OpenClaw issues.
argument-hint: "[channel-name | topic: getting-started | channels | automation | gateway | skills | agents | browser | memory | cli]"
---

# OpenClaw Setup

Fetch live OpenClaw documentation and guide the user through setup and configuration.

## Fetch Docs

Always fetch fresh docs — do NOT rely on training knowledge for specific configs:

```bash
python3 skills/skills/openclaw-setup/scripts/fetch-docs.py <page-path>
```

### Key pages by topic

| Topic | Page path |
|-------|-----------|
| Getting started | `start/getting-started` |
| All docs index | `index` |
| Gateway config | `gateway/configuration` |
| Gateway config reference | `gateway/configuration-reference` |
| Telegram | `channels/telegram` |
| Discord | `channels/discord` |
| WhatsApp | `channels/whatsapp` |
| Signal | `channels/signal` |
| Slack | `channels/slack` |
| Cron jobs | `automation/cron-jobs` |
| Webhooks | `automation/webhook` |
| Heartbeat | `gateway/heartbeat` |
| Hooks | `automation/hooks` |
| Skills CLI | `cli/skills` |
| Agent runtime | `concepts/agent` |
| Memory | `concepts/memory` |
| Browser tool | `cli/browser` |
| Session management | `concepts/session` |
| Multi-agent | `concepts/multi-agent` |
| Channels index | `channels/index` |

For unknown topics: fetch `index` first to discover the right page, then fetch that page.

## Workflow

1. Identify what the user wants to set up or fix
2. Fetch the relevant doc page(s) using the script
3. Guide step-by-step based on fetched content
4. If config examples needed → fetch `gateway/configuration-examples`
5. Test: suggest `openclaw gateway status` or `openclaw doctor` to verify

## Common Patterns

**New install:**
```bash
python3 skills/skills/openclaw-setup/scripts/fetch-docs.py start/getting-started
```

**Channel setup (e.g. Telegram):**
```bash
python3 skills/skills/openclaw-setup/scripts/fetch-docs.py channels/telegram
```

**Troubleshoot:**
```bash
python3 skills/skills/openclaw-setup/scripts/fetch-docs.py channels/troubleshooting
python3 skills/skills/openclaw-setup/scripts/fetch-docs.py gateway/doctor
```
