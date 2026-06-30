#!/usr/bin/env bash
# healthcheck.sh — quick health gate for cron/CI. Exits non-zero if the gateway
# is down or doctor reports errors. Prints a compact summary.
set -uo pipefail

command -v openclaw >/dev/null || { echo "openclaw CLI not found"; exit 2; }

echo "== status =="
openclaw status 2>&1 | grep -E 'Gateway|Channel|Agents|Sessions|Tasks' || true

echo "== health =="
openclaw health 2>&1 | head -8 || true

echo "== doctor (errors only) =="
DOCTOR="$(openclaw doctor 2>&1)"
echo "$DOCTOR" | grep -iE 'error|invalid|failed|blocked|conflict' || echo "(no error-level findings)"

# Exit non-zero if the gateway isn't active.
if ! systemctl --user is-active --quiet openclaw-gateway.service 2>/dev/null; then
  echo "GATEWAY NOT ACTIVE"; exit 1
fi
# Exit non-zero if doctor printed schema/invalid errors.
echo "$DOCTOR" | grep -iqE 'invalid .* schema|startup_failed' && { echo "DOCTOR ERRORS PRESENT"; exit 1; }
echo "OK"
