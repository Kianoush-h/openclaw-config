# 07 · Memory, Skills, Plugins & MCP

Four distinct extension/state systems. Don't confuse them:

| System | What it is | Configured under |
|--------|-----------|------------------|
| **Memory** | Long-term recall over markdown + sessions | `memory` + `memory-core`/`memory-wiki` plugins |
| **Skills** | CLI tool packs the agent can invoke | `skills.entries` |
| **Plugins** | Gateway extensions (search, browser, channels, memory) | `plugins` |
| **MCP** | Remote tool servers over Model Context Protocol | `mcp.servers` |

---

## Memory

Backend is **qmd** (a markdown query/index tool at `~/.bun/bin/qmd`).
```jsonc
"memory": { "backend": "qmd", "qmd": {
  "command": "~/.bun/bin/qmd", "searchMode": "search", "includeDefaultMemory": true,
  "paths": [ { "path": "~/.openclaw/workspace", "name": "workspace-context", "pattern": "*.md" },
             { "path": "~/.openclaw/workspace/shared", "name": "shared-findings", "pattern": "**/*.md" } ],
  "sessions": { "enabled": true, "retentionDays": 30 },
  "scope": { "default": "allow" } } }
```
- Indexes workspace markdown (`MEMORY.md`, `memory/YYYY-MM-DD.md`, daily notes) and session history (30-day retention).
- Agents query via `memory_search` / `memory_get` tools.
- **memory-core** plugin adds "dreaming" (`dreaming.enabled: true`) — periodic consolidation of memories into `DREAMS.md`.
- **memory-wiki** plugin maintains a wiki/vault at `~/.openclaw/wiki/main` in `bridge` mode, auto-indexing memory artifacts, dream reports, daily notes, and creating backlinks/dashboards.

```bash
openclaw memory search "<query>"
openclaw memory reindex
```

## Skills

Skills are tool packs (often CLI wrappers) discovered by clawhub. The reference host has **90+ skills defined, almost all disabled** — only load what you use.

Enabled in the standard config:
- `clawhub` — skill registry/installer
- `session-logs` — session log access
- `taskflow-inbox-triage` — triage TaskFlow inbox

```bash
openclaw skills list
openclaw skills inspect <name>
openclaw skills install <name>     # uses pnpm (skills.install.nodeManager)
```
Enable/disable via `skills.entries.<name>.enabled`.

### Proposed additions (opt-in, see docs/10)
Useful, low-risk skills to standardize on: `github`/`gh-issues` (repo + issue ops), `weather`, `summarize`, `diagram-maker`. Enable deliberately — each adds tools and prompt surface.

## Plugins

```jsonc
"plugins": {
  "allow": ["brave","browser","duckduckgo","memory-core","memory-wiki","ollama","openrouter","slack"],
  "entries": { "<name>": { "enabled": bool, "config": {...} } } }
```
Loaded on the reference host (7): `slack`, `brave`, `duckduckgo`, `browser`, `openrouter`, `memory-core`, `memory-wiki`. (`ollama` allowed but disabled.) Doctor also reports ~90 disabled bundled plugins — normal.

| Plugin | Role |
|--------|------|
| `slack` | Slack channel transport |
| `brave` | Brave web search (key via SecretRef `/brave/apiKey`) |
| `duckduckgo` | Fallback web search (no key) |
| `browser` | Headless Chrome tool |
| `openrouter` | Model provider plumbing |
| `memory-core` | Memory + dreaming |
| `memory-wiki` | Wiki/vault bridge |

```bash
openclaw plugins list
openclaw plugins enable|disable <name>
```

### Plugin install state: JSON → SQLite

Install bookkeeping lives in a shared **SQLite** registry (rebuildable with `openclaw plugins registry --refresh`). A legacy `~/.openclaw/plugins/installs.json` may linger from older versions; if its records conflict with SQLite, the migration keeps the JSON and warns on every command. Make SQLite authoritative (`registry --refresh`) and retire the JSON — full procedure in `docs/09`. Don't hand-edit `installs.json`. (This was live issue #2, now resolved.)

## MCP (Model Context Protocol)

Remote tool servers the gateway connects to:
```jsonc
"mcp": { "servers": { "vexa": {
  "url": "https://<host>/mcp", "transport": "streamable-http",
  "headers": { "X-API-Key": <SecretRef> } } } }
```
- `vexa` is a custom MCP endpoint; its API key MUST be a SecretRef (was inline on the host — fix in `DIAGNOSIS.md`).
```bash
openclaw mcp list
openclaw mcp add <name> --url <url> --transport streamable-http
```

### Proposed additions (opt-in)
Standard MCP servers worth considering: a GitHub MCP, a filesystem/docs MCP, or an internal tools MCP — added the same way, always with header/keys as SecretRefs.
