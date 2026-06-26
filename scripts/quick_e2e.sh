#!/usr/bin/env bash
# Quick E2E test script for local TTS service
# Usage: ./scripts/quick_e2e.sh [endpoint]

set -euo pipefail
ENDPOINT=${1:-http://127.0.0.1:8080}
VOICES_URL="$ENDPOINT/api/v1/voices"
TTS_URL="$ENDPOINT/api/v1/tts"

echo "Checking TTS voices endpoint: $VOICES_URL"
if ! curl -fsS "$VOICES_URL" -o /dev/null; then
  echo "ERROR: cannot reach $VOICES_URL"
  exit 2
fi

echo "Voices endpoint reachable. Listing voices:"
curl -fsS "$VOICES_URL" | jq -r '.[]?.id' || true

TMP_OUT="/tmp/tts_test_$(date +%s).mp3"
PAYLOAD='{"text":"测试合成：你好世界。","voice":"zh-CN-XiaoxiaoNeural","rate":0,"pitch":0,"style":"neutral"}'

echo "Requesting TTS synth to $TTS_URL -> $TMP_OUT"
if curl -fsS -X POST "$TTS_URL" -H "Content-Type: application/json" -d "$PAYLOAD" --output "$TMP_OUT"; then
  echo "Synthesis succeeded, saved to $TMP_OUT"
  ls -lh "$TMP_OUT"
  exit 0
else
  echo "Synthesis request failed"
  exit 3
fi
