# Tutorial: Headless Mode & Agent SDK

Run Claude Code programmatically — from scripts, CI/CD pipelines, automation workflows, or the Python/TypeScript Agent SDK.

---

## Step 1: The Basics — `-p` Flag

The `-p` (or `--print`) flag runs Claude non-interactively:

```bash
# Ask a question
claude -p "What does the auth module do?"

# Run a task
claude -p "Find and fix the bug in src/auth/login.ts"

# With specific tools
claude -p "Run tests and report failures" \
  --allowedTools "Bash,Read,Edit"

# From a file or pipe
echo "Summarize this project" | claude -p -
cat PROMPT.md | claude -p -
```

---

## Step 2: Output Formats

### Text (default)
```bash
claude -p "Explain what useAuth.ts does"
# → plain text response
```

### JSON (with metadata)
```bash
claude -p "Summarize this project" --output-format json
# → { "result": "...", "session_id": "abc123", "usage": {...}, "cost_usd": 0.012 }

# Extract just the text
claude -p "Summarize this project" --output-format json | jq -r '.result'
```

### Structured JSON (with schema)
```bash
# Extract data conforming to a schema
claude -p "Extract function names from auth.ts" \
  --output-format json \
  --json-schema '{"type":"object","properties":{"functions":{"type":"array","items":{"type":"string"}}},"required":["functions"]}'

# → { "result": "...", "structured_output": { "functions": ["login", "logout", "refresh"] }, ... }

# Extract structured output
... | jq '.structured_output'
```

### Streaming JSON (real-time)
```bash
# Stream tokens as they generate
claude -p "Write a detailed analysis" \
  --output-format stream-json \
  --verbose \
  --include-partial-messages

# Filter for just the text tokens
claude -p "Write a poem" \
  --output-format stream-json --verbose --include-partial-messages | \
  jq -rj 'select(.type == "stream_event" and .event.delta.type? == "text_delta") | .event.delta.text'
```

---

## Step 3: Auto-Approve Tools

Use `--allowedTools` to let Claude use tools without prompting:

```bash
# Allow basic file operations
claude -p "Refactor the auth module" \
  --allowedTools "Read,Edit,Grep,Glob"

# Allow bash with specific command prefixes
claude -p "Run tests and fix failures" \
  --allowedTools "Bash,Read,Edit"

# Restrict bash to specific commands (prefix matching with space+*)
claude -p "Create a commit for staged changes" \
  --allowedTools "Bash(git diff *),Bash(git log *),Bash(git status *),Bash(git commit *)"

# Allow all tools (bypass all permission prompts — use carefully)
claude -p "..." --dangerously-skip-permissions
```

**Permission rule syntax:**
- `Bash` — any bash command
- `Bash(git *)` — any command starting with `git` (space + `*` = prefix match)
- `Bash(git diff)` — exact match only
- `Read,Edit,Grep` — comma-separated list

---

## Step 4: Customize the System Prompt

```bash
# Append to Claude Code's default system prompt
claude -p "Review this PR for security vulnerabilities" \
  --append-system-prompt "You are a security engineer. Focus on OWASP Top 10."

# Fully replace the system prompt (loses Claude Code's default behavior)
claude -p "Analyze this data" \
  --system-prompt "You are a data scientist. Respond only with JSON."

# Pipe a PR diff and review it
gh pr diff 123 | claude -p \
  --append-system-prompt "You are a senior TypeScript engineer reviewing a NestJS PR." \
  --output-format json
```

---

## Step 5: Multi-Turn Conversations

```bash
# Continue the most recent conversation
claude -p "Review this codebase for performance issues"
claude -p "Now focus specifically on the database layer" --continue
claude -p "Generate a fix plan for the top 3 issues" --continue

# Continue a specific session
session=$(claude -p "Start a deep review" --output-format json | jq -r '.session_id')
claude -p "Continue that review focusing on security" --resume "$session"
claude -p "Generate a full report" --resume "$session"
```

---

## Step 6: Common CI/CD Patterns

