# TOOLS.md - Local Notes

> Notes on tool/CLI specifics for THIS host: binary paths, accounts, env vars, viewports.
> Record *locations and non-secret config* here — NEVER actual credentials (those live in
> ~/.openclaw/secrets.json). Example structure below; replace with your real tools.

## Example: a CLI tool
- Binary: `~/.local/bin/<tool>`
- Account: `REPLACE_WITH_ACCOUNT`
- Required env vars:
  ```
  export PATH="$HOME/.local/bin:$PATH"
  export <TOOL>_ACCOUNT="REPLACE_WITH_ACCOUNT"
  ```
- Credentials: `source ~/.openclaw/skills/<tool>/.env`  (the .env file holds the secret, not this note)

## Example: an HTTP API (ticketing)
- Auth: token from secrets; `curl -u "user:$API_TOKEN" https://<host>/rest/api/...`
- Common transitions/ids: REPLACE_WITH_IDS

## Browser (use the `agent-browser` CLI via exec — there is NO built-in `browser` tool)

Browser automation is the `agent-browser` CLI skill, run through exec/Bash. There is no
structured `browser` tool (an allow-listed `browser` entry is a no-op). Do NOT invent commands
like `openclaw-browser-automation` — only `agent-browser` exists.

- Navigate:    `agent-browser open <url>`
- Snapshot:    `agent-browser snapshot -i`   (returns element refs @e1, @e2 …)
- Interact:    `agent-browser click @e1` / `agent-browser fill @e2 "text"` / `agent-browser press Enter`
- Wait:        `agent-browser wait --load networkidle`
- Screenshot:  `agent-browser screenshot page.png`
- Full guide:  `agent-browser skills get core --full`

Notes: headless Chrome profile "openclaw"; sequential only (parallel sessions crash);
standard viewport 1920x1080 (tall trick 1280x3000 for long forms).
