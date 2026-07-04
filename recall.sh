#!/usr/bin/env bash
# recall.sh — fail-open qmd memory recall against the SHARED fleet index (qmd-shared).
# Generalized from /root/.claude/qmd/claude-recall.sh; used by the pi `qmd-recall` skill and
# by any agent's bash tool that wants shared-memory recall without an MCP client.
#
# Usage: recall.sh [-m fast|deep|query] [-n N] [-c collection] [-s minscore] "<query>"
#   fast  (default): normalized BM25 search, no LLM, timeout 6s
#   deep           : vec-only (vec: + --no-rerank, no expansion) ~5s CPU; full hybrid if GPU flag
#   query          : full hybrid (auto-expansion + rerank), timeout 200s
# Always exits 0. Emits a compact <memory-recall> block on stdout, or nothing.

set -u
export XDG_CONFIG_HOME="/root/qmd-shared/xdg-config"
export XDG_CACHE_HOME="/root/qmd-shared/xdg-cache"
export VK_ICD_FILENAMES="/usr/share/vulkan/icd.d/intel_icd.json"
export VK_DRIVER_FILES="/usr/share/vulkan/icd.d/intel_icd.json"
export QMD_EMBED_MODEL="hf:Qwen/Qwen3-Embedding-0.6B-GGUF/Qwen3-Embedding-0.6B-Q8_0.gguf"

QMD="/usr/bin/qmd"
MODE=fast; N=""; COLL=""; MINSCORE=""
while [ $# -gt 0 ]; do
  case "$1" in
    -m) MODE="${2:-fast}"; shift 2 ;;
    -n) N="${2:-}"; shift 2 ;;
    -c) COLL="${2:-}"; shift 2 ;;
    -s) MINSCORE="${2:-}"; shift 2 ;;
    --) shift; break ;;
    -*) shift ;;
    *) break ;;
  esac
done

QUERY="${*:-}"
QUERY="$(printf '%s' "$QUERY" | tr '\n' ' ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
[ -z "$QUERY" ] && exit 0
[ "${#QUERY}" -lt 3 ] && exit 0

normalize() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9 ' ' ' | tr ' ' '\n' \
    | grep -Evx 'the|is|a|an|of|to|in|on|for|and|or|how|what|why|when|where|who|do|does|did|can|could|would|should|i|you|it|this|that|with|are|was|be|my|me|we|us|your|please|tell|show|about|get|whats|its|so|if|but|as|at|by|from|have|has|had|will|just|im|ive' 2>/dev/null \
    | tr '\n' ' ' | sed -e 's/  */ /g' -e 's/^ //' -e 's/ $//'
}

# The shared gateway lives on the host; its GPU flag mirrors Claude's (Intel iGPU via Vulkan).
GPU_FLAG="/root/.claude/qmd/.gpu"

case "$MODE" in
  deep)
    if [ -f "$GPU_FLAG" ]; then
      TIMEOUT=60; DEFN=6; [ -z "$MINSCORE" ] && MINSCORE=0
      CMD=(query "$QUERY" --format json)
    else
      TIMEOUT=30; DEFN=6; [ -z "$MINSCORE" ] && MINSCORE=0.15
      CMD=(query "vec: $QUERY" --no-rerank --format json)
    fi ;;
  query)
    TIMEOUT=200; DEFN=6; [ -z "$MINSCORE" ] && MINSCORE=0
    CMD=(query "$QUERY" --format json) ;;
  fast|*)
    TIMEOUT=6; DEFN=3; [ -z "$MINSCORE" ] && MINSCORE=0.1
    NQ="$(normalize "$QUERY")"; [ -z "$NQ" ] && exit 0
    CMD=(search "$NQ" --format json) ;;
esac
[ -z "$N" ] && N="$DEFN"
CMD=("${CMD[0]}" "${CMD[1]}" -n "$N" "${CMD[@]:2}")
[ -n "$COLL" ] && CMD+=(-c "$COLL")

JSON="$(timeout -k 2 "$TIMEOUT" "$QMD" "${CMD[@]}" 2>/dev/null)" || exit 0
[ -z "$JSON" ] && exit 0

printf '%s' "$JSON" | MINSCORE="$MINSCORE" node -e '
let raw=""; const MIN=parseFloat(process.env.MINSCORE||"0")||0;
process.stdin.on("data",d=>raw+=d); process.stdin.on("end",()=>{
  let arr; try { arr = JSON.parse(raw); } catch(e){ process.exit(0); }
  if(!Array.isArray(arr)||arr.length===0) process.exit(0);
  const clip=(s,n)=>{ s=String(s||"").replace(/\s+/g," ").trim(); return s.length>n?s.slice(0,n)+"…":s; };
  let out=[], budget=1800;
  for(const r of arr){
    if(typeof r.score==="number" && r.score<MIN) continue;
    const title=clip(r.title||r.file||"untitled",80);
    const file=String(r.file||"");
    const snip=clip(r.snippet||"",260);
    const block=`- ${title} [${file}]\n  ${snip}`;
    if(budget-block.length<0) break;
    budget-=block.length; out.push(block);
  }
  if(out.length===0) process.exit(0);
  process.stdout.write("<memory-recall source=\"qmd-fleet\">\n");
  process.stdout.write("Possibly-relevant shared fleet memory (retrieved, may be stale — verify before relying):\n");
  process.stdout.write(out.join("\n")+"\n");
  process.stdout.write("Read full files with: qmd get <qmd-uri>. Persist a new fact with: /root/qmd-gateway/qmd-remember.sh.\n");
  process.stdout.write("</memory-recall>\n");
});
' 2>/dev/null || exit 0
exit 0
