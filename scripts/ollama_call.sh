#!/usr/bin/env bash
# Thin wrapper around Ollama /api/generate.
# Usage: ollama_call.sh <model> <prompt-file> [temperature] [seed]
# Reads prompt from file, prints model response to stdout. Exits non-zero on HTTP error.

set -euo pipefail

MODEL="${1:?model required (e.g. qwen2.5:7b)}"
PROMPT_FILE="${2:?prompt file required}"
TEMPERATURE="${3:-0.7}"
SEED="${4:-0}"
HOST="${OLLAMA_HOST:-http://localhost:11434}"

[[ -r "$PROMPT_FILE" ]] || { echo "prompt file not readable: $PROMPT_FILE" >&2; exit 2; }

PROMPT_JSON=$(jq -Rs . < "$PROMPT_FILE")

PAYLOAD=$(jq -n \
  --arg model "$MODEL" \
  --argjson prompt "$PROMPT_JSON" \
  --argjson temperature "$TEMPERATURE" \
  --argjson seed "$SEED" \
  '{model: $model, prompt: $prompt, stream: false, options: {temperature: $temperature, seed: $seed}}')

RESPONSE=$(curl -sS --fail-with-body -X POST "$HOST/api/generate" \
  -H 'Content-Type: application/json' \
  -d "$PAYLOAD")

echo "$RESPONSE" | jq -r '.response'
