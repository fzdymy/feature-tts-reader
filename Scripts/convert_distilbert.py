#!/usr/bin/env python3
"""Convert Chinese BERT to Core ML (embedding model, iOS 17+)."""

import json, sys, shutil
from pathlib import Path

import torch
import coremltools as ct
import numpy as np
from transformers import AutoModel, AutoTokenizer

# Models to try in order (first successful conversion wins)
MODEL_CANDIDATES = [
    "google-bert/bert-base-chinese",
    "shibing624/text2vec-base-chinese",
]
MAX_LENGTH = 128
OUTPUT_DIR = Path(__file__).resolve().parent.parent / "Sources" / "FeatureTTSReaderApp" / "Models"


class EmbeddingWrapper(torch.nn.Module):
    """Wrapper that returns mean-pooled sentence embedding.
    
    Pre-computes position_ids and token_type_ids to avoid dynamic
    slicing ops (aten::Int) that coremltools cannot convert.
    """
    def __init__(self, model, max_length: int = MAX_LENGTH):
        super().__init__()
        self.model = model
        self.max_length = max_length
        self.register_buffer("position_ids", torch.arange(max_length).unsqueeze(0))

    def forward(self, input_ids, attention_mask):
        # Use pre-computed position_ids + zero token_type_ids to
        # bypass BERT's dynamic slicing / tensor creation ops
        outputs = self.model(
            input_ids=input_ids,
            attention_mask=attention_mask,
            position_ids=self.position_ids,
            token_type_ids=torch.zeros_like(input_ids),
        )
        last_hidden = outputs.last_hidden_state  # (1, seq_len, 768)
        mask = attention_mask.unsqueeze(-1).float()
        pooled = (last_hidden * mask).sum(dim=1) / mask.sum(dim=1).clamp(min=1e-9)
        return pooled


def tokenize(tokenizer, text: str) -> tuple:
    enc = tokenizer(text, max_length=MAX_LENGTH, padding="max_length", truncation=True, return_tensors="pt")
    return enc["input_ids"], enc["attention_mask"]


