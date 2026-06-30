# 03 · Configuration Reference (`openclaw.json`)

The complete annotated walkthrough of `config/openclaw.json`. JSON can't carry comments, so this file is the comment layer. Keys are grouped top-level as they appear in the file.

> Edit on the host with `openclaw config set <dot.path> '<json>'` (atomic, snapshots, validates) rather than a text editor when possible. Read with `openclaw config get <dot.path>`.

---

## `meta` / `update`
```jsonc
"meta":   { "lastTouchedVersion": "2026.6.8" },   // written by the CLI; informational
"update": { "checkOnStart": true, "channel": "stable" }  // auto update-check on boot
```

## `browser`
Headless Chrome for the `browser` tool.
```jsonc
"browser": {
  "enabled": true,
  "executablePath": "/usr/bin/google-chrome-stable",
  "headless": true,
  "noSandbox": true,            // required when running as a service user / in containers
  "defaultProfile": "openclaw",
  "evaluateEnabled": true       // allow page.evaluate(); disable for stricter sandboxing
}
```

## `auth`
Named auth profiles bound to providers.
```jsonc
"auth": { "profiles": { "openrouter:default": { "provider": "openrouter", "mode": "api_key" } } }
```

## `models.providers`
One entry per model provider. This deployment uses **OpenRouter** exclusively — a single API that proxies many vendors' models, so you manage one key.
```jsonc
"openrouter": {
  "baseUrl": "https://openrouter.ai/api/v1",
  "auth": "api-key",
  "api": "openai-completions",                       // OpenAI-compatible wire format
  "apiKey": { "source": "env", "provider": "default", "id": "OPENROUTER_API_KEY" }, // from process env
  "models": [ { "id": "<vendor>/<model>", "name": "...", "contextWindow": N }, ... ]
}
```
- Model ids are referenced elsewhere as `openrouter/<vendor>/<model>` (provider prefix + id).
- `contextWindow` informs context-pruning/compaction math.
- The key comes from the **environment** (`OPENROUTER_API_KEY`), supplied by the systemd `EnvironmentFile`. (Other secrets use the file-based SecretRef provider — see `docs/04`.)

## `agents`
Two parts: `defaults` (inherited by all agents) and `list` (per-agent overrides).

### `agents.defaults`
```jsonc
"model": { "primary": "openrouter/google/gemini-3.1-flash-lite",
           "fallbacks": ["openrouter/ibm-granite/granite-4.1-8b"] },
"models": { "<provider/model>": { "streaming": true }, ... },  // per-model runtime flags
"workspace": "~/.openclaw/workspace",
"contextPruning": { "mode": "cache-ttl", "ttl": "1h", "keepLastAssistants": 3 },
"compaction": {                       // what to do as context fills
  "mode": "safeguard",
  "memoryFlush": { "enabled": true, "softThresholdTokens": 4000,
                   "prompt": "...store durable memories now...",
                   "systemPrompt": "..." }
},
"heartbeat": { "every": "1h" },       // periodic wake (see HEARTBEAT.md to make it a no-op)
"maxConcurrent": 4,                   // concurrent turns per agent
"subagents": { "maxConcurrent": 8, "runTimeoutSeconds": 1800 },
"timeoutSeconds": 600,                // per-turn timeout
"bootstrapMaxChars": 10000,           // max chars injected PER bootstrap file
"bootstrapTotalMaxChars": 80000,      // max chars injected across ALL bootstrap files
"contextInjection": "continuation-skip"
```
> `bootstrapMaxChars` is why a large `MEMORY.md` gets truncated (see `docs/09`). Raise it or trim the file.

### `agents.list[]`
Each agent overrides defaults:
```jsonc
{
  "id": "main", "default": true, "name": "OpenClaw",
  "workspace": "~/.openclaw/workspace",
  "model": { "primary": "...", "fallbacks": ["..."] },
  "subagents": { "allowAgents": ["qa", "critic", "coder"] },  // who main may spawn
  "tools": { "deny": ["canvas", "nodes"], "profile": "full" } // tool gating (docs/05)
}
```
The roster and rationale are in `docs/05-agents-and-tools.md`.

## `tools`
Global tool config (not per-agent gating).
```jsonc
"tools": {
  "web": { "search": { "enabled": true, "provider": "brave", "maxResults": 5, "timeoutSeconds": 30 },
           "fetch":  { "enabled": true } },
  "sessions": { "visibility": "all" },
  "profile": "coding"            // default tool profile
}
```