### Auto-review on PR

```bash
#!/bin/bash
# .github/scripts/review-pr.sh

PR_NUMBER="$1"

# Fetch PR context
DIFF=$(gh pr diff "$PR_NUMBER")
DESCRIPTION=$(gh pr view "$PR_NUMBER" --json title,body -q '.title + "\n\n" + .body')

# Run Claude review
REVIEW=$(echo "$DIFF" | claude -p \
  --append-system-prompt "You are a TypeScript/NestJS expert reviewing a PR. Be concise and specific." \
  --output-format json | jq -r '.result')

# Post review as GitHub comment
gh pr comment "$PR_NUMBER" --body "$REVIEW"
```

### Auto-fix lint errors in CI

```bash
#!/bin/bash
# Run lint, capture failures, fix with Claude

LINT_OUTPUT=$(npm run lint 2>&1 || true)

if echo "$LINT_OUTPUT" | grep -q "error"; then
  echo "Lint errors found. Asking Claude to fix..."

  echo "$LINT_OUTPUT" | claude -p \
    "These are lint errors from our codebase. Fix all of them:" \
    --allowedTools "Read,Edit,Bash(npm run lint *)" \
    --append-system-prompt "Fix lint errors minimally. Do not refactor unrelated code."
fi
```

### Batch file processing

```bash
#!/bin/bash
# Process all TypeScript files missing JSDoc comments

find src -name "*.ts" | while read -r file; do
  HAS_JSDOC=$(grep -c "@param\|@returns\|@description" "$file" || echo "0")

  if [ "$HAS_JSDOC" -eq 0 ]; then
    claude -p "Add JSDoc comments to all exported functions in $file" \
      --allowedTools "Read,Edit"
  fi
done
```

### Generate reports from codebase analysis

```bash
#!/bin/bash
# Generate weekly codebase health report

REPORT=$(claude -p \
  "Analyze this codebase and produce a JSON health report with: complexity_score (1-10), test_coverage_estimate, biggest_risks (array), recommended_actions (array)" \
  --allowedTools "Read,Grep,Glob,Bash" \
  --output-format json \
  --json-schema '{
    "type": "object",
    "properties": {
      "complexity_score": {"type": "number"},
      "test_coverage_estimate": {"type": "string"},
      "biggest_risks": {"type": "array", "items": {"type": "string"}},
      "recommended_actions": {"type": "array", "items": {"type": "string"}}
    }
  }' | jq '.structured_output')

echo "$REPORT" | jq '.'
# Save to file or send to Slack
```

---

## Step 7: GitHub Actions Integration

Use the official Claude Code GitHub Action to run Claude in CI/CD pipelines with full GitHub context (PR diffs, issue bodies, comment threads).

### Basic Setup

```yaml
# .github/workflows/claude.yml
name: Claude Code

on:
  pull_request:
    types: [opened, synchronize]
  issue_comment:
    types: [created]   # For @claude comment triggers

jobs:
  claude:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
      issues: write
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          github_token: ${{ secrets.GITHUB_TOKEN }}
```

### Action Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `anthropic_api_key` | Yes (direct API) | From `${{ secrets.ANTHROPIC_API_KEY }}` |
| `github_token` | No | For GitHub API access (comments, PR info) |
| `prompt` | No | Instructions or skill (e.g., `/review`) |
| `claude_args` | No | Any CLI flags passed through |
| `trigger_phrase` | No | Default: `@claude` (for comment triggers) |
| `use_bedrock` | No | `"true"` for AWS Bedrock |
| `use_vertex` | No | `"true"` for Google Vertex AI |

### Passing CLI Arguments via `claude_args`

```yaml
- uses: anthropics/claude-code-action@v1
  with:
    anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
    github_token: ${{ secrets.GITHUB_TOKEN }}
    claude_args: "--max-turns 5 --model claude-opus-4-6 --allowedTools Read,Grep,Glob"
```

