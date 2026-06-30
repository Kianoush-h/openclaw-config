# DIAGNOSIS — live instance `192.168.2.25` (host `openclaw`)

Captured 2026-06-30 from `openclaw status`, `openclaw health`, and `openclaw doctor` on `openclaw@2026.6.8`.

**Headline:** the gateway itself is **stable** — systemd `openclaw-gateway.service` is active, no journal errors in 2 days, event loop healthy (p99 ~80ms). The historical `gateway.startup_failed` crashes were a Tailscale-funnel-vs-auth misconfig from 2026-06-05 and are resolved (now `tailscale.mode: serve`). The "buggy" feel comes from **config drift + state-integrity issues** below, not crashes.

We will fix these **one at a time**: I explain the problem → we discuss → apply on the host → test → reflect the change in this repo → push. Nothing is changed on the server without your go-ahead.

> Convention before any host change: `cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak.$(date +%s)`

---

## Issue list (prioritized)

### #1 — `qa` agent model catalog is broken — **HIGH** — ✅ RESOLVED 2026-06-30
- **Symptom:** `model catalog load issue: Invalid models.json schema: providers must have required properties providers` for `~/.openclaw/agents/qa/agent/models.json`.
- **Root cause:** that file was literally `{}` (2 bytes, dated Apr 7) — a per-agent model override with no `providers` object.
- **Effect:** `qa`'s catalog failed to load on every gateway start.
- **Fix applied:** backed up (`models.json.empty.bak.<ts>`) and **deleted** the empty file so `qa` inherits the root `models` catalog (its configured models — `gemini-3.1-flash-lite` + `grok-4.3` fallback — both live in root). Restarted the gateway.
- **Verified:** `openclaw doctor` no longer reports the schema error; a live `openclaw agent --agent qa` turn returned `QA_OK openrouter/google/gemini-3.1-flash-lite` with `result: success`, `fallbackUsed: false`.
- **Key learning:** a per-agent `models.json` *extends* the root catalog with extra providers (see `docs/05`). If an agent needs no extras, the file must be **absent** — an empty `{}` is invalid. Repo ships a valid example at `config/agents/qa/agent/models.json` for the override case.

### #2 — Plugin install-index conflict (`brave`, `slack`) — **MED** — ✅ RESOLVED 2026-06-30
- **Symptom:** every doctor/status run printed `Left plugin install index in place … conflicting plugin install metadata for: brave, slack` (a startup state-migration warning emitted before the command runs).
- **Root cause:** legacy `~/.openclaw/plugins/installs.json` held install records for `brave`/`slack` that conflicted with the newer shared **SQLite** plugin registry, so the migration refused to clobber and left the legacy file in place. `openclaw plugins doctor` reported "No plugin issues detected" — purely cosmetic, plugins worked.
- **Why `doctor --fix` alone wasn't enough:** the migration deliberately *won't* overwrite on conflict, so it kept re-warning.
- **Fix applied (staged, reversible):**
  1. `cp installs.json installs.json.bak.<ts>` (backup).
  2. `openclaw plugins registry --refresh` → rebuilt SQLite registry from manifests (`7/97 enabled plugins indexed`), making SQLite authoritative.
  3. `mv installs.json installs.json.disabled.<ts>` → removed the stale legacy index (it was **not** regenerated; SQLite is now the single source).
  4. `systemctl --user restart openclaw-gateway.service`.
- **Verified:** `doctor` warning **CLEARED**; Plugins `Loaded: 7, Errors: 0` (unchanged); `brave` + `slack` both `enabled`/loaded (v2026.6.8); live agent turn succeeded.
- **Key learning:** the plugin install index migrated from JSON (`plugins/installs.json`) → shared SQLite. On conflict the migration keeps the JSON and warns forever. Reconcile by `plugins registry --refresh` then retiring the legacy JSON — don't hand-edit it (`DO NOT EDIT` header). See `docs/07`/`docs/09`.

