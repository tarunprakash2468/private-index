#!/usr/bin/env python3
"""
convert_model.py — Core ML Conversion Pipeline for Private Index

Converts `sentence-transformers/all-MiniLM-L6-v2` into an Apple Neural Engine
optimized Core ML `.mlpackage` with FP16 precision.

The model graph includes mean pooling and L2 normalization baked in,
so a single inference call produces a normalized (1, 384) embedding vector.

Usage:
    python3 -m venv .venv && source .venv/bin/activate
    pip install -r requirements.txt
    python3 convert_model.py [--output OUTPUT_PATH] [--max-length 128] [--verify]
"""

import argparse
import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn


# ---------------------------------------------------------------------------
# 1. Wrapper Module: Transformer + Mean Pooling + L2 Normalization
# ---------------------------------------------------------------------------


class SentenceTransformerWrapper(nn.Module):
    """
    Wraps a HuggingFace transformer model with mean-pooling and L2
    normalization so the entire pipeline is a single traceable graph.

    Input:  input_ids (1, seq_len), attention_mask (1, seq_len)
    Output: normalized embedding (1, 384)
    """

    def __init__(self, transformer: nn.Module):
        super().__init__()
        self.transformer = transformer

    def forward(
        self,
        input_ids: torch.Tensor,
        attention_mask: torch.Tensor,
    ) -> torch.Tensor:
        # Run the transformer backbone
        outputs = self.transformer(
            input_ids=input_ids,
            attention_mask=attention_mask,
        )
        token_embeddings = outputs.last_hidden_state  # (1, seq_len, 384)

        # Mean pooling: mask out padding tokens before averaging
        mask_expanded = attention_mask.unsqueeze(-1).float()  # (1, seq_len, 1)
        sum_embeddings = (token_embeddings * mask_expanded).sum(dim=1)  # (1, 384)
        sum_mask = mask_expanded.sum(dim=1).clamp(min=1e-9)  # (1, 384)
        mean_pooled = sum_embeddings / sum_mask  # (1, 384)

        # L2 normalize
        norm = mean_pooled.norm(p=2, dim=1, keepdim=True).clamp(min=1e-12)
        normalized = mean_pooled / norm  # (1, 384)

        return normalized


# ---------------------------------------------------------------------------
# 2. Conversion
# ---------------------------------------------------------------------------


def convert_model(output_path: str, max_length: int = 128) -> str:
    """
    Downloads, wraps, traces, and converts the model to Core ML.

    Args:
        output_path: Where to save the .mlpackage.
        max_length: Fixed sequence length for ANE optimization.

    Returns:
        Path to the saved .mlpackage.
    """
    import coremltools as ct
    from transformers import AutoModel, AutoTokenizer

    model_id = "sentence-transformers/all-MiniLM-L6-v2"
    print(f"[1/5] Loading model: {model_id}")
    tokenizer = AutoTokenizer.from_pretrained(model_id)
    base_model = AutoModel.from_pretrained(model_id)
    base_model.eval()

    # Wrap with mean pooling + L2 norm
    wrapper = SentenceTransformerWrapper(base_model)
    wrapper.eval()

    print(f"[2/5] Preparing dummy inputs (max_length={max_length})")
    dummy_text = "This is an example sentence for on-device embedding generation."
    inputs = tokenizer(
        dummy_text,
        padding="max_length",
        max_length=max_length,
        truncation=True,
        return_tensors="pt",
    )
    input_ids = inputs["input_ids"].to(torch.int32)
    attention_mask = inputs["attention_mask"].to(torch.int32)

    print("[3/5] Tracing model with torch.jit.trace")
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, (input_ids, attention_mask))

    print("[4/5] Converting to Core ML .mlpackage (FP16, mlprogram)")
    mlmodel = ct.convert(
        traced,
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, max_length), dtype=np.int32),
            ct.TensorType(
                name="attention_mask", shape=(1, max_length), dtype=np.int32
            ),
        ],
        compute_units=ct.ComputeUnit.ALL,
    )

    # Add metadata
    mlmodel.author = "Private Index"
    mlmodel.short_description = (
        "all-MiniLM-L6-v2 sentence embedding model with mean pooling + L2 norm. "
        f"Input: (1, {max_length}) token IDs. Output: (1, 384) normalized embedding."
    )
    mlmodel.version = "1.0.0"

    print(f"[5/5] Saving to {output_path}")
    mlmodel.save(output_path)
    print(f"✅ Model saved to {output_path}")

    return output_path


