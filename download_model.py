"""
Download models required by the Smart Cane app.

Usage:
    python download_model.py              # download all models
    python download_model.py --llm-only   # only Gemma 4 E2B
    python download_model.py --stt-only   # only Bengali sherpa-onnx model

Models downloaded:
  1. Bengali STT  — sherpa-onnx streaming Zipformer (Bangla/Vosk 2026-02-09)
  2. LLM          — Gemma 4 E2B Instruction-tuned (.litertlm, ~2.58 GB)
                    Source: https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm
"""

import os
import sys
import urllib.request
import argparse

MODELS_DIR = os.path.join("assets", "models")


# ── progress callback ──────────────────────────────────────────────────────────

def _progress(block_num, block_size, total_size):
    downloaded = block_num * block_size
    if total_size > 0:
        pct = min(100.0, downloaded * 100 / total_size)
        mb_done = downloaded / 1_048_576
        mb_total = total_size / 1_048_576
        sys.stdout.write(f"\r  {pct:5.1f}%  {mb_done:.1f} / {mb_total:.1f} MB")
        sys.stdout.flush()
    else:
        mb_done = downloaded / 1_048_576
        sys.stdout.write(f"\r  {mb_done:.1f} MB downloaded")
        sys.stdout.flush()


# ── individual download helpers ────────────────────────────────────────────────

def download_file(url: str, dest: str, label: str) -> None:
    """Download url → dest, skipping if dest already exists and is non-empty."""
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        size_mb = os.path.getsize(dest) / 1_048_576
        print(f"  {label}: already present ({size_mb:.1f} MB), skipping.")
        return

    os.makedirs(os.path.dirname(dest), exist_ok=True)
    print(f"  {label}: downloading from {url}")
    try:
        urllib.request.urlretrieve(url, dest, reporthook=_progress)
        print()  # newline after progress
        size_mb = os.path.getsize(dest) / 1_048_576
        print(f"  {label}: done ({size_mb:.1f} MB → {dest})")
    except Exception as exc:
        print(f"\n  {label}: FAILED — {exc}")
        if os.path.exists(dest):
            os.remove(dest)
        raise


# ── model definitions ──────────────────────────────────────────────────────────

def download_stt_model() -> None:
    """Bengali sherpa-onnx streaming Zipformer (bundled in APK assets)."""
    base_url = (
        "https://huggingface.co/csukuangfj/"
        "sherpa-onnx-streaming-zipformer-bn-vosk-2026-02-09/resolve/main"
    )
    model_dir = os.path.join(
        MODELS_DIR,
        "sherpa-onnx-streaming-zipformer-bn-vosk-2026-02-09",
    )
    files = [
        "encoder-epoch-99-avg-1.int8.onnx",
        "decoder-epoch-99-avg-1.int8.onnx",
        "joiner-epoch-99-avg-1.int8.onnx",
        "tokens.txt",
    ]
    print("\n[Bengali STT model]")
    for f in files:
        download_file(f"{base_url}/{f}", os.path.join(model_dir, f), f)


def download_llm_model() -> None:
    """Gemma 4 E2B Instruction-tuned LiteRT-LM model (~2.58 GB)."""
    # Direct download URL for the .litertlm file from HuggingFace
    url = (
        "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm"
        "/resolve/main/gemma-4-E2B-it.litertlm"
    )
    dest = os.path.join(MODELS_DIR, "gemma-4-E2B-it.litertlm")
    print("\n[Gemma 4 E2B LLM model (~2.58 GB — this will take a while)]")
    download_file(url, dest, "gemma-4-E2B-it.litertlm")


# ── entry point ────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Download Smart Cane app models.")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--llm-only", action="store_true", help="Only download LLM model")
    group.add_argument("--stt-only", action="store_true", help="Only download Bengali STT model")
    args = parser.parse_args()

    os.makedirs(MODELS_DIR, exist_ok=True)

    if args.llm_only:
        download_llm_model()
    elif args.stt_only:
        download_stt_model()
    else:
        download_stt_model()
        download_llm_model()

    print("\nAll requested models downloaded successfully.")


if __name__ == "__main__":
    main()
