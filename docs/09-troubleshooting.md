# 09 · Troubleshooting

Start every investigation with the three CLI lenses:
```bash
openclaw status        # gateway/channels/agents/sessions at a glance
openclaw health        # event loop latency, agent stores
openclaw doctor        # full config/state/plugin/channel audit  (--fix to repair, --deep for more)
```

## Reading `openclaw doctor`

Doctor groups findings into sections. Mapping of what we saw on the reference host to fixes:

| Doctor finding | Meaning | Fix |
|----------------|---------|-----|
| `Invalid models.json schema: providers must have required properties` | An `agents/<id>/agent/models.json` exists but lacks a `providers` object (e.g. is `{}`) | Delete the file (inherit root models) or give it a valid `providers` block. See `config/agents/qa/agent/models.json` |
| `Left plugin install index in place … conflicting plugin install metadata for: brave, slack` | Legacy `plugins/installs.json` conflicts with the shared SQLite registry; migration won't clobber, so it warns forever | See **"Plugin install-index conflict"** below — `doctor --fix` alone won't clear it |
| `No command owner is configured` | `commands.ownerAllowFrom` unset → nobody can run owner-only commands/approvals | `openclaw config set commands.ownerAllowFrom '["slack:UXXXXXXXX"]'` then restart |
| `Found stale Google session routing state in N sessions` | Old sessions pinned to a prior model/runtime | `openclaw doctor --fix` → "Cleared stale … routing state for N sessions". Note: `openclaw sessions cleanup` only prunes artifacts, it does **not** re-pin routing. `--fix` is safe-by-default: it does not cancel blocked TaskFlows or change cron, it only re-pins routing + runs safe migrations |
| `tools.<agent>.allow … unknown entries (image)` | Allowlist names a tool not available in this runtime | Remove `image` from the allowlist, or enable an image-capable provider/tool |
| `Cron model overrides detected … will not inherit agents.defaults.model` | Jobs hardcode `payload.model` | `openclaw cron show <id>`; remove `payload.model` to track the default |
| `TaskFlow recovery … blocked TaskFlow points at missing task` | Orphaned TaskFlows reference deleted tasks | `openclaw tasks flow show <flow-id>` then `openclaw tasks flow cancel <flow-id>` |
| `Workspace bootstrap files exceed limits … MEMORY.md truncated` | A bootstrap file is larger than `bootstrapMaxChars` | Trim/curate `MEMORY.md` (archive to dated notes) or raise `agents.defaults.bootstrapMaxChars` |
| `gateway.startup_failed: tailscale funnel requires gateway auth mode=password` | `tailscale.mode: funnel` (public) needs password auth | Use `mode: serve` (private tailnet, token auth) or set `gateway.auth.mode: password` |

> Most state-drift items (stale routing, plugin index, blocked flows) are fixed by `openclaw doctor --fix`. **Read the proposed changes first**, snapshot config, and restart after.

## Plugin install-index conflict (`installs.json` ↔ SQLite)

OpenClaw migrated plugin install bookkeeping from `~/.openclaw/plugins/installs.json` to a shared **SQLite** registry. If the two disagree for a plugin, the migration keeps the JSON and re-warns on every command. `openclaw plugins doctor` will still say "No plugin issues detected" — the plugins work; it's stale-state noise. Clear it by making SQLite authoritative, then retiring the JSON:

```bash
cp ~/.openclaw/plugins/installs.json ~/.openclaw/plugins/installs.json.bak.$(date +%s)
openclaw plugins registry --refresh        # rebuild SQLite registry from manifests
mv ~/.openclaw/plugins/installs.json ~/.openclaw/plugins/installs.json.disabled.$(date +%s)
systemctl --user restart openclaw-gateway.service
openclaw doctor | grep -i "install index" || echo CLEARED
openclaw plugins list | grep -iE 'brave|slack'   # confirm still enabled/loaded
```
The JSON is **not** regenerated — SQLite becomes the single source. Never hand-edit `installs.json` (it carries a `DO NOT EDIT` header). Rollback: restore the `.bak` file and restart.

## The gateway won't start / keeps restarting

1. `journalctl --user -u openclaw-gateway.service -e` — read the last error.
2. `ls -t ~/.openclaw/logs/stability/*startup_failed*.json | head -1 | xargs cat` — structured crash report with the failing phase + error.
3. **Exit 78 = config error.** The unit has `RestartPreventExitStatus=78`, so it deliberately stops instead of thrashing. Run `openclaw config validate`, fix, then `systemctl --user start`.
4. Roll back config: `cp ~/.openclaw/openclaw.json.last-good ~/.openclaw/openclaw.json` (OpenClaw keeps `.last-good`, `.bak`, timestamped, and `.clobbered.*` snapshots).

## Channel issues

- Slack shows `SETUP`/`status unavailable in fast mode` → run `openclaw status --deep` or `openclaw channels …` for live state.
- Bot not responding in a channel → confirm the channel id is in `channels.slack.channels` and `enabled: true`; confirm the bot is invited to the channel in Slack.
- DMs ignored → user must be in `allowFrom` and complete pairing (`openclaw pairing`).

## Model/provider issues

- 401/quota → check `OPENROUTER_API_KEY` (env for the service): `systemctl --user show-environment` won't show it; verify `~/.openclaw/secrets/openrouter.env` and restart.
- A model id changed/retired → update `models.providers.openrouter.models` and any agent `model.primary`.

## "It's buggy" checklist (fast triage)

1. `openclaw doctor` — fix everything it flags (one at a time).
2. `openclaw doctor --fix` — clear state drift.
3. Restart: `systemctl --user restart openclaw-gateway.service`.
4. `openclaw status` — confirm clean.
5. Prune old snapshots if `~/.openclaw` is cluttered: archive `openclaw.json.clobbered.*` / `.bak-*`.

See `DIAGNOSIS.md` for the current reference host's prioritized issue list and the agreed one-by-one fix workflow.