### #3 — No command owner configured — **MED (security/usability)** — ✅ RESOLVED 2026-06-30
- **Symptom:** `No command owner is configured.`
- **Root cause:** `commands.ownerAllowFrom` was unset → nobody could run owner-only commands (`/config`, `/diagnostics`, exec approvals).
- **Fix applied:** backed up config, `openclaw config set commands.ownerAllowFrom '["slack:U0724…"]'` (the operator's confirmed Slack user id), restarted gateway.
- **Verified:** config reads back the owner id; doctor "No command owner" warning **CLEARED**.
- **Repo:** standard config keeps `ownerAllowFrom` as a `REPLACE_WITH_OWNER_SLACK_USER_ID` placeholder (real id not committed).

### #4 — Stale Google session routing — **MED** — ✅ RESOLVED 2026-06-30
- **Symptom:** `Found stale Google session routing state in 12 sessions outside the current configured model/runtime route` (had grown 11→12).
- **Root cause:** old `agent:main` sessions (Slack threads/channels + a cron session, back to ~March) carried pinned "runtime model state" for a prior Google route.
- **Fix applied (targeted, staged):**
  1. Backed up config + **all** agent session stores + cron.
  2. `openclaw sessions cleanup` → pruned 618 unreferenced artifacts (did **not** clear routing).
  3. `openclaw doctor --fix` → reported `Cleared stale Google session routing state for 12 sessions` (also ran a safe auth-profile JSON→SQLite migration). Restarted gateway.
- **Verified:** doctor reports **0 stale sessions**; a live `main` turn routed to the default `google/gemini-3.1-flash-lite` (`result: success`).
- **Scope guard:** confirmed `doctor --fix` did **not** auto-cancel TaskFlows (#5 unchanged: 16 blocked) or alter cron (#6 unchanged: 6 jobs) — it only re-pins routing and runs safe migrations; TaskFlow/cron items are left for manual review.
- **Key learning:** `sessions cleanup` prunes artifacts but does **not** re-pin model routing; the routing repair is in `doctor --fix` under "State integrity". `--fix` is safe-by-default — it reports (not cancels) blocked TaskFlows and only warns on cron overrides.

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

### #9 — Secret hygiene: inline secrets — **MED** — ⏸ DEFERRED (user choice 2026-06-30; 2 live OpenRouter keys remain exposed)
- **Symptoms (live config):**
  - `OPENROUTER_API_KEY` was **inlined** in the systemd unit (`Environment=OPENROUTER_API_KEY=sk-or-…5a93c35a…`). A drop-in `EnvironmentFile` already exists (`secrets/openrouter.env`), so the inline copy is redundant and leaky.
  - A **second, different** OpenRouter key (`sk-or-v1-0206…99e2`) is hardcoded **inline** in `~/.openclaw/agents/jira-ops/agent/models.json` (both the `openrouter` and `arcee` provider blocks). Found 2026-06-30 while fixing #1. Every other agent's `models.json` correctly uses `"apiKey": "OPENROUTER_API_KEY"` (env reference) — only `jira-ops` hardcodes the literal.
  - `hooks.token` stored **inline** in `openclaw.json`.
  - `mcp.servers.vexa.headers["X-API-Key"]` stored **inline** in `openclaw.json`.
- **Fix:**
  1. Remove the inline `Environment=OPENROUTER_API_KEY=…` line from the unit (keep the `.d/env.conf` EnvironmentFile). **Rotate** the key — it sat in a readable unit.
  2. Replace the hardcoded key in `jira-ops/agent/models.json` (both provider blocks) with `"apiKey": "OPENROUTER_API_KEY"` like the other agents. **Rotate** this key too.
  3. Move `hooks.token` to SecretRef `/hooks/token` (add value to `secrets.json`).
  4. Move vexa `X-API-Key` to SecretRef `/vexa/apiKey`.
  - The standard config in this repo already uses SecretRefs / env references for all of these.
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
