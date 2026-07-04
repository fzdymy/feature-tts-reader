#!/bin/bash
set -euo pipefail

BASE_DIR="${SRCROOT:-$(dirname "$0")/../..}"
MODEL_DIR="$BASE_DIR/Sources/FeatureTTSReaderApp/Resources"
MODEL_NAME="ckip_ner_q8"
BASE_URL="https://huggingface.co/FakeRockert543/ckip-coreml/resolve/main/${MODEL_NAME}.mlpackage"

if [ -f "$MODEL_DIR/${MODEL_NAME}.mlpackage/Manifest.json" ]; then
    echo "✅ NER model already exists, skipping download"
    exit 0
fi

echo "📥 Downloading NER model (~98MB)..."

mkdir -p "$MODEL_DIR/${MODEL_NAME}.mlpackage/Data/com.apple.CoreML/weights"

curl -fsSL "$BASE_URL/Manifest.json" -o "$MODEL_DIR/${MODEL_NAME}.mlpackage/Manifest.json" &
curl -fsSL "$BASE_URL/Data/com.apple.CoreML/model.mlmodel" -o "$MODEL_DIR/${MODEL_NAME}.mlpackage/Data/com.apple.CoreML/model.mlmodel" &
curl -fsSL "$BASE_URL/Data/com.apple.CoreML/weights/weight.bin" -o "$MODEL_DIR/${MODEL_NAME}.mlpackage/Data/com.apple.CoreML/weights/weight.bin" &

wait

echo "✅ NER model downloaded to $MODEL_DIR/${MODEL_NAME}.mlpackage"
