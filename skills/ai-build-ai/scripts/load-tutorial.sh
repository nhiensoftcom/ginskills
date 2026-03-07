#!/bin/bash
# load-tutorial.sh — Loads the right tutorial doc based on the topic argument.
# Used by ai-build-ai SKILL.md via the !`command` dynamic context injection.
#
# Usage: load-tutorial.sh [topic]
# Topics: skill | agent | mcp | headless | hooks | plugin | teams | memory | permissions | overview (default)

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOPIC="${1:-overview}"

# Normalize input: lowercase, strip leading /, trim spaces
TOPIC=$(echo "$TOPIC" | tr '[:upper:]' '[:lower:]' | sed 's|^/||' | xargs)

case "$TOPIC" in
  skill|skills|create-skill|new-skill|add-skill|write-skill)
    cat "$SKILL_DIR/docs/create-skill.md"
    ;;
  agent|agents|subagent|subagents|create-agent|new-agent|add-agent|custom-agent)
    cat "$SKILL_DIR/docs/create-agent.md"
    ;;
  mcp|mcp-server|create-mcp|new-mcp|add-mcp|model-context-protocol|server)
    cat "$SKILL_DIR/docs/create-mcp.md"
    ;;
  headless|headless-mode|programmatic|cli|sdk|agent-sdk|automation|script|ci|cicd|pipeline|github-actions|gitlab)
    cat "$SKILL_DIR/docs/headless-mode.md"
    ;;
  hook|hooks|lifecycle|event|events|automation|pretooluse|posttooluse|sessionstart|stop)
    cat "$SKILL_DIR/docs/hooks.md"
    ;;
  plugin|plugins|distribute|distribution|marketplace|package|publish)
    cat "$SKILL_DIR/docs/plugins.md"
    ;;
  team|teams|agent-team|agent-teams|multi-agent|parallel|teammate|teammates)
    cat "$SKILL_DIR/docs/agent-teams.md"
    ;;
  team-lead|teamlead|lead|workflow|multi-pass|verification|orchestrat*)
    cat "$SKILL_DIR/docs/team-lead-workflow.md"
    ;;
  memory|claude-md|claudemd|rules|persistent|instructions|context|remember)
    cat "$SKILL_DIR/docs/memory-claude-md.md"
    ;;
  permission|permissions|allow|deny|rule|rules|access|bypasspermissions)
    cat "$SKILL_DIR/docs/permissions.md"
    ;;
  sandbox|sandboxing|isolat*|seatbelt|bubblewrap|filesystem|network-filter)
    cat "$SKILL_DIR/docs/sandbox.md"
    ;;
  checkpoint|checkpointing|rewind|restore|fork|session|resume|undo)
    cat "$SKILL_DIR/docs/checkpointing.md"
    ;;
  output-style|output-styles|style|styles|tone|explanatory|learning)
    cat "$SKILL_DIR/docs/output-styles.md"
    ;;
  *)
    cat "$SKILL_DIR/docs/overview.md"
    ;;
esac
