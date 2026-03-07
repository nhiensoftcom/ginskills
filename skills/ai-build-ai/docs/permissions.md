# Tutorial: Permissions

Claude Code has a permission system to control what tools, files, and domains Claude can access. Configure it in `settings.json` or manage interactively with `/permissions`.

---

## Step 1: The Permission Tiers

| Tool type | Default behavior |
|-----------|----------------|
| Read-only (Read, Grep, Glob) | No approval needed |
| Bash commands | Prompts first time per project per command |
| File modification (Edit, Write) | Prompts, "yes don't ask again" lasts until session end |

Rules are evaluated: **deny → ask → allow**. The first matching rule wins.

---

## Step 2: Permission Modes

Set `defaultMode` in `.claude/settings.json`:

```json
{
  "defaultMode": "acceptEdits"
}
```

| Mode | Behavior |
|------|----------|
| `default` | Standard: prompts on first use of each tool |
| `acceptEdits` | Auto-accepts file edits for the session |
| `plan` | Read-only: Claude can analyze but not modify files or execute commands |
| `dontAsk` | Auto-denies tools unless pre-approved via rules |
| `bypassPermissions` | Skips ALL permission prompts (only in safe/isolated environments) |

---

## Step 3: Permission Rules

Define allow/deny rules in `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(npm run *)",
      "Bash(git commit *)",
      "Read",
      "Edit(/src/**)"
    ],
    "deny": [
      "Bash(git push *)",
      "Bash(rm -rf *)",
      "Edit(.env)"
    ]
  }
}
```

You can also set `ask` rules to force a prompt even if normally auto-allowed:
```json
{
  "permissions": {
    "ask": ["Bash(git push *)"]
  }
}
```

---

## Step 4: Rule Syntax

### Match all uses of a tool
```
Bash          ← any bash command
Read          ← any file read
Edit          ← any file edit
WebFetch      ← any web fetch
```

### Exact match
```
Bash(npm run build)        ← only this exact command
Read(./.env)               ← only this file
```

### Wildcard prefix matching (`*`)
```
Bash(npm run *)            ← any command starting with "npm run "
Bash(git *)                ← any git command
Bash(* --version)          ← any command ending with " --version"
Bash(git * main)           ← git checkout main, git merge main, etc.
```

**Space before `*` matters:**
- `Bash(ls *)` — matches `ls -la` but NOT `lsof` (word boundary enforced)
- `Bash(ls*)` — matches both `ls -la` AND `lsof` (no boundary)

**Shell operators are NOT trusted:**
- `Bash(safe-cmd *)` will NOT give permission to `safe-cmd && dangerous-cmd`
- Claude Code is operator-aware — each chained command is checked separately

### File path patterns

For `Read` and `Edit` rules, use gitignore-style patterns:

| Pattern prefix | Meaning | Example |
|---------------|---------|---------|
| `//path` | Absolute from filesystem root | `Read(//Users/alice/secrets/**)` |
| `~/path` | From home directory | `Read(~/.ssh/*)` |
| `/path` | Relative to project root | `Edit(/src/**/*.ts)` |
| `path` | Relative to cwd | `Read(*.env)` |

```json
{
  "permissions": {
    "allow": [
      "Edit(/src/**/*.ts)",
      "Edit(/src/**/*.tsx)",
      "Read"
    ],
    "deny": [
      "Edit(.env)",
      "Edit(package-lock.json)",
      "Read(//etc/passwd)"
    ]
  }
}
```

Note: `*` matches files in one directory, `**` matches recursively.

### WebFetch rules

```
WebFetch(domain:github.com)      ← only github.com
WebFetch(domain:api.example.com) ← only this API
```

### MCP tool rules

```
mcp__puppeteer                   ← all tools from puppeteer MCP server
mcp__puppeteer__*                ← same (wildcard form)
mcp__github__search_repositories ← specific tool from github server
mcp__.*__write.*                 ← any "write" tool across all MCP servers (regex)
```

### Agent/Subagent rules

```
Agent(Explore)              ← the Explore built-in agent
Agent(Plan)                 ← the Plan built-in agent
Agent(my-custom-agent)      ← your custom agent
```

To block Claude from using specific agents:
```json
{
  "permissions": {
    "deny": ["Agent(Explore)", "Agent(dangerous-agent)"]
  }
}
```

---

## Step 5: Practical Configuration Examples

### Safe exploration mode (read-only + specific bash)

