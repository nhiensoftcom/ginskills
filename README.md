# GinStudio Skills

Claude Code skills and agents — install with one command, select what you need.

## Quick Start

```bash
npx ginskill-init
```

Interactive TUI — use **Space** to select, **A** to toggle all, **Enter** to confirm.

---

## Installation

### Install to current project

```bash
npx ginskill-init
```

### Install to a specific project

```bash
npx ginskill-init -t /path/to/project
```

### Install globally (available in all projects)

```bash
npx ginskill-init -g
```

### Non-interactive (CI / scripts)

```bash
npx ginskill-init --all                          # Install everything
npx ginskill-init --skills react-query,mongodb   # Specific skills
npx ginskill-init --agents developer,tester      # Specific agents
npx ginskill-init --all -g                       # Everything, globally
```

---

## Commands

| Command | Description |
|---------|-------------|
| `ginskill-init` | Interactive install (default) |
| `ginskill-init upgrade` | Re-install installed skills/agents from latest bundled version |
| `ginskill-init uninstall` | Remove installed skills/agents |
| `ginskill-init status` | Show what's installed vs available |
| `ginskill-init list` | List all available skills & agents |
| `ginskill-init versions` | Show all published npm versions |

### Flags (work on all commands)

| Flag | Short | Description |
|------|-------|-------------|
| `--global` | `-g` | Target `~/.claude/` (available in all projects) |
| `--target <path>` | `-t` | Target a specific project path |
| `--all` | `-a` | Skip prompts, select all |

### Examples

```bash
# Check what's installed in current project
ginskill-init status

# Check a specific project
ginskill-init status -t /path/to/project

# Upgrade all installed skills to latest version
npx ginskill-init@latest upgrade --all

# Uninstall interactively
ginskill-init uninstall

# Remove from a specific project
ginskill-init uninstall -t /path/to/project
```

---

## Where files are installed

```
<project>/
  .claude/
    skills/
      react-query/SKILL.md
      mongodb/SKILL.md
      ...
    agents/
      developer.md
      tester.md
      ...
```

After installing, **restart Claude Code** (or type `/agents`) to pick up the new skills and agents.

---

## Available Skills

| Skill | Description |
|-------|-------------|
| `ai-asset-generator` | Generate images, videos, icons using KIE AI API |
| `ai-build-ai` | Master guide for extending Claude Code — skills, agents, MCP, hooks, headless |
| `ant-design` | Ant Design v5/v6 expert — components, theming, Form, Table, Modal, TypeScript |
| `icon-generator` | Generate SVG icon components (.tsx) for React Native |
| `mobile-app-review` | Pre-submission audit for App Store & Google Play |
| `mongodb` | MongoDB & Mongoose best practices for NestJS |
| `nestjs-architecture` | NestJS feature-based architecture patterns |
| `performance` | React Native performance optimization |
| `react-fsd-architecture` | Feature-Sliced Design (FSD) for frontend projects |
| `react-query` | TanStack React Query v5+ best practices |
| `review-code` | Comprehensive code review for fullstack monorepos |
| `security-scanner` | OWASP-aligned security audit (Top 10, LLM, Mobile) |
| `react-native-expo` | React Native Expo best practices for Sty AI mobile (navigation, state, design system, performance) |
| `ui-ux-pro-max` | Design intelligence with 67 styles, palettes, typography |

## Available Agents

| Agent | Description |
|-------|-------------|
| `developer` | Full-stack developer for features, bugs, production code |
| `frontend-design` | Frontend designer with Next.js, Tailwind, shadcn/ui |
| `mobile-reviewer` | React Native/Expo app reviewer for store compliance |
| `review-code` | Senior code reviewer for fullstack monorepos |
| `security-scanner` | Security auditor (OWASP Top 10, LLM, Mobile) |
| `tester` | QA engineer and testing specialist |

---

## Contributing

See [DEVELOPMENT.md](./DEVELOPMENT.md) for:
- How to add a new skill or agent
- How to release a new version to npm
- CLI development and testing guide
