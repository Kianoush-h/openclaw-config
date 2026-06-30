# 04 · Secrets & SecretRefs

OpenClaw keeps credentials **out of** `openclaw.json`. Instead, secret-bearing fields hold a **SecretRef** — a pointer that the gateway resolves at runtime from a secrets provider.

## The SecretRef shape

```jsonc
{ "source": "file", "provider": "filemain", "id": "/slack/botToken" }
```
- `source` — resolver kind (`file` here; `env` is also used for the OpenRouter key).
- `provider` — which configured provider to use (`filemain`).
- `id` — a path that maps into the provider's data. For the JSON file provider, `/slack/botToken` → `secrets.slack.botToken`.

The provider is declared once:
```jsonc
"secrets": { "providers": {
  "filemain": { "source": "file", "path": "~/.openclaw/secrets.json", "mode": "json" } } }
```

## `~/.openclaw/secrets.json`

A plain JSON tree, `chmod 600`, **never committed**. Its shape (values redacted) on the reference host:
```json
{
  "gateway": { "authToken": "…" },
  "slack":   { "botToken": "xoxb-…", "appToken": "xapp-…" },
  "brave":   { "apiKey": "…" }
}
```
The standard config adds two more so nothing is left inline (see `config/secrets.example.json`):
```json
{ "hooks": { "token": "…" }, "vexa": { "apiKey": "…" } }
```

`id` → file mapping:
| SecretRef `id` | secrets.json path | Used by |
|----------------|-------------------|---------|
| `/gateway/authToken` | `gateway.authToken` | `gateway.auth.token` |
| `/slack/botToken` | `slack.botToken` | `channels.slack.botToken` |
| `/slack/appToken` | `slack.appToken` | `channels.slack.appToken` |
| `/brave/apiKey` | `brave.apiKey` | `plugins.entries.brave` |
| `/hooks/token` | `hooks.token` | `hooks.token` |
| `/vexa/apiKey` | `vexa.apiKey` | `mcp.servers.vexa` header |

## The two secret channels

1. **File provider (`filemain`)** — most secrets. Edit `~/.openclaw/secrets.json`, then `openclaw secrets reload` (or restart).
2. **Process env** — the OpenRouter model key. `models.providers.openrouter.apiKey` is `{ source: env, id: OPENROUTER_API_KEY }`. The gateway reads it from its environment, supplied by the systemd drop-in:
   ```ini
   # ~/.config/systemd/user/openclaw-gateway.service.d/env.conf
   [Service]
   EnvironmentFile=/home/USER/.openclaw/secrets/openrouter.env
   ```
   `openrouter.env` (mode 600) contains `OPENROUTER_API_KEY=sk-or-…`.

## CLI

```bash
openclaw secrets audit       # find inline secrets / missing refs / weak perms
openclaw secrets apply       # write/refresh SecretRef-backed credentials
openclaw secrets reload      # re-read providers without a full restart
```

## Hard rules

- **Never** put a literal token in a tracked file. If you must reference a new secret, add it to `secrets.json` and point a SecretRef at it.
- `secrets.json` and `secrets/*.env` are **`chmod 600`** and **git-ignored**.
- Don't echo secrets into logs, Slack, or memory files. The workspace `SOUL.md`/`AGENTS.md` instruct agents to redact.
- Rotating a key = edit `secrets.json` (or the `.env`) → `openclaw secrets reload` (or restart) → revoke the old key upstream.

## Known hygiene gaps on the reference host (see DIAGNOSIS.md)

- `hooks.token` was stored **inline** in `openclaw.json` → moved to SecretRef `/hooks/token`.
- `mcp.servers.vexa.headers["X-API-Key"]` was **inline** → moved to SecretRef `/vexa/apiKey`.
- `OPENROUTER_API_KEY` was **inlined in the systemd unit** → moved to `EnvironmentFile`.
