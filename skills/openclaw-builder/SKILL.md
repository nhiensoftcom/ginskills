---
name: openclaw-builder
description: |
  Guide for setting up, configuring, and extending OpenClaw — an AI gateway for connecting LLM agents to messaging channels (Telegram, Discord, WhatsApp, Signal, etc.), automation (cron, webhooks, heartbeat), browser control, skills, and multi-agent workflows.
  - MANDATORY TRIGGERS: setup openclaw, configure openclaw, install openclaw, openclaw telegram, openclaw discord, openclaw channel, openclaw gateway, openclaw cron, openclaw webhook, openclaw heartbeat, openclaw skills, openclaw agent, openclaw browser, openclaw memory, openclaw session, how to use openclaw, openclaw config, add skill to openclaw, install skill openclaw, openclaw mcp, openclaw acp, openclaw plugin, extend openclaw, openclaw builder, multi-agent openclaw, openclaw model, openclaw api key, openclaw anthropic, openclaw openai, dm scope, session isolation
  - Use this skill when the user wants to: install/setup OpenClaw, connect a messaging channel, configure the gateway, set up automation, add skills or agents, work with ACP/plugins, set up multi-agent routing, or troubleshoot OpenClaw issues.
argument-hint: "[topic: getting-started | channels | automation | gateway | skills | acp | multi-agent | browser | memory | cli | plugins]"
---

# OpenClaw Builder

Fetch live docs or load local guides based on what the user needs.

## Tutorial Routing

Run this to load the relevant guide:

```bash
cat skills/skills/openclaw-builder/docs/$TOPIC
```

Or fetch live docs from openclaw.ai:

```bash
python3 skills/skills/openclaw-builder/scripts/fetch-docs.py <page-path>
```

---

## Local Guides (bundled)

| Topic | File | When to use |
|-------|------|-------------|
| Adding skills | `docs/skills-guide.md` | User wants to install/add/enable a skill |
| ACP setup | `docs/acp-guide.md` | User wants to connect an IDE or use ACP protocol |
| Multi-agent | `docs/multi-agent-guide.md` | User wants multiple agents, routing, or personas |
| Automation (cron/heartbeat) | `docs/automation-guide.md` | User wants scheduled tasks, reminders, or heartbeat |
| Hooks | `docs/hooks-guide.md` | User wants event-driven automation, custom hooks |
| Plugins | `docs/plugins-guide.md` | User wants to install/create plugins, add channels |
| Workspace & Memory | `docs/workspace-memory-guide.md` | User asks about memory, workspace files, MEMORY.md |
| Gateway config | `docs/config-guide.md` | User wants to configure openclaw.json, channels, tools |
| Channels setup | `docs/channels-guide.md` | User wants to setup Telegram, Discord, WhatsApp, Signal |
| Models & Auth | `docs/models-auth-guide.md` | User wants to set API keys, model providers, DM scope |
| Browser control | `docs/browser-guide.md` | User wants to use/configure browser automation |
| Webhooks | `docs/webhooks-guide.md` | User wants external HTTP triggers, GitHub/Gmail webhooks |
| Sandboxing | `docs/sandboxing-guide.md` | User wants Docker isolation for agent tools |

**Load a local guide:**
```bash
cat skills/skills/openclaw-builder/docs/skills-guide.md
cat skills/skills/openclaw-builder/docs/acp-guide.md
cat skills/skills/openclaw-builder/docs/multi-agent-guide.md
cat skills/skills/openclaw-builder/docs/automation-guide.md
cat skills/skills/openclaw-builder/docs/hooks-guide.md
cat skills/skills/openclaw-builder/docs/plugins-guide.md
cat skills/skills/openclaw-builder/docs/workspace-memory-guide.md
cat skills/skills/openclaw-builder/docs/config-guide.md
cat skills/skills/openclaw-builder/docs/channels-guide.md
cat skills/skills/openclaw-builder/docs/models-auth-guide.md
cat skills/skills/openclaw-builder/docs/browser-guide.md
cat skills/skills/openclaw-builder/docs/webhooks-guide.md
cat skills/skills/openclaw-builder/docs/sandboxing-guide.md
```

---

## Live Docs Pages (fetch-docs.py)

For anything not covered by local guides, fetch fresh from docs.openclaw.ai:

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
| Skills system | `tools/skills` |
| Skills config | `tools/skills-config` |
| ClawHub | `tools/clawhub` |
| Plugins | `tools/plugin` |
| ACP CLI | `cli/acp` |
| Agent runtime | `concepts/agent` |
| Memory | `concepts/memory` |
| Browser tool | `cli/browser` |
| Session management | `concepts/session` |
| Channels index | `channels/index` |

For unknown topics: fetch `index` first to discover the right page.

---

## Workflow

1. Identify what the user wants (setup / extend / troubleshoot)
2. Check local guides first — faster than fetching
3. If not covered → fetch live docs with `fetch-docs.py`
4. Guide step-by-step based on content
5. Verify: `openclaw gateway status` or `openclaw doctor`
