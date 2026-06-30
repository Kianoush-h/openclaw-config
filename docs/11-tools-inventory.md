# 11 · Tools Inventory & Live Health

Snapshot of what the reference host's agents can actually use, and whether each works. Captured 2026-06-30 by probing the live gateway.

## How tools reach an agent

Four layers (see `docs/07`): **built-in tools** (gated per agent via `tools.allow/deny`), **plugins** (gateway extensions), **skills** (CLI tool packs), **MCP servers** (remote tool endpoints). An agent can only use a tool if it's (a) available in the runtime and (b) allowed by that agent's tool gating.

## Health verdict

| Tool / capability | Type | Status | Evidence |
|-------------------|------|--------|----------|
| `exec`, `read`, `write`, `edit` | built-in | ✅ working | agents run turns + commands |
| `web_search` (Brave) | plugin | ✅ working | coder agent returned a live result |
| `web_fetch` | built-in/plugin | ✅ working | fetched example.com |
| `memory_search`/`memory_get` (qmd) | memory | ✅ working | 5 collections, search returns hits |
| Memory dreaming / wiki | plugins | ✅ loaded | memory-core + memory-wiki enabled |
| **vexa** MCP | MCP | ✅ working | `mcp probe`: connects, **17 tools + prompts** |
| **Jira** (mcp-atlassian) | skill | ✅ working | `GET /rest/api/3/myself` → HTTP 200, valid token |
| Chrome (browser engine) | system | ✅ present | Google Chrome 149 at `/usr/bin/google-chrome-stable` |
| Core browser task | built-in | ✅ working | qa agent returned example.com `<h1>` |
| Browser automation (`agent-browser` CLI skill) | skill | ✅ working | `agent-browser open` succeeds; `qa` runs `open`+`snapshot -i` correctly after the #11 fix. NB: there is **no** structured `browser` tool — agents must call the `agent-browser` CLI via `exec` |
| **Google Workspace** (`gog`: Gmail, Calendar, Drive, Docs, Sheets) | skill | ❌ **broken** | `oauth2: "invalid_grant"` on Gmail **and** Calendar — OAuth refresh token expired/revoked |
| Slack channel | plugin | ✅ working | gateway connected; agent replies delivered |
| 6 agents (main/qa/critic/coder/standup/jira-ops) | runtime | ✅ working | live turns succeeded (main, qa, coder) |

## Ready skills (20 of 67)

Enabled/ready on the host: `browser-automation`, `clawhub`, `gog`, `gojitech-reports`, `group-chat-protocol`, `healthcheck`, `mcp-atlassian`, `meme-maker`, `memory-management`, `nano-pdf`, `obsidian-vault-maintainer`, `scrapling-official`, `session-logs`, `skill-creator`, `slack-conventions`, `taskflow`, `taskflow-inbox-triage`, `tmux`, `wiki-maintainer` (+ session/taskflow helpers). The other ~47 are disabled (Apple/iMessage/Spotify/etc.).

## Plugins loaded (7)

`slack`, `brave`, `duckduckgo`, `browser`, `openrouter`, `memory-core`, `memory-wiki` — 0 load errors.

## MCP servers (1)

`vexa` — `streamable-http`, 17 tools + prompts, connects live. (Key should be a SecretRef — see `DIAGNOSIS.md` #9.)

---

## Action items found

### ❌ Google Workspace OAuth is dead (`gog`) — needs re-auth
Gmail/Calendar/Drive calls fail with `invalid_grant`. The refresh token is expired or was revoked. Any agent task touching Google (mail triage, calendar, drive) currently fails.

**Fix (requires interactive OAuth — operator action):**
```bash
export GOG_KEYRING_PASSWORD=...        # the gog keyring password
export GOG_ACCOUNT=<account@domain>
gog auth add                            # re-authorize via the OAuth consent flow
gog calendar list                       # verify
```
Because OAuth consent needs a browser, this can't be done headlessly from the gateway — run it from an interactive shell on the host (`! gog auth add` in a session, or SSH in).

### ✅ Browser automation (was #11) — fixed
There is **no structured `browser` tool**; browser work is the **`agent-browser` CLI skill** run via `exec`. Agents that lacked the command in their workspace `TOOLS.md` hallucinated a fake `openclaw-browser-automation` command. Fixed by adding the real `agent-browser` interface to the qa/coder workspaces (and to `workspace-template/TOOLS.md`). The correct commands:
```bash
agent-browser open <url>            # navigate
agent-browser snapshot -i           # element refs @e1, @e2 …
agent-browser click @e1             # interact
agent-browser fill @e2 "text"
agent-browser wait --load networkidle
agent-browser screenshot page.png
agent-browser skills get core --full   # full reference
```
Any agent expected to browse needs this in its bootstrap `TOOLS.md`. See `DIAGNOSIS.md` #11.

## How to re-run these checks

```bash
openclaw skills list                 # ready vs disabled
openclaw plugins list                # loaded plugins
openclaw mcp probe                   # live-connect MCP servers, list tools
openclaw memory search "<q>"         # memory backend
openclaw agent --agent coder --message "use web_search to ..." --json   # brave
openclaw agent --agent qa --message "use the browser tool to open ..." --json  # browser
gog calendar list                    # Google Workspace (after re-auth)
curl -u "$USER:$JIRA_API_TOKEN" https://<site>.atlassian.net/rest/api/3/myself   # Jira
```