```json
{
  "permissions": {
    "allow": [
      "Read",
      "Bash(git log *)",
      "Bash(git diff *)",
      "Bash(git status)",
      "Bash(npm test *)",
      "Bash(* --help *)",
      "Bash(* --version)"
    ],
    "deny": [
      "Edit",
      "Write",
      "Bash(git push *)",
      "Bash(rm *)",
      "Bash(sudo *)"
    ]
  }
}
```

### Development workflow (allow most, deny dangerous)

```json
{
  "permissions": {
    "allow": [
      "Read",
      "Edit(/src/**)",
      "Edit(/tests/**)",
      "Write(/src/**)",
      "Bash(npm run *)",
      "Bash(bun *)",
      "Bash(git commit *)",
      "Bash(git add *)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git status)"
    ],
    "deny": [
      "Edit(.env)",
      "Edit(.env.local)",
      "Edit(package-lock.json)",
      "Bash(git push *)",
      "Bash(rm -rf *)",
      "Bash(sudo *)",
      "Bash(curl *)",
      "Bash(wget *)"
    ]
  }
}
```

### CI/CD (fully open for automation)

For automated pipelines in isolated environments:
```json
{
  "defaultMode": "bypassPermissions"
}
```

Or via CLI flag: `claude -p "..." --dangerously-skip-permissions`

---

## Step 6: Settings Files and Precedence

Permissions can be set at multiple levels. Higher priority wins for conflicting rules:

```
1. Managed policy settings     ← Highest (org admin, can't be overridden)
2. CLI flags (--disallowedTools)
3. .claude/settings.local.json (project-local, not committed)
4. .claude/settings.json       (project-level, committed to git)
5. ~/.claude/settings.json     ← Lowest (personal defaults)
```

**Example: deny list via CLI:**
```bash
claude --disallowedTools "Agent(Explore),Bash(rm *)"
```

**Example: settings.json with all permission options:**
```json
{
  "defaultMode": "default",
  "permissions": {
    "allow": [
      "Bash(npm run *)",
      "Read",
      "Edit(/src/**)"
    ],
    "ask": [
      "Bash(git push *)"
    ],
    "deny": [
      "Bash(sudo *)",
      "Edit(.env)"
    ]
  }
}
```

---

## Step 7: Extend Permissions with Hooks

For dynamic, context-aware permission decisions, use `PreToolUse` hooks:

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": ".claude/hooks/validate-commands.sh"
      }]
    }]
  }
}
```

```bash
#!/bin/bash
# .claude/hooks/validate-commands.sh
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Block production deployments without approval
if echo "$CMD" | grep -q "deploy.*production"; then
  echo "Blocked: production deployments require manual approval from lead" >&2
  exit 2
fi

# Block database migrations in non-migration sessions
if echo "$CMD" | grep -q "migrate.*run"; then
  echo "Blocked: run migrations via the /migrate skill instead" >&2
  exit 2
fi

exit 0
```

Hooks run before the permission system, giving you fine-grained runtime control that static rules can't provide.

---

## Step 8: Working Directories

By default, Claude accesses files in its launch directory. Extend access:

```bash
# At startup
claude --add-dir /path/to/shared-lib --add-dir /path/to/config

# During session
/add-dir /path/to/new-directory

# Permanently in settings
```

**In settings.json:**
```json
{
  "additionalDirectories": [
    "/path/to/shared-lib",
    "../sibling-project"
  ]
}
```

Files in additional directories follow the same permission rules as the main working directory.

---

## Step 9: Managed / Enterprise Settings

For org-wide policies, admins deploy settings to:
- macOS: `/Library/Application Support/ClaudeCode/`
- Linux/WSL: `/etc/claude-code/`
- Windows: `C:\Program Files\ClaudeCode\`

**Managed-only settings** (can only be set by admin):

| Setting | Effect |
|---------|--------|
| `disableBypassPermissionsMode: "disable"` | Prevents `bypassPermissions` mode entirely |
| `allowManagedPermissionRulesOnly: true` | Only managed rules apply; users can't add their own |
| `allowManagedHooksOnly: true` | Only managed hooks run; user/project hooks blocked |
| `allowManagedMcpServersOnly: true` | Only managed MCP server allowlist applies |

---

## Quick Reference

```bash
# View and manage permissions interactively
/permissions

# Allow specific tools via CLI
claude --allowedTools "Read,Edit,Bash(npm run *)"

# Deny specific tools via CLI
claude --disallowedTools "Agent(Explore),Bash(rm *)"

# Skip all permissions (CI only!)
claude -p "..." --dangerously-skip-permissions

# Run in plan mode (read-only, no edits)
claude --default-permission-mode plan
```

**Rule priority:** `deny > ask > allow` — deny always wins.

**Rule tip:** Use hooks for dynamic decisions, rules for static patterns.
