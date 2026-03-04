# Tutorial: Connect MCP Servers

The Model Context Protocol (MCP) gives Claude access to external tools, databases, APIs, and services. Once connected, Claude can use MCP tools naturally as part of any conversation.

---

## Step 1: Understand MCP Transport Types

| Transport | When to Use | Example |
|-----------|-------------|---------|
| **HTTP** | Remote cloud services (recommended) | `https://mcp.sentry.dev/mcp` |
| **SSE** | Legacy remote services (deprecated, prefer HTTP) | `https://mcp.asana.com/sse` |
| **stdio** | Local processes, custom scripts, CLI tools | `npx -y @modelcontextprotocol/server-fs` |

---

## Step 2: Add a Remote HTTP MCP Server

```bash
# Basic
claude mcp add --transport http <name> <url>

# With auth header
claude mcp add --transport http <name> <url> \
  --header "Authorization: Bearer YOUR_TOKEN"

# Real examples:
claude mcp add --transport http github https://api.githubcopilot.com/mcp/
claude mcp add --transport http sentry https://mcp.sentry.dev/mcp
claude mcp add --transport http notion https://mcp.notion.com/mcp
claude mcp add --transport http hubspot https://mcp.hubspot.com/anthropic
```

For servers requiring OAuth (like GitHub, Sentry), authenticate after adding:
```bash
# In Claude Code session:
/mcp
# → Select the server → Authenticate → Follow browser flow
```

---

## Step 3: Add a Local stdio MCP Server

```bash
# Basic syntax — double dash separates claude's args from server command
claude mcp add --transport stdio <name> -- <command> [args...]

# With environment variables
claude mcp add --transport stdio <name> \
  --env API_KEY=your-key \
  -- npx -y @package/mcp-server

# Real examples:
claude mcp add --transport stdio filesystem \
  -- npx -y @modelcontextprotocol/server-filesystem /Users/abc/projects

claude mcp add --transport stdio db \
  -- npx -y @bytebase/dbhub \
  --dsn "postgresql://user:pass@localhost:5432/mydb"

claude mcp add --transport stdio airtable \
  --env AIRTABLE_API_KEY=your_key \
  -- npx -y airtable-mcp-server
```

**Important:** All flags (`--transport`, `--env`, `--scope`) MUST come BEFORE the server name. The `--` separates Claude's flags from the server's command.

---

## Step 4: Choose the Right Scope

```bash
# Local (default) — only you, only this project
claude mcp add --transport http stripe https://mcp.stripe.com

# Project — shared with team via .mcp.json (commit to git)
claude mcp add --transport http github https://api.githubcopilot.com/mcp/ --scope project

# User — all your projects, personal
claude mcp add --transport http notion https://mcp.notion.com/mcp --scope user
```

**Where config is stored:**
- Local & User: `~/.claude.json`
- Project: `.mcp.json` in project root (commit this!)

---

## Step 5: The .mcp.json Format

When using `--scope project`, Claude creates/updates `.mcp.json`:

```json
{
  "mcpServers": {
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/"
    },
    "sentry": {
      "type": "http",
      "url": "https://mcp.sentry.dev/mcp"
    },
    "local-db": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@bytebase/dbhub", "--dsn", "${DB_URL}"],
      "env": {
        "CACHE_DIR": "/tmp/mcp-cache"
      }
    }
  }
}
```

**Environment variable expansion in .mcp.json:**
- `${VAR}` — expands to env var value
- `${VAR:-default}` — uses `default` if VAR not set

```json
{
  "mcpServers": {
    "api": {
      "type": "http",
      "url": "${API_BASE_URL:-https://api.example.com}/mcp",
      "headers": {
        "Authorization": "Bearer ${API_TOKEN}"
      }
    }
  }
}
```

---

## Step 6: Manage Your Servers

```bash
# List all configured servers
claude mcp list

# Get details for a specific server
claude mcp get github

# Remove a server
claude mcp remove github

# Import from Claude Desktop (macOS/WSL only)
claude mcp add-from-claude-desktop

# Add from JSON config directly
claude mcp add-json my-server '{"type":"http","url":"https://example.com/mcp"}'

# Check status and authenticate in Claude Code
/mcp
```

---

## Step 7: Build Your Own MCP Server

For custom integrations, build an MCP server using the official SDK.

### Option A: Using Node.js (MCP TypeScript SDK)

```bash
npm install @modelcontextprotocol/sdk
```

