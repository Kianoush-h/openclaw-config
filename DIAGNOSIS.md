# DIAGNOSIS — live instance `192.168.2.25` (host `openclaw`)

Captured 2026-06-30 from `openclaw status`, `openclaw health`, and `openclaw doctor` on `openclaw@2026.6.8`.

**Headline:** the gateway itself is **stable** — systemd `openclaw-gateway.service` is active, no journal errors in 2 days, event loop healthy (p99 ~80ms). The historical `gateway.startup_failed` crashes were a Tailscale-funnel-vs-auth misconfig from 2026-06-05 and are resolved (now `tailscale.mode: serve`). The "buggy" feel comes from **config drift + state-integrity issues** below, not crashes.

We will fix these **one at a time**: I explain the problem → we discuss → apply on the host → test → reflect the change in this repo → push. Nothing is changed on the server without your go-ahead.

> Convention before any host change: `cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak.$(date +%s)`

---

## Issue list (prioritized)

### #1 — `qa` agent model catalog is broken — **HIGH**
- **Symptom:** `model catalog load issue: Invalid models.json schema: providers must have required properties providers` for `~/.openclaw/agents/qa/agent/models.json`.
- **Root cause:** that file is literally `{}` — a per-agent model override with no `providers` object.
- **Effect:** `qa` can't load its model catalog cleanly; may fall back unpredictably.
- **Fix:** delete the file so `qa` inherits the root `models` (simplest), **or** replace it with a valid `providers` block (example shipped at `config/agents/qa/agent/models.json`).
- **Test:** `openclaw doctor` no longer reports the schema error; run a `qa` turn.

### #2 — Plugin install-index conflict (`brave`, `slack`) — **MED**
- **Symptom:** every doctor/status run prints `Left plugin install index in place … conflicting plugin install metadata for: brave, slack`.
- **Root cause:** legacy `~/.openclaw/plugins/installs.json` conflicts with the newer shared SQLite plugin state.
- **Fix:** `openclaw doctor --fix` (migrates the index). If it persists, back up and reconcile/remove the legacy `installs.json` entries for brave/slack.
- **Test:** doctor stops printing the migration warning.

### #3 — No command owner configured — **MED (security/usability)**
- **Symptom:** `No command owner is configured.`
- **Root cause:** `commands.ownerAllowFrom` is unset → nobody can run owner-only commands (`/config`, `/diagnostics`, exec approvals).
- **Fix:** `openclaw config set commands.ownerAllowFrom '["slack:<OWNER_USER_ID>"]'` (confirm which Slack user id is the operator — the host's `allowFrom` list is the candidate set) → restart.
- **Test:** owner-only command works from that account; doctor warning clears.
- **Repo:** standard config already sets `ownerAllowFrom` (placeholder) — we'll fill the real id.

### #4 — Stale Google session routing in 11 sessions — **MED**
- **Symptom:** `Found stale Google session routing state in 11 sessions outside the current configured model/runtime route.`
- **Root cause:** old sessions pinned to a prior model/runtime; can keep later channel runs on an outdated route.
- **Fix:** `openclaw doctor --fix` re-pins to the current default; or clear the affected sessions.
- **Test:** doctor reports 0 stale sessions; new channel messages use the default model.

### #5 — 16 blocked TaskFlows pointing at missing tasks — **MED**
- **Symptom:** `TaskFlow recovery: … blocked TaskFlow points at missing task …` (5 shown, "+11 more").
- **Root cause:** orphaned TaskFlows reference tasks that were deleted.
- **Fix:** inspect each: `openclaw tasks flow show <flow-id>`; cancel the dead ones: `openclaw tasks flow cancel <flow-id>`. (We'll review the list before cancelling.)
- **Test:** `openclaw status` Tasks line shows `0 issues`; doctor recovery section clears.

### #6 — Cron model overrides + one job in error — **MED**
- **Symptoms:**
  - 3 jobs hardcode `payload.model` (`granite-4.1-8b`, `grok-4.3`) so they ignore `agents.defaults.model`.
  - `openclaw-stable-release` (`214e9c80-…`) is in **error** status.
- **Fix:** `openclaw cron show 214e9c80-…` to find why it errors; for the model-pinned jobs, decide per job whether to remove `payload.model`.
- **Test:** the failing job runs `ok` on next trigger (or manual run); doctor cron section reflects intended model routing.

### #7 — Unknown tool `image` in `qa`/`coder` allowlists — **LOW**
- **Symptom:** `tools.qa.tools.allow … unknown entries (image)` (and same for `coder`).
- **Root cause:** `image` isn't available in the current runtime/provider/model.
- **Fix:** remove `image` from those allowlists (the standard config already omits it), or enable an image-capable model/tool if you actually want it.
- **Test:** doctor stops flagging unknown allow entries.

### #8 — `MEMORY.md` truncated on bootstrap — **LOW**
- **Symptom:** `MEMORY.md: 16,442 raw / 9,999 injected (39% truncated)`.
- **Root cause:** file exceeds `agents.defaults.bootstrapMaxChars` (10000).
- **Fix:** curate `MEMORY.md` down (archive detail to `memory/YYYY-MM-DD.md`), or raise `bootstrapMaxChars`. Recommend trimming — keeps prompt lean.
- **Test:** doctor bootstrap-size warning clears; `MEMORY.md` injects fully.

### #9 — Secret hygiene: inline secrets — **MED**
- **Symptoms (live config):**
  - `OPENROUTER_API_KEY` was **inlined** in the systemd unit (`Environment=OPENROUTER_API_KEY=sk-or-…`). A drop-in `EnvironmentFile` already exists (`secrets/openrouter.env`), so the inline copy is redundant and leaky.
  - `hooks.token` stored **inline** in `openclaw.json`.
  - `mcp.servers.vexa.headers["X-API-Key"]` stored **inline** in `openclaw.json`.
- **Fix:**
  1. Remove the inline `Environment=OPENROUTER_API_KEY=…` line from the unit (keep the `.d/env.conf` EnvironmentFile). Consider **rotating** the key since it sat in a readable unit.
  2. Move `hooks.token` to SecretRef `/hooks/token` (add value to `secrets.json`).
  3. Move vexa `X-API-Key` to SecretRef `/vexa/apiKey`.
  - The standard config in this repo already uses SecretRefs for all three.
- **Test:** `openclaw secrets audit` reports no inline secrets; gateway still authenticates to OpenRouter, webhooks, and the vexa MCP after restart.

---

## Suggested fix order

1. **#9 secrets** (security first — and rotate the OpenRouter key)
2. **#1 qa models.json** (clear the only HIGH functional break)
3. **#3 owner** (enable privileged ops)
4. **#2 plugin index + #4 stale sessions** (both via `doctor --fix`)
5. **#5 TaskFlows + #6 cron** (review then clean)
6. **#7 image tool + #8 MEMORY.md** (cosmetic/hygiene)

Each fix, once verified on the host, is mirrored into this repo's `config/` and committed.

## Quick reference: what's healthy
- Gateway: systemd active, reachable 25ms, token auth, Tailscale serve exposure.
- 6 agents, 174 sessions, Slack channel connected, memory enabled (qmd + memory-core/wiki).
- 7 plugins loaded, 20 skills eligible, 0 plugin load errors.
- No channel security warnings.
