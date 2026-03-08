# Adding Skills to OpenClaw

## Locations & Precedence

Skills are loaded from 3 places (highest → lowest priority):

1. `<workspace>/skills/` — per-agent only
2. `~/.openclaw/skills/` — shared across all agents on the machine
3. Bundled skills — shipped with the install

If a skill name conflicts, workspace wins → managed/local → bundled.

## Method 1: Copy to Workspace

```bash
cp -r your-skill ~/.openclaw/workspace-main/skills/
```

OpenClaw auto-detects changes (skills watcher is on by default). No restart needed.

## Method 2: extraDirs in Config

Add a custom skill directory in `~/.openclaw/openclaw.json`:

```json5
{
  "skills": {
    "load": {
      "extraDirs": ["/path/to/your/skills"]
    }
  }
}
```

Useful to share a skills pack across multiple agents or point at a Git repo.

## Method 3: ClawHub (Public Registry)

```bash
clawhub install <skill-slug>   # installs into ./skills
clawhub update --all           # update all installed skills
clawhub sync --all             # sync local changes back
```

Browse skills at: https://clawhub.com

## Verify

```bash
openclaw skills list
openclaw skills list --eligible
openclaw skills info <name>
openclaw skills check
```

## Enable/Disable via Config

```json5
{
  "skills": {
    "entries": {
      "my-skill": { "enabled": true },
      "another-skill": { "enabled": false }
    }
  }
}
```

## Skill Format (SKILL.md)

Minimum required:

```markdown
---
name: my-skill
description: What this skill does and when to use it
---

# My Skill
Instructions here...
```

Optional frontmatter keys:
- `metadata` — single-line JSON for gating (requires bins, env, config)
- `user-invocable` — expose as slash command (default: true)
- `argument-hint` — hint shown in the slash command UI

## Security Notes

- Treat third-party skills as untrusted code — read before enabling
- `skills.entries.*.env` injects into the host process (not sandbox)
- Keep secrets out of prompts and logs
