#!/usr/bin/env bash
# Download public audio samples for default character voices.
# Sources are from official TTS model repos with permissive licenses.
set -euo pipefail

DEST="Sources/FeatureTTSReaderApp/Models/default_samples"
mkdir -p "$DEST"

echo "=== Downloading default voice samples ==="

# CosyVoice 3 zero-shot reference (Chinese female, from FunAudioLLM official repo)
# License: Apache 2.0 (FunAudioLLM/CosyVoice)
if [ ! -f "$DEST/zero_shot_prompt.wav" ]; then
  echo "  [1/3] CosyVoice 3 zero-shot reference..."
  wget -q "https://huggingface.co/FunAudioLLM/Fun-CosyVoice3-0.5B-2512/resolve/main/asset/zero_shot_prompt.wav" \
    -O "$DEST/zero_shot_prompt.wav" 2>/dev/null || \
  curl -sL "https://huggingface.co/FunAudioLLM/Fun-CosyVoice3-0.5B-2512/resolve/main/asset/zero_shot_prompt.wav" \
    -o "$DEST/zero_shot_prompt.wav"
  echo "    done ($(du -h "$DEST/zero_shot_prompt.wav" | cut -f1))"
fi

# Qwen3-TTS clone reference (English female, from Qwen official OSS)
# License: Apache 2.0 (QwenLM/Qwen3-TTS)
if [ ! -f "$DEST/qwen_clone.wav" ]; then
  echo "  [2/3] Qwen3-TTS clone reference..."
  curl -sL "https://qianwen-res.oss-cn-beijing.aliyuncs.com/Qwen3-TTS-Repo/clone.wav" \
    -o "$DEST/qwen_clone.wav"
  echo "    done ($(du -h "$DEST/qwen_clone.wav" | cut -f1))"
fi

# Qwen3-TTS tokenizer demo (Chinese, from Qwen official OSS)
# License: Apache 2.0 (QwenLM/Qwen3-TTS)
if [ ! -f "$DEST/qwen_demo.wav" ]; then
  echo "  [3/3] Qwen3-TTS tokenizer demo..."
  curl -sL "https://qianwen-res.oss-cn-beijing.aliyuncs.com/Qwen3-TTS-Repo/tokenizer_demo_1.wav" \
    -o "$DEST/qwen_demo.wav"
  echo "    done ($(du -h "$DEST/qwen_demo.wav" | cut -f1))"
fi

echo ""
echo "=== Samples downloaded ==="
ls -lh "$DEST/"
echo ""
echo "Transcripts:"
echo "  zero_shot_prompt.wav: 希望你以后能够做的比我还好呦。"
echo "  qwen_clone.wav:       Okay. Yeah. I resent you. I love you..."
echo "  qwen_demo.wav:        (Chinese demo audio)"
echo ""
echo "Use these in CharacterEditorView to enroll default voices."
