# AGENTS.md — Operator Guide for this Repo

You are an LLM (or human) using this repo to **set up, understand, or repair** an OpenClaw deployment. Read this before changing anything.

## What OpenClaw is (60-second model)

- A **gateway** daemon (`openclaw gateway`) runs persistently (systemd user service, port `18789`).
- It bridges **channels** (Slack, Telegram, …) to a roster of **agents**.
- Each **agent** = a workspace dir + a primary/fallback **model** + an allow/deny **tool** set.
- One master file controls everything: `~/.openclaw/openclaw.json`. State lives under `~/.openclaw/`.
- **Secrets** are never inline — they are `SecretRef` pointers resolved from `~/.openclaw/secrets.json`.
- The `openclaw` CLI is how you operate it: `status`, `health`, `doctor`, `config`, `cron`, `agents`, `plugins`, `skills`, `logs`.

## How to apply this repo

| Goal | Do this |
|------|---------|
| Stand up a new host | Follow `README.md` Quickstart or run `scripts/install.sh` |
| Understand a running host | Read `docs/`, then run `openclaw status` / `openclaw doctor` on the host |
| Change config | Edit `~/.openclaw/openclaw.json` on the host → `openclaw config validate` → `openclaw doctor` → restart |
| Diagnose "buggy" behavior | Work through `DIAGNOSIS.md` items in order |

## Placeholders you MUST replace in `config/openclaw.json`

Everything `REPLACE_WITH_*` is a stub:
- `commands.ownerAllowFrom` → your operator's `slack:UXXXXXXXX` id (privileged commands & approvals).
- `channels.slack.allowFrom` → Slack user IDs allowed to DM the bot.
- `channels.slack.channels` → Slack channel IDs the bot listens in.
- `hooks.mappings[].messageTemplate` channel id → where webhook summaries post.
- `mcp.servers.vexa.url` → your MCP server host (or delete the `mcp` block).

## Safety rules (non-negotiable)

1. **Secrets never enter git.** If you see a real token (`xoxb-`, `sk-or-`, `xapp-`, hex auth tokens) about to be written to a tracked file, stop and convert it to a SecretRef.
2. **Validate before restart.** A bad `openclaw.json` makes the gateway exit 78 and (by design) it will not auto-restart.
3. **One change at a time on the live host.** Snapshot first: `cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak.$(date +%s)`.
4. **Destructive ops need explicit approval.** Clearing sessions, cancelling TaskFlows, removing plugins — state the blast radius, then wait for a human "yes."
5. **`trash` over `rm`**, and prefer `openclaw <subcommand>` over hand-editing state files (sessions, cron, plugin index live in SQLite + JSON; the CLI keeps them consistent).

## Validate / apply loop (on the host)

```bash
openclaw config validate                 # schema check
openclaw config get agents.defaults.model # read a key
openclaw config set <path> '<json>'      # write a key (keeps backups)
openclaw doctor                          # full health pass
openclaw doctor --fix                    # apply safe repairs (review proposal first)
systemctl --user restart openclaw-gateway.service
openclaw status                          # confirm healthy
```

## When something is "buggy"

Run `openclaw doctor` first — it surfaces config-schema errors, stale session routing, plugin-index conflicts, blocked TaskFlows, cron drift, and secret hygiene. Most issues map to a one-line fix. See `docs/09-troubleshooting.md` and `DIAGNOSIS.md`.
