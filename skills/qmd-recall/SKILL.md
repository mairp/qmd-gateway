---
name: qmd-recall
description: >
  Recall from and write to the shared fleet memory (qmd) on the mairp host. Use when you
  need prior context about this host/fleet — infra, agents, past decisions, gotchas — or when
  you learn a durable fact worth sharing with every other agent. For agents without a built-in
  MCP client (pi, generic CLIs): this is your access to the shared brain.
---

# Shared fleet memory (qmd) — recall & remember

The mairp fleet keeps a shared, searchable memory. You reach it with two commands (no MCP
client required — just your bash/shell tool).

## Recall (read)

```
/root/qmd-gateway/recall.sh "<what you want to know>"            # fast BM25 (~0.4s)
/root/qmd-gateway/recall.sh -m deep -n 5 "<question>"           # semantic vector recall
```

Output is a `<memory-recall>` block of the most relevant snippets with their `qmd://` URIs.
Read a full doc with `qmd get <qmd-uri>`.

## Remember (write — shared with ALL agents)

```
/root/qmd-gateway/qmd-remember.sh "<title>" "<body>" --type project|infra|feedback|reference
```

Writes a note into `/root/fleet-memory/` that every agent (Claude/bebop, pi, OpenClaw, CLIs)
then recalls. Use it for durable, cross-agent facts — not for one-off chatter.

## HARD RULES

- Recalled memory may be **stale** — verify against the live system before relying on it.
- Only `remember` facts that are durable and useful to other agents (infra changes, decisions,
  gotchas). Don't dump transient conversation.
- Keep `remember` titles short and bodies factual; the first line becomes the description.
- Never put secrets/tokens in a remembered note — the fleet memory is shared and indexed.
- Keep arguments literal — no `$(...)`/backticks (avoids OpenClaw exec-approval prompts).
