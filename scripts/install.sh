#!/usr/bin/env bash
# install.sh — bootstrap an OpenClaw host from this repo.
# Idempotent and cautious: prints each privileged step and asks before running it.
# Usage: scripts/install.sh [--yes]   (--yes skips prompts; review the script first!)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OC="$HOME/.openclaw"
ASSUME_YES="${1:-}"

confirm() { # confirm "message"
  [ "$ASSUME_YES" = "--yes" ] && return 0
  read -r -p "→ $1 [y/N] " a; [ "$a" = "y" ] || [ "$a" = "Y" ]
}

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }

say "1) Check prerequisites"
command -v node >/dev/null || { echo "node not found (need 22+)"; exit 1; }
node -e 'process.exit(parseInt(process.versions.node) >= 22 ? 0 : 1)' || { echo "node 22+ required"; exit 1; }
command -v npm  >/dev/null || { echo "npm not found"; exit 1; }
echo "node $(node --version), npm $(npm --version) OK"

if ! command -v openclaw >/dev/null; then
  if confirm "Install 'openclaw' and 'clawhub' globally via npm?"; then
    npm install -g openclaw clawhub
  fi
fi

say "2) Lay down config"
mkdir -p "$OC" "$OC/secrets" "$OC/workspace"
if [ ! -f "$OC/openclaw.json" ] || confirm "Overwrite existing $OC/openclaw.json?"; then
  cp "$REPO_DIR/config/openclaw.json" "$OC/openclaw.json"
  echo "Wrote $OC/openclaw.json — remember to replace REPLACE_WITH_* placeholders."
fi
if [ ! -f "$OC/secrets.json" ]; then
  cp "$REPO_DIR/config/secrets.example.json" "$OC/secrets.json"
  chmod 600 "$OC/secrets.json"
  echo "Wrote $OC/secrets.json (600) — fill in real tokens."
else
  echo "Kept existing $OC/secrets.json (not overwriting secrets)."
fi

say "3) Provider env file (OPENROUTER_API_KEY)"
if [ ! -f "$OC/secrets/openrouter.env" ]; then
  install -m 600 /dev/null "$OC/secrets/openrouter.env"
  echo "# OPENROUTER_API_KEY=sk-or-..." > "$OC/secrets/openrouter.env"
  echo "Created $OC/secrets/openrouter.env (600) — add your key."
fi

say "4) Workspace bootstrap files"
for f in "$REPO_DIR"/workspace-template/*; do
  base="$(basename "$f")"
  [ -e "$OC/workspace/$base" ] || cp "$f" "$OC/workspace/$base"
done
echo "Workspace seeded at $OC/workspace (existing files preserved)."

say "5) systemd user service"
echo "Edit USER in config/systemd/* before installing on a real host."
if confirm "Install + enable openclaw-gateway.service for $USER now?"; then
  mkdir -p "$HOME/.config/systemd/user/openclaw-gateway.service.d"
  sed "s/USER/$USER/g" "$REPO_DIR/config/systemd/openclaw-gateway.service" \
    > "$HOME/.config/systemd/user/openclaw-gateway.service"
  sed "s/USER/$USER/g" "$REPO_DIR/config/systemd/openclaw-gateway.service.d/env.conf" \
    > "$HOME/.config/systemd/user/openclaw-gateway.service.d/env.conf"
  systemctl --user daemon-reload
  systemctl --user enable --now openclaw-gateway.service
  loginctl enable-linger "$USER" || true
fi

say "6) Verify"
openclaw doctor || true
echo
echo "Done. Replace placeholders in $OC/openclaw.json, fill secrets, then:"
echo "  openclaw doctor && systemctl --user restart openclaw-gateway.service && openclaw status"
