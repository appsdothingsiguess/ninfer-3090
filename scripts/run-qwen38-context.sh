#!/usr/bin/env bash
set -euo pipefail

# Start the RTX 3090 Qwen3.8 server with a user-selected context limit.
# KV capacity is automatic: startup succeeds only when one full request at
# the chosen limit fits in the remaining GPU memory.

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
server="${NINFER_SERVER:-$root/../build-sm86-gcc15-vcpkg/apps/ninfer-serve}"
if [[ ! -x "$server" && -x "$root/../build-sm86/apps/ninfer-serve" ]]; then
  server="$root/../build-sm86/apps/ninfer-serve"
fi

model="${1:-${NINFER_MODEL_DIR:-/home/john/llm-stack/models}/qwen3_8_27b.ninfer}"
# Bind to the LAN by default so clients on this machine's network can use the server.
# Set NINFER_HOST=127.0.0.1 when localhost-only access is preferred.
host="${NINFER_HOST:-0.0.0.0}"
port="${NINFER_PORT:-18080}"
request_log="${NINFER_REQUEST_LOG:-$root/../logs/requests.jsonl}"

if [[ ! -x "$server" ]]; then
  printf 'Missing executable: %s\n' "$server" >&2
  printf '%s\n' 'Set NINFER_SERVER to your ninfer-serve executable.' >&2
  exit 1
fi
if [[ ! -f "$model" ]]; then
  printf 'Missing model: %s\n' "$model" >&2
  printf '%s\n' 'Set NINFER_MODEL_DIR or pass the model path as the first argument.' >&2
  exit 1
fi

read -r -p 'Maximum context tokens [150000]: ' max_context
max_context="${max_context:-150000}"
if [[ ! "$max_context" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Context must be a positive whole number, for example 65536 or 131072.\n' >&2
  exit 2
fi

read -r -p 'Default response token limit [8192]: ' default_max_tokens
default_max_tokens="${default_max_tokens:-8192}"
if [[ ! "$default_max_tokens" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Response token limit must be a positive whole number, for example 4096 or 8192.\n' >&2
  exit 2
fi

read -r -p 'Default reasoning [medium] (none or medium): ' reasoning
reasoning="${reasoning:-medium}"
case "$reasoning" in
none) no_thinking=(--no-thinking) ;;
medium) no_thinking=() ;;
*)
  printf '%s\n' 'The server can set only none or the model default (medium).' >&2
  printf '%s\n' 'Choose low or xhigh per request in Pi; see thinkingLevelMap in models.json.' >&2
  exit 2
  ;;
esac

request_log_args=()
if [[ -n "$request_log" ]]; then
  mkdir -p -- "$(dirname -- "$request_log")"
  request_log_args=(--request-log-jsonl "$request_log")
fi

printf 'Starting Qwen3.8-27B at http://%s:%s/v1\n' "$host" "$port"
printf 'Context limit: %s; default response limit: %s; reasoning: %s; KV capacity: automatic.\n' \
  "$max_context" "$default_max_tokens" "$reasoning"
printf '%s\n' 'If startup succeeds, the selected context fits at least one request on the GPU.'
if [[ -n "$request_log" ]]; then
  printf 'Structured request log: %s\n' "$request_log"
fi

exec "$server" "$model" \
  --host "$host" --port "$port" \
  --max-context "$max_context" --kv-capacity auto \
  --max-concurrency 1 --max-pending-requests 16 \
  --default-max-tokens "$default_max_tokens" \
  --prefill-chunk 1024 --kv-dtype int8 \
  --spec mtp --draft-tokens 3 --lm-head-draft \
  "${request_log_args[@]}" \
  "${no_thinking[@]}"
