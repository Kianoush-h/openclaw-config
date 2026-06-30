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

## Browser
- Use the configured browser tool/skill.
- Standard viewport: 1920x1080