# ---------------------------------------------------------------------------
# 3. Verification
# ---------------------------------------------------------------------------


def verify_model(mlpackage_path: str, max_length: int = 128) -> bool:
    """
    Verifies the converted Core ML model produces correct output:
    - Output shape is (1, 384)
    - L2 norm ≈ 1.0
    - Cosine similarity with PyTorch reference ≥ 0.99
    """
    import coremltools as ct
    from transformers import AutoModel, AutoTokenizer

    model_id = "sentence-transformers/all-MiniLM-L6-v2"
    print("\n--- Verification ---")
    print(f"Loading PyTorch reference model: {model_id}")
    tokenizer = AutoTokenizer.from_pretrained(model_id)
    base_model = AutoModel.from_pretrained(model_id)
    base_model.eval()
    wrapper = SentenceTransformerWrapper(base_model)
    wrapper.eval()

    test_sentence = "Private Index enables semantic search on your device."
    inputs = tokenizer(
        test_sentence,
        padding="max_length",
        max_length=max_length,
        truncation=True,
        return_tensors="pt",
    )
    input_ids = inputs["input_ids"].to(torch.int32)
    attention_mask = inputs["attention_mask"].to(torch.int32)

    # PyTorch reference
    with torch.no_grad():
        pt_output = wrapper(input_ids, attention_mask).numpy()

    # Core ML inference
    print(f"Loading Core ML model: {mlpackage_path}")
    mlmodel = ct.models.MLModel(mlpackage_path)
    coreml_pred = mlmodel.predict(
        {
            "input_ids": input_ids.numpy(),
            "attention_mask": attention_mask.numpy(),
        }
    )

    # The output key may vary; find the embedding output
    output_key = list(coreml_pred.keys())[0]
    cml_output = np.array(coreml_pred[output_key])

    # Ensure shapes match
    print(f"\nPyTorch output shape:  {pt_output.shape}")
    print(f"Core ML output shape:  {cml_output.shape}")

    # Reshape if needed (Core ML sometimes adds batch dims)
    if cml_output.ndim == 1:
        cml_output = cml_output.reshape(1, -1)

    all_passed = True

    # Check 1: Shape
    if cml_output.shape == (1, 384):
        print("✅ Shape check passed: (1, 384)")
    else:
        print(f"❌ Shape check FAILED: expected (1, 384), got {cml_output.shape}")
        all_passed = False

    # Check 2: L2 norm ≈ 1.0
    l2_norm = float(np.linalg.norm(cml_output))
    if abs(l2_norm - 1.0) < 1e-3:
        print(f"✅ L2 norm check passed: {l2_norm:.6f}")
    else:
        print(f"❌ L2 norm check FAILED: {l2_norm:.6f} (expected ≈ 1.0)")
        all_passed = False

    # Check 3: Cosine similarity with PyTorch
    cosine_sim = float(
        np.dot(pt_output.flatten(), cml_output.flatten())
        / (np.linalg.norm(pt_output) * np.linalg.norm(cml_output) + 1e-12)
    )
    if cosine_sim >= 0.99:
        print(f"✅ Cosine similarity check passed: {cosine_sim:.6f}")
    else:
        print(f"❌ Cosine similarity check FAILED: {cosine_sim:.6f} (expected ≥ 0.99)")
        all_passed = False

    if all_passed:
        print("\n🎉 All verification checks passed!")
    else:
        print("\n⚠️  Some verification checks failed.")

    return all_passed


# ---------------------------------------------------------------------------
# 4. CLI Entry Point
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="Convert all-MiniLM-L6-v2 to Core ML .mlpackage"
    )
    parser.add_argument(
        "--output",
        type=str,
        default="all-MiniLM-L6-v2.mlpackage",
        help="Output path for the .mlpackage (default: all-MiniLM-L6-v2.mlpackage)",
    )
    parser.add_argument(
        "--max-length",
        type=int,
        default=128,
        help="Fixed sequence length (default: 128)",
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="Run verification after conversion",
    )
    args = parser.parse_args()

    output_path = convert_model(args.output, args.max_length)

    if args.verify:
        success = verify_model(output_path, args.max_length)
        if not success:
            sys.exit(1)

    print("\nDone.")


if __name__ == "__main__":
    main()
