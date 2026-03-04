# Tutorial: Create a Plugin

Plugins package skills, agents, hooks, and MCP servers into a distributable unit. Use plugins when you want to share functionality across teams, publish to a marketplace, or maintain versioned releases that can be installed with one command.

---

## Step 1: Plugins vs Standalone Config

| Aspect | Standalone (`.claude/`) | Plugin |
|--------|------------------------|--------|
| Skill names | `/hello` | `/my-plugin:hello` (namespaced) |
| Sharing | Manual copy | Install via marketplace |
| Versioning | Git-based | Semantic versioning in manifest |
| Best for | Personal, project-specific, experiments | Team distribution, open source, reuse |

**Start with standalone** config in `.claude/` for quick iteration. Convert to a plugin when you're ready to share.

---

## Step 2: Plugin Directory Structure

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json          ← REQUIRED: plugin manifest
├── skills/
│   └── my-skill/
│       └── SKILL.md         ← Skills (namespaced as /my-plugin:my-skill)
├── commands/
│   └── quick-cmd.md         ← Legacy commands format (also supported)
├── agents/
│   └── my-agent.md          ← Custom agents
├── hooks/
│   └── hooks.json           ← Hook configurations
├── .mcp.json                ← MCP server configurations
├── .lsp.json                ← LSP server configurations (optional)
├── settings.json            ← Default settings when plugin is enabled
└── README.md                ← Documentation
```

**CRITICAL:** `.claude-plugin/` only contains `plugin.json`. Everything else goes at the plugin root.

---

## Step 3: Create the Manifest

**`.claude-plugin/plugin.json`:**

```json
{
  "name": "my-plugin",
  "description": "What this plugin does",
  "version": "1.0.0",
  "author": {
    "name": "Your Name",
    "email": "you@example.com"
  },
  "homepage": "https://github.com/you/my-plugin",
  "repository": "https://github.com/you/my-plugin",
  "license": "MIT"
}
```

| Field | Required | Purpose |
|-------|----------|---------|
| `name` | Yes | Unique ID and skill namespace prefix. Lowercase, hyphens. |
| `description` | Yes | Shown in plugin manager when browsing/installing. |
| `version` | Yes | Semantic versioning (`1.0.0`). Increment for updates. |
| `author` | No | Attribution info. |
| `homepage` | No | Link to docs or landing page. |
| `repository` | No | Source code URL. |
| `license` | No | SPDX license identifier. |

The `name` field becomes the namespace prefix for all skills: a skill named `review` in a plugin named `code-tools` becomes `/code-tools:review`.

---

## Step 4: Add Skills

Skills in a plugin live in `skills/<skill-name>/SKILL.md`:

```
my-plugin/
└── skills/
    └── code-review/
        └── SKILL.md
```

**`skills/code-review/SKILL.md`:**
```yaml
---
name: code-review
description: Reviews code for best practices. Use when reviewing code, checking PRs, or auditing quality.
---

# Code Review

When reviewing code, check for:
1. Security vulnerabilities
2. Error handling completeness
3. TypeScript type safety
4. Test coverage

...
```

After installing, use it as `/my-plugin:code-review`.

Skills in plugins support all the same features as standalone skills: arguments (`$ARGUMENTS`), dynamic context (`!`cmd``), `context: fork`, `allowed-tools`, etc.

---

## Step 5: Add Agents

Agents in plugins live in `agents/<name>.md` — exactly the same format as standalone agents:

```
my-plugin/
└── agents/
    └── security-reviewer.md
```

**`agents/security-reviewer.md`:**
```yaml
---
name: security-reviewer
description: Security expert. Use proactively when reviewing code changes for vulnerabilities.
tools: Read, Grep, Glob, Bash
model: sonnet
---

You are a security engineer specializing in web application security...
```

Agents are **not** namespaced like skills — they keep their plain `name`.

---

## Step 6: Add Hooks

Hooks in plugins live in `hooks/hooks.json`:

```
my-plugin/
└── hooks/
    └── hooks.json
```

**`hooks/hooks.json`:**
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.file_path' | xargs npx prettier --write 2>/dev/null || true"
          }
        ]
      }
    ]
  }
}
```

Same format as `settings.json` hooks — just the `"hooks"` key and below.

---

## Step 7: Add MCP Servers

MCP servers in plugins live in `.mcp.json` at the plugin root:

```
my-plugin/
└── .mcp.json
```

**`.mcp.json`:**
```json
{
  "mcpServers": {
    "my-internal-api": {
      "type": "stdio",
      "command": "${CLAUDE_PLUGIN_ROOT}/servers/api-server",
      "args": ["--config", "${CLAUDE_PLUGIN_ROOT}/config.json"],
      "env": {
        "API_URL": "${MY_API_URL}"
      }
    }
  }
}
```

- `${CLAUDE_PLUGIN_ROOT}` — resolved to the plugin's directory at runtime
- MCP servers start automatically when the plugin is enabled (requires Claude Code restart to apply changes)
- Supports `stdio`, `http`, and `sse` transport types

