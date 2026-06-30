# 08 · Workspace Bootstrap Files

Each agent has a **workspace** directory (`~/.openclaw/workspace`, `…-qa`, `…-coder`, …). At session start the gateway injects a set of markdown "bootstrap" files that define the agent's identity, instructions, and continuity. These are the *behavioral* config — as important as `openclaw.json`.

Templates live in `workspace-template/`. Copy them into a workspace and customize.

## The standard files

| File | Purpose | Injected when |
|------|---------|---------------|
| `SOUL.md` | Personality, values, boundaries, responsiveness norms | every session |
| `AGENTS.md` | Operating instructions: session start/end ritual, memory rules, safety, channel formatting | every session |
| `USER.md` | Who the agent serves (the human/org) | every session |
| `IDENTITY.md` | Name, avatar, emoji, vibe | every session |
| `TOOLS.md` | Local notes on tool/CLI specifics (paths, env vars, auth) | reference |
| `HEARTBEAT.md` | Periodic tasks; **empty = no heartbeat API calls** | heartbeat tick |
| `MEMORY.md` | Curated long-term memory (main sessions only) | main session |
| `memory/YYYY-MM-DD.md` | Daily raw logs | recent days |
| `memory/session-state.md` | "What I was doing last session" | every session |

## Injection limits

Controlled by `agents.defaults`:
- `bootstrapMaxChars` (10000) — max chars injected **per file**
- `bootstrapTotalMaxChars` (80000) — max across **all** files

> If `MEMORY.md` exceeds `bootstrapMaxChars` it is truncated (the reference host's 16KB `MEMORY.md` truncates ~39%). Either trim it (curate, archive to dated files) or raise the per-file limit. Keep total well under 80000 so the model has room to work.

## The session ritual (from the standard `AGENTS.md`)

**Start:** read `SOUL.md` → `USER.md` → `memory/session-state.md` → recent `memory/YYYY-MM-DD.md` → playbook index; in a main session also read `MEMORY.md`.

**End (long/main sessions):** write `memory/session-state.md` (what/unfinished/next steps), append reflections to today's daily note, log significant tasks, trim memory if large.

## Safety norms baked into bootstrap

- Never exfiltrate private data; never store credentials in memory/summaries/Slack — redact if seen.
- `trash` over `rm`; ask before destructive or external actions.
- **Approval gates:** before config edits, external writes (email/public Slack/Jira), destructive ops, or restarting the live gateway — state action + blast radius + rollback, then wait for an explicit "yes." A yes for one action ≠ the next.

## Customizing for your org

1. Edit `IDENTITY.md` (name/emoji) and `SOUL.md` (voice).
2. Fill `USER.md` with the operator/team context.
3. Put real tool/credential *locations* (not secrets) in `TOOLS.md`.
4. Leave `HEARTBEAT.md` empty unless you want periodic autonomous checks.
5. Start `MEMORY.md` small; let the agent grow it.

> The reference host's workspace is a git repo (`~/.openclaw/workspace/.git`) — version-controlling bootstrap + memory is a good practice. Keep secrets out of it.
