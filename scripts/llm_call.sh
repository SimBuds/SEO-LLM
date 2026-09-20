#!/usr/bin/env bash
# Thin wrapper around the llama.cpp router's OpenAI-compatible chat endpoint.
# Usage: llm_call.sh <prompt-file> [temperature] [seed] [schema-file]
# Sends prompts/system.md as the system message on every call: router models
# carry no built-in system prompt, so a call without one gets the bare model.
# With a schema file, the router constrains the reply to that JSON schema.
# Reads the router's served context size first and refuses to call below MIN_CTX.
# Prints the reply to stdout. Exits non-zero on HTTP error or an empty reply.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYSTEM_FILE="$ROOT/prompts/system.md"

PROMPT_FILE="${1:?prompt file required}"
TEMPERATURE="${2:-0.7}"
SEED="${3:-0}"
SCHEMA_FILE="${4:-}"
HOST="${LLM_HOST:-http://localhost:8080}"
# Optional caps: LLM_MAX_TOKENS bounds the reply (a schema-constrained reply can
# otherwise loop until the context fills), LLM_TIMEOUT bounds the request in seconds.
MAX_TOKENS="${LLM_MAX_TOKENS:-}"
TIMEOUT="${LLM_TIMEOUT:-}"
MODEL="${LLM_MODEL:-qwen}"
MIN_CTX=32768

[[ -r "$PROMPT_FILE" ]] || { echo "prompt file not readable: $PROMPT_FILE" >&2; exit 2; }
# An empty prompt is never intentional, and it does not fail loudly on its own:
# the router answers the system message alone and returns confident, unrelated
# text that can even satisfy a schema. Seen 2026-09-20 when a mis-chained
# fill_prompt.sh left the file empty.
grep -q '[^[:space:]]' "$PROMPT_FILE" \
  || { echo "prompt file is empty: $PROMPT_FILE" >&2
       echo "  the step that wrote it failed. Chain the fill and the call with && so this cannot reach the router." >&2
       exit 2; }
[[ -r "$SYSTEM_FILE" ]] || { echo "system prompt not readable: $SYSTEM_FILE" >&2; exit 2; }

# An empty or non-object schema file must fail here: sent as-is, the router
# would answer unconstrained and the caller would never know.
SCHEMA_ARGS=(--argjson schema null --arg schema_name "")
if [[ -n "$SCHEMA_FILE" ]]; then
  [[ -r "$SCHEMA_FILE" ]] || { echo "schema file not readable: $SCHEMA_FILE" >&2; exit 2; }
  jq -e 'type == "object"' "$SCHEMA_FILE" > /dev/null \
    || { echo "schema file is not a JSON object: $SCHEMA_FILE" >&2; exit 2; }
  SCHEMA_ARGS=(--slurpfile schema "$SCHEMA_FILE" --arg schema_name "$(basename "$SCHEMA_FILE" .schema.json)")
fi

# Context is fixed at load time by the router's preset, so it is read here and
# checked before any work: a preset deployed below MIN_CTX would otherwise
# shrink the budget silently. An unloaded model has no .meta, but its
# status.args still carry --ctx-size, so this never forces a model load.
MODELS_JSON=$(curl -sS --fail-with-body "$HOST/models") \
  || { rc=$?; echo "$MODELS_JSON" >&2; echo "cannot read $HOST/models to check context size" >&2; exit "$rc"; }

SERVED_CTX=$(jq -er --arg m "$MODEL" '
  ([.data[]? | select(.id == $m)][0] // error("model not served by the router: " + $m)) as $e
  | ($e.status.args // []) as $args
  | ($e.meta.n_ctx // ($args | index("--ctx-size") as $i | if $i == null then null else $args[$i + 1] end))
  | if . == null then error("no context size in the /models entry for " + $m) else (tonumber | floor) end
' <<< "$MODELS_JSON")

if (( SERVED_CTX < MIN_CTX )); then
  echo "router serves $SERVED_CTX tokens of context for $MODEL, below the $MIN_CTX this app needs" >&2
  exit 3
fi

# Sampling pinned in-repo rather than inherited from the router preset.
# Values match Local-LLM build-qwen PARAMS as of 2026-09-14. There is no
# per-request context override; an oversized prompt returns HTTP 400.
PAYLOAD=$(jq -n \
  --arg model "$MODEL" \
  --rawfile system "$SYSTEM_FILE" \
  --rawfile prompt "$PROMPT_FILE" \
  --argjson temperature "$TEMPERATURE" \
  --argjson seed "$SEED" \
  --arg max_tokens "$MAX_TOKENS" \
  "${SCHEMA_ARGS[@]}" \
  '{
    model: $model,
    messages: [
      {role: "system", content: $system},
      {role: "user", content: $prompt}
    ],
    stream: false,
    temperature: $temperature,
    seed: $seed,
    top_p: 0.95,
    top_k: 40,
    min_p: 0.05,
    presence_penalty: 0.0,
    repeat_penalty: 1.05,
    chat_template_kwargs: {enable_thinking: false}
  }
  + (if $max_tokens == "" then {} else {max_tokens: ($max_tokens | tonumber)} end)
  + if $schema == null then {} else
      # Nested json_schema shape per the Local-LLM contract. The top-level
      # "schema" shape from the llama-server README was ignored on build 10968.
      {response_format: {type: "json_schema", json_schema: {name: $schema_name, schema: $schema[0]}}}
    end')

# On HTTP error, --fail-with-body leaves the server's explanation in RESPONSE.
# Print it before exiting, or set -e drops it and only the status code shows.
RESPONSE=$(curl -sS --fail-with-body ${TIMEOUT:+--max-time "$TIMEOUT"} -X POST "$HOST/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  --data-binary @- <<< "$PAYLOAD") || { rc=$?; echo "$RESPONSE" >&2; exit "$rc"; }

echo "$RESPONSE" | jq -er '.choices[0].message.content'
