# 01 · Architecture

## The big picture

```
        Slack / Telegram / webhooks                 OpenRouter (models)
                  │                                        ▲
                  ▼                                        │
        ┌───────────────────────────────────────────────────────────┐
        │                     OpenClaw Gateway                        │
        │   (systemd user service · node · ws://127.0.0.1:18789)      │
        │                                                             │
        │   channels ──► router ──► agents ──► tools / skills / MCP   │
        │                              │                              │
        │     cron · hooks · memory(qmd) · plugins · sessions         │
        └───────────────────────────────────────────────────────────┘
                  │                         │
                  ▼                         ▼
        ~/.openclaw/  (state)      Tailscale serve (remote access)
```

- **Gateway** — the one long-lived process. Owns the websocket/RPC, the HTTP endpoints (incl. an OpenAI-compatible `/chat/completions`), the Control UI/dashboard, channel connections, the scheduler (cron), webhooks (hooks), and the agent runtime. Started by systemd; the CLI talks to it over the loopback websocket.
- **Channels** — inbound/outbound message transports. This deployment uses **Slack** in socket mode. DMs are gated by `dmPolicy: pairing` + an `allowFrom` user list; channels are explicitly enabled by ID.
- **Agents** — named runtimes (`main`, `qa`, `critic`, `coder`, `standup`, `jira-ops`). Each has its own workspace dir, model routing, and tool allow/deny. `main` is the default and may spawn subagents (`qa`, `critic`, `coder`).
- **Models** — provided through **OpenRouter** (one provider, many models). Each agent picks a `primary` and `fallbacks`.
- **Tools** — built-in capabilities (`exec`, `read`, `write`, `edit`, `browser`, `web_fetch`, `web_search`, `message`, `cron`, `memory_*`, …) gated per agent.
- **Skills / Plugins / MCP** — three extension mechanisms (see `docs/07`). Skills are CLI-tool packs; plugins extend the gateway (search, memory, browser, channels); MCP servers add remote tool endpoints.
- **Memory** — backed by **qmd**, indexing workspace markdown + session history; augmented by `memory-core` (incl. "dreaming") and `memory-wiki` plugins.
- **Cron + Hooks** — scheduled agent runs (daily digests, standups) and inbound webhooks (Jira) that wake an agent.

## State directory: `~/.openclaw/`

| Path | What it holds |
|------|---------------|
| `openclaw.json` | **Master config** (the only file you normally edit) |
| `secrets.json` | SecretRef values (tokens/keys), `mode: json`, `chmod 600` |
| `secrets/*.env` | Env files for the systemd unit (e.g. `openrouter.env`) |
| `agents/<id>/` | Per-agent state: `sessions/`, optional `agent/models.json` override |
| `workspace*/` | Agent working dirs (`workspace`, `workspace-qa`, `workspace-coder`, …) |
| `cron/jobs.json` | Scheduled jobs |
| `tasks/`, `flows/` | TaskFlow state |
| `plugins/`, `plugin-state/`, `plugin-skills/` | Plugin install index + state |
| `skills/`, `skill-workshop/` | Installed skills |
| `memory/`, `wiki/`, `qmd/` | Memory + wiki index |
| `logs/` | `commands.log`, `config-audit.jsonl`, `stability/` crash reports |
| `identity/`, `devices/`, `credentials/` | Device pairing + auth |
| `*.bak`, `*.clobbered.*` | Automatic config snapshots (safe to prune) |

> The proliferation of `openclaw.json.bak*` / `.clobbered.*` files is normal — OpenClaw snapshots config on every mutation. It is also a smell that config has been hand-edited a lot; prefer `openclaw config set`.

## Process & networking

- Runs as **systemd user service** `openclaw-gateway.service`. `loginctl enable-linger` keeps it alive without an active login.
- Binds **loopback only** (`gateway.bind: loopback`), port `18789`.
- Remote access is via **Tailscale serve** (`gateway.tailscale.mode: serve`) → `https://<host>.<tailnet>.ts.net`. Auth is a token from `secrets.json` (`gateway.auth.token`), with `allowTailscale: true`.
- An optional **ClawMetry** dashboard service runs separately (Python venv, port 8900).

## Versions observed on the reference host

- OpenClaw `2026.6.8`, clawhub `0.18.0`
- Node `22.22.3`, npm `10.9.8`, Ubuntu kernel `6.14`
- Installed via `npm -g` → binary symlinked at `~/.npm-global/bin/openclaw`
