#!/usr/bin/env python3
"""
convert_model.py — Core ML Conversion Pipeline for Private Index

Converts `sentence-transformers/all-MiniLM-L6-v2` into an Apple Neural Engine (ANE)
optimized Core ML `.mlpackage` with FP16 precision.

The model graph includes mean pooling and L2 normalization baked in,
so a single inference call produces a normalized (1, 384) embedding vector.

Usage:
    python3 -m venv .venv && source .venv/bin/activate
    pip install -r scripts/requirements.txt
    python3 scripts/convert_model.py [--output OUTPUT_PATH] [--max-length 128] [--compute-units ALL] [--verify] [--compile]
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional

try:
    import numpy as np
    import torch
    import torch.nn as nn
    TORCH_AVAILABLE = True
except ImportError:
    np = None  # type: ignore
    torch = None  # type: ignore
    nn = None  # type: ignore
    TORCH_AVAILABLE = False


# ---------------------------------------------------------------------------
# 1. Wrapper Module: Transformer + Mean Pooling + L2 Normalization
# ---------------------------------------------------------------------------


if TORCH_AVAILABLE:
    class SentenceTransformerWrapper(nn.Module):
        """
        Wraps a HuggingFace transformer model with mean-pooling and L2
        normalization so the entire pipeline is a single traceable graph.

        Inputs:
            input_ids: torch.Tensor of shape (1, seq_len) with int32 token IDs.
            attention_mask: torch.Tensor of shape (1, seq_len) with int32 binary mask (1 for active token, 0 for padding).

        Outputs:
            torch.Tensor: L2-normalized sentence embedding vector of shape (1, 384).
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
else:
    class SentenceTransformerWrapper:  # type: ignore
        def __init__(self, *args, **kwargs):
            raise RuntimeError(
                "PyTorch is not available. Please install dependencies: pip install -r scripts/requirements.txt"
            )


# ---------------------------------------------------------------------------
# 2. Custom MIL Ops Registration
# ---------------------------------------------------------------------------


def _register_custom_torch_ops():
    """
    Register PyTorch frontend converters for ops missing in coremltools.
    Recent transformers versions (>= 5.x) use tensor.new_ones(()) and tensor.new_zeros(())
    during attention masking, which either lack a converter or need int32 shape handling in coremltools.
    """
    try:
        from coremltools.converters.mil.frontend.torch.ops import (  # type: ignore
            _cast_to,
            _get_inputs,
            NUM_TO_DTYPE_STRING,
            register_torch_op,
        )
        from coremltools.converters.mil.mil import Builder as mb  # type: ignore

        @register_torch_op(override=True)
        def new_ones(context, node):
            inputs = _get_inputs(context, node)
            shape = inputs[1]
            dtype = inputs[2] if len(inputs) > 2 and inputs[2] is not None else None

            if isinstance(shape, list):
                shape = mb.concat(values=shape, axis=0)
            elif hasattr(shape, "dtype") and shape.dtype != np.int32:
                if hasattr(shape, "val") and shape.val is not None:
                    shape = np.array(shape.val, dtype=np.int32)
                else:
                    shape = mb.cast(x=shape, dtype="int32")

            res = mb.fill(shape=shape, value=1.0)
            if dtype is not None and hasattr(dtype, "val") and dtype.val in NUM_TO_DTYPE_STRING:
                res = _cast_to(res, NUM_TO_DTYPE_STRING[dtype.val], node.name)
            context.add(res, node.name)

        @register_torch_op(torch_alias=["new_empty"], override=True)
        def new_zeros(context, node):
            inputs = _get_inputs(context, node)
            shape = inputs[1]
            dtype = inputs[2] if len(inputs) > 2 and inputs[2] is not None else None

            if isinstance(shape, list):
                shape = mb.concat(values=shape, axis=0)
            elif hasattr(shape, "dtype") and shape.dtype != np.int32:
                if hasattr(shape, "val") and shape.val is not None:
                    shape = np.array(shape.val, dtype=np.int32)
                else:
                    shape = mb.cast(x=shape, dtype="int32")

            res = mb.fill(shape=shape, value=0.0)
            if dtype is not None and hasattr(dtype, "val") and dtype.val in NUM_TO_DTYPE_STRING:
                res = _cast_to(res, NUM_TO_DTYPE_STRING[dtype.val], node.name)
            context.add(res, node.name)

    except Exception as e:
        print(f"Warning: could not register custom torch ops: {e}")


# ---------------------------------------------------------------------------
# 3. Compute Units Resolution
# ---------------------------------------------------------------------------


