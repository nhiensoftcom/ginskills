# Automation — Cron Jobs & Heartbeat

## Cron vs Heartbeat — When to Use Each

| | Cron | Heartbeat |
|---|---|---|
| Timing | Exact schedule | Approximate interval |
| Context | Isolated session (no history) | Main session (has context) |
| Use case | Precise tasks, background chores | Proactive check-ins, inbox scans |
| Config | `openclaw cron add ...` | `agents.defaults.heartbeat` |

## Heartbeat

Runs periodic agent turns in the **main session** — agent checks for anything needing attention.

### Quick Config

```json5
// ~/.openclaw/openclaw.json
{
  agents: {
    defaults: {
      heartbeat: {
        every: "30m",           // interval (0m to disable)
        target: "last",         // deliver to last used channel (default: "none")
        lightContext: true,     // only inject HEARTBEAT.md (faster, cheaper)
        activeHours: { start: "08:00", end: "23:00" }, // optional time window
      }
    }
  }
}
```

### HEARTBEAT.md

Create in workspace root — agent reads this every heartbeat:

```markdown
# Heartbeat checklist

- Quick scan: anything urgent in inbox?
- Calendar events in next 2 hours?
- If nothing: reply HEARTBEAT_OK
```

**Rules:**
- Agent replies `HEARTBEAT_OK` if nothing to do (stripped, not delivered)
- Agent sends alert text if something needs attention
- Keep file small to avoid token bloat
- Empty file = heartbeat skipped (saves API calls)

### Manual Wake

```bash
openclaw system event --text "Check urgent follow-ups" --mode now
```

## Cron Jobs

Runs tasks on a schedule — isolated sessions, full agent turns.

### Quick Start

```bash
# One-shot reminder in 20 minutes
openclaw cron add \
  --name "Reminder" \
  --at "20m" \
  --session main \
  --system-event "Reminder: check expense reports" \
  --wake now \
  --delete-after-run

# Recurring daily job — deliver to Telegram
openclaw cron add \
  --name "Morning brief" \
  --cron "0 7 * * *" \
  --tz "Asia/Ho_Chi_Minh" \
  --session isolated \
  --message "Summarize overnight updates." \
  --announce \
  --channel telegram \
  --to "YOUR_CHAT_ID"

# List all jobs
openclaw cron list

# Run a job immediately
openclaw cron run <job-id>
```

### Schedule Types

| Type | Example | Description |
|------|---------|-------------|
| `--at "20m"` | In 20 minutes | One-shot relative |
| `--at "2026-03-08T09:00:00Z"` | Exact datetime | One-shot absolute |
| `--cron "0 7 * * *"` | Every day 7am | Cron expression |

### Session Targets

- `--session main` — runs during next heartbeat (use `--system-event`)
- `--session isolated` — dedicated isolated session (use `--message`)

### Delivery Options

```bash
--announce               # deliver to channel
--channel telegram       # which channel
--to "CHAT_ID"           # recipient

# Webhook instead
--delivery webhook --to "https://your-webhook.com"
```

### Management

```bash
openclaw cron list                    # list all jobs
openclaw cron run <id>                # run now
openclaw cron edit <id> --message "new prompt"
openclaw cron runs --id <id>          # view run history
openclaw cron remove <id>
```

### Config (openclaw.json)

```json5
{
  cron: {
    enabled: true,
    sessionRetention: "24h",  // keep isolated run sessions for 24h
  }
}
```
