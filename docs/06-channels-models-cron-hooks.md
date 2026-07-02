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

### Cron delivery: `announce` vs the agent's own posting (avoid double-posts)

A cron job can deliver its result two ways, and using **both** spams the channel:
- **`announce`** (`delivery.mode: announce`, set via `--announce`) — the runner posts the agent's **final response text** to `delivery.to`.
- **The agent's `message` tool** — if the prompt tells the agent to "post to channel X", the agent posts there itself.

If the prompt says "post to the channel" **and** `announce` is on, you get **two posts** per run: the real deliverable (tool) + a chatty "has been posted…" confirmation (announce). Observed live on the reference host's `daily-roaster-report`.

Rules of thumb:
- **Posting to the SAME channel as `delivery.to` (most report jobs)** → prefer **announce-only**: `--announce` + prompt tells the agent to **output the deliverable as its reply and NOT call any message-send tool** (`NO_REPLY` to skip). This is deterministic — exactly one post, or none.
- **Posting to a DIFFERENT channel than `delivery.to`** (e.g. the competitor digest posts to its own channel) → the agent *must* tool-post; set **`--no-deliver`** so the runner doesn't also announce to the wrong channel.
- **Silent when nothing to report** → have the prompt reply with exactly `NO_REPLY` (suppresses delivery). Don't rely on the agent's status text — with `announce` on, that status becomes a post.

⚠️ **Gotcha (live #13):** `--no-deliver` (tool-only delivery) assumes the agent *reliably* calls message-send. It doesn't — the same prompt on a cheap model will sometimes just **output the report as text** expecting `announce` to deliver it. With `announce` off, that run posts **nothing** (a silent miss). For a same-channel job, announce-only avoids this because the agent's reply is always delivered. Only use `--no-deliver` when the agent genuinely must post elsewhere via the tool.

Inspect/repair: `openclaw cron get <id>` shows `delivery.mode`; `openclaw cron edit <id> --no-deliver` / `--announce --channel slack --to <id>` toggles it. Reading a run's session trajectory (`~/.openclaw/agents/<agent>/sessions/<id>.jsonl`) shows whether the agent tool-posted or only replied.

### Scheduled reports that summarize chat activity: gate on real same-day data

A cron job that "reads a channel and summarizes today's posts" (standup roaster, digest, etc.) will **fabricate or echo stale data on off days** unless the prompt guards its inputs. A weekday cron (`* * * * 1-5`) still fires on holidays, and an unguarded prompt that says "scan since the last report / account for timezone differences" will grab the previous day's posts when today is empty. Bake these guards into the prompt:

1. **Date/holiday gate (first step):** determine today's date/weekday in the target timezone; if weekend or a listed statutory holiday → reply `NO_REPLY`, post nothing. (Keep a per-year holiday list; update it yearly.)
2. **Strict same-day matching:** count only source posts actually made *today*; never include, infer, carry over, or reuse prior-day posts — or the agent's own past reports.
3. **Empty-input gate:** if there is no real source data today (zero posts) → `NO_REPLY`, post nothing. Never fabricate or reuse to "fill" an empty run.
4. Combine with `--no-deliver` (see above) so the agent's single tool post is the only post.

This was live issue #13: the standup roaster ran on Canada Day with zero posts and re-posted the prior workday's data as "today". The `NO_REPLY` sentinel suppresses delivery, so gates 1–3 make the job silently skip off days.

### Internal hooks
Lifecycle hooks that ship with OpenClaw (`hooks.internal.entries`): `boot-md` (inject boot files), `command-logger`, `session-memory`, `bootstrap-extra-files`. Keep enabled unless debugging.
