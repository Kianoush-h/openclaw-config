# 02 · Installation & Running

## Prerequisites

- **OS**: Linux (reference host is Ubuntu, kernel 6.14). macOS works too; systemd steps differ.
- **Node**: 22+ (`node --version`). OpenClaw ships its runtime expectation in `package.json`.
- **Package managers**: npm for the CLI; `pnpm` used for skill installs (`skills.install.nodeManager: pnpm`).
- **Service user**: a normal non-root user (reference: `clouduser`). Never run the gateway as root.
- **Optional**: Google Chrome (`/usr/bin/google-chrome-stable`) for the `browser` tool; Tailscale for remote access; `qmd` (`~/.bun/bin/qmd`) for memory search.

## 1. Install the CLI

```bash
npm install -g openclaw clawhub
which openclaw            # ~/.npm-global/bin/openclaw -> .../openclaw/openclaw.mjs
openclaw --version        # OpenClaw 2026.6.8 (...)
```

If `~/.npm-global/bin` is not on PATH, add it (the systemd unit sets PATH explicitly, so this only matters for interactive use):

```bash
echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.bashrc
```

## 2. Configuration & secrets

```bash
mkdir -p ~/.openclaw ~/.openclaw/secrets
cp config/openclaw.json        ~/.openclaw/openclaw.json
cp config/secrets.example.json ~/.openclaw/secrets.json
chmod 600 ~/.openclaw/secrets.json
$EDITOR ~/.openclaw/secrets.json          # fill in real tokens
```

Replace every `REPLACE_WITH_*` placeholder in `~/.openclaw/openclaw.json` (owner id, Slack user/channel ids, MCP host). See `docs/03` for what each does.

Provider key for the service (kept out of the unit file):

```bash
install -m 600 /dev/null ~/.openclaw/secrets/openrouter.env
printf 'OPENROUTER_API_KEY=%s\n' "$YOUR_KEY" > ~/.openclaw/secrets/openrouter.env
```

## 3. Workspace bootstrap

```bash
mkdir -p ~/.openclaw/workspace
cp workspace-template/* ~/.openclaw/workspace/
```

These markdown files (`SOUL.md`, `AGENTS.md`, `USER.md`, `IDENTITY.md`, `TOOLS.md`, `HEARTBEAT.md`, `MEMORY.md`) are read by the agent at session start. Edit them for your org. See `docs/08`.

## 4. Install & start the gateway service

Edit `config/systemd/openclaw-gateway.service` and `…/env.conf`, replacing `USER` with the service account, then:

```bash
mkdir -p ~/.config/systemd/user/openclaw-gateway.service.d
cp config/systemd/openclaw-gateway.service             ~/.config/systemd/user/
cp config/systemd/openclaw-gateway.service.d/env.conf  ~/.config/systemd/user/openclaw-gateway.service.d/
systemctl --user daemon-reload
systemctl --user enable --now openclaw-gateway.service
loginctl enable-linger "$USER"
```

> **Why an EnvironmentFile?** The reference host had `OPENROUTER_API_KEY` inlined directly in the unit — a secret in a readable file. The standard pattern here moves it to `~/.openclaw/secrets/openrouter.env` (mode 600) referenced via a `.d/env.conf` drop-in.

Alternative (no systemd): `openclaw gateway --port 18789` in a tmux/screen, or `openclaw daemon` helpers.

## 5. Channels, models, pairing

```bash
openclaw status                      # gateway up? channels? models?
openclaw configure                   # interactive: credentials, channels, gateway
openclaw channels login slack        # if not pre-seeded via secrets.json
openclaw pairing                     # approve inbound DM pairing requests
```

## 6. Verify

```bash
openclaw doctor          # expect: no errors (warnings explained in docs/09)
openclaw health          # event loop, agents, session stores
openclaw status --deep   # adds live probes + security audit
```

## Updating

```bash
npm update -g openclaw clawhub
openclaw doctor --fix     # apply any state migrations the new version needs
systemctl --user restart openclaw-gateway.service
```

`update.checkOnStart: true` makes the gateway check for new versions on boot; channel is `stable`.

## Backups

```bash
openclaw backup create   # local archive of ~/.openclaw state
# or scripts/backup.sh for a tar snapshot excluding caches
```
