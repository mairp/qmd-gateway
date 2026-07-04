#!/usr/bin/env bash
# qmd-attach.sh — attach a coding agent to the SHARED qmd gateway (:8190) without re-indexing.
#
# Targets:
#   claude-http [path]   Point Claude/bebop's `qmd` MCP server at the shared warm SSE endpoint
#                        (default path: /root/.claude.json). Backs up first. Reversible.
#   claude-stdio [path]  Restore Claude's original per-session stdio `qmd` (its own index).
#   pi                   Register the shared skills dir + qmd-recall skill into ~/.pi/agent/settings.json
#                        (pi has no built-in MCP; it uses recall.sh via a skill).
#   openclaw <agent>     Add the shared fleet-ops read to an OpenClaw agent's qmd index.yml.
#   cli                  Print env + .mcp.json snippet for a third-party CLI (aider/opencode/crush).
#   status               Show what's currently attached.
#
# The gateway must be reachable at http://127.0.0.1:8190/sse (systemctl status qmd-gateway).
set -u

GW_URL="http://127.0.0.1:8190/sse"
CLAUDE_JSON_DEFAULT="/root/.claude.json"
PI_SETTINGS="/root/.pi/agent/settings.json"
SHARED_SKILLS="/root/.claude/skills"
STDIO_BAK="/root/qmd-gateway/.qmd-stdio-backup.json"

die() { echo "qmd-attach: $*" >&2; exit 1; }

cmd="${1:-status}"; shift || true

case "$cmd" in
  claude-http)
    CJ="${1:-$CLAUDE_JSON_DEFAULT}"
    [ -f "$CJ" ] || die "no such file: $CJ"
    cp -a "$CJ" "$CJ.bak-qmdattach-$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo bak)"
    node -e '
      const fs=require("fs"); const f=process.argv[1], url=process.argv[2], bak=process.argv[3];
      const j=JSON.parse(fs.readFileSync(f,"utf8"));
      j.mcpServers=j.mcpServers||{};
      // Preserve the original stdio qmd once, so claude-stdio can restore it.
      if(j.mcpServers.qmd && j.mcpServers.qmd.type!=="http" && !fs.existsSync(bak)){
        fs.writeFileSync(bak, JSON.stringify(j.mcpServers.qmd,null,2));
      }
      j.mcpServers.qmd={ type:"http", url };
      fs.writeFileSync(f, JSON.stringify(j,null,2));
      console.log("attached: Claude qmd -> "+url+"  ("+f+")");
    ' "$CJ" "$GW_URL" "$STDIO_BAK"
    echo "Start a NEW Claude/bebop session to pick up the change."
    ;;

  claude-stdio)
    CJ="${1:-$CLAUDE_JSON_DEFAULT}"
    [ -f "$CJ" ] || die "no such file: $CJ"
    [ -f "$STDIO_BAK" ] || die "no stdio backup at $STDIO_BAK (was claude-http ever run?)"
    node -e '
      const fs=require("fs"); const f=process.argv[1], bak=process.argv[2];
      const j=JSON.parse(fs.readFileSync(f,"utf8"));
      j.mcpServers=j.mcpServers||{};
      j.mcpServers.qmd=JSON.parse(fs.readFileSync(bak,"utf8"));
      fs.writeFileSync(f, JSON.stringify(j,null,2));
      console.log("restored: Claude qmd -> original stdio ("+f+")");
    ' "$CJ" "$STDIO_BAK"
    echo "Start a NEW Claude/bebop session to pick up the change."
    ;;

  pi)
    [ -f "$PI_SETTINGS" ] || die "no pi settings at $PI_SETTINGS"
    cp -a "$PI_SETTINGS" "$PI_SETTINGS.bak-qmdattach"
    node -e '
      const fs=require("fs"); const f=process.argv[1], dir=process.argv[2];
      const j=JSON.parse(fs.readFileSync(f,"utf8"));
      j.skills=Array.isArray(j.skills)?j.skills:[];
      if(!j.skills.includes(dir)) j.skills.push(dir);
      fs.writeFileSync(f, JSON.stringify(j,null,2));
      console.log("pi skills now include: "+dir);
    ' "$PI_SETTINGS" "$SHARED_SKILLS"
    echo "pi will load the shared skills (incl. qmd-recall) on next run."
    ;;

  openclaw)
    AGENT="${1:-}"; [ -n "$AGENT" ] || die "usage: qmd-attach.sh openclaw <agent>"
    IDX="/root/.openclaw/agents/$AGENT/qmd/xdg-config/qmd/index.yml"
    [ -f "$IDX" ] || die "no qmd index.yml for agent '$AGENT' at $IDX"
    if grep -q "fleet-ops-shared:" "$IDX"; then
      echo "openclaw '$AGENT' already attached to shared fleet-ops."
    else
      cp -a "$IDX" "$IDX.bak-qmdattach"
      cat >> "$IDX" <<'YML'
  # --- shared fleet-ops (read-only view of the cross-agent memory) — added by qmd-attach.sh ---
  fleet-ops-shared:
    path: /root/fleet-memory
    pattern: "**/*.md"
YML
      echo "attached: openclaw '$AGENT' -> shared fleet-ops (read). Reindex on its next boot."
    fi
    ;;

  cli)
    cat <<EOF
# --- Attach a third-party CLI coding agent to the mairp fleet ---
# Models (pick one):
export ANTHROPIC_BASE_URL=http://127.0.0.1:8088     # cc-compass-shim (claude-* + qwen via Anthropic API)
export ANTHROPIC_AUTH_TOKEN=dummy
#   or OpenAI-style:
export OPENAI_BASE_URL=http://127.0.0.1:4000/v1     # LiteLLM (qwen3.6-*, gpt-5.5, gemini)
export OPENAI_API_KEY=\$(grep -E '^LITELLM_MASTER_KEY=' /root/litellm/.env | cut -d= -f2)

# Retrieval over MCP (for MCP-capable CLIs) — .mcp.json snippet:
{
  "mcpServers": {
    "qmd": { "type": "http", "url": "$GW_URL" }
  }
}
# Non-MCP CLIs: call /root/qmd-gateway/recall.sh "<query>" from the agent's shell/bash tool,
# and /root/qmd-gateway/qmd-remember.sh to persist facts.
EOF
    ;;

  status)
    echo "== qmd-attach status =="
    printf 'gateway  : %s ' "$GW_URL"; curl -fsS -m 2 "http://127.0.0.1:8190/status" >/dev/null 2>&1 && echo "(up)" || echo "(DOWN)"
    if [ -f "$CLAUDE_JSON_DEFAULT" ]; then
      printf 'claude   : '; node -e 'const j=require("/root/.claude.json"); const q=(j.mcpServers||{}).qmd||{}; console.log(q.type==="http"?("http -> "+q.url):"stdio (own index)")' 2>/dev/null || echo "?"
    fi
    if [ -f "$PI_SETTINGS" ]; then
      printf 'pi       : '; node -e 'const j=require("'"$PI_SETTINGS"'"); console.log((Array.isArray(j.skills)&&j.skills.includes("'"$SHARED_SKILLS"'"))?"shared skills attached":"not attached")' 2>/dev/null || echo "?"
    fi
    ;;

  *) die "unknown target '$cmd' (claude-http|claude-stdio|pi|openclaw <agent>|cli|status)" ;;
esac
