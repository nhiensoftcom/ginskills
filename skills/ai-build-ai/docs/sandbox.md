# Tutorial: Sandboxing

Claude Code's sandbox restricts what bash commands and their child processes can do at the **OS level** — independent of Claude's permission rules.

---

## Step 1: Understand How Sandboxing Works

The sandbox adds OS-level enforcement ON TOP of Claude's permission system:

| Layer | What it controls | How to configure |
|-------|-----------------|-----------------|
| **Permissions** | Which tools Claude can call | `.claude/settings.json` permissions |
| **Sandbox** | What bash commands can access at OS level | `/sandbox` or `settings.json` sandbox config |

Both layers run independently. A command can pass Claude's permission check but still be blocked by the sandbox if it tries to access a restricted path or network domain.

### Platform Support

| Platform | Implementation | Prerequisites |
|----------|---------------|--------------|
| macOS | Seatbelt (built-in) | None |
| Linux / WSL2 | bubblewrap + socat | `sudo apt-get install bubblewrap socat` |
| WSL1 | ❌ Not supported | Requires WSL2 kernel features |
| Windows native | Planned | Not yet available |

---

## Step 2: Enable Sandboxing

```bash
# Toggle in the current session
/sandbox
```

This opens a mode selection menu. Choose:

1. **Auto-allow mode** — Sandboxed bash commands run automatically without prompts. Commands that can't be sandboxed fall through to normal permissions.
2. **Regular permissions mode** — All commands still go through standard permission prompts, but are also sandboxed at OS level.

Or enable permanently in `.claude/settings.json`:

```json
{
  "sandbox": {
    "enabled": true
  }
}
```

---

## Step 3: Default Filesystem Behavior

By default, sandboxed commands can:
- **Read**: all of your filesystem EXCEPT explicitly denied directories
- **Write**: ONLY the current working directory and subdirectories

All restrictions apply to child processes too (kubectl, terraform, npm scripts, etc.).

---

## Step 4: Configure Filesystem Rules

```json
{
  "sandbox": {
    "filesystem": {
      "allowWrite": ["//tmp/build", "~/.kube/cache"],
      "denyWrite": ["/src/secrets/**"],
      "denyRead": ["~/.ssh/", "~/.aws/credentials"]
    }
  }
}
```

### Path Prefix Convention

| Prefix | Meaning | Example |
|--------|---------|---------|
| `//` | Absolute filesystem path | `//tmp/build` → `/tmp/build` |
| `~/` | Home directory | `~/.kube` → `$HOME/.kube` |
| `/` | Relative to settings file directory | `/build` → `$SETTINGS_DIR/build` |
| `./` or none | Relative, runtime-resolved | `./output` |

**Arrays merge across config scopes.** If managed settings allow `//opt/company-tools` and you add `~/.kube`, both are active simultaneously.

---

## Step 5: Configure Network Rules

By default, no network filtering. To restrict outbound access from bash commands:

```json
{
  "sandbox": {
    "network": {
      "allowedDomains": [
        "registry.npmjs.org",
        "api.github.com",
        "*.internal.company.com"
      ],
      "blockedDomains": ["*.social-media.com"]
    }
  }
}
```

Network filtering works via a proxy running **outside** the sandbox — all subprocess traffic routes through it. When an unapproved domain is accessed:
- Blocked at OS level
- User gets immediate notification with options: deny, allow once, or permanently allow

**Important distinction:**
- `sandbox.network.allowedDomains` — controls what **bash commands** can reach
- `WebFetch(domain:x)` permission rules — controls what Claude's **WebFetch tool** can access
- These are completely separate controls

### Custom Proxy

For advanced logging, HTTPS inspection, or custom filtering:

```json
{
  "sandbox": {
    "network": {
      "httpProxyPort": 8080,
      "socksProxyPort": 8081
    }
  }
}
```

---

## Step 6: Exclude Specific Commands from Sandbox

