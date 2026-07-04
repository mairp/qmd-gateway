#!/usr/bin/env bash
# qmd-remember.sh — persist a fact into the SHARED fleet memory (/root/fleet-memory) so every
# agent recalls it via the qmd gateway. A bare `qmd` has no write path; this is it.
#
# Usage:
#   qmd-remember.sh "<title>" "<body>" [--type project|infra|feedback|reference]
#
# Writes a slugged markdown leaf under /root/fleet-memory/<topicdir>/<slug>.md with YAML
# frontmatter, adds/refreshes a one-line pointer under the matching section of MEMORY.md,
# then triggers an incremental reindex. Idempotent on the slug (re-running updates in place).
set -u

MEMDIR="/root/fleet-memory"
INDEX="$MEMDIR/MEMORY.md"
REINDEX="/root/qmd-gateway/reindex.sh"

TITLE=""; BODY=""; TYPE="project"
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --type) TYPE="${2:-project}"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) args+=("$1"); shift ;;
  esac
done
TITLE="${args[0]:-}"; BODY="${args[1]:-}"

if [ -z "$TITLE" ] || [ -z "$BODY" ]; then
  echo "usage: qmd-remember.sh \"<title>\" \"<body>\" [--type project|infra|feedback|reference]" >&2
  exit 2
fi

case "$TYPE" in
  infra)     TOPIC="infra";     SECTION="## Infrastructure" ;;
  feedback)  TOPIC="feedback";  SECTION="## Feedback" ;;
  reference) TOPIC="reference"; SECTION="## Reference" ;;
  project|*) TOPIC="projects";  SECTION="## Projects" ;;
esac

# slug: lowercase, alnum + dashes, collapse repeats, trim
SLUG="$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' \
        | sed -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')"
[ -z "$SLUG" ] && SLUG="note-$(printf '%s' "$TITLE" | cksum | cut -d' ' -f1)"

mkdir -p "$MEMDIR/$TOPIC"
LEAF="$MEMDIR/$TOPIC/$SLUG.md"

# One-line description = first line of the body, trimmed to ~100 chars.
DESC="$(printf '%s' "$BODY" | tr '\n' ' ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | cut -c1-100)"

cat > "$LEAF" <<EOF
---
name: $SLUG
description: $DESC
metadata:
  type: $TYPE
---

# $TITLE

$BODY
EOF

# Ensure the section exists in MEMORY.md, then add the pointer if not already present.
POINTER="- [$TITLE]($TOPIC/$SLUG.md) — $DESC"
if ! grep -qF "]($TOPIC/$SLUG.md)" "$INDEX" 2>/dev/null; then
  if grep -qF "$SECTION" "$INDEX" 2>/dev/null; then
    # insert the pointer on the line after the section header
    awk -v sec="$SECTION" -v ptr="$POINTER" '
      { print }
      $0==sec && !done { print ptr; done=1 }
    ' "$INDEX" > "$INDEX.tmp" && mv "$INDEX.tmp" "$INDEX"
  else
    printf '\n%s\n%s\n' "$SECTION" "$POINTER" >> "$INDEX"
  fi
fi

echo "remembered: $LEAF"
# Kick an incremental reindex so the fact is recallable promptly (background, flock-guarded).
"$REINDEX" >/dev/null 2>&1 & disown
exit 0
