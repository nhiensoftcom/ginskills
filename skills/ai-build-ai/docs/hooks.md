# Tutorial: Hooks

Hooks are shell commands, HTTP endpoints, or LLM prompts that fire automatically at specific lifecycle points in Claude Code. They give you **deterministic control** — certain actions always happen regardless of what Claude decides to do.

Use hooks to: auto-format files after edits, block dangerous commands, inject context after compaction, send notifications, audit tool use, enforce project rules.

---

## Step 1: The Hooks Lifecycle

All 16 hook events in order:

| Event | When it fires | Can block? |
|-------|--------------|-----------|
| `SessionStart` | Session begins or resumes | No (but can inject context) |
| `UserPromptSubmit` | You submit a prompt, before Claude processes | No (but can inject context) |
| `PreToolUse` | Before any tool executes | **Yes** |
| `PermissionRequest` | When a permission dialog appears | **Yes** |
| `PostToolUse` | After a tool succeeds | No (but can block continuation) |
| `PostToolUseFailure` | After a tool fails | No |
| `Notification` | Claude needs your attention | No |
| `SubagentStart` | A subagent is spawned | No |
| `SubagentStop` | A subagent finishes | No |
| `Stop` | Claude finishes responding | No (but can keep Claude working) |
| `TeammateIdle` | Agent team teammate goes idle | **Yes** (send feedback) |
| `TaskCompleted` | A task marked as completed | **Yes** (block completion) |
| `ConfigChange` | A settings/skills file changes live | **Yes** |
| `WorktreeCreate` | A worktree is being created | Replaces default behavior |
| `WorktreeRemove` | A worktree is being removed | Replaces default behavior |
| `PreCompact` | Before context compaction | No |
| `SessionEnd` | Session terminates | No |

---

## Step 2: Where to Configure Hooks

Hooks live in settings JSON files:

```
~/.claude/settings.json                ← All your projects (personal)
.claude/settings.json                  ← This project only (commit to git)
.claude/settings.local.json            ← This project, not committed
plugin/hooks/hooks.json                ← Bundled with a plugin
skill/agent frontmatter                ← Active only while component runs
```

Basic structure:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "npx prettier --write $(jq -r '.tool_input.file_path')"
          }
        ]
      }
    ]
  }
}
```

You can also manage hooks interactively: run `/hooks` inside Claude Code.

---

## Step 3: Hook Types

### Type 1: `command` (most common)

Runs a shell command. Receives event data as JSON on stdin.

```json
{
  "type": "command",
  "command": "./scripts/my-hook.sh",
  "timeout": 30
}
```

### Type 2: `http`

POSTs event JSON to an HTTP endpoint. Response body uses same JSON format as command output.

```json
{
  "type": "http",
  "url": "https://my-server.com/hooks/tool-use",
  "headers": {
    "Authorization": "Bearer $MY_TOKEN"
  },
  "allowedEnvVars": ["MY_TOKEN"]
}
```

Header values support `$VAR` interpolation — only vars listed in `allowedEnvVars` are expanded.

### Type 3: `prompt` (LLM-based judgment)

Sends your prompt + event data to Claude Haiku for a yes/no decision. Returns `{"ok": true}` or `{"ok": false, "reason": "..."}`.

```json
{
  "type": "prompt",
  "prompt": "Check if all requested tasks are complete. If any remain, respond with {\"ok\": false, \"reason\": \"what remains\"}.",
  "model": "haiku"
}
```

Use prompt hooks when you need judgment rather than deterministic rules.

### Type 4: `agent` (multi-step verification)

Spawns a subagent that can use tools (read files, run commands) to verify conditions, then returns `{"ok": true/false}`.

```json
{
  "type": "agent",
  "prompt": "Run the test suite. If any tests fail, return {\"ok\": false, \"reason\": \"list of failing tests\"}.",
  "timeout": 120
}
```

Use agent hooks when verification requires inspecting actual code/files.

---

## Step 4: Exit Codes and Output

For `command` hooks, communication is via stdin/stdout/stderr + exit codes:

| Exit Code | Meaning |
|-----------|---------|
| `0` | Allow the action. Stdout is added to Claude's context (for SessionStart/UserPromptSubmit hooks). |
| `2` | **Block** the action. Stderr content is shown to Claude as feedback. |
| Other | Allow the action. Stderr is logged but NOT shown to Claude. |

```bash
#!/bin/bash
INPUT=$(cat)  # Read JSON event from stdin
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

if echo "$COMMAND" | grep -q "rm -rf"; then
  echo "Blocked: destructive command not allowed" >&2
  exit 2   # Block
fi

exit 0  # Allow
```

### Structured JSON output (instead of exit codes)

For more control, exit 0 and print JSON to stdout:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Use rg instead of grep for performance"
  }
}
```

