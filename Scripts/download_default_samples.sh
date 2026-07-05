#!/usr/bin/env bash
# Download public audio samples for default character voices.
# Sources:
#   1. IndexTTS2 demo page — emotion-labeled Chinese reference audio (AAC)
#      https://index-tts.github.io/index-tts2.github.io/
#   2. PaddleSpeech CSMSC GT — Chinese female human recordings (WAV)
#      https://paddlespeech.bj.bcebos.com/Parakeet/docs/demos/
#   3. CosyVoice official repo — zero-shot & cross-lingual prompts (WAV)
#      https://github.com/FunAudioLLM/CosyVoice
#   4. Qwen3-TTS official repo — clone & tokenizer demos (WAV)
#      https://github.com/QwenLM/Qwen3-TTS
#
# License: all sources are Apache 2.0 or similarly permissive.
# Note: AAC files are auto-converted to WAV via ffmpeg (if installed)
#       for CAM++ compatibility. If ffmpeg is missing, AAC files are
#       kept as-is (CosyVoiceService can handle AAC via AVFoundation).
set -euo pipefail

DEST="Sources/FeatureTTSReaderApp/Models/default_samples"
mkdir -p "$DEST"

INDEX_BASE="https://index-tts.github.io/index-tts2.github.io"
PADDLE_BASE="https://paddlespeech.bj.bcebos.com/Parakeet/docs/demos"
COSY_BASE="https://raw.githubusercontent.com/FunAudioLLM/CosyVoice/main/asset"
QWEN_BASE="https://qianwen-res.oss-cn-beijing.aliyuncs.com/Qwen3-TTS-Repo"

HAVE_FFMPEG=false
command -v ffmpeg &>/dev/null && HAVE_FFMPEG=true

download() {
  local url="$1" dest="$2" label="$3"
  if [ -f "$dest" ]; then
    echo "  SKIP (exists): $dest"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  echo "  → $label ($dest)"
  local code size
  code=$(curl -sL -o "$dest" -w "%{http_code}" "$url")
  if [ "$code" != "200" ]; then
    echo "    FAIL: HTTP $code from $url"
    rm -f "$dest"
    return 1
  fi
  size=$(du -h "$dest" | cut -f1)
  echo "    OK (HTTP 200, $size)"
}

to_wav() {
  local src="$1" dst="$2"
  if [ -f "$dst" ]; then
    echo "    SKIP convert (exists): $dst"
    return 0
  fi
  if ! $HAVE_FFMPEG; then
    echo "    SKIP convert (no ffmpeg): keeping .aac"
    return 0
  fi
  ffmpeg -i "$src" -ar 16000 -ac 1 -sample_fmt s16 "$dst" -y -loglevel error 2>/dev/null
  rm -f "$src"
  echo "    CONVERTED: $(basename "$src") → $(basename "$dst") ($(du -h "$dst" | cut -f1))"
}

# Clean old flat-structure samples from previous version (if any)
# Old script put files directly in DEST; new script uses subdirectories.
OLD_FLAT=(
  "cosyvoice_zero_shot.wav" "cosyvoice_cross_lingual.wav"
  "qwen_clone.wav" "qwen_demo.wav" "qwen_chinese_female.wav" "qwen_chinese_male.wav"
)
for f in "${OLD_FLAT[@]}"; do
  if [ -f "$DEST/$f" ]; then
    echo "  [cleanup] removing old flat sample: $DEST/$f"
    rm -f "$DEST/$f"
  fi
done

echo "=== Downloading default voice samples ==="
echo "Target: $DEST"
echo "ffmpeg available: $HAVE_FFMPEG"
echo ""

