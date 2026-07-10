#!/bin/bash
# Download Chinese speech samples from PaddleSpeech demo page
# Output: Sources/FeatureTTSReaderApp/Models/default_samples/paddlespeech_*

set -euo pipefail
BASE="https://paddlespeech.bj.bcebos.com/Parakeet/docs/demos"
OUTDIR="Sources/FeatureTTSReaderApp/Models/default_samples/paddlespeech"
mkdir -p "$OUTDIR"

# Helper: download all numbered WAVs from a subdir
dl_subdir() {
    local subdir="$1"
    local label="$2"
    local count="${3:-10}"
    local dest="$OUTDIR/$label"
    mkdir -p "$dest"
    for i in $(seq -w 1 "$count"); do
        # Try 3-digit and with/without leading zeros
        for f in "${i}.wav" "00${i}.wav" "0${i}.wav"; do
            url="$BASE/$subdir/$f"
            dest_file="$dest/$f"
            if [ -f "$dest_file" ] && [ "$(stat -c%s "$dest_file")" -gt 1000 ]; then
                break  # exists already
            fi
            if curl -fsSL -o "$dest_file" "$url" 2>/dev/null; then
                size=$(stat -c%s "$dest_file")
                if [ "$size" -gt 1000 ]; then
                    echo "  OK  $label/$f (${size}B)"
                else
                    rm -f "$dest_file"
                fi
                break
            fi
        done
    done
}

echo "=== Baker (female, standard Chinese) ==="
dl_subdir "baker_gt_24k" "baker" 20

echo "=== Baker (fastspeech2 conformer) ==="
dl_subdir "fastspeech2_conformer_baker_ckpt_0.5_pwg_baker_ckpt_0.4" "baker_fs2_conformer" 15

echo "=== Baker (fastspeech2 nosil) ==="
dl_subdir "fastspeech2_nosil_baker_ckpt_0.4_parallel_wavegan_baker_ckpt_0.4" "baker_fs2_nosil" 15

echo "=== Child voice ==="
# child_voice uses 3-digit names without leading dir
for i in 001 002 003 004 005 007 008 009; do
    url="$BASE/child_voice/$i.wav"
    dest="$OUTDIR/child_voice/$i.wav"
    if [ -f "$dest" ] && [ "$(stat -c%s "$dest")" -gt 1000 ]; then continue; fi
    mkdir -p "$OUTDIR/child_voice"
    if curl -fsSL -o "$dest" "$url" 2>/dev/null; then
        echo "  OK  child_voice/$i.wav"
    fi
done

echo "=== Speed variations ==="
dl_subdir "speed" "speed" 10

echo "=== With frontend ==="
dl_subdir "with_frontend" "with_frontend" 10

echo "=== Without frontend ==="
dl_subdir "without_frontend" "without_frontend" 10

echo "=== Finetune ==="
dl_subdir "finetune" "finetune" 10

echo "=== AISHELL3 multi-speaker ==="
# Try to find AISHELL3 generated samples
for i in $(seq -w 1 15); do
    url="$BASE/fs2_aishell3_demos/generated/ssss$i.wav"
    dest="$OUTDIR/aishell3/ssss$i.wav"
    if [ -f "$dest" ] && [ "$(stat -c%s "$dest")" -gt 1000 ]; then continue; fi
    mkdir -p "$OUTDIR/aishell3"
    if curl -fsSL -o "$dest" "$url" 2>/dev/null; then
        echo "  OK  aishell3/ssss$i.wav"
    fi
done

# Also try numbered names
for i in $(seq 1 10); do
    for name in "SSSS${i}.wav" "SSSS0${i}.wav" "SSSS00${i}.wav"; do
        url="$BASE/fs2_aishell3_demos/generated/$name"
        dest="$OUTDIR/aishell3/$name"
        if [ -f "$dest" ] && [ "$(stat -c%s "$dest")" -gt 1000 ]; then continue; fi
        mkdir -p "$OUTDIR/aishell3"
        if curl -fsSL -o "$dest" "$url" 2>/dev/null; then
            echo "  OK  aishell3/$name"
            break
        fi
    done
done

echo ""
echo "=== Cleanup: remove empty files ==="
find "$OUTDIR" -type f -size -1000c -delete
find "$OUTDIR" -type d -empty -delete 2>/dev/null || true

echo "=== Summary ==="
find "$OUTDIR" -name "*.wav" | wc -l
echo "WAV files total"
du -sh "$OUTDIR"
