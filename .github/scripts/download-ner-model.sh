#!/bin/bash
set -euo pipefail

# Download to a temp directory so Xcode doesn't try to compile the .mlpackage during build.
# CI packaging step copies it into the .app bundle.
OUT_DIR="${MODEL_OUTPUT_DIR:-/tmp/ner-model}"
MODEL_NAME="ckip_ner_q8"
BASE_URL="https://huggingface.co/FakeRockert543/ckip-coreml/resolve/main/${MODEL_NAME}.mlpackage"

if [ -f "$OUT_DIR/${MODEL_NAME}.mlpackage/Manifest.json" ]; then
    echo "✅ NER model already exists at $OUT_DIR/${MODEL_NAME}.mlpackage, skipping download"
    exit 0
fi

echo "📥 Downloading NER model (~98MB) to $OUT_DIR ..."

mkdir -p "$OUT_DIR/${MODEL_NAME}.mlpackage/Data/com.apple.CoreML/weights"

curl -fsSL "$BASE_URL/Manifest.json" -o "$OUT_DIR/${MODEL_NAME}.mlpackage/Manifest.json" &
curl -fsSL "$BASE_URL/Data/com.apple.CoreML/model.mlmodel" -o "$OUT_DIR/${MODEL_NAME}.mlpackage/Data/com.apple.CoreML/model.mlmodel" &
curl -fsSL "$BASE_URL/Data/com.apple.CoreML/weights/weight.bin" -o "$OUT_DIR/${MODEL_NAME}.mlpackage/Data/com.apple.CoreML/weights/weight.bin" &

wait

# Also copy vocab.txt (bundled by SPM, but also place alongside model for dev use)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VOCAB_SRC="$SCRIPT_DIR/../../Sources/FeatureTTSReaderApp/Resources/vocab.txt"
if [ -f "$VOCAB_SRC" ]; then
    cp "$VOCAB_SRC" "$OUT_DIR/vocab.txt"
    echo "✅ vocab.txt copied to $OUT_DIR"
fi

echo "✅ NER model downloaded to $OUT_DIR/${MODEL_NAME}.mlpackage"
