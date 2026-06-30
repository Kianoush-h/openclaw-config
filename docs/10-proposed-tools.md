# 10 · Proposed Tools & Standardization

Opt-in additions to consider when standardizing OpenClaw across hosts. Nothing here is enabled by default — each adds tools and prompt surface, so enable deliberately and re-run `openclaw doctor` after.

## Decision principles

- **Least privilege first.** Only enable a skill/plugin/MCP if an agent actually needs it.
- **Keys as SecretRefs.** Any new credential goes in `secrets.json` + a SecretRef (`docs/04`).
- **Scope to agents.** Add new tools to the *specific* agent's `tools.allow`, not globally.
- **Measure cost.** New skills inflate the system prompt; watch `bootstrapTotalMaxChars` and token spend.

## Recommended skills (low risk, high value)

| Skill | Why | Notes |
|-------|-----|-------|
| `github` / `gh-issues` | Repo + issue/PR ops from chat | Needs a GitHub token (SecretRef); scope to `coder`/`main` |
| `weather` | Common assistant ask | No key for basic providers |
| `summarize` | On-demand summarization | Pairs well with `web_fetch` |
| `diagram-maker` | Generate diagrams from text | Output to workspace |
| `model-usage` | Track token/cost per model | Ops visibility |

Enable: `openclaw config set skills.entries.github.enabled true` (+ token in secrets), then `openclaw skills install github`.

## Recommended plugins

| Plugin | Why |
|--------|-----|
| `duckduckgo` (already enabled) | Keyless search fallback when brave quota hits |
| A second channel (e.g. `telegram`/`discord`) | Redundant operator reach | scope `allowFrom` tightly |

## Recommended MCP servers

| MCP | Why |
|-----|-----|
| GitHub MCP | Richer repo tooling than the CLI skill |
| Internal tools MCP | Expose org-specific actions uniformly |

Add: `openclaw mcp add <name> --url https://<host>/mcp --transport streamable-http` — put any auth header value in `secrets.json` and reference it as a SecretRef.

## Repo-level tooling included here

- `scripts/install.sh` — bootstrap a fresh host (idempotent, asks before privileged steps).
- `scripts/apply-config.sh` — validate + diff + apply `openclaw.json` to a host.
- `scripts/healthcheck.sh` — wrapper over `status`/`health`/`doctor` with a non-zero exit on problems (CI/cron friendly).
- `scripts/backup.sh` — tar snapshot of `~/.openclaw` excluding caches/node_modules.

## Standardization checklist (per host)

- [ ] CLI installed (`openclaw`, `clawhub`) at a known version
- [ ] `openclaw.json` from this repo, placeholders replaced
- [ ] `secrets.json` + `secrets/openrouter.env` (600), no inline secrets anywhere
- [ ] systemd unit + `.d/env.conf` installed, lingering enabled
- [ ] workspace bootstrap files in place
- [ ] `commands.ownerAllowFrom` set
- [ ] `openclaw doctor` clean
- [ ] backup scheduled
