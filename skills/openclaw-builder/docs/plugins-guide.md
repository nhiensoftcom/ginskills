# Plugins — Extending OpenClaw

## What Are Plugins?

Plugins are TypeScript modules loaded at runtime that extend OpenClaw with extra features: new channels, tools, CLI commands, Gateway RPC, background services, and more.

**Plugins run in-process with the Gateway** — treat them as trusted code.

## Official Plugins

```bash
openclaw plugins list              # see all loaded plugins
openclaw plugins install <spec>    # install from npm
openclaw plugins list --available  # see what's available
```

| Plugin | Install | What it adds |
|--------|---------|-------------|
| Voice Call | `@openclaw/voice-call` | Voice call handling |
| Microsoft Teams | `@openclaw/msteams` | Teams channel |
| Zalo Personal | `@openclaw/zalouser` | Zalo personal account |
| Matrix | `@openclaw/matrix` | Matrix protocol |
| Nostr | `@openclaw/nostr` | Nostr protocol |
| Memory (LanceDB) | bundled | Long-term auto-recall memory |

## Install & Configure

```bash
# Install
openclaw plugins install @openclaw/voice-call

# Restart gateway to load
openclaw gateway restart

# Configure in openclaw.json under plugins.entries.<id>.config
```

```json5
// ~/.openclaw/openclaw.json
{
  plugins: {
    entries: {
      "voice-call": {
        enabled: true,
        config: {
          // plugin-specific config here
        }
      }
    }
  }
}
```

## What Plugins Can Do

- Register **Gateway RPC methods** and **HTTP routes**
- Add **agent tools** (available to the LLM)
- Add **CLI commands** (`openclaw <command>`)
- Run **background services**
- Ship **skills** (via `skills` directories in manifest)
- Register **channels** (e.g. Matrix, Teams)
- Register **auto-reply commands** (no AI invocation needed)

## Memory Plugins (Slots)

OpenClaw uses a "slot" system for swappable memory backends:

```json5
{
  plugins: {
    slots: {
      memory: "memory-core"      // default: in-process search
      // memory: "memory-lancedb"  // long-term auto-recall
      // memory: "none"            // disable memory tools
    }
  }
}
```

## Creating a Plugin

Minimum structure:

```
my-plugin/
├── openclaw.plugin.json    # manifest (required)
├── index.ts                # plugin entry point
└── skills/                 # optional skills directory
    └── my-skill/
        └── SKILL.md
```

### openclaw.plugin.json

```json
{
  "id": "my-plugin",
  "name": "My Plugin",
  "description": "Does something useful",
  "configSchema": {
    "type": "object",
    "additionalProperties": false,
    "properties": {
      "apiKey": { "type": "string" }
    }
  },
  "skills": ["./skills"]
}
```

### Plugin Entry (index.ts)

```typescript
export default function register(ctx) {
  // Register a tool
  ctx.registerTool({
    name: "my_tool",
    description: "Does something",
    inputSchema: { type: "object", properties: { input: { type: "string" } } },
    handler: async ({ input }) => ({ result: `Processed: ${input}` })
  });

  // Register a CLI command
  ctx.registerCommand("my-plugin do-thing", async (args) => {
    console.log("Doing thing...");
  });
}
```

## Security

- Plugins run **in-process** with full host access
- Only install plugins from trusted sources
- `openclaw plugins install` uses npm with `--ignore-scripts` by default