# ═══════════════════════════════════════════════════════════════
# GROUP A: IndexTTS2 emotion-labeled Chinese reference prompts
# These are ~3s AAC clips with clear emotion labels.
# Great for matching CosyVoice emotion tags: angry/sad(happy)/calm/etc.
# ═══════════════════════════════════════════════════════════════
echo "--- Group A: IndexTTS2 emotion prompts (14 files) ---"
declare -A idx_emo=(
  ["08_angry_3.aac"]="angry, Chinese, 男声愤怒语气"
  ["12_angry_2.aac"]="angry, Chinese, 另男声愤怒语气"
  ["05_cry_1.aac"]="sad/cry, Chinese, 男声哭泣语气"
  ["10_cry_2.aac"]="sad/cry, Chinese, 男声哭泣语气"
  ["03_low_3.aac"]="depressed, Chinese, 女声低落"
  ["12_low_3.aac"]="depressed, Chinese, 男声低沉"
  ["09_happy_3.aac"]="happy, Chinese, 女声开心"
  ["10_happy_2.aac"]="happy, Chinese, 女声愉快"
  ["08_fear_3.aac"]="fear, Chinese, 男声恐惧"
  ["11_fear_2.aac"]="fear, Chinese, 男声恐惧"
  ["06_surprise_2.aac"]="surprise, Chinese, 男声惊讶"
  ["12_surprise_2.aac"]="surprise, Chinese, 女声惊讶"
  ["07_calm_3.aac"]="calm, Chinese, 女声平静"
  ["06_calm_2.aac"]="calm, Chinese, 男声冷静"
)
for fname in "${!idx_emo[@]}"; do
  label="${idx_emo[$fname]}"
  tag="${label%%,*}"  # angry/sad/happy etc
  aac="$DEST/indextts2_emo/${fname}"
  wav="${aac%.aac}.wav"
  download "$INDEX_BASE/ex1/prompt/$fname" "$aac" "[$tag] $label"
  to_wav "$aac" "$wav"
done
echo ""

# ═══════════════════════════════════════════════════════════════
# GROUP B: IndexTTS2 distinct speaker timbre prompts
# These are ~3-5s AAC clips of 3 different real human speakers.
# Perfect for assigning distinct voices to characters.
# ═══════════════════════════════════════════════════════════════
echo "--- Group B: IndexTTS2 speaker timbre prompts (3 files) ---"
declare -A idx_timbre=(
  ["bage.aac"]="bage, Chinese, 女声 (#甄嬛传华妃配音演员)"
  ["jieshuonan.aac"]="jieshuonan, Chinese, 男声 (低沉稳重)"
  ["xindong.aac"]="xindong, Chinese, 男声 (年轻活泼)"
)
for fname in "${!idx_timbre[@]}"; do
  label="${idx_timbre[$fname]}"
  speaker="${label%%,*}"
  aac="$DEST/indextts2_speakers/${fname}"
  wav="${aac%.aac}.wav"
  download "$INDEX_BASE/ex2/timbre-prompt/$fname" "$aac" "[$speaker] $label"
  to_wav "$aac" "$wav"
done
echo ""

# ═══════════════════════════════════════════════════════════════
# GROUP C: IndexTTS2 duration-control prompts (Chinese + English)
# These are baseline reference clips for cross-speaker comparison.
# ═══════════════════════════════════════════════════════════════
echo "--- Group C: IndexTTS2 duration prompts (4 files) ---"
declare -A idx_dur=(
  ["ex4_zh_289_prompt.aac"]="Chinese, 女声, prompt for '只有当科技为本地社群创造价值的时候，才真正有意义'"
  ["ex4_zh_319_prompt.aac"]="Chinese, 女声, prompt for '类推可用于颠覆惯性思维'"
  ["ex4_en_943_prompt.aac"]="English, 男声, prompt for 'The equipment needed...'"
  ["ex4_en_1037_prompt.aac"]="English, 男声, prompt for 'There is no wine in this country'"
)
declare -A idx_dur_urls=(
  ["ex4_zh_289_prompt"]="ex4/zh/289/prompt.aac"
  ["ex4_zh_319_prompt"]="ex4/zh/319/prompt.aac"
  ["ex4_en_943_prompt"]="ex4/en/943/prompt.aac"
  ["ex4_en_1037_prompt"]="ex4/en/1037/prompt.aac"
)
for key in "${!idx_dur_urls[@]}"; do
  label="${idx_dur[${key}.aac]}"
  src="${idx_dur_urls[$key]}"
  aac="$DEST/indextts2_duration/${key}.aac"
  wav="${aac%.aac}.wav"
  download "$INDEX_BASE/$src" "$aac" "$label"
  to_wav "$aac" "$wav"
