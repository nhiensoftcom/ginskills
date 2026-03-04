---
name: ai-build-ai
description: |
  **AI Build AI**: Master guide for extending Claude Code — creating skills, custom subagents (agents), MCP servers, hooks, plugins, agent teams, running Claude programmatically, and more.
  - MANDATORY TRIGGERS: create skill, new skill, add skill, write skill, build skill, create agent, new agent, add subagent, custom agent, create MCP, add MCP server, connect MCP, build MCP, headless mode, agent SDK, run claude programmatically, claude -p, how to extend claude, claude extensibility, how to create, how to build, hooks, plugin, agent team, sandbox, checkpoint, rewind, output style
  - Use this skill when the user wants to: create or design a new Claude Code skill, build a custom subagent/agent, connect an MCP server or build their own, run Claude programmatically via CLI or SDK, configure hooks, build a plugin, set up agent teams, configure sandboxing, use checkpointing, or change output styles.
  - Invoke the correct tutorial based on the topic argument.
argument-hint: "[skill | agent | mcp | headless | hooks | plugins | teams | memory | permissions | sandbox | checkpoint | output-styles]"
disable-model-invocation: false
---

# AI Build AI

You are an expert guide for extending Claude Code. Load the right tutorial based on what the user wants to build.

## Tutorial Routing

Run this to load the relevant tutorial:

!`bash ginstudio-skills/skills/ai-build-ai/scripts/load-tutorial.sh $ARGUMENTS`

---

## How to Use This Skill

After reading the tutorial above, help the user build their extension by:

1. **Understanding their goal** — What do they want to create? What problem does it solve?
2. **Choosing the right type** — Skill vs Agent vs MCP vs Headless (see decision table below)
3. **Following the tutorial** — Apply the patterns from the loaded tutorial
4. **Creating files** — Write the actual SKILL.md / agent .md / scripts / config
5. **Testing** — Guide them through testing the new extension

---

## Decision Table: What Should I Build?

| Goal | Build This |
|------|-----------|
| Teach Claude a repeatable workflow (code review, PR creation, deploy) | **Skill** |
| Add domain knowledge Claude should always apply (API conventions, style guide) | **Skill** (`user-invocable: false`) |
| Run heavy/verbose operations without polluting main context | **Subagent** |
| Give Claude access to GitHub, Slack, databases, external APIs | **MCP Server** |
| Run Claude in CI/CD, scripts, or automation | **Headless / Agent SDK** |
| Run Claude in GitHub Actions | **Headless** (`/ai-build-ai headless`) |
| Build an app that uses Claude as the AI backend | **Agent SDK** |
| Isolate tool access (read-only, specific commands) | **Subagent** |
| Auto-format files, block dangerous commands, send notifications | **Hooks** |
| Distribute extensions to a team or community | **Plugin** |
| Parallel work where teammates need to communicate | **Agent Teams** |
| Persist coding standards across sessions | **CLAUDE.md / Memory** |
| Restrict what files/commands Claude can touch | **Permissions** |
| Add OS-level protection for bash commands | **Sandbox** |
| Undo mistakes or experiment safely | **Checkpointing** |
| Change Claude's tone, verbosity, or teaching style | **Output Style** |

---

## Topic Commands

The user can invoke with a specific topic to load the deep tutorial immediately:

| Command | What Loads |
|---------|-----------|
| `/ai-build-ai skill` | Create SKILL.md, frontmatter, arguments, dynamic context, supporting files |
| `/ai-build-ai agent` | Create subagents, tools, models, memory, hooks, worktree isolation |
| `/ai-build-ai mcp` | Connect remote/local MCP servers, build your own MCP server |
| `/ai-build-ai headless` | `claude -p`, output formats, GitHub Actions, CI/CD, Python/TypeScript SDK |
| `/ai-build-ai hooks` | All hook events, types, exit codes, matchers, notification matchers, recipes |
| `/ai-build-ai plugins` | Plugin manifest, structure, skills/agents/hooks/MCP in plugins, distribution |
| `/ai-build-ai teams` | Agent teams: enable, start, control, display modes, use cases |
| `/ai-build-ai memory` | CLAUDE.md, .claude/rules/, auto memory, imports, monorepo setup |
| `/ai-build-ai permissions` | Allow/deny rules, modes, Bash/Read/Edit/WebFetch/MCP/Agent rules |
| `/ai-build-ai sandbox` | OS-level enforcement, filesystem rules, network filtering |
| `/ai-build-ai checkpoint` | Rewind, fork, session management, summarize from here |
| `/ai-build-ai output-styles` | Built-in styles, custom styles, keep-coding-instructions |
| `/ai-build-ai` | Overview of all 12 extension types + decision table |

---

## Supporting Files

- `docs/overview.md` — Overview + decision table (loaded when no topic given)
- `docs/create-skill.md` — Complete skill creation guide with examples
- `docs/create-agent.md` — Complete agent creation guide with examples
- `docs/create-mcp.md` — MCP server setup + building your own
- `docs/headless-mode.md` — Programmatic usage, GitHub Actions, CI/CD, Agent SDK
- `docs/hooks.md` — All hook events, types, matchers, notification matchers, recipes
- `docs/plugins.md` — Plugin manifest, structure, distribution
- `docs/agent-teams.md` — Team architecture, display modes, use cases
- `docs/memory-claude-md.md` — CLAUDE.md, rules/, auto memory, imports
- `docs/permissions.md` — Permission modes, rule syntax, examples
- `docs/sandbox.md` — OS-level sandboxing, filesystem and network rules
- `docs/checkpointing.md` — Rewind, fork, session management
- `docs/output-styles.md` — Built-in and custom output styles
- `scripts/load-tutorial.sh` — Routes to the right doc based on argument

---

## After Creating an Extension

### For Skills
1. Test auto-trigger: describe your use case naturally, confirm Claude loads the skill
2. Test direct invoke: `/skill-name [args]`
3. Check `SKILL.md` is under 500 lines — move excess to `docs/`
4. Add to `ginstudio-skills/skills/` to share with the team (this repo)

### For Agents
1. Run `/agents` to verify the agent appears
2. Ask Claude: "Use the [agent-name] agent to [task]"
3. Check tool restrictions work correctly
4. Enable `memory` if the agent should learn across sessions

### For MCP Servers
1. Run `claude mcp list` to confirm the server is registered
2. In Claude Code, type `/mcp` to check server status
3. Try using an MCP tool naturally: "Check GitHub for open PRs"
4. Use `--scope project` + commit `.mcp.json` to share with your team

### For Headless
1. Test with a simple prompt first: `claude -p "hello" --output-format json`
2. Verify tool permissions: use `--allowedTools` explicitly
3. Check output format: pipe through `jq` to validate JSON structure
4. Add to CI/CD workflow as a step