| Flag | Purpose |
|------|---------|
| `--max-turns N` | Limit iterations (default: 10) — key for cost control |
| `--model <model>` | Override model (default: Sonnet) |
| `--allowedTools <list>` | Restrict which tools Claude can use |
| `--disallowedTools <list>` | Block specific tools |
| `--append-system-prompt <text>` | Add instructions to system prompt |
| `--mcp-config <path>` | Use an MCP config file |

**Auto-detection:** If `prompt` is omitted and the trigger is a comment event, the action runs in interactive mode (responds to `@claude` comments). If `prompt` is set, it runs in automation mode.

### Common Patterns

#### Auto-review PRs

```yaml
name: PR Review
on:
  pull_request:
    types: [opened, synchronize]
jobs:
  review:
    runs-on: ubuntu-latest
    permissions:
      pull-requests: write
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          github_token: ${{ secrets.GITHUB_TOKEN }}
          prompt: "/review"
          claude_args: "--max-turns 5"
```

#### Respond to @claude comments on PRs/Issues

```yaml
name: Claude Interactive
on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
jobs:
  respond:
    runs-on: ubuntu-latest
    if: contains(github.event.comment.body, '@claude')
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          github_token: ${{ secrets.GITHUB_TOKEN }}
          # No prompt = interactive mode; responds to the @claude comment
```

### AWS Bedrock Setup

```yaml
jobs:
  review:
    runs-on: ubuntu-latest
    permissions:
      id-token: write   # REQUIRED for OIDC
      pull-requests: write
    steps:
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_TO_ASSUME }}
          aws-region: us-west-2

      - uses: anthropics/claude-code-action@v1
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          use_bedrock: "true"
          claude_args: "--model us.anthropic.claude-sonnet-4-6 --max-turns 10"
```

**AWS requirements:** GitHub OIDC provider in AWS, IAM role with `AmazonBedrockFullAccess`, model ID format: `us.anthropic.claude-sonnet-4-6` (region-prefixed).

### Google Vertex AI Setup

```yaml
    steps:
      - name: Auth with Google Cloud
        uses: google-github-actions/auth@v2
        id: auth
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

      - uses: anthropics/claude-code-action@v1
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          use_vertex: "true"
          claude_args: "--model claude-sonnet-4@20250514"
        env:
          ANTHROPIC_VERTEX_PROJECT_ID: ${{ steps.auth.outputs.project_id }}
          CLOUD_ML_REGION: us-east5
```

**Vertex AI requirements:** Workload Identity Federation (not service account keys), Vertex AI API enabled. Model ID format: `claude-sonnet-4@20250514`.

### Cost Control

```yaml
# Limit turns to control cost
claude_args: "--max-turns 5"

# Set a workflow-level timeout
jobs:
  claude:
    timeout-minutes: 10

# Prevent parallel runs (cancel in-progress if new commit pushed)
concurrency:
  group: claude-${{ github.ref }}
  cancel-in-progress: true
```

---

## Step 8: Agent SDK (Python)

For full programmatic control with callbacks, streaming, and native objects:

```bash
pip install claude-agent-sdk
```

```python
import asyncio
import claude_agent_sdk as agent

async def main():
    # Simple one-shot
    result = await agent.run(
        prompt="Analyze the auth module and list all security concerns",
        options=agent.ClaudeCodeOptions(
            allowed_tools=["Read", "Grep", "Glob"],
            cwd="/path/to/project",
        )
    )
    print(result)

asyncio.run(main())
```

### With streaming and callbacks

```python
import asyncio
import claude_agent_sdk as agent
from claude_agent_sdk import MessageParam, AssistantMessageParam

async def process_stream():
    async with agent.run_stream(
        prompt="Run the test suite and fix all failures",
        options=agent.ClaudeCodeOptions(
            allowed_tools=["Bash", "Read", "Edit"],
            max_turns=20,
        ),
    ) as stream:
        async for event in stream:
            if event.type == "assistant":
                for block in event.message.content:
                    if hasattr(block, "text"):
                        print(block.text, end="", flush=True)
            elif event.type == "result":
                print(f"\n\nFinal result: {event.result}")
                print(f"Session: {event.session_id}")
                print(f"Cost: ${event.cost_usd:.4f}")

asyncio.run(process_stream())
```