done
echo ""

# ═══════════════════════════════════════════════════════════════
# GROUP D: PaddleSpeech CSMSC ground-truth (Chinese female, 5 WAV files)
# These are ~2-3s clips from CSMSC (Chinese Standard Mandarin Speech Corpus).
# All are the same single-speaker (Chinese female, professional recording).
# ═══════════════════════════════════════════════════════════════
echo "--- Group D: PaddleSpeech CSMSC ground-truth (5 files) ---"
declare -A paddle_text=(
  ["009901.wav"]="昨日，这名'伤者'与医生全部被警方依法刑事拘留 (Chinese female, neutral/narrative)"
  ["009902.wav"]="钱伟长想到上海来办学校是经过深思熟虑的 (Chinese female, calm)"
  ["009903.wav"]="她见我一进门就骂，吃饭时也骂，骂得我抬不起头 (Chinese female, grievance/complaint)"
  ["009904.wav"]="李述德在离开之前，只说了一句'柱驼杀父亲了' (Chinese female, dramatic)"
  ["009905.wav"]="这种车票和保险单捆绑出售属于重复性购买 (Chinese female, neutral/reporting)"
)
for fname in "${!paddle_text[@]}"; do
  label="${paddle_text[$fname]}"
  wav="$DEST/paddlespeech_csmsc/$fname"
  download "$PADDLE_BASE/baker_gt_24k/$fname" "$wav" "$label"
done
echo ""

# ═══════════════════════════════════════════════════════════════
# GROUP E: CosyVoice official prompts (2 WAV files)
# From the FunAudioLLM/CosyVoice GitHub repo.
# ═══════════════════════════════════════════════════════════════
echo "--- Group E: CosyVoice official prompts (2 files) ---"
declare -A cosy=(
  ["cosyvoice_zero_shot.wav"]="CosyVoice 3 zero-shot, Chinese female, neutral"
  ["cosyvoice_cross_lingual.wav"]="CosyVoice 3 cross-lingual, Chinese female"
)
for fname in "${!cosy[@]}"; do
  label="${cosy[$fname]}"
  case "$fname" in
    cosyvoice_zero_shot*) src="zero_shot_prompt.wav" ;;
    cosyvoice_cross_lingual*) src="cross_lingual_prompt.wav" ;;
  esac
  dest="$DEST/cosyvoice/$fname"
  download "$COSY_BASE/$src" "$dest" "$label"
done
echo ""

# ═══════════════════════════════════════════════════════════════
# GROUP F: Qwen3-TTS official demos (4 WAV files)
# From Qwen3-TTS repo OSS (clone reference + tokenizer demos).
# ═══════════════════════════════════════════════════════════════
echo "--- Group F: Qwen3-TTS official demos (4 files) ---"
declare -A qwen=(
  ["qwen_clone.wav"]="Qwen3-TTS clone reference, English female, neutral"
  ["qwen_tokenizer_demo1.wav"]="Qwen3-TTS demo 1, Chinese female"
  ["qwen_tokenizer_demo2.wav"]="Qwen3-TTS demo 2, Chinese female"
  ["qwen_tokenizer_demo3.wav"]="Qwen3-TTS demo 3, Chinese male"
)
for key in "${!qwen[@]}"; do
  label="${qwen[$key]}"
  case "$key" in
    qwen_clone*) src="clone.wav" ;;
    qwen_tokenizer_demo1*) src="tokenizer_demo_1.wav" ;;
    qwen_tokenizer_demo2*) src="tokenizer_demo_2.wav" ;;
    qwen_tokenizer_demo3*) src="tokenizer_demo_3.wav" ;;
  esac
  dest="$DEST/qwen3tts/$key"
  download "$QWEN_BASE/$src" "$dest" "$label"
