#!/usr/bin/env bash
# backup.sh — tar snapshot of ~/.openclaw state, excluding caches/heavy dirs.
# Prefer `openclaw backup create` when available; this is a portable fallback.
# Usage: scripts/backup.sh [dest-dir]   (default: ~/openclaw-backups)
set -euo pipefail

OC="$HOME/.openclaw"
DEST="${1:-$HOME/openclaw-backups}"
mkdir -p "$DEST"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$DEST/openclaw-state-$STAMP.tar.gz"

# If the CLI offers native backup, use it.
if command -v openclaw >/dev/null && openclaw backup --help >/dev/null 2>&1; then
  echo "Using native: openclaw backup create"
  openclaw backup create || echo "(native backup failed; falling back to tar)"
fi

echo "Creating tar snapshot -> $OUT"
tar --exclude="$OC/cache" \
    --exclude="$OC/browser" \
    --exclude="$OC/npm" \
    --exclude="$OC/clawmetry-venv" \
    --exclude='*/node_modules' \
    --exclude='*.clobbered.*' \
    -czf "$OUT" -C "$HOME" .openclaw

echo "Done: $OUT ($(du -h "$OUT" | cut -f1))"
echo "NOTE: this archive contains ~/.openclaw/secrets.json — store it securely, never commit it."
