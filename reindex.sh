#!/usr/bin/env bash
# reindex.sh — refresh the SHARED qmd index (qmd-shared). flock-guarded; safe to run
# concurrently / in the background. Called by the systemd timer (qmd-gateway-reindex.timer)
# and on-demand by qmd-remember.sh after a write.
set -u
export XDG_CONFIG_HOME="/root/qmd-shared/xdg-config"
export XDG_CACHE_HOME="/root/qmd-shared/xdg-cache"
export VK_ICD_FILENAMES="/usr/share/vulkan/icd.d/intel_icd.json"
export VK_DRIVER_FILES="/usr/share/vulkan/icd.d/intel_icd.json"
export QMD_EMBED_MODEL="hf:Qwen/Qwen3-Embedding-0.6B-GGUF/Qwen3-Embedding-0.6B-Q8_0.gguf"

QMD="/usr/bin/qmd"
LOCK="/root/qmd-shared/.reindex.lock"
exec 9>"$LOCK" || exit 0
flock -n 9 || exit 0                       # a reindex is already running -> skip (no pile-ups)
"$QMD" update >/dev/null 2>&1 || exit 0
"$QMD" embed  >/dev/null 2>&1 || exit 0     # incremental: only new/changed docs
exit 0