```typescript
// my-mcp-server.ts
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

const server = new Server(
  { name: "my-server", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

// Register tools
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "get_data",
      description: "Fetch data from our internal API",
      inputSchema: {
        type: "object",
        properties: {
          query: { type: "string", description: "Search query" },
          limit: { type: "number", description: "Max results", default: 10 },
        },
        required: ["query"],
      },
    },
  ],
}));

// Handle tool calls
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  if (request.params.name === "get_data") {
    const { query, limit = 10 } = request.params.arguments as {
      query: string;
      limit?: number;
    };

    // Your implementation here
    const results = await fetchFromAPI(query, limit);

    return {
      content: [{ type: "text", text: JSON.stringify(results, null, 2) }],
    };
  }
  throw new Error(`Unknown tool: ${request.params.name}`);
});

// Start the server
const transport = new StdioServerTransport();
await server.connect(transport);
```

Register it:
```bash
claude mcp add --transport stdio my-server -- node my-mcp-server.js
```

### Option B: Using Python (MCP Python SDK)

```bash
pip install mcp
```

```python
# my_server.py
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent
import json

app = Server("my-server")

@app.list_tools()
async def list_tools() -> list[Tool]:
    return [
        Tool(
            name="search_database",
            description="Search the company database",
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {"type": "string"},
                    "table": {"type": "string", "enum": ["users", "orders", "products"]},
                },
                "required": ["query", "table"],
            },
        )
    ]

@app.call_tool()
async def call_tool(name: str, arguments: dict) -> list[TextContent]:
    if name == "search_database":
        results = await query_db(arguments["query"], arguments["table"])
        return [TextContent(type="text", text=json.dumps(results))]
    raise ValueError(f"Unknown tool: {name}")

async def main():
    async with stdio_server() as (read_stream, write_stream):
        await app.run(read_stream, write_stream, app.create_initialization_options())

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
```

Register it:
```bash
claude mcp add --transport stdio my-db-server -- python my_server.py
```

### Option C: HTTP Server (for remote access)

For a server that multiple users can access:

```typescript
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import express from "express";

const app = express();

app.post("/mcp", async (req, res) => {
  const server = new Server({ name: "my-server", version: "1.0.0" }, { capabilities: { tools: {} } });
  // ... register tools ...

  const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
  await server.connect(transport);
  await transport.handleRequest(req, res, req.body);
});

app.listen(3000);
```

Register it:
```bash
claude mcp add --transport http my-server http://localhost:3000/mcp
```

---

## Step 8: MCP Resources (@ mentions)

MCP servers can expose resources accessible via `@mention`:

```
# In Claude Code conversation:
@github:issue://123      ← Reference a GitHub issue
@docs:file://api/auth    ← Reference a doc page
@postgres:schema://users ← Reference a DB schema
```

Resources are automatically fetched when mentioned. Use `@` to see available resources from connected servers.

---

## Step 9: Include MCP in a Subagent

Give specific MCP servers to a subagent:

```yaml
---
name: github-agent
description: Handle GitHub operations. Reads issues, creates PRs, checks CI.
mcpServers:
  - github                    # Reference already-configured server by name
  - name: slack               # Or inline definition
    type: http
    url: https://mcp.slack.com/mcp
tools: Read, Grep
model: sonnet
---

You are a GitHub workflow specialist. When invoked:
1. Check the current PR status
2. Review any failing CI checks
3. Respond to review comments
4. Update PR description if needed
```

---

## Popular MCP Servers Quick Reference

```bash
# GitHub — issues, PRs, code search
claude mcp add --transport http github https://api.githubcopilot.com/mcp/

# Sentry — error monitoring
claude mcp add --transport http sentry https://mcp.sentry.dev/mcp

# Notion — docs and pages
claude mcp add --transport http notion https://mcp.notion.com/mcp

# Slack — channels and messages (use /mcp to auth)
claude mcp add --transport http slack https://mcp.slack.com/mcp

# PostgreSQL database
claude mcp add --transport stdio postgres \
  -- npx -y @bytebase/dbhub \
  --dsn "postgresql://user:pass@localhost:5432/mydb"

# Local filesystem
claude mcp add --transport stdio filesystem \
  -- npx -y @modelcontextprotocol/server-filesystem /path/to/allow

# Playwright browser automation
claude mcp add --transport stdio playwright \
  -- npx -y @playwright/mcp@latest
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Connection closed" on Windows | Wrap with `cmd /c`: `-- cmd /c npx -y package` |
| Server not showing up | Run `/mcp` to check status |
| OAuth flow fails | Use "Clear authentication" in `/mcp` and retry |
| Large MCP output truncated | Set `MAX_MCP_OUTPUT_TOKENS=50000` env var |
| Too many tools consuming context | `ENABLE_TOOL_SEARCH=auto` (default) or `=true` |
| Server requires specific startup time | Set `MCP_TIMEOUT=30000` (30 seconds) |
