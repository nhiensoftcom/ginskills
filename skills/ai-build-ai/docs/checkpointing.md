# Tutorial: Checkpointing & Rewind

Claude Code automatically saves checkpoints before each file edit. Rewind any mistake without losing work — across sessions.

---

## Step 1: How Checkpoints Work

- Created automatically before each file edit
- One checkpoint per **user prompt** (not per individual file change within a prompt)
- Persist across sessions (accessible when you resume)
- Auto-cleaned after 30 days

**What checkpoints track:**
- File changes made by Edit, Write, and NotebookEdit tools

**What checkpoints do NOT track:**
- Files modified by bash commands (`rm`, `mv`, `cp`, shell scripts)
- Changes made outside Claude Code (manual edits in your editor)
- Edits from other concurrent Claude sessions on the same files

---

## Step 2: Open the Rewind Menu

```bash
Esc+Esc      # Press Escape twice
/rewind      # Same effect
/checkpoint  # Alias
```

This opens a scrollable list of all prompts from the session. Select the checkpoint you want to revert to.

---

## Step 3: Rewind Options

When you select a checkpoint, you have 5 choices:

| Option | What it does |
|--------|-------------|
| **Restore code and conversation** | Reverts both file changes AND conversation history to that point |
| **Restore conversation** | Rewinds messages only; keeps current code state |
| **Restore code** | Reverts file changes only; keeps full conversation history |
| **Summarize from here** | Compresses conversation from this point forward; early messages stay intact |
| **Never mind** | Exit without making any changes |

After any restore option, the original prompt from the selected message is placed back in your input field.

---

## Step 4: Summarize from Here

**"Summarize from here"** is a targeted context management tool — different from `/compact`:

```
/rewind → select message → "Summarize from here"
```

- Messages BEFORE the selected point remain in **full detail**
- Messages AFTER (and including) the selected point are replaced with an AI summary
- The original messages are still stored in the session transcript (Claude can still reference them)
- Optionally provide instructions to guide what the summary focuses on

| | `/compact` | "Summarize from here" |
|-|------------|----------------------|
| Scope | Entire conversation | From selected point forward |
| Preserves early context in full | No | Yes |
| Use when | Context is almost full, start fresh | You want to keep early context detailed |

---

## Step 5: Fork a Session

To experiment on a branch without losing your current state:

```bash
# Fork via command (creates a new session from the current point)
/fork

# Fork with a name
/fork experiment-v2

# Fork from CLI (branches off the most recent conversation)
claude --continue --fork-session
```

Forked sessions appear **grouped under their root session** in the session picker. The original session stays completely intact.

---

## Step 6: Session Management

### CLI Flags

```bash
# Resume most recent conversation in the current directory
claude --continue

# Open interactive session picker
claude --resume

# Resume a specific session by name
claude --resume auth-refactor

# Resume the session linked to a specific GitHub PR
claude --from-pr 123
```

### In-Session Commands

```bash
# Name the current session for easy resuming later
/rename auth-refactor

# Switch to a different conversation without exiting
/resume

# Fork current conversation at this point
/fork
```

### Session Picker Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `P` | Preview session content |
| `R` | Rename highlighted session |
| `/` | Search / filter sessions |
| `A` | Toggle: current directory / all projects |
| `B` | Filter by current git branch |
| `→` / `←` | Expand / collapse grouped sessions |

---

## Quick Reference

```bash
Esc+Esc         # Open rewind menu
/rewind         # Same as Esc+Esc
/fork           # Fork current session at this point
/compact        # Compact the entire conversation

claude --continue         # Resume most recent conversation
claude --resume           # Interactive session picker
claude --resume <name>    # Resume by name
claude --from-pr 123      # Resume session linked to a PR
```

**Restore code only** (keep conversation):
→ `/rewind` → select checkpoint → **Restore code**

**Restore conversation only** (keep code):
→ `/rewind` → select checkpoint → **Restore conversation**

**Compress context from a point**:
→ `/rewind` → select checkpoint → **Summarize from here**

---

**Design intent:** Checkpointing is "local undo" that complements Git's "permanent history". Use Git for versioning your work across the project; use checkpointing for in-session recovery from mistakes.