def _resolve_compute_units(compute_units_str: str):
    """
    Maps string identifier to coremltools ComputeUnit enum.

    Args:
        compute_units_str: One of 'ALL', 'CPU_AND_NE', 'CPU_AND_GPU', 'CPU_ONLY'.

    Returns:
        ct.ComputeUnit enum value.

    Raises:
        ValueError: If compute_units_str is unrecognized.
    """
    import coremltools as ct

    mapping = {
        "ALL": ct.ComputeUnit.ALL,
        "CPU_AND_NE": ct.ComputeUnit.CPU_AND_NE,
        "CPU_AND_GPU": ct.ComputeUnit.CPU_AND_GPU,
        "CPU_ONLY": ct.ComputeUnit.CPU_ONLY,
    }
    key = compute_units_str.upper()
    if key not in mapping:
        raise ValueError(
            f"Unsupported compute units '{compute_units_str}'. Supported options: {list(mapping.keys())}"
        )
    return mapping[key]


# ---------------------------------------------------------------------------
# 4. Conversion
# ---------------------------------------------------------------------------


def convert_model(
    output_path: str,
    max_length: int = 128,
    compute_units: str = "ALL",
    model_id: str = "sentence-transformers/all-MiniLM-L6-v2",
) -> str:
    """
    Downloads, wraps, traces, and converts the transformer model to Core ML.

    Configured specifically for Apple Silicon and Apple Neural Engine (ANE)
    acceleration:
    - Fixed sequence length (static input shapes required by ANE)
    - FP16 precision (optimal for ANE throughput and reduced memory footprint)
    - Modern MIL mlprogram format

    Args:
        output_path: Path where the .mlpackage will be saved.
        max_length: Fixed sequence length for ANE optimization (default: 128).
        compute_units: Target compute units ('ALL', 'CPU_AND_NE', 'CPU_AND_GPU', 'CPU_ONLY').
        model_id: HuggingFace model repo identifier.

    Returns:
        String path to the saved .mlpackage.

    Raises:
        RuntimeError: If dependency import, model loading, tracing, or conversion fails.
    """
    if not TORCH_AVAILABLE:
        raise RuntimeError(
            "Required dependencies (torch, numpy) are missing. "
            "Please run: pip install -r scripts/requirements.txt"
        )

    try:
        import coremltools as ct
        from transformers import AutoModel, AutoTokenizer
    except ImportError as e:
        raise RuntimeError(
            f"Required dependency missing: {e}. "
            "Please run: pip install -r scripts/requirements.txt"
        ) from e

    _register_custom_torch_ops()
    target_compute_unit = _resolve_compute_units(compute_units)

    print(f"[1/5] Loading model: {model_id}")
    try:
        tokenizer = AutoTokenizer.from_pretrained(model_id)
        if tokenizer is None:
            raise ValueError(f"Failed to load tokenizer for {model_id}")
        base_model = AutoModel.from_pretrained(model_id)
        base_model.eval()
    except Exception as e:
        raise RuntimeError(
            f"Failed to load model or tokenizer '{model_id}' from HuggingFace Hub: {e}"
        ) from e

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
    try:
        with torch.no_grad():
            traced = torch.jit.trace(wrapper, (input_ids, attention_mask))
    except Exception as e:
        raise RuntimeError(f"PyTorch JIT tracing failed: {e}") from e

    print(
        f"[4/5] Converting to Core ML .mlpackage (FP16, mlprogram, compute_units={compute_units.upper()})"
    )
    try:
        mlmodel = ct.convert(
            traced,
            convert_to="mlprogram",
            compute_precision=ct.precision.FLOAT16,
            inputs=[
                ct.TensorType(
                    name="input_ids",
                    shape=(1, max_length),
                    dtype=np.int32,
                ),
                ct.TensorType(
                    name="attention_mask",
                    shape=(1, max_length),
                    dtype=np.int32,
                ),
            ],
            compute_units=target_compute_unit,
        )
    except Exception as e:
        raise RuntimeError(f"Core ML conversion failed: {e}") from e

    # Add metadata
    mlmodel.author = "Private Index"
    mlmodel.short_description = (
        "all-MiniLM-L6-v2 sentence embedding model with mean pooling + L2 norm. "
        f"Input: (1, {max_length}) token IDs. Output: (1, 384) normalized embedding."
    )
    mlmodel.version = "1.0.0"
    mlmodel.input_description["input_ids"] = (
        f"Token IDs from BertTokenizer, padded/truncated to shape (1, {max_length})"
    )
    mlmodel.input_description["attention_mask"] = (
        f"Attention mask (1 for active token, 0 for padding), shape (1, {max_length})"
    )

    print(f"[5/5] Saving to {output_path}")
    out_path = Path(output_path).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(out_path))
    print(f"✅ Model saved to {out_path}")

    # Export vocab.txt for the Swift BertTokenizer
    try:
        vocab_dest = (
            Path(__file__).resolve().parent.parent
            / "Packages"
            / "PrivateIndexEngine"
            / "Sources"
            / "PrivateIndexEngine"
            / "Resources"
            / "vocab.txt"
        )
        vocab_dest.parent.mkdir(parents=True, exist_ok=True)
        tokenizer.save_vocabulary(str(vocab_dest.parent))
        extra_model = vocab_dest.parent / "tokenizer.model"
        if extra_model.exists():
            extra_model.unlink()
        print(f"✅ Vocabulary saved to {vocab_dest}")
    except Exception as e:
        print(f"⚠️ Note: Could not export vocab.txt automatically: {e}")

    return str(out_path)


