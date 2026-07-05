#!/usr/bin/env python3
"""Convert distilbert-base-chinese to Core ML (embedding model, iOS 17)."""

import json, sys, shutil
from pathlib import Path

import torch
import coremltools as ct
import numpy as np
from transformers import AutoModel, AutoTokenizer

MODEL_ID = "Geotrend/distilbert-base-zh-cased"
MAX_LENGTH = 128
OUTPUT_DIR = Path(__file__).resolve().parent.parent / "Sources" / "FeatureTTSReaderApp" / "Models"


class EmbeddingWrapper(torch.nn.Module):
    """Wrapper that returns mean-pooled sentence embedding."""
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, input_ids, attention_mask):
        outputs = self.model(input_ids=input_ids, attention_mask=attention_mask)
        last_hidden = outputs.last_hidden_state  # (1, seq_len, 768)
        mask = attention_mask.unsqueeze(-1).float()
        pooled = (last_hidden * mask).sum(dim=1) / mask.sum(dim=1).clamp(min=1e-9)
        return pooled


def tokenize(tokenizer, text: str) -> tuple:
    enc = tokenizer(text, max_length=MAX_LENGTH, padding="max_length", truncation=True, return_tensors="pt")
    return enc["input_ids"], enc["attention_mask"]


def main():
    print(f"Loading {MODEL_ID} ...")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
    model = AutoModel.from_pretrained(MODEL_ID)
    model.eval()

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Save vocabulary for Swift tokenizer
    saved = tokenizer.save_vocabulary(str(OUTPUT_DIR))
    print(f"Saved vocab files: {saved}")
    # Rename to vocab.txt for Swift BertTokenizer
    vocab_path = OUTPUT_DIR / "vocab.txt"
    if not vocab_path.exists():
        for f in saved:
            p = Path(f)
            if p.exists() and "vocab" in p.name:
                import shutil
                shutil.copy(p, vocab_path)
                break

    # Also save tokenizer.json for reference (not needed for Swift, but useful)
    tokenizer.save_pretrained(str(OUTPUT_DIR))

    wrapper = EmbeddingWrapper(model)
    wrapper.eval()

    # Trace with a real input
    input_ids, attention_mask = tokenize(tokenizer, "你好世界")
    traced = torch.jit.trace(wrapper, (input_ids, attention_mask))

    # Convert to Core ML
    print("Converting to Core ML (iOS 17, FLOAT16) ...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, MAX_LENGTH), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, MAX_LENGTH), dtype=np.int32),
        ],
        outputs=[
            ct.TensorType(name="embedding"),
        ],
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT16,
    )

    out_path = OUTPUT_DIR / "distilbert_chinese.mlpackage"
    if out_path.exists():
        shutil.rmtree(out_path)
    mlmodel.save(str(out_path))

    # Show size
    total = sum(f.stat().st_size for f in out_path.rglob("*"))
    print(f"Saved to {out_path}  ({total / 1024 / 1024:.1f} MB)")

    # Quick sanity check
    test_ids, test_mask = tokenize(tokenizer, "陈煜笑道")
    pred = mlmodel.predict({"input_ids": test_ids.numpy(), "attention_mask": test_mask.numpy()})
    embedding = pred["embedding"]
    print(f"Embedding shape: {embedding.shape}  (should be [1, 768])")
    print("Done!")


if __name__ == "__main__":
    main()
