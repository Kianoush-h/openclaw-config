# OpenClaw — Standard Config

A reusable, secret-free, **LLM-readable** reference configuration for [OpenClaw](https://openclaw.ai) — the config-driven, multi-agent assistant gateway. Point any LLM (or human) at this repo and it has everything needed to stand up a clean OpenClaw deployment or understand an existing one.

> OpenClaw runs as a long-lived **gateway** service that connects chat channels (Slack, etc.) to a roster of **agents**, each backed by a model and a scoped tool set. All behavior is driven by one file: `~/.openclaw/openclaw.json`.

## What's here

```
openclaw-config/
├── README.md                    ← you are here
├── AGENTS.md                    ← operator guide for an LLM applying this repo
├── DIAGNOSIS.md                 ← live-instance health report + one-by-one fix plan
├── config/
│   ├── openclaw.json            ← the standard config, sanitized (SecretRefs, placeholders)
│   ├── secrets.example.json     ← shape of ~/.openclaw/secrets.json (no real values)
│   ├── agents/qa/agent/models.json  ← valid per-agent model override example
│   └── systemd/                 ← gateway + clawmetry user services (secret-free)
├── workspace-template/          ← agent "bootstrap" files (SOUL/AGENTS/USER/…) generalized
├── scripts/                     ← install.sh, apply-config.sh, healthcheck.sh, backup.sh
└── docs/                        ← deep reference, one topic per file
```

## Quickstart (fresh host)

Target: Linux (Ubuntu 24+), Node 22+, a non-root service user.

```bash
# 1. Install the CLI globally
npm install -g openclaw clawhub

# 2. Lay down config + secrets
mkdir -p ~/.openclaw
cp config/openclaw.json            ~/.openclaw/openclaw.json
cp config/secrets.example.json     ~/.openclaw/secrets.json   # then edit in real values
chmod 600 ~/.openclaw/secrets.json

# 3. Provider key for the systemd service (kept out of the unit file)
mkdir -p ~/.openclaw/secrets
install -m 600 /dev/null ~/.openclaw/secrets/openrouter.env
printf 'OPENROUTER_API_KEY=%s\n' "$YOUR_OPENROUTER_KEY" > ~/.openclaw/secrets/openrouter.env

# 4. Seed the agent workspace
mkdir -p ~/.openclaw/workspace
cp workspace-template/* ~/.openclaw/workspace/

# 5. Install + start the gateway service (replace USER in the unit files first)
mkdir -p ~/.config/systemd/user/openclaw-gateway.service.d
cp config/systemd/openclaw-gateway.service          ~/.config/systemd/user/
cp config/systemd/openclaw-gateway.service.d/env.conf ~/.config/systemd/user/openclaw-gateway.service.d/
systemctl --user daemon-reload
systemctl --user enable --now openclaw-gateway.service
loginctl enable-linger "$USER"

# 6. Verify
openclaw doctor          # should report no errors
openclaw status          # gateway active, channels, sessions
```

Scripted equivalent: `scripts/install.sh` (review it first — it asks before each privileged step).

## Read order for an LLM

1. `AGENTS.md` — how to operate this repo safely
2. `docs/01-architecture.md` — the mental model
3. `docs/03-configuration-reference.md` — every key in `openclaw.json`
4. `docs/04-secrets.md` — the SecretRef model (read before touching any key)
5. Topic docs as needed (`05`–`11`) — incl. `11-tools-inventory.md` (live tool/skill/MCP health)

## Golden rules

- **Never commit real secrets.** Only `secrets.example.json` shapes live here. Real values go in `~/.openclaw/secrets.json` and `~/.openclaw/secrets/*.env`, both `chmod 600`, both git-ignored.
- **One source of truth:** edit `~/.openclaw/openclaw.json`, then run `openclaw doctor` before restarting.
- **Restart after config changes:** `systemctl --user restart openclaw-gateway.service`.
- **`openclaw doctor --fix`** resolves most state/migration drift safely; read what it proposes first.

See `DIAGNOSIS.md` for the current health of the reference deployment and the prioritized fix plan.