Some tools are incompatible with the sandbox. Run them outside it entirely:

```json
{
  "sandbox": {
    "excludedCommands": ["docker", "git"]
  }
}
```

**Known incompatibilities:**
- `watchman` — incompatible with sandbox; use `jest --no-watchman` instead
- `docker` — incompatible; add to `excludedCommands`

---

## Step 7: The Escape Hatch

When a command fails due to sandbox restrictions, Claude can retry it with `dangerouslyDisableSandbox` — those retried commands bypass the sandbox and fall through to normal permission prompts.

To disable this escape hatch entirely:

```json
{
  "sandbox": {
    "allowUnsandboxedCommands": false
  }
}
```

When set to `false`, `dangerouslyDisableSandbox` is completely ignored — useful for stricter enterprise environments.

---

## Step 8: Full Configuration Example

```json
{
  "sandbox": {
    "filesystem": {
      "allowWrite": [
        "//tmp/**",
        "~/.npm/**",
        "~/Library/Caches/**"
      ],
      "denyWrite": [
        "~/.ssh/**",
        "~/.aws/**",
        "/etc/**"
      ],
      "denyRead": [
        "~/.ssh/id_rsa",
        "~/.aws/credentials"
      ]
    },
    "network": {
      "allowedDomains": [
        "registry.npmjs.org",
        "api.github.com",
        "pypi.org",
        "*.amazonaws.com"
      ]
    },
    "excludedCommands": ["docker"],
    "allowUnsandboxedCommands": false
  }
}
```

---

## Step 9: Sandbox + Permissions — How They Interact

| Tool | Permissions control | Sandbox applies? |
|------|--------------------|--------------------|
| `Read` tool | Yes — permission rules | No |
| `Edit` / `Write` tool | Yes — permission rules | No |
| `WebFetch` tool | Yes — `WebFetch(domain:x)` rules | No |
| `Bash` command | Yes — permission rules | **Yes** — OS-level enforcement |
| Bash child processes | Inherited from Bash | **Yes** — all child processes sandboxed |

**Key insight:** `Edit`/`Read` deny rules and `sandbox.filesystem.denyRead`/`denyWrite` are **merged** — both apply simultaneously. So `Edit(.env)` deny in permissions blocks the Edit tool, while `denyWrite: [".env"]` in sandbox blocks any bash command that tries to write `.env`.

---

## Step 10: Security Limitations to Know

1. **Network filtering does not inspect traffic content** — domain-level only; domain fronting may bypass it
2. **Broad domains** — allowing `github.com` could theoretically enable data exfiltration via repository uploads
3. **Unix sockets** — `allowUnixSockets` can grant sandbox bypass; allowing `/var/run/docker.sock` effectively grants host system access
4. **Filesystem write permissions** — allowing writes to `$PATH` dirs or shell configs (`.bashrc`, `.zshrc`) enables privilege escalation
5. **Weak nested sandbox** — `enableWeakerNestedSandbox: true` (for Docker environments without privileged namespaces) considerably weakens security

### Linux / WSL2 inside Docker

```json
{
  "sandbox": {
    "enableWeakerNestedSandbox": true
  }
}
```

Only use when additional isolation is enforced externally (e.g., the Docker container itself is isolated).

---

## Quick Reference

```bash
# Enable/disable sandbox interactively
/sandbox

# Open source sandbox runtime (sandbox arbitrary programs, including MCP servers)
npx @anthropic-ai/sandbox-runtime <command>

# Install prerequisites on Linux/WSL2
sudo apt-get install bubblewrap socat     # Ubuntu/Debian
sudo dnf install bubblewrap socat         # Fedora
```

**Sandbox applies to:** Bash commands and all their child processes.

**Sandbox does NOT apply to:** Read, Edit, Write, Glob, Grep, WebFetch, MCP tools.

**Rule priority:** `denyRead` / `denyWrite` always win over `allowWrite`.
