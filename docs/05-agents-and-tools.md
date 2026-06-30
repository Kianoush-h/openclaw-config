# 05 · Agents & Tools

## The agent roster

| Agent | Role | Primary model | Fallback | Notable tool posture |
|-------|------|---------------|----------|----------------------|
| `main` | Default operator; talks to humans, orchestrates | gemini-3.1-flash-lite | granite-4.1-8b | `profile: full`, denies `canvas`,`nodes`; may spawn `qa`,`critic`,`coder` |
| `qa` | Test/verify; runs things, browses | gemini-3.1-flash-lite | grok-4.3 | exec/read/write/edit/browser/web_fetch + memory read; no messaging/sessions |
| `critic` | Reasoning/review; no execution | grok-4.3 | gemini-3.1-flash-lite | read/write/edit/web_search/web_fetch only — **no `exec`, no `browser`** |
| `coder` | Code generation & edits | kimi-k2.6 | qwen3.6-35b-a3b | exec/read/write/edit/browser/web_* + memory read |
| `standup` | Daily standup summaries | granite-4.1-8b | gemini-3.1-flash-lite | denies exec/browser/cron/gateway/tts — read/summarize only |
| `jira-ops` | Jira automation responder | granite-4.1-8b | gemini-3.1-flash-lite | exec/message/read/write only |

Model choice tracks the job: cheap/fast default (gemini-flash-lite) for chat, a strong reasoner (grok) for the critic, a coding model (kimi) for the coder, a small cheap model (granite) for routine summaries.

## How tool gating works

Each agent has `tools.allow` and/or `tools.deny`:
- **`profile`** (`full`, `coding`, …) sets a baseline tool set.
- **`allow`** — explicit allowlist (when present, it's the universe of tools the agent can use).
- **`deny`** — subtracted from whatever is allowed.
- Deny wins over allow.

### Common tools

| Tool | What it does | Risk |
|------|--------------|------|
| `exec` | Run shell commands | **High** — only on trusted agents |
| `read`/`write`/`edit` | File I/O in workspace | Med |
| `browser` | Headless Chrome automation | Med |
| `web_fetch` / `web_search` | Fetch a URL / search (brave) | Low |
| `message` | Post to channels | **High** — external side effects |
| `cron` | Create/modify scheduled jobs | High |
| `gateway` | Control the gateway itself | **High** |
| `nodes` | Drive paired device nodes | High |
| `canvas` | Canvas/drawing surface | Low |
| `tts` | Text-to-speech | Low |
| `memory_search` / `memory_get` | Query memory index | Low |
| `agents_list`, `sessions_*`, `session_status` | Introspect other agents/sessions | Med (info disclosure) |

### Design principles in this config

1. **Least privilege.** `critic` can't `exec` or `browser`; `standup` can't act externally; `jira-ops` is limited to exec/message/read/write.
2. **Containment of cross-agent visibility.** Subagents deny `sessions_*`/`agents_list` so they can't read other agents' conversations.
3. **Only `main` orchestrates.** `subagents.allowAgents` on `main` enumerates spawnable agents; subagents can't spawn further.

## Per-agent model overrides (`agents/<id>/agent/models.json`)

Optional. If present, it **must** contain a top-level `providers` object. An empty `{}` is invalid and breaks the agent's model catalog (this was the live `qa` bug — see `DIAGNOSIS.md` #1). If an agent needs no special catalog, **delete the file** and it inherits the root `models`. A valid minimal example is in `config/agents/qa/agent/models.json`.

### What per-agent catalogs are actually for (observed on the reference host)

These files **extend** the root catalog with providers/models only that agent should see — they're how the deployment gives different agents different model menus beyond what's in root `openclaw.json`:

| Agent | Extra providers in its `models.json` | Example models |
|-------|--------------------------------------|----------------|
| `main` | `arcee`, `codex` | `arcee/trinity-large-thinking`, `codex/gpt-5.4` |
| `critic` | `openrouter` (subset) | `kimi-k2.6`, `qwen3.6-35b-a3b` |
| `coder` | `openrouter` (full list) | full root model set |
| `standup` | `openrouter`, `arcee`, `ollama`, `codex` | `minimax-m2.5`, `claude-sonnet-4.6`, local `ollama` @ `192.168.2.30:11434` |
| `jira-ops` | `openrouter` (`auto`/`hunter`/`healer`), `arcee`, `ollama` | OpenRouter Auto routing |
| `qa` | *(none — inherits root)* | gemini-flash-lite + grok |

Model entries can carry rich metadata: `reasoning` (bool), `input` (`["text","image"]`), `cost` (input/output/cache), `contextWindow`, `maxTokens`, `compat` flags. Each provider block needs an `apiKey` — use the **env-var reference form** `"apiKey": "OPENROUTER_API_KEY"` (resolved from the gateway environment), **never** a literal key. (The reference host's `jira-ops` file hardcoded a literal OpenRouter key — flagged in `DIAGNOSIS.md` #9.)

> Note: a local **Ollama** server (`http://192.168.2.30:11434/v1`) is referenced by `standup`/`jira-ops` catalogs even though the `ollama` plugin is disabled in root — the per-agent catalog is what wires those models in.

## The `image` tool gotcha

`qa` and `coder` allowlists include `image`, but it isn't available in the current runtime/provider, so doctor warns:
`allowlist contains unknown entries (image)`. Either enable an image-capable model/tool or remove `image` from those allowlists. Unknown allow entries are harmless (ignored) but noisy.

## Adding / editing an agent

```bash
openclaw agents list
openclaw config set agents.list '<full json array>'   # or edit the array and validate
openclaw config validate && openclaw doctor
systemctl --user restart openclaw-gateway.service
```