### Multi-turn conversation

```python
import asyncio
import claude_agent_sdk as agent

async def multi_turn():
    messages = []

    # First turn
    async with agent.run_stream(
        prompt="Review the codebase for performance issues",
        messages=messages,
        options=agent.ClaudeCodeOptions(allowed_tools=["Read", "Grep", "Glob"]),
    ) as stream:
        async for event in stream:
            if hasattr(event, 'messages'):
                messages.extend(event.messages)

    # Continue the conversation
    async with agent.run_stream(
        prompt="Now suggest concrete fixes for the top 3 issues",
        messages=messages,  # Pass previous messages for context
        options=agent.ClaudeCodeOptions(allowed_tools=["Read", "Edit"]),
    ) as stream:
        async for event in stream:
            if event.type == "assistant":
                for block in event.message.content:
                    if hasattr(block, "text"):
                        print(block.text, end="", flush=True)

asyncio.run(multi_turn())
```

---

## Step 9: Agent SDK (TypeScript)

```bash
npm install @anthropic-ai/claude-code
```

```typescript
import { query, type Options } from "@anthropic-ai/claude-code";

async function reviewCode(projectPath: string) {
  const options: Options = {
    allowedTools: ["Read", "Grep", "Glob", "Bash"],
    cwd: projectPath,
    maxTurns: 15,
  };

  // One-shot
  const result = await query({
    prompt: "Review the authentication module for security issues",
    options,
  });
  console.log(result);
}

// With streaming
async function streamReview(projectPath: string) {
  const stream = query({
    prompt: "Analyze and fix all TypeScript type errors",
    options: {
      allowedTools: ["Read", "Edit", "Bash(tsc *)"],
      cwd: projectPath,
    },
  });

  for await (const event of stream) {
    if (event.type === "assistant") {
      for (const block of event.message.content) {
        if (block.type === "text") process.stdout.write(block.text);
      }
    }
    if (event.type === "result") {
      console.log(`\nCost: $${event.cost_usd.toFixed(4)}`);
    }
  }
}
```

---

## Step 10: Run Claude as an MCP Server

Expose Claude Code's tools to other applications:

```bash
# Start Claude Code as an MCP server
claude mcp serve
```

Add to Claude Desktop's `claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "claude-code": {
      "type": "stdio",
      "command": "/usr/local/bin/claude",
      "args": ["mcp", "serve"],
      "env": {}
    }
  }
}
```

This exposes Read, Edit, Bash, and other tools to any MCP client. The client is responsible for user confirmation.

---

## Step 11: Environment Variables

```bash
# Model selection
ANTHROPIC_MODEL=claude-opus-4-6 claude -p "..."

# Skip permission prompts (scripts/CI only — dangerous in interactive use)
CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS=1 claude -p "..."

# Auto-compaction threshold (default: 95%)
CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=70 claude -p "..."

# MCP timeout in milliseconds
MCP_TIMEOUT=30000 claude -p "..."

# Disable background tasks
CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 claude -p "..."

# Disable claude.ai MCP servers
ENABLE_CLAUDEAI_MCP_SERVERS=false claude -p "..."
```

---

## Quick Reference

```bash
# Basic
claude -p "prompt"

# With tools
claude -p "prompt" --allowedTools "Read,Edit,Bash"

# JSON output
claude -p "prompt" --output-format json | jq -r '.result'

# Streaming
claude -p "prompt" --output-format stream-json --verbose --include-partial-messages

# Continue conversation
claude -p "prompt" --continue
claude -p "prompt" --resume "session-id"

# Custom system prompt
claude -p "prompt" --append-system-prompt "You are a..."

# Structured output
claude -p "extract data" --output-format json \
  --json-schema '{"type":"object","properties":{"items":{"type":"array"}}}'
```