## `messages`
Channel message handling.
```jsonc
"groupChat": { "historyLimit": 20 },
"queue":   { "mode": "followup", "byChannel": { "slack": "followup" }, "debounceMs": 3000 },
"inbound": { "debounceMs": 3000, "byChannel": { "slack": 3000 } },  // coalesce bursts
"ackReaction": "eyes", "ackReactionScope": "all",                   // 👀 on receipt
"tts": { "provider": "none" }
```

## `commands`
Slash/owner command behavior.
```jsonc
"native": "auto", "nativeSkills": "auto",
"restart": true,                 // allow /restart
"ownerDisplay": "raw",
"ownerAllowFrom": ["slack:UXXXXXXXX"]  // ⚠ who can run owner-only/privileged commands + approvals
```
> If `ownerAllowFrom` is unset, **no one** is the privileged operator and doctor warns. DM pairing ≠ owner. Set this to your channel user id.

## `session`
```jsonc
"session": { "dmScope": "per-channel-peer" }   // isolate DM sessions per (channel, peer)
```

## `hooks`
Inbound webhooks + internal lifecycle hooks.
```jsonc
"hooks": {
  "enabled": true, "path": "/hooks",
  "token": { "source": "file", "provider": "filemain", "id": "/hooks/token" }, // SecretRef, not inline
  "mappings": [ { "match": { "path": "jira" }, "action": "agent", "wakeMode": "now",
                 "messageTemplate": "Jira webhook: ... post to Slack <channel> or reply NO_REPLY",
                 "deliver": false } ],
  "internal": { "enabled": true, "entries": {
      "boot-md": {...}, "command-logger": {...}, "session-memory": {...}, "bootstrap-extra-files": {...} } }
}
```
See `docs/06`. The webhook `token` MUST be a SecretRef (the live host had it inline — fix in `DIAGNOSIS.md`).

## `channels.slack`
Full Slack reference is `docs/06`. Key fields:
```jsonc
"mode": "socket",                       // socket mode (no public webhook needed)
"botToken"/"appToken": <SecretRef>,
"dmPolicy": "pairing", "allowFrom": ["Uxxxx", ...],   // gate DMs
"channels": { "Cxxxx": { "enabled": true, "allowBots": "mentions" } },
"slashCommand": { "enabled": true, "name": "openclaw", "ephemeral": true },
"streaming": { "mode": "partial", "nativeTransport": true }
```

## `gateway`
```jsonc
"port": 18789, "mode": "local", "bind": "loopback",
"controlUi": { "enabled": true, "allowInsecureAuth": true },  // dashboard
"auth": { "mode": "token", "token": <SecretRef>, "allowTailscale": true },
"tailscale": { "mode": "serve", "resetOnExit": false },       // remote access
"http": { "endpoints": { "chatCompletions": { "enabled": true } } }, // OpenAI-compatible API
"nodes": { "denyCommands": ["camera.snap", "screen.record", ...] }   // device-node safety
```
> `tailscale.mode: serve` (private tailnet) needs token auth. `funnel` (public) requires `gateway.auth.mode: password` — mixing them caused historic startup failures on the reference host.

## `memory`
```jsonc
"backend": "qmd",
"qmd": { "command": "~/.bun/bin/qmd", "searchMode": "search", "includeDefaultMemory": true,
         "paths": [ { "path": "~/.openclaw/workspace", "name": "workspace-context", "pattern": "*.md" }, ... ],
         "sessions": { "enabled": true, "retentionDays": 30 },
         "scope": { "default": "allow" } }
```
See `docs/07`.

## `skills`
```jsonc
"install": { "nodeManager": "pnpm" },
"entries": { "<skill>": { "enabled": true|false }, ... }   // 90+ skills, most disabled
```
Only enabled skills load. The standard config keeps the enabled set small (`clawhub`, `session-logs`, `taskflow-inbox-triage`). See `docs/07` + `docs/10` for proposed additions.

## `plugins`
```jsonc
"allow": ["brave", "browser", "duckduckgo", "memory-core", "memory-wiki", "ollama", "openrouter", "slack"],
"entries": { "<plugin>": { "enabled": bool, "config": {...} } },
"bundledDiscovery": "compat"
```
`allow` is the load allowlist; `entries` enables/configures each. Plugin details in `docs/07`.

## `secrets`
The SecretRef resolver. **Read `docs/04` before editing anything secret.**
```jsonc
"secrets": { "providers": { "filemain": { "source": "file", "path": "~/.openclaw/secrets.json", "mode": "json" } } }
```

## `mcp`
Remote tool servers (Model Context Protocol).
```jsonc
"mcp": { "servers": { "vexa": {
  "url": "https://<host>/mcp", "transport": "streamable-http",
  "headers": { "X-API-Key": <SecretRef> } } } }   // header key MUST be a SecretRef, not inline
```
