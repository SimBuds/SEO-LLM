#!/usr/bin/env bash
# Thin wrapper around the llama.cpp router's OpenAI-compatible chat endpoint.
# Usage: llm_call.sh <prompt-file> [temperature] [seed] [schema-file]
# Sends prompts/system.md as the system message on every call: router models
# carry no built-in system prompt, so a call without one gets the bare model.
# With a schema file, the router constrains the reply to that JSON schema.
# Prints the reply to stdout. Exits non-zero on HTTP error or an empty reply.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYSTEM_FILE="$ROOT/prompts/system.md"

PROMPT_FILE="${1:?prompt file required}"
TEMPERATURE="${2:-0.7}"
SEED="${3:-0}"
SCHEMA_FILE="${4:-}"
HOST="${LLM_HOST:-http://localhost:8080}"
MODEL="${LLM_MODEL:-qwen}"

[[ -r "$PROMPT_FILE" ]] || { echo "prompt file not readable: $PROMPT_FILE" >&2; exit 2; }
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

# Sampling pinned in-repo rather than inherited from the router preset.
# Values match Local-LLM build-qwen PARAMS as of 2026-09-14. Context is fixed
# at 32768 by the preset (no per-request override); overflow returns HTTP 400.
PAYLOAD=$(jq -n \
  --arg model "$MODEL" \
  --rawfile system "$SYSTEM_FILE" \
  --rawfile prompt "$PROMPT_FILE" \
  --argjson temperature "$TEMPERATURE" \
  --argjson seed "$SEED" \
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
  + if $schema == null then {} else
      # Nested json_schema shape per the Local-LLM contract. The top-level
      # "schema" shape from the llama-server README was ignored on build 10968.
      {response_format: {type: "json_schema", json_schema: {name: $schema_name, schema: $schema[0]}}}
    end')

# On HTTP error, --fail-with-body leaves the server's explanation in RESPONSE.
# Print it before exiting, or set -e drops it and only the status code shows.
RESPONSE=$(curl -sS --fail-with-body -X POST "$HOST/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  --data-binary @- <<< "$PAYLOAD") || { rc=$?; echo "$RESPONSE" >&2; exit "$rc"; }

echo "$RESPONSE" | jq -er '.choices[0].message.content'
