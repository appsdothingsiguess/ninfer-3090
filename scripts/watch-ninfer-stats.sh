#!/usr/bin/env bash
set -euo pipefail

# Follow NInfer's optional JSONL request log and show live request activity.
# Start the server with NINFER_REQUEST_LOG=/path/to/requests.jsonl first.

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
log_path="${1:-$root/../logs/requests.jsonl}"

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' 'jq is required; install it with: sudo apt-get install jq' >&2
  exit 1
fi

if [[ ! -f "$log_path" ]]; then
  printf 'Log not found: %s\n' "$log_path" >&2
  printf '%s\n' 'Restart NInfer with NINFER_REQUEST_LOG=/path/to/requests.jsonl.' >&2
  exit 1
fi

printf 'Watching NInfer activity: %s\n' "$log_path"
printf '%s\n' 'Shows new events only. Press Ctrl+C to stop.'

tail -n 0 -F "$log_path" | while IFS= read -r line; do
  printf '%s\n' "$line" | jq -r '
    def clock: (.timestamp_unix_ms / 1000 | floor | strftime("%H:%M:%S"));
    def rate($tokens; $seconds):
      if $tokens > 0 and $seconds > 0 then (($tokens / $seconds) | tostring) else "n/a" end;

    if .event == "request_start" then
      "[\(clock)] START req=\(.request.request_id) model=\(.request.model) " +
      "messages=\(.request.message_count) max_out=\(.request.requested_output_tokens) " +
      "thinking=\(.request.enable_thinking) tools=\(.request.tool_count)"
    elif .event == "throughput" then
      "[\(clock)] LIVE prefill=\(.throughput_tokens_per_second.prefill|floor) tok/s " +
      "decode=\(.throughput_tokens_per_second.decode|floor) tok/s " +
      "running=\(.scheduler.running) prefilling=\(.scheduler.prefilling) " +
      "ready=\(.scheduler.decode_ready)"
    elif .event == "request_done" then
      "[\(clock)] DONE req=\(.request.request_id) finish=\(.result.finish_reason) " +
      "prompt=\(.result.prompt_tokens) completion=\(.result.completion_tokens) " +
      "ttft=\((.timings_seconds.ttft * 1000)|floor)ms " +
      "prefill=\(rate(.result.computed_prefill_tokens; .timings_seconds.prefill)) tok/s " +
      "decode=\(rate((.result.completion_tokens - 1); .timings_seconds.decode)) tok/s " +
      "wall=\(.timings_seconds.total)s"
    elif .event == "request_error" then
      "[\(clock)] ERROR req=\(.request.request_id) \(.error.message)"
    else empty end
  ' 2>/dev/null || true
done
