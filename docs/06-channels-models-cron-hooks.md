# 06 · Channels, Models, Cron & Hooks

## Slack channel

OpenClaw connects to Slack in **socket mode** (`channels.slack.mode: socket`) — an outbound websocket, so no public inbound URL is required.

### Tokens (SecretRefs)
- `botToken` → `xoxb-…` (bot user OAuth token)
- `appToken` → `xapp-…` (app-level token with `connections:write` for socket mode)

Created in the Slack app config (api.slack.com/apps). Scopes typically include `chat:write`, `channels:history`, `groups:history`, `im:history`, `reactions:write`, `commands`, `app_mentions:read`.

### Access control
```jsonc
"dmPolicy": "pairing",                 // DMs require pairing approval
"allowFrom": ["Uxxxx", ...],           // Slack user ids allowed to DM the bot
"groupPolicy": "open",
"channels": {                          // channels the bot listens in, by id
  "Cxxxx": { "enabled": true },
  "Cyyyy": { "enabled": true, "allowBots": "mentions" }  // respond to other bots only on @mention
}
```
- Find ids: `openclaw directory self|peers|groups`, or Slack → right-click channel → copy link.
- `openclaw pairing` approves inbound DM pairing requests.
- **Owner**: also set `commands.ownerAllowFrom` (see `docs/03`) to grant privileged-command rights to your user — separate from DM access.

### UX
```jsonc
"slashCommand": { "enabled": true, "name": "openclaw", "ephemeral": true },  // /openclaw …
"streaming": { "mode": "partial", "nativeTransport": true,
               "preview": { "toolProgress": true, "commandText": "status" } },
"thread": { "historyScope": "thread", "initialHistoryLimit": 20 },
"ackReaction": "eyes"   // 👀 reaction acknowledges receipt
```

### Slack formatting rules for agents
No markdown tables (use bullet lists), use `<@USERID>` mentions, reply in-thread where the message originated. These are enforced in the workspace `AGENTS.md`.

## Models & routing

- One provider: **OpenRouter** (`models.providers.openrouter`), key from `OPENROUTER_API_KEY`.
- Models referenced as `openrouter/<vendor>/<model>`.
- Each agent sets `model.primary` + `model.fallbacks` — on primary failure/ratelimit, the next is tried.
- `agents.defaults.models["<id>"].streaming: true` enables token streaming per model.

| Model | Use |
|-------|-----|
| `google/gemini-3.1-flash-lite` | cheap/fast default chat (1M ctx) |
| `x-ai/grok-4.3` | strong reasoning (critic) |
| `moonshotai/kimi-k2.6` | coding (coder) |
| `qwen/qwen3.6-35b-a3b` | coding fallback |
| `ibm-granite/granite-4.1-8b` | cheap routine summaries (standup, jira-ops) |
| `openai/gpt-chat-latest`, `perceptron/perceptron-mk1` | available, situational |

```bash
openclaw models list
openclaw models set <agent> <provider/model>
openclaw capability <…>     # probe provider capabilities
```

## Cron (scheduled agent runs)

Jobs live in `~/.openclaw/cron/jobs.json`; manage with the CLI.
```bash
openclaw cron list
openclaw cron show <job-id>
openclaw cron add …   # see --help
```
Reference jobs: `ai-news-daily-digest`, `competitor-intelligence`, `daily-roaster-report`, `openclaw-stable-release`, `Memory Dreaming`, `Weekly Stale Ticket Review`. Each is `isolated` (own session) and most `announce` results to a Slack channel.

> **Gotcha 1 — pinning bypasses fallback:** a job with `payload.model` set does **not** inherit `agents.defaults.model` **and bypasses the agent's fallback chain**. Pinning a rate-limited free model (e.g. `ibm-granite/granite-4.1-8b`) therefore makes the job fail hard (`FailoverError: rate_limit`) instead of failing over. Pin only reliable models, or omit `payload.model` to inherit the default + fallbacks.
>
> **Gotcha 2 — masked errors:** cron delivery errors surface as a generic `⚠️ ✉️ Message failed`. To get the *real* cause, run the job in debug and wait for the result:
> ```bash
> openclaw cron run <job-id> --wait --expect-final --wait-timeout 300s
> # inspect run.errorReason / run.error  (e.g. rate_limit, not a Slack problem)
> ```
> Manage jobs: `openclaw cron disable|enable|edit|rm <id>`, `openclaw cron runs --id <id>` for history.

## Hooks (inbound webhooks)

`hooks.path: /hooks`, authenticated by `hooks.token` (SecretRef). Mappings route a webhook path to an action:
```jsonc
{ "match": { "path": "jira" }, "action": "agent", "wakeMode": "now",
  "messageTemplate": "Jira webhook: {{webhookEvent}} on {{issue.key}} … post to Slack <channel> or NO_REPLY",
  "deliver": false }
```
- Caller POSTs to `https://<host>/hooks/jira` with the token → wakes an agent with the templated message.
- `{{...}}` placeholders interpolate the webhook JSON payload.
- `deliver: false` = the agent decides whether to post (it can reply `NO_REPLY`).

### Internal hooks
Lifecycle hooks that ship with OpenClaw (`hooks.internal.entries`): `boot-md` (inject boot files), `command-logger`, `session-memory`, `bootstrap-extra-files`. Keep enabled unless debugging.