# ---------------------------------------------------------------------------
# 5. Compilation Helper
# ---------------------------------------------------------------------------


def compile_model(mlpackage_path: str, output_dir: Optional[str] = None) -> Path:
    """
    Compiles a Core ML .mlpackage into an optimized .mlmodelc bundle using `xcrun coremlc`.

    Args:
        mlpackage_path: Path to input .mlpackage.
        output_dir: Optional destination folder. Defaults to PrivateIndexEngine Resources folder.

    Returns:
        Path to the compiled .mlmodelc directory.

    Raises:
        FileNotFoundError: If mlpackage_path does not exist.
        RuntimeError: If xcrun is missing or compilation fails.
    """
    pkg_path = Path(mlpackage_path).resolve()
    if not pkg_path.exists():
        raise FileNotFoundError(f"Model package not found at: {pkg_path}")

    if not shutil.which("xcrun"):
        raise RuntimeError("xcrun not found in PATH. Ensure Xcode Command Line Tools are installed.")

    if output_dir is None:
        dest_dir = (
            Path(__file__).resolve().parent.parent
            / "Packages"
            / "PrivateIndexEngine"
            / "Sources"
            / "PrivateIndexEngine"
            / "Resources"
        )
    else:
        dest_dir = Path(output_dir).resolve()

    dest_dir.mkdir(parents=True, exist_ok=True)
    print(f"\n[Compiling] Running coremlc compile {pkg_path} to {dest_dir}...")
    try:
        subprocess.run(
            ["xcrun", "coremlc", "compile", str(pkg_path), str(dest_dir)],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as e:
        stderr_msg = e.stderr.strip() if e.stderr else e.stdout.strip()
        raise RuntimeError(f"xcrun coremlc compilation failed:\n{stderr_msg}") from e

    compiled_name = pkg_path.stem + ".mlmodelc"
    compiled_path = dest_dir / compiled_name
    print(f"✅ Successfully compiled model to {compiled_path}")
    return compiled_path


# ---------------------------------------------------------------------------
# 6. Verification
# ---------------------------------------------------------------------------


def verify_model(
    mlpackage_path: str,
    max_length: int = 128,
    compute_units: str = "ALL",
) -> bool:
    """
    Verifies the converted Core ML model produces correct output:
    - Output shape is (1, 384)
    - L2 norm ≈ 1.0 (unit vector)
    - Cosine similarity with PyTorch reference ≥ 0.99
    - Executes correctly under target compute units (e.g. ANE / CPU / GPU)

    Args:
        mlpackage_path: Path to the .mlpackage directory.
        max_length: Sequence length used during conversion (default: 128).
        compute_units: Compute unit target to verify.

    Returns:
        True if all checks pass, False otherwise.
    """
    if not TORCH_AVAILABLE:
        raise RuntimeError(
            "Required dependencies (torch, numpy) are missing. "
            "Please run: pip install -r scripts/requirements.txt"
        )

    try:
        import coremltools as ct
        from transformers import AutoModel, AutoTokenizer
    except ImportError as e:
        raise RuntimeError(
            f"Required dependency missing: {e}. "
            "Please run: pip install -r scripts/requirements.txt"
        ) from e

    _register_custom_torch_ops()
    target_compute_unit = _resolve_compute_units(compute_units)

    model_id = "sentence-transformers/all-MiniLM-L6-v2"
    print("\n--- Verification ---")
    print(f"Loading PyTorch reference model: {model_id}")
    tokenizer = AutoTokenizer.from_pretrained(model_id)
    assert tokenizer is not None
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
    print(f"Loading Core ML model: {mlpackage_path} (compute_units={compute_units.upper()})")
    mlmodel = ct.models.MLModel(mlpackage_path, compute_units=target_compute_unit)
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
# 7. CLI Entry Point
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="Convert all-MiniLM-L6-v2 to Core ML .mlpackage with ANE acceleration"
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
        help="Fixed sequence length for ANE optimization (default: 128)",
    )
    parser.add_argument(
        "--compute-units",
        type=str,
        default="ALL",
        choices=["ALL", "CPU_AND_NE", "CPU_AND_GPU", "CPU_ONLY"],
        help="Target compute units for Core ML execution (default: ALL)",
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="Run verification after conversion against PyTorch reference",
    )
    parser.add_argument(
        "--compile",
        action="store_true",
        help="Compile .mlpackage to .mlmodelc and place in PrivateIndexEngine resources",
    )
    args = parser.parse_args()

    try:
        output_path = convert_model(
            output_path=args.output,
            max_length=args.max_length,
            compute_units=args.compute_units,
        )

        if args.verify:
            success = verify_model(
                mlpackage_path=output_path,
                max_length=args.max_length,
                compute_units=args.compute_units,
            )
            if not success:
                sys.exit(1)

        if args.compile:
            compile_model(mlpackage_path=output_path)

        print("\nDone.")
    except Exception as e:
        print(f"\n❌ Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
