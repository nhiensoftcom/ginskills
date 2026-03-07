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
| `active-life-dev` | Active Life Backend Dev Guide: Comprehensive development guide for the Active Life Global Store NestJS backend (be-store-active-life-global). |
| `ai-asset-generator` | AI Asset Generator: Generate production-ready images, icons, videos, and visual assets using KIE AI and background removal APIs. |
| `ai-build-ai` | AI Build AI: Master guide for extending Claude Code — creating skills, custom subagents (agents), MCP servers, hooks, plugins, agent teams, running... |
| `ant-design` | Ant Design (antd) Expert: Production patterns for building React UIs with Ant Design v5/v6 — components, theming, Form, Table, Modal, layout, icons... |
| `icon-generator` | SVG Icon Generator: Generate beautiful, clean SVG icon components (.tsx) for React Native apps using react-native-svg. |
| `mobile-app-review` | Mobile App Store Review Checklist: Comprehensive pre-submission audit for Apple App Store and Google Play Store. |
| `mongodb` | MongoDB & Mongoose Best Practices: Production patterns for schema design, indexing, aggregation pipelines, transactions, connection management, and... |
| `nestjs-architecture` | NestJS Feature-Based Architecture: Production patterns for organizing NestJS backends — feature modules, core infrastructure, shared utilities, gua... |
| `react-fsd-architecture` | Feature-Sliced Design (FSD) Architecture: Architectural methodology for organizing frontend projects by business features — layers, slices, segment... |
| `react-native-expo` | React Native Expo (Sty AI Mobile): Production patterns for the Sty AI React Native app — Expo SDK 54, Expo Router v5, React Query v5, Zustand v5, R... |
| `react-query` | TanStack React Query Best Practices: Comprehensive guide for writing production-quality React Query code — query keys, mutations, caching, optimist... |
| `review-code` | Code Review: Comprehensive code review and quality analysis for fullstack monorepos (NestJS backend, Next.js frontend, React Native mobile). |
| `security-scanner` | Security Scanner: Comprehensive security audit for fullstack monorepos — NestJS backend, Next.js frontend, and React Native mobile app. |
| `ui-ux-pro-max` | UI/UX design intelligence. |


## Available Agents

| Agent | Description |
|-------|-------------|
| `developer` | Full-stack developer agent for implementing features, fixing bugs, and writing production-quality code |
| `frontend-design` | Frontend design agent for building beautiful, accessible UI components and pages |
| `mobile-reviewer` | Reviews React Native / Expo apps for App Store & Google Play compliance, UX best practices, and platform-specific issues |
| `review-code` | Reviews code for quality, architecture, and best practices across the fullstack monorepo |
| `security-scanner` | Scans for security vulnerabilities aligned with OWASP Top 10:2025, LLM Top 10, and Mobile Top 10 |
| `tester` | Testing agent for writing and running unit tests, integration tests, and e2e tests |


---

## Contributing

See [DEVELOPMENT.md](./DEVELOPMENT.md) for:
- How to add a new skill or agent
- How to release a new version to npm
- CLI development and testing guide