def try_convert(model_id: str) -> bool:
    print(f"\n{'='*60}")
    print(f"Trying model: {model_id}")
    print(f"{'='*60}")

    try:
        tokenizer = AutoTokenizer.from_pretrained(model_id)
        model = AutoModel.from_pretrained(
            model_id,
            attn_implementation="eager",  # Avoid SDPA (new_ones) not supported by coremltools
        )
        model.eval()
    except Exception as e:
        print(f"  FAILED to load model: {e}")
        return False

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Save vocabulary for Swift tokenizer
    tokenizer.save_vocabulary(str(OUTPUT_DIR))
    vocab_path = OUTPUT_DIR / "vocab.txt"
    if not vocab_path.exists():
        txts = sorted(Path(OUTPUT_DIR).glob("*vocab*"))
        if txts:
            shutil.copy(txts[0], vocab_path)
            print(f"  Using vocab file: {txts[0].name}")
        else:
            vocab = tokenizer.get_vocab()
            if vocab:
                sorted_tokens = sorted(vocab, key=vocab.get)
                vocab_path.write_text("\n".join(sorted_tokens))
                print(f"  Wrote vocab.txt from tokenizer ({len(sorted_tokens)} tokens)")
    if vocab_path.exists():
        print(f"  Vocab saved ({vocab_path.stat().st_size / 1024:.0f} KB)")

    tokenizer.save_pretrained(str(OUTPUT_DIR))

    wrapper = EmbeddingWrapper(model)
    wrapper.eval()

    input_ids, attention_mask = tokenize(tokenizer, "你好世界")

    # Strategy 1: Direct pytorch conversion (without explicit JIT trace)
    print(f"  Converting via direct pytorch ...")
    try:
        mlmodel = ct.convert(
            wrapper,
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
        return _save_and_verify(mlmodel, tokenizer, model_id, "direct-pytorch")
    except Exception as e:
        print(f"  FAILED direct pytorch: {e}")
        _cleanup_mlpackage()

    # Strategy 2: JIT trace then convert
    print(f"  Converting via JIT trace ...")
    try:
        traced = torch.jit.trace(wrapper, (input_ids, attention_mask), strict=False)
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
        return _save_and_verify(mlmodel, tokenizer, model_id, "jit-trace")
    except Exception as e:
        print(f"  FAILED JIT trace: {e}")
        _cleanup_mlpackage()

    # Strategy 3: ONNX → Core ML
    print(f"  Converting via ONNX intermediary ...")
    try:
        onnx_path = OUTPUT_DIR / "bert_chinese.onnx"
        torch.onnx.export(
            wrapper,
            (input_ids, attention_mask),
            str(onnx_path),
            input_names=["input_ids", "attention_mask"],
            output_names=["embedding"],
            dynamic_axes={
                "input_ids": {0: "batch_size"},
                "attention_mask": {0: "batch_size"},
            },
            opset_version=17,
        )
        mlmodel = ct.convert(
            str(onnx_path),
            source="onnx",
            minimum_deployment_target=ct.target.iOS17,
            compute_precision=ct.precision.FLOAT16,
        )
        onnx_path.unlink(missing_ok=True)
        return _save_and_verify(mlmodel, tokenizer, model_id, "onnx")
    except Exception as e:
        print(f"  FAILED ONNX: {e}")
        _cleanup_mlpackage()

    return False


def _save_and_verify(mlmodel, tokenizer, model_id, strategy):
    out_path = OUTPUT_DIR / "distilbert_chinese.mlpackage"
    if out_path.exists():
        shutil.rmtree(out_path)
    mlmodel.save(str(out_path))

    total = sum(f.stat().st_size for f in out_path.rglob("*"))
    print(f"  SUCCESS! Saved to {out_path} ({total / 1024 / 1024:.1f} MB)")

    # Sanity check
    test_ids, test_mask = tokenize(tokenizer, "陈煜笑道")
    pred = mlmodel.predict({"input_ids": test_ids.numpy(), "attention_mask": test_mask.numpy()})
    embedding = pred["embedding"]
    print(f"  Embedding shape: {embedding.shape} (should be [1, 768])")
    print(f"  Model: {model_id} | Strategy: {strategy}")
    return True


def _cleanup_mlpackage():
    partial = OUTPUT_DIR / "distilbert_chinese.mlpackage"
    if partial.exists():
        shutil.rmtree(partial)


def main():
    print(f"Chinese BERT → Core ML Converter")
    print(f"Max length: {MAX_LENGTH}")
    print(f"Output: {OUTPUT_DIR}")

    # Try each model candidate
    for model_id in MODEL_CANDIDATES:
        if try_convert(model_id):
            print(f"\n{'='*60}")
            print(f"SUCCESS with {model_id}")
            print(f"{'='*60}")
            sys.exit(0)

    # If all failed, try one more: save just vocab from shibing624
    print(f"\n{'='*60}")
    print("ALL models failed to convert to Core ML!")
    print("Falling back: saving vocab only from text2vec-base-chinese")
    print(f"{'='*60}")
    try:
        tokenizer = AutoTokenizer.from_pretrained("shibing624/text2vec-base-chinese")
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        tokenizer.save_vocabulary(str(OUTPUT_DIR))
        vocab_path = OUTPUT_DIR / "vocab.txt"
        if not vocab_path.exists():
            txts = sorted(Path(OUTPUT_DIR).glob("*vocab*"))
            if txts:
                shutil.copy(txts[0], vocab_path)
        if vocab_path.exists():
            print(f"Vocab saved ({vocab_path.stat().st_size / 1024:.0f} KB)")
        else:
            print("Failed to save vocab!")
            sys.exit(1)
    except Exception as e:
        print(f"Fatal: {e}")
        sys.exit(1)

    print("Vocab-only fallback succeeded. Download / commit .mlpackage manually.")
    sys.exit(1)


if __name__ == "__main__":
    main()