---

## Step 8: Add LSP Servers (Optional)

LSP servers give Claude real-time code intelligence for languages not natively supported:

**`.lsp.json`:**
```json
{
  "go": {
    "command": "gopls",
    "args": ["serve"],
    "extensionToLanguage": {
      ".go": "go"
    }
  }
}
```

Users need the LSP binary installed. For common languages (TypeScript, Python, Rust), use pre-built plugins from the marketplace instead.

---

## Step 9: Default Settings

Ship default settings with your plugin via `settings.json` at the plugin root:

```json
{
  "agent": "security-reviewer"
}
```

Setting `agent` activates one of the plugin's custom agents as the default main thread. This changes how Claude Code behaves when the plugin is enabled. Currently only the `agent` key is supported here.

---

## Step 10: Test Locally

Use `--plugin-dir` to load your plugin without installing:

```bash
# Load single plugin
claude --plugin-dir ./my-plugin

# Load multiple plugins
claude --plugin-dir ./plugin-one --plugin-dir ./plugin-two

# Inside Claude Code:
/my-plugin:skill-name    # Test a skill
/agents                  # Check agents appear
/hooks                   # Verify hooks are registered
/mcp                     # Check MCP servers
```

Changes to plugin files require restarting Claude Code to take effect.

---

## Step 11: Convert Existing Config to Plugin

If you have skills/hooks in `.claude/`, convert them:

```bash
# Create plugin structure
mkdir -p my-plugin/.claude-plugin

# Create manifest
cat > my-plugin/.claude-plugin/plugin.json << 'EOF'
{
  "name": "my-plugin",
  "description": "Migrated from standalone configuration",
  "version": "1.0.0"
}
EOF

# Copy existing files
cp -r .claude/skills my-plugin/      # If you have skills
cp -r .claude/agents my-plugin/      # If you have agents
cp -r .claude/commands my-plugin/    # If you have commands

# Migrate hooks from settings.json → hooks/hooks.json
mkdir my-plugin/hooks
# Copy the "hooks" object from .claude/settings.json to hooks/hooks.json
```

**What changes after migration:**

| Standalone | Plugin |
|-----------|--------|
| `/hello` | `/my-plugin:hello` |
| `.claude/commands/` | `plugin/commands/` |
| `.claude/settings.json` hooks | `plugin/hooks/hooks.json` |
| Manual sharing | `claude plugin install` |

---

## Step 12: Distribute

### Via URL/Git

Users install with:
```bash
claude plugin install https://github.com/you/my-plugin
```

Or via marketplace if you submit to one:
```bash
/plugin install my-plugin  # From configured marketplace
```

### Submit to official marketplace

1. Go to `claude.ai/settings/plugins/submit` or `platform.claude.com/plugins/submit`
2. Fill out the submission form
3. Once approved, users can install via `/plugin install plugin-name`

### Via team marketplace

Create a `marketplace.json` registry file and host it. Teams can point Claude Code to it:
```bash
claude plugin source add https://your-company.com/plugins/marketplace.json
```

---

## Complete Plugin Example: Code Quality Toolkit

```
code-quality/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   ├── review/
│   │   └── SKILL.md          # /code-quality:review
│   └── refactor/
│       └── SKILL.md          # /code-quality:refactor
├── agents/
│   └── code-reviewer.md      # Auto-review agent
├── hooks/
│   └── hooks.json            # Auto-format on save
└── README.md
```

**`.claude-plugin/plugin.json`:**
```json
{
  "name": "code-quality",
  "description": "Code review, refactoring, and auto-formatting toolkit",
  "version": "2.1.0",
  "author": { "name": "GinStudio Team" },
  "repository": "https://github.com/ginstudio/code-quality-plugin"
}
```

**`hooks/hooks.json`:**
```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Edit|Write",
      "hooks": [{
        "type": "command",
        "command": "jq -r '.tool_input.file_path' | xargs npx prettier --write 2>/dev/null || true"
      }]
    }]
  }
}
```

**`agents/code-reviewer.md`:**
```yaml
---
name: code-reviewer
description: Expert code reviewer. Use proactively after any code changes.
tools: Read, Grep, Glob, Bash
model: sonnet
memory: project
---

You are a senior code reviewer. After code changes, run git diff HEAD~1 and provide structured feedback by severity (CRITICAL/WARNING/SUGGESTION).
```

---

## Checklist Before Publishing

- [ ] `version` follows semver (`1.0.0`)
- [ ] `description` clearly explains what the plugin does
- [ ] Skills tested with `/plugin-name:skill-name`
- [ ] Agents appear in `/agents`
- [ ] Hooks fire correctly (test via `/hooks`)
- [ ] MCP servers start up (check via `/mcp`)
- [ ] `README.md` explains installation + usage
- [ ] No secrets or credentials in plugin files
- [ ] Plugin loads cleanly with `claude --plugin-dir ./my-plugin`
