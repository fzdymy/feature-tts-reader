#!/bin/bash
# Download the latest Core ML model from GitHub Releases.
# Usage: bash Scripts/download_model.sh

set -euo pipefail

REPO="cooip/feature-tts-reader"
DEST="Sources/FeatureTTSReaderApp/Models"

echo "Fetching latest release from $REPO ..."
RELEASE_JSON=$(gh release view --json tagName,assets 2>/dev/null || true)

if [ -z "$RELEASE_JSON" ]; then
  # Fallback: get latest release tag
  TAG=$(gh release list --limit 1 --json tagName -q '.[0].tagName' 2>/dev/null || echo "")
  if [ -z "$TAG" ]; then
    echo "No releases found. Run the 'Convert DistilBERT to Core ML' workflow first."
    exit 1
  fi
  gh release download "$TAG" --pattern "*.zip" --dir "$DEST" --clobber
else
  TAG=$(echo "$RELEASE_JSON" | jq -r '.tagName')
  gh release download "$TAG" --pattern "*.zip" --dir "$DEST" --clobber
fi

ZIP_FILE=$(ls "$DEST"/*.zip 2>/dev/null | head -1)
if [ -z "$ZIP_FILE" ]; then
  echo "No zip file found in release assets."
  exit 1
fi

echo "Extracting $ZIP_FILE to $DEST/ ..."
unzip -o "$ZIP_FILE" -d "$DEST/"
rm "$ZIP_FILE"

echo "Done! Model files in $DEST/"
ls -lh "$DEST/distilbert_chinese.mlpackage"
