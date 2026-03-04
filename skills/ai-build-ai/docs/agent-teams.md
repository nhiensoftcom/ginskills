# Tutorial: Agent Teams

Agent teams let you coordinate multiple Claude Code instances working together. One session acts as the **team lead**, assigning tasks. Teammates work independently in their own context windows and can communicate directly with each other.

---

## Step 1: Agent Teams vs Subagents

| | Subagents | Agent Teams |
|--|-----------|-------------|
| **Context** | Own window, reports back to main | Own window, fully independent |
| **Communication** | One-way: report results to main agent | Direct messaging between teammates |
| **Coordination** | Main agent manages all work | Shared task list, self-coordinating |
| **Best for** | Focused tasks where only result matters | Complex work needing inter-agent discussion |
| **Token cost** | Lower | Higher (each teammate = separate Claude instance) |

**Use agent teams when:**
- Teammates need to share findings and challenge each other (e.g., parallel hypothesis testing)
- Work spans multiple independent domains (frontend + backend + tests)
- You need sustained parallelism that exceeds one context window

**Use subagents when:**
- You just need parallel execution of isolated tasks
- Workers only need to report back, not communicate
- You want lower token cost

---

## Step 2: Enable Agent Teams

Agent teams are **experimental** and disabled by default. Enable via `.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

Or set in your shell environment:
```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
claude
```

---

## Step 3: Start a Team

Just describe the task and ask for a team:

```
Create an agent team to explore this codebase from different angles:
one teammate on security, one on performance, one on maintainability.
Have them each analyze and report findings.
```

Claude creates the team, spawns teammates, assigns tasks, and synthesizes results.

You can also specify details:
```
Create a team with 4 teammates to refactor these modules in parallel.
Use Sonnet for each teammate.
```

Claude won't create a team without your approval.

---

## Step 4: Display Modes

**In-process (default):** all teammates run inside your terminal.
- Press `Shift+Down` to cycle through teammates
- Type to message the selected teammate
- Press `Enter` to view a teammate's session, `Escape` to interrupt
- Press `Ctrl+T` to toggle the task list

**Split-panes:** each teammate gets its own pane (requires tmux or iTerm2).
- See all teammates' output simultaneously
- Click a pane to interact directly

Configure in settings:
```json
{
  "teammateMode": "in-process"
}
```

Or for one session:
```bash
claude --teammate-mode in-process
```

**Auto** (default): uses split-panes if already in tmux, in-process otherwise.

Install tmux for split-pane mode:
```bash
brew install tmux  # macOS
```

---

## Step 5: Control the Team

### Talk to teammates directly

In in-process mode: press `Shift+Down` to cycle to the teammate, then type.
In split-pane mode: click their pane.

### Assign tasks

Tell the lead to assign specific work:
```
Ask the security teammate to focus only on the auth module
```

Or teammates can self-claim from the shared task list.

### Require plan approval before implementation

```
Spawn an architect teammate to refactor the auth module.
Require plan approval before they make any changes.
```

The teammate stays in read-only plan mode until the lead approves. If rejected, they revise and resubmit.

### Broadcast to all teammates

```
Tell all teammates to focus on critical issues only
```

Use sparingly — costs scale with team size.

### Shut down a teammate

```
Ask the researcher teammate to shut down
```

### Clean up the team when done

```
Clean up the team
```

Always use the lead for cleanup. The lead checks all teammates have shut down first.

---

## Step 6: Architecture Details

**Components:**
- **Team lead**: the main Claude Code session, spawns and coordinates teammates
- **Teammates**: separate Claude Code instances, each with their own context window
- **Task list**: shared work items (`~/.claude/tasks/{team-name}/`)
- **Mailbox**: direct messaging between agents (delivered automatically)

**Team config stored at:** `~/.claude/teams/{team-name}/config.json`

**Context each teammate gets:**
- CLAUDE.md from project
- MCP servers
- Skills
- The spawn prompt from the lead
- Does NOT get the lead's conversation history

**Permissions:** teammates inherit the lead's permission settings. If lead uses `--dangerously-skip-permissions`, all teammates do too.

---

## Step 7: Quality Gates with Hooks

Use hooks to enforce rules across the team:

```json
{
  "hooks": {
    "TeammateIdle": [{
      "hooks": [{
        "type": "prompt",
        "prompt": "Check if the teammate has completed all assigned tasks. If incomplete work remains, respond with {\"ok\": false, \"reason\": \"what still needs to be done\"}."
      }]
    }],
    "TaskCompleted": [{
      "hooks": [{
        "type": "agent",
        "prompt": "Verify the task was actually completed: run tests for the changed files and confirm they pass. Return {\"ok\": false, \"reason\": \"failing tests\"} if tests fail.",
        "timeout": 60
      }]
    }]
  }
}
```

- `TeammateIdle` — fires when teammate goes idle. Exit code 2 / `"ok": false` sends feedback and keeps them working.
- `TaskCompleted` — fires when a task is marked complete. Can block completion.

---

## Step 8: Use Case Examples

### Parallel code review

```
Create an agent team to review PR #142. Spawn three reviewers:
- One focused on security implications
- One checking performance impact
- One validating test coverage
Have them each review and report findings.
```

### Competing hypotheses debugging

```
Users report the app exits after one message instead of staying connected.
Spawn 5 agent teammates to investigate different hypotheses. Have them talk
to each other to try to disprove each other's theories, like a scientific debate.
Update the findings doc with whatever consensus emerges.
```

### Cross-layer feature implementation

```
Implement the new payment flow across:
- Backend: API endpoints and service logic
- Frontend: UI components and state management
- Mobile: React Native screens
- Tests: E2E test coverage