**Permission decisions** (PreToolUse only):
- `"allow"` — proceed without showing permission prompt
- `"deny"` — cancel tool call, send reason to Claude
- `"ask"` — show normal permission prompt to user

**Block continuation** (PostToolUse/Stop):
```json
{ "decision": "block", "reason": "Tests are still failing" }
```

**Inject context** (UserPromptSubmit):
```json
{ "additionalContext": "Remember: we're in a migration sprint, don't change DB schemas." }
```

---

## Step 5: Matcher Patterns

The `matcher` field is a **regex** that filters when hooks fire. Omit or set to `""` or `"*"` to match everything.

| Event | Matcher filters on |
|-------|--------------------|
| `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest` | Tool name |
| `SessionStart` | How session started: `startup` \| `resume` \| `clear` \| `compact` |
| `SessionEnd` | Why session ended: `clear` \| `logout` \| `prompt_input_exit` \| `other` |
| `Notification` | Type: `permission_prompt` \| `idle_prompt` \| `auth_success` |
| `SubagentStart`, `SubagentStop` | Agent type name |
| `PreCompact` | Trigger: `manual` \| `auto` |
| `ConfigChange` | Source: `user_settings` \| `project_settings` \| `local_settings` \| `skills` |
| `UserPromptSubmit`, `Stop`, `TeammateIdle`, `TaskCompleted`, `WorktreeCreate`, `WorktreeRemove` | No matcher — always fires |

Matcher is a regex, so:
- `"Edit|Write"` — matches either Edit or Write tool
- `"Notebook.*"` — matches any Notebook tool
- `"mcp__github__.*"` — matches all GitHub MCP tools
- `"mcp__.*__write.*"` — matches any MCP write tool across servers

---

## Step 6: JSON Input Schemas

Every hook receives a JSON object on stdin. Common fields across all events:

```json
{
  "session_id": "abc123",
  "cwd": "/Users/abc/project",
  "hook_event_name": "PreToolUse"
}
```

**PreToolUse / PostToolUse / PermissionRequest:**
```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm test"
  }
}
```

**For Edit/Write tools:**
```json
{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "/path/to/file.ts",
    "old_string": "...",
    "new_string": "..."
  }
}
```

**UserPromptSubmit:**
```json
{
  "prompt": "user's message text here"
}
```

**SessionStart:**
```json
{
  "source": "startup"
}
```

**Stop:**
```json
{
  "stop_hook_active": false
}
```

**ConfigChange:**
```json
{
  "source": "project_settings",
  "file_path": "/path/to/.claude/settings.json"
}
```

---

## Step 7: Common Hook Recipes

### Auto-format after edits

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

### Desktop notification when Claude needs input

```json
{
  "hooks": {
    "Notification": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "osascript -e 'display notification \"Claude needs your attention\" with title \"Claude Code\"'"
      }]
    }]
  }
}
```

### Block edits to protected files

**`.claude/hooks/protect-files.sh`:**
```bash
#!/bin/bash
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
PROTECTED=(".env" "package-lock.json" ".git/")
for pattern in "${PROTECTED[@]}"; do
  if [[ "$FILE" == *"$pattern"* ]]; then
    echo "Blocked: $FILE matches protected pattern '$pattern'" >&2
    exit 2
  fi
done
exit 0
```

**`.claude/settings.json`:**
```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Edit|Write",
      "hooks": [{
        "type": "command",
        "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/protect-files.sh"
      }]
    }]
  }
}
```

### Re-inject context after compaction

```json
{
  "hooks": {
    "SessionStart": [{
      "matcher": "compact",
      "hooks": [{
        "type": "command",
        "command": "echo 'Reminder: use Bun not npm. Current sprint: auth refactor. Run bun test before commits.'"
      }]
    }]
  }
}
```

### Log all bash commands

```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "jq -r '[now|todate, .tool_input.command] | @tsv' >> ~/.claude/bash-log.tsv"
      }]
    }]
  }
}
```

### Keep Claude working until tests pass (Stop hook)

```json
{
  "hooks": {
    "Stop": [{
      "hooks": [{
        "type": "agent",
        "prompt": "Run `npm test` and check the output. If any tests fail, respond with {\"ok\": false, \"reason\": \"X tests failing: [test names]\"}. If all tests pass or there are no tests, respond with {\"ok\": true}.",
        "timeout": 120
      }]
    }]
  }
}
```

### Validate only READ-only SQL (PreToolUse + hook)

**`.claude/hooks/validate-readonly-sql.sh`:**
```bash
#!/bin/bash
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
if echo "$CMD" | grep -iE '\b(INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|TRUNCATE|REPLACE|MERGE)\b' > /dev/null 2>&1; then
  echo "Blocked: only SELECT queries are allowed in this context" >&2
  exit 2
fi
exit 0
```

