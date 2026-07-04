# qmd-gateway

One **shared, always-on, warm** qmd memory service for the whole mairp agent fleet, plus a
**writable** cross-agent knowledge collection. Replaces the old model where every `claude`/`bebop`
session spawned its own `qmd mcp` stdio child (cold models, no sharing) and OpenClaw kept a
separate per-agent index.

```
                         ┌───────────────────────────────────────────────┐
 Claude / bebop  ─┐      │  qmd-gateway.service                           │
 pi (via skill)  ─┤ MCP  │   uvx mcp-proxy  --host 0.0.0.0 --port 8190    │
 OpenClaw agents ─┤ SSE  │        └─ one warm `qmd mcp` (stdio child)     │
 3rd-party CLIs  ─┘ 8190 │             XDG -> /root/qmd-shared            │
                         └───────────────────────────────────────────────┘
   recall.sh / qmd-remember.sh (bash path, no MCP client needed)
        │ read                              │ write
        ▼                                   ▼
   qmd-shared index (sqlite)          /root/fleet-memory/**  ── reindex.sh (timer + on-write)
   collections: fleet-ops (RW) + claude-memory (RO) + openclaw-memory (RO)
   models: Qwen3-Embedding-0.6B · qmd-query-expansion-1.7B · Qwen3-Reranker-0.6B (local GGUF)
```

## Endpoints & binding

| | |
|---|---|
| SSE MCP | `http://127.0.0.1:8190/sse` (also reachable on `10.8.0.1:8190` over WireGuard) |
| Liveness | `http://127.0.0.1:8190/status` → 200 |
| Bind | `0.0.0.0:8190`, but the host firewall (`setup-firewall.sh`, INPUT policy DROP) admits only `lo` + `10.8.0.0/24`. No public exposure, no key material in the unit. |

## Files

| Path | What |
|---|---|
| `run.sh` | The service: `mcp-proxy` fronting one warm `qmd mcp`. Env pins the shared XDG + Intel-iGPU Vulkan (RTX 3090 stays reserved for llama-swap). |
| `recall.sh` | Fail-open recall against the shared index (`fast` BM25 / `deep` vec-only / `query` hybrid). For agents without an MCP client (pi, CLIs) — call from a bash tool. |
| `qmd-remember.sh` | **The write path.** `qmd-remember.sh "<title>" "<body>" [--type project\|infra\|feedback\|reference]` → leaf under `/root/fleet-memory/`, pointer in `MEMORY.md`, then reindex. |
| `reindex.sh` | flock-guarded `qmd update && qmd embed` on the shared index. Run by the timer and after each write. |
| `qmd-attach.sh` | Attach an agent (see matrix below). |

## Attach matrix

| Agent | Command | Path |
|---|---|---|
| Claude / bebop | `qmd-attach.sh claude-http` | MCP/SSE → shared warm index (revert: `claude-stdio`) |
| pi | `qmd-attach.sh pi` | registers `~/.claude/skills` (incl. `qmd-recall`) into `~/.pi/agent/settings.json`; recall via bash. **Opt-in MCP:** `pi install npm:<mcp-client-ext>` → `:8190/sse` |
| OpenClaw agent | `qmd-attach.sh openclaw <agent>` | adds shared fleet-ops read to the agent's `index.yml`. **Opt-in MCP:** enable `mcporter` → `:8190/sse` |
| 3rd-party CLI | `qmd-attach.sh cli` | prints env + `.mcp.json` (MCP CLIs) or the `recall.sh` bash pattern |
| — | `qmd-attach.sh status` | show what's attached |

## Systemd

- `qmd-gateway.service` — the SSE service (`Restart=always`).
- `qmd-gateway-reindex.timer` / `.service` — incremental reindex every 10 min.
- Started/stopped/reported by `/root/fleet.sh` (step 5).

## Collections

Defined in `/root/qmd-shared/xdg-config/qmd/index.yml`:
- **`fleet-ops` / `fleet-ops-root`** (writable) → `/root/fleet-memory/**` — the cross-agent brain.
- **`claude-memory-*`** (read-only) → `/root/.claude/projects/-root/memory`.
- **`openclaw-memory-*`** (read-only) → `/root/.openclaw/workspace{,/memory}`.

Only `fleet-ops` is ever written (via `qmd-remember.sh`); the others are one-way read shares.