Create a team with 4 teammates, one per layer. Have the backend teammate
finish the API contracts first, then the others can work in parallel.
```

---

## Step 9: Best Practices

**Team size:** start with 3-5 teammates. More teammates = more coordination overhead and higher token cost.

**Task sizing:**
- Too small: coordination overhead exceeds benefit
- Too large: teammates work too long without check-ins, risk wasted effort
- Ideal: 5-6 tasks per teammate, each producing a clear deliverable

**Avoid file conflicts:** two teammates editing the same file causes overwrites. Assign each teammate different files.

**Give enough context in spawn prompt:** teammates don't inherit conversation history — include task-specific details in the prompt.

**Monitor and steer:** check in on progress, redirect approaches not working, synthesize findings as they come in.

**Wait for teammates:** if the lead starts implementing instead of waiting:
```
Wait for your teammates to complete their tasks before proceeding
```

---

## Step 10: Known Limitations (Experimental)

- **No session resumption with in-process teammates**: `/resume` doesn't restore them. Spawn new teammates if needed.
- **Task status can lag**: teammates sometimes fail to mark tasks complete. Check manually if stuck.
- **Shutdown can be slow**: teammates finish current tool call before shutting down.
- **One team per session**: a lead can only manage one team at a time.
- **No nested teams**: teammates cannot spawn their own teams.
- **Lead is fixed**: the session that creates the team leads forever.
- **Split panes don't work in**: VS Code integrated terminal, Windows Terminal, Ghostty.

---

## Quick Reference

```bash
# Enable agent teams
echo '{"env":{"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS":"1"}}' > .claude/settings.json

# Start a team (in Claude Code):
"Create an agent team with 3 teammates to research X, Y, Z in parallel"

# Navigate between teammates (in-process mode):
Shift+Down         # Cycle to next teammate
Ctrl+T             # Toggle task list
Enter              # View teammate's session
Escape             # Interrupt current teammate turn

# Control the team:
"Ask teammate [name] to focus on [specific area]"
"Require plan approval before any teammate makes changes"
"Ask all teammates to shut down"
"Clean up the team"
```
