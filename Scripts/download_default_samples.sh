#!/usr/bin/env bash
# Download public audio samples for default character voices.
# Sources from official TTS model repos with permissive licenses (Apache 2.0).
set -euo pipefail

DEST="Sources/FeatureTTSReaderApp/Models/default_samples"
mkdir -p "$DEST"

echo "=== Downloading default voice samples ==="

# CosyVoice 3 zero-shot reference (Chinese female, from GitHub raw)
# Repo: github.com/FunAudioLLM/CosyVoice (Apache 2.0)
if [ ! -f "$DEST/cosyvoice_zero_shot.wav" ]; then
  echo "  [1/6] CosyVoice 3 zero-shot prompt (Chinese reference)..."
  curl -sL "https://raw.githubusercontent.com/FunAudioLLM/CosyVoice/main/asset/zero_shot_prompt.wav" \
    -o "$DEST/cosyvoice_zero_shot.wav"
  echo "    done ($(du -h "$DEST/cosyvoice_zero_shot.wav" | cut -f1))"
fi

# CosyVoice 3 cross-lingual reference (Chinese female, different voice)
if [ ! -f "$DEST/cosyvoice_cross_lingual.wav" ]; then
  echo "  [2/6] CosyVoice 3 cross-lingual prompt..."
  curl -sL "https://raw.githubusercontent.com/FunAudioLLM/CosyVoice/main/asset/cross_lingual_prompt.wav" \
    -o "$DEST/cosyvoice_cross_lingual.wav"
  echo "    done ($(du -h "$DEST/cosyvoice_cross_lingual.wav" | cut -f1))"
fi

# Qwen3-TTS clone reference (English female, from Qwen official OSS)
# License: Apache 2.0 (QwenLM/Qwen3-TTS)
if [ ! -f "$DEST/qwen_clone.wav" ]; then
  echo "  [3/6] Qwen3-TTS clone reference (English female)..."
  curl -sL "https://qianwen-res.oss-cn-beijing.aliyuncs.com/Qwen3-TTS-Repo/clone.wav" \
    -o "$DEST/qwen_clone.wav"
  echo "    done ($(du -h "$DEST/qwen_clone.wav" | cut -f1))"
fi

# Qwen3-TTS demo (Chinese, from Qwen official OSS)
if [ ! -f "$DEST/qwen_demo.wav" ]; then
  echo "  [4/6] Qwen3-TTS demo (Chinese)..."
  curl -sL "https://qianwen-res.oss-cn-beijing.aliyuncs.com/Qwen3-TTS-Repo/tokenizer_demo_1.wav" \
    -o "$DEST/qwen_demo.wav"
  echo "    done ($(du -h "$DEST/qwen_demo.wav" | cut -f1))"
fi

# Qwen3-TTS Chinese female demo
if [ ! -f "$DEST/qwen_chinese_female.wav" ]; then
  echo "  [5/6] Qwen3-TTS Chinese female demo..."
  curl -sL "https://qianwen-res.oss-cn-beijing.aliyuncs.com/Qwen3-TTS-Repo/tokenizer_demo_2.wav" \
    -o "$DEST/qwen_chinese_female.wav"
  echo "    done ($(du -h "$DEST/qwen_chinese_female.wav" | cut -f1))"
fi

# Qwen3-TTS Chinese male demo
if [ ! -f "$DEST/qwen_chinese_male.wav" ]; then
  echo "  [6/6] Qwen3-TTS Chinese male demo..."
  curl -sL "https://qianwen-res.oss-cn-beijing.aliyuncs.com/Qwen3-TTS-Repo/tokenizer_demo_3.wav" \
    -o "$DEST/qwen_chinese_male.wav"
  echo "    done ($(du -h "$DEST/qwen_chinese_male.wav" | cut -f1))"
fi

echo ""
echo "=== All samples downloaded ==="
ls -lh "$DEST/"
echo ""
echo "Transcripts (approximate):"
echo "  cosyvoice_zero_shot.wav:  希望你以后能够做的比我还好呦 (female, neutral)"
echo "  cosyvoice_cross_lingual:  (cross-lingual reference, female)"
echo "  qwen_clone.wav:           Okay. Yeah. I resent you... (English female)"
echo "  qwen_demo.wav:            (Chinese demo)"
echo "  qwen_chinese_female.wav:  (Chinese female demo)"
echo "  qwen_chinese_male.wav:    (Chinese male demo)"
echo ""
echo "Use these in CharacterEditorView to enroll default voices."
echo "Recommended mappings:"
echo "  cosyvoice_zero_shot.wav  → 旁白 (narrator, neutral female)"
echo "  qwen_chinese_female.wav  → 女性角色 (female characters)"
echo "  qwen_chinese_male.wav    → 男性角色 (male characters)"
echo "  qwen_clone.wav           → English-speaking characters"