### Audit config changes

```json
{
  "hooks": {
    "ConfigChange": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "jq -c '{ts: now|todate, source: .source, file: .file_path}' >> ~/claude-config-audit.log"
      }]
    }]
  }
}
```

### Stop hook infinite loop prevention

Stop hooks can re-trigger themselves. Always check `stop_hook_active`:

```bash
#!/bin/bash
INPUT=$(cat)
# If already triggered once, let Claude stop
if [ "$(echo "$INPUT" | jq -r '.stop_hook_active')" = "true" ]; then
  exit 0
fi
# Your check logic here
# ...
exit 2  # Keep Claude working
```

---

## Step 8: Hooks in Skills and Agents

Define hooks scoped to a skill's or agent's active lifetime in the frontmatter:

**In a skill's SKILL.md:**
```yaml
---
name: safe-reviewer
allowed-tools: Read, Grep
hooks:
  PostToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "echo 'Bash used by skill' >> /tmp/skill-log.txt"
---
```

**In an agent's .md file:**
```yaml
---
name: db-agent
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: ".claude/hooks/validate-sql.sh"
  Stop:
    - hooks:
        - type: command
          command: "./scripts/cleanup.sh"
---
```

`Stop` hooks in skill/agent frontmatter automatically become `SubagentStop` events at runtime.

---

## Step 9: Troubleshooting

**Hook not firing:**
- Run `/hooks` and confirm it's listed under the correct event
- Check matcher regex is correct (case-sensitive)
- `PermissionRequest` hooks don't fire in headless mode (`-p`) — use `PreToolUse` instead

**Hook errors in output:**
- Test manually: `echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | ./my-hook.sh`
- Make scripts executable: `chmod +x ./my-hook.sh`
- Use absolute paths or `$CLAUDE_PROJECT_DIR` to reference scripts
- Install `jq` if missing: `brew install jq`

**Stop hook loops forever:**
```bash
# Add this at the top of your stop hook script:
INPUT=$(cat)
if [ "$(echo "$INPUT" | jq -r '.stop_hook_active')" = "true" ]; then
  exit 0
fi
```

**JSON output ignored:**
- Don't mix: if you exit 2, JSON is ignored. For JSON output, exit 0.
- Profile echo statements can corrupt JSON: wrap them in `if [[ $- == *i* ]]; then`.

**Debug all hook execution:**
- Press `Ctrl+O` to toggle verbose mode — shows hook output in transcript
- Or run `claude --debug` for full hook execution details

---

## Step 10: Notification Hook Matchers

The `Notification` event supports specific matchers to target different notification types:

| Matcher | Fires when |
|---------|-----------|
| `permission_prompt` | Claude needs approval for a tool (permission dialog appearing) |
| `idle_prompt` | Claude has finished responding and is waiting for your input |
| `auth_success` | Authentication / OAuth flow completes |
| `elicitation_dialog` | Claude is asking you a question (AskUserQuestion tool) |
| `""` (empty) | All notification types |

**Example: different sounds for different notifications:**

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [{
          "type": "command",
          "command": "afplay /System/Library/Sounds/Ping.aiff"
        }]
      },
      {
        "matcher": "idle_prompt",
        "hooks": [{
          "type": "command",
          "command": "afplay /System/Library/Sounds/Glass.aiff"
        }]
      }
    ]
  }
}
```

---

## Step 11: Managed Settings for Hooks

For enterprise / team deployments, these settings control hooks at the org level (set in managed policy files):

| Setting | Effect |
|---------|--------|
| `allowManagedHooksOnly: true` | Blocks user/project/plugin hooks — only managed hooks run |
| `allowedHttpHookUrls: ["https://hooks.company.com/*"]` | HTTP hooks can only call these URLs (wildcard supported) |
| `allowedHttpHookUrls: []` | Block all HTTP hook calls |
| `httpHookAllowedEnvVars: ["MY_TOKEN"]` | Env vars HTTP hooks can interpolate (intersection with hook's own `allowedEnvVars`) |

**Example managed settings file:**

```json
{
  "allowManagedHooksOnly": true,
  "allowedHttpHookUrls": [
    "https://hooks.company.com/*",
    "https://audit.internal.company.com/claude"
  ],
  "httpHookAllowedEnvVars": ["AUDIT_TOKEN", "TEAM_ID"]
}
```

When `allowedHttpHookUrls` is `undefined` (not set), there are no URL restrictions. When set to `[]`, all HTTP hooks are blocked.

---

## Environment Variables Available in Hooks

- `$CLAUDE_PROJECT_DIR` — absolute path to the project root
- `$CLAUDE_SESSION_ID` — current session ID
- `$MY_VAR` — any env var listed in `allowedEnvVars` (HTTP hooks only)
