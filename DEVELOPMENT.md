# GinStudio Skills — Development Guide

Everything you need to contribute skills, release new versions, and manage the CLI.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [How to Add a New Skill](#how-to-add-a-new-skill)
3. [How to Add a New Agent](#how-to-add-a-new-agent)
4. [How to Release (Publish to npm)](#how-to-release-publish-to-npm)
5. [CLI Reference](#cli-reference)
6. [How Users Install Skills](#how-users-install-skills)
7. [How to Upgrade Installed Skills](#how-to-upgrade-installed-skills)
8. [How to Uninstall](#how-to-uninstall)
9. [Local Development & Testing](#local-development--testing)
10. [Troubleshooting](#troubleshooting)

---

## Project Structure

```
ginstudio-skills/
├── bin/
│   └── cli.js              # npm CLI entrypoint (ginskill-init)
├── skills/
│   └── my-skill/           # One directory per skill
│       ├── SKILL.md        # Main skill file (required)
│       ├── docs/           # Supporting docs loaded at runtime
│       └── scripts/        # Shell scripts used by the skill
├── agents/
│   ├── my-agent.md         # Single-file agent (simple)
│   └── my-agent/           # Directory agent (with supporting files)
│       └── agent.md
├── package.json            # npm package config
├── .npmignore              # Files excluded from npm publish
├── .gitignore
├── README.md
└── DEVELOPMENT.md          # This file
```

---

## How to Add a New Skill

### 1. Create the skill directory

```bash
mkdir -p skills/my-skill/docs
mkdir -p skills/my-skill/scripts
```

### 2. Write `SKILL.md` (required)

Every skill needs a `SKILL.md` at `skills/my-skill/SKILL.md`.

**Minimal template:**

```markdown
---
name: my-skill
description: |
  Short description visible to Claude when deciding to load this skill.
  - MANDATORY TRIGGERS: keyword1, keyword2, keyword3
  - Use this skill when the user wants to: do X, Y, Z
argument-hint: "[optional | args | here]"
disable-model-invocation: false
---

# My Skill Title

You are an expert in [domain]. Help the user [goal].

## Step 1 — Do Something

...instructions...

## Step 2 — Do Something Else

...
```

**SKILL.md frontmatter fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Identifier, must match the directory name |
| `description` | yes | Shown to Claude; include `MANDATORY TRIGGERS` keywords |
| `argument-hint` | no | Shown in `/skill-name [hint]` |
| `disable-model-invocation` | no | Set `true` to block Claude from calling models inside the skill |
| `user-invocable` | no | Set `false` for domain-knowledge skills that auto-load but aren't called directly |

**Rules:**
- Keep `SKILL.md` under **500 lines**. Move excess content to `docs/`.
- Put reusable deep-dives in `docs/*.md` and load them via a script or inline reference.
- Scripts go in `scripts/` and are invoked with `` !`bash skills/my-skill/scripts/my-script.sh $ARGUMENTS` ``.

### 3. Load docs dynamically (optional)

Create `scripts/load-tutorial.sh` if your skill routes to different docs based on arguments:

```bash
#!/bin/bash
TOPIC="${1:-overview}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOCS_DIR="$SCRIPT_DIR/../docs"

case "$TOPIC" in
  intro)   cat "$DOCS_DIR/intro.md" ;;
  advanced) cat "$DOCS_DIR/advanced.md" ;;
  *)       cat "$DOCS_DIR/overview.md" ;;
esac
```

Then in `SKILL.md`:

```markdown
!`bash skills/my-skill/scripts/load-tutorial.sh $ARGUMENTS`
```

### 4. Register the skill's auto-triggers

The `description` field in the frontmatter is used by Claude to decide when to auto-load the skill. Include:

```yaml
description: |
  Brief one-liner.
  - MANDATORY TRIGGERS: the exact words or phrases that should trigger it
  - Use this skill when the user wants to: create X, build Y, fix Z
```

### 5. Test the skill locally

```bash
# Install from local repo to a test .claude directory
node bin/cli.js --skills my-skill -t /tmp/test-project

# Verify it's there
ls /tmp/test-project/.claude/skills/my-skill/

# In Claude Code, invoke directly
/my-skill
# Or let it auto-trigger by describing your goal
```

---

## How to Add a New Agent

Agents live in `agents/` and are copied to `.claude/agents/` during install.

### Simple agent (single `.md` file)

Create `agents/my-agent.md`:

```markdown
---
name: my-agent
description: Use this agent to do X. TRIGGER when user asks about Y.
tools: Read, Grep, Glob, Bash
model: claude-haiku-4-5-20251001
---

You are a specialized agent for [domain].

## Capabilities
...

## Instructions
...
```

### Directory agent (with supporting files)

Create `agents/my-agent/` directory with an `agent.md` (or any `.md`) and supporting scripts/configs.

### Agent frontmatter fields

| Field | Description |
|-------|-------------|
| `name` | Agent identifier |
| `description` | When to invoke; visible in `/agents` list |
| `tools` | Comma-separated tool allowlist (restricts what the agent can call) |
| `model` | Override the model (e.g., `claude-haiku-4-5-20251001` for speed) |

### Test the agent

```bash
node bin/cli.js --agents my-agent -t /tmp/test-project
# In Claude Code: "Use the my-agent agent to [task]"
# Or: /agents  to verify it appears
```

---

## How to Release (Publish to npm)

### Prerequisites

- npm account with access to the `ginskill-init` package
- `npm login` completed

### Step 1 — Bump the version

```bash
# patch: 1.0.0 → 1.0.1  (bug fixes, content updates)
npm version patch

# minor: 1.0.0 → 1.1.0  (new skills/agents added)
npm version minor

# major: 1.0.0 → 2.0.0  (breaking changes to CLI or skill format)
npm version major
```

This updates `package.json` and creates a git tag automatically.

### Step 2 — Preview what will be published

```bash
npm pack --dry-run
```

Check that:
- No `node_modules/` is included
- No `screenshots/`, `evals/`, or large media files
- All `skills/` and `agents/` directories are present
- Total size is reasonable (< 2MB target)

### Step 3 — Publish

```bash
npm publish
```

For a pre-release (beta):

```bash
npm version prerelease --preid=beta   # 1.1.0-beta.0
npm publish --tag beta
# Users install with: npx ginskill-init@beta
```

### Step 4 — Push the tag

```bash
git push && git push --tags
```

### What `.npmignore` excludes

The `.npmignore` file keeps the package small by excluding:

```
**/screenshots/    # demo images
**/evals/          # evaluation files
**/*.mov, *.mp4    # video files
node_modules/
install.py, install.js   # legacy installers
*.local.json
**/.env*
```

To add more exclusions, edit `.npmignore`. **Do not add a `files` field to `package.json`** — it overrides `.npmignore` and can accidentally include everything.

---

## CLI Reference

```
ginskill-init [command] [options]
```

### Default: `install`

```bash
ginskill-init                           # Interactive TUI — select skills/agents
ginskill-init --all                     # Install everything, no prompts
ginskill-init --skills react-query,mongodb
ginskill-init --agents developer,tester
ginskill-init -g                        # Install to ~/.claude (global)
ginskill-init -t /path/to/project       # Install to specific project
```

### `upgrade`

Re-copies installed skills/agents from the bundled version.

```bash
ginskill-init upgrade                   # Interactive — choose what to upgrade
ginskill-init upgrade --all             # Upgrade everything
ginskill-init upgrade -t /path/to/project
ginskill-init upgrade -g
```

### `uninstall` (alias: `remove`)

Removes installed skills/agents from the target `.claude/` directory.

```bash
ginskill-init uninstall                 # Interactive — choose what to remove
ginskill-init uninstall -t /path/to/project
ginskill-init uninstall -g
```

### `status` (alias: `info`)

Shows which skills/agents are installed vs available.

```bash
ginskill-init status
ginskill-init status -t /path/to/project
ginskill-init status -g
```

### `list` (alias: `ls`)

Lists all skills and agents bundled in this package (not what's installed).

```bash
ginskill-init list
```

### `versions` (alias: `ver`)

Fetches all published versions from the npm registry.

```bash
ginskill-init versions
```

### Global flags (work on all commands)

| Flag | Short | Description |
|------|-------|-------------|
| `--global` | `-g` | Target `~/.claude/` (available in all projects) |
| `--target <path>` | `-t` | Target a specific project directory |
| `--version` | `-V` | Print CLI version |
| `--help` | `-h` | Print help |

---

## How Users Install Skills

### One-time install (recommended)

```bash
npx ginskill-init
```

Runs the interactive TUI to select skills and agents.

### Install to a specific project

```bash
cd /path/to/my-project
npx ginskill-init
# or
npx ginskill-init -t /path/to/my-project
```

### Install globally (all projects)

```bash
npx ginskill-init -g
# or
npx ginskill-init --global
```

### Non-interactive (CI/scripts)

```bash
npx ginskill-init --all                         # all skills + agents
npx ginskill-init --skills react-query,mongodb  # specific skills only
npx ginskill-init --agents developer            # specific agent only
npx ginskill-init --all -g                      # everything, globally
```

---

## How to Upgrade Installed Skills

When a new version of `ginskill-init` is published, users upgrade their installed skills by running:

```bash
# Interactive — choose which skills/agents to upgrade
npx ginskill-init@latest upgrade

# Upgrade everything silently
npx ginskill-init@latest upgrade --all

# Upgrade in a specific project
npx ginskill-init@latest upgrade -t /path/to/project
```

The `upgrade` command re-copies skills/agents from the npm package, overwriting the existing files. Only skills/agents already installed are shown.

---

## How to Uninstall

### Remove specific skills/agents interactively

```bash
ginskill-init uninstall
# or from any version:
npx ginskill-init uninstall
```

### Remove from a specific project

```bash
ginskill-init uninstall -t /path/to/project
```

### Remove globally installed skills

```bash
ginskill-init uninstall -g
```

### Manual removal

Skills are plain directories — you can also delete them manually:

```bash
# Remove a specific skill
rm -rf .claude/skills/my-skill

# Remove a specific agent
rm .claude/agents/my-agent.md
# or
rm -rf .claude/agents/my-agent/
```

---

## Local Development & Testing

### Setup

```bash
cd ginstudio-skills
npm install
```

### Run CLI locally

```bash
node bin/cli.js --help
node bin/cli.js list
node bin/cli.js status -t /tmp/test
node bin/cli.js --all -t /tmp/test
node bin/cli.js upgrade --all -t /tmp/test
node bin/cli.js uninstall -t /tmp/test
```

### Link globally for testing

```bash
npm link
# Now you can run: ginskill-init --help
npm unlink ginskill-init   # when done
```

### Test pack before publishing

```bash
npm pack --dry-run         # preview what's included
npm pack                   # creates ginskill-init-x.x.x.tgz
# Test install from the tgz:
npx ./ginskill-init-x.x.x.tgz
```

---

## Troubleshooting

### Skills not appearing in Claude Code

Run `/agents` or restart Claude Code after installing. Skills are picked up on session start.

### `npx ginskill-init` installs an old version

Force the latest:

```bash
npx ginskill-init@latest
# or clear npx cache:
npx --yes ginskill-init@latest
```

### Target not recognized

If `-t /path/to/project` seems to be ignored, make sure you're passing it **after** the command:

```bash
ginskill-init upgrade -t /path/to/project   ✓
ginskill-init -t /path/to/project upgrade   ✗  (flag consumed by parent)
```

### Package is too large

Check `.npmignore` is present and `package.json` has no `files` field. Run `npm pack --dry-run` to inspect.

### Skill doesn't auto-trigger

Verify the `description` frontmatter in `SKILL.md` includes `MANDATORY TRIGGERS` with the exact words the user would say.
