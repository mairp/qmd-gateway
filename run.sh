#!/usr/bin/env bash
# run.sh — the shared qmd MCP gateway.
#
# Keeps ONE warm `qmd mcp` (stdio) process alive behind an SSE/HTTP bridge (mcp-proxy), so the
# embedding/rerank models load once and every coding agent on mairp queries the same warm index
# instead of each spawning its own stdio child. Exposes:
#   http://<bind>:8190/sse       — MCP-over-SSE endpoint (Claude/bebop, pi ext, OpenClaw mcporter, CLIs)
#   http://<bind>:8190/status    — mcp-proxy status (used as a liveness check)
#
# Binding: 0.0.0.0, but reachable ONLY from loopback + the wg0 subnet (10.8.0.0/24). This is
# enforced by the host firewall (/usr/local/bin/setup-firewall.sh): INPUT policy is DROP and the
# only broad allow is `-s 10.8.0.0/24` plus `-i lo`. No public interface, no new firewall rule
# needed (and no key material lives here). See /root/qmd-gateway/README.md.
set -u

export XDG_CONFIG_HOME="/root/qmd-shared/xdg-config"
export XDG_CACHE_HOME="/root/qmd-shared/xdg-cache"
# Pin Vulkan to the Intel iGPU; the discrete RTX 3090 is reserved for llama.cpp inference
# (llama-swap) and must never be contended by qmd embedding/rerank.
export VK_ICD_FILENAMES="/usr/share/vulkan/icd.d/intel_icd.json"
export VK_DRIVER_FILES="/usr/share/vulkan/icd.d/intel_icd.json"
export QMD_EMBED_MODEL="hf:Qwen/Qwen3-Embedding-0.6B-GGUF/Qwen3-Embedding-0.6B-Q8_0.gguf"

SSE_PORT="${QMD_GATEWAY_PORT:-8190}"
SSE_HOST="${QMD_GATEWAY_HOST:-0.0.0.0}"
QMD="/usr/bin/qmd"

# mcp-proxy runs a stdio->SSE/StreamableHTTP server: it launches `qmd mcp` once and fronts it
# on --port. Use --port/--host (the --sse-port/--sse-host aliases are deprecated and are NOT
# honored by the installed mcp-proxy version — they fall back to a random loopback port).
# --pass-environment forwards the XDG_/VK_/QMD_ vars above into the spawned `qmd mcp` child.
exec uvx mcp-proxy \
  --host "$SSE_HOST" \
  --port "$SSE_PORT" \
  --pass-environment \
  -- "$QMD" mcp