done
echo ""

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════
echo ""
echo "============================================================"
echo "  DOWNLOAD SUMMARY"
echo "============================================================"
tree -h "$DEST" 2>/dev/null || find "$DEST" -type f -exec ls -lh {} \; | awk '{print $5, $NF}'
echo ""
echo "Total samples: $(find "$DEST" -type f | wc -l)"
total_size=$(du -sh "$DEST" 2>/dev/null | cut -f1)
echo "Total size:    $total_size"
echo ""
echo "─────────────────────────────────────────────────────────────"
echo "  ROLE MAPPING GUIDE"
echo "─────────────────────────────────────────────────────────────"
cat << 'MAP'
A. IndexTTS2 emotion prompts (14):
   → indextts2_emo/ — use these as REFERENCE prompts for specific
     emotions in CAM++ enrollment. E.g. enroll an 'angry' voice variant.

B. IndexTTS2 speaker timbre (3 distinct speakers):
   → indextts2_speakers/
     bage.wav         → 女性角色 (年轻女声, 可用于女主/活泼角色)
     jieshuonan.wav   → 男性角色 (低沉, 可用作长辈/权威角色)
     xindong.wav      → 男性角色 (活跃, 可用于年轻男主)

C. IndexTTS2 duration control (4):
   → indextts2_duration/ — English M + Chinese F reference prompts.
     ex4_zh_289.wav   → 女性角色 (中性)
     ex4_zh_319.wav   → 女性角色 (中性)
     ex4_en_*.wav     → English-speaking characters

D. PaddleSpeech CSMSC (5):
   → paddlespeech_csmsc/ — the SAME female speaker, different texts.
     009901.wav  → neutral: news/legal reporting
     009903.wav  → emotional: grievance/complaint
     009904.wav  → dramatic: dramatic announcement

E. CosyVoice official (2):
   → cosyvoice/ — Chinese female reference clips shipped with CosyVoice model.

F. Qwen3-TTS official (4):
   → qwen3tts/ — 3 Chinese (2F+1M) + 1 English (F) reference clips.
     qwen_tokenizer_demo1.wav → 女性角色 (中性)
     qwen_tokenizer_demo2.wav → 女性角色 (中性)
     qwen_tokenizer_demo3.wav → 男性角色 (中性)
     qwen_clone.wav           → English-speaking characters

Best practices for Chinese novel characters:
  - Narrator/旁白 → cosyvoice_zero_shot.wav or csmsc 009901.wav
  - Female lead → bage.wav or qwen_tokenizer_demo1.wav
  - Male lead → xindong.wav or qwen_tokenizer_demo3.wav
  - Angry scenes → indextts2_emo_08_angry_3.wav (emotion overlay)
  - Elder/serious → jieshuonan.wav
  - Each character needs 10-30s of WAV for good CAM++ enrollment.
    These downloads give ~2-5s each — use them as starting points,
    then record longer samples in CharacterEditorView.
MAP
echo ""
echo "============================================================"
echo "  NEXT STEPS"
echo "============================================================"
echo ""
echo "1. Run ./Scripts/download_default_samples.sh"
echo "2. In the app, open CharacterEditorView for each character"
echo "3. Import a matching .wav sample as voice reference"
echo "4. Tap '提取声纹' to enroll via CAM++ (CosyVoiceService.enrollSpeaker)"
echo "5. (Optional) Record 10-30s custom audio for better voice cloning"
echo "6. Once enrolled, TTS will use the cloned voice per character"
echo ""
echo "Emotion tags for CAM++ enrollment:"
echo "  angry/cry/fear/depressed/happy/surprise/calm"
echo "  CosyVoice auto-maps these from analyzeSentenceTone()"
echo ""
echo "============================================================"