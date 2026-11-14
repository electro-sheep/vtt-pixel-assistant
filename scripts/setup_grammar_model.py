"""
One-time setup for the whole-sentence grammar suggestions.

Downloads vennify/t5-base-grammar-correction from Hugging Face (~890 MB,
licence CC BY-NC-SA 4.0: personal / non-commercial use) and converts it to a
compact 8-bit CTranslate2 model (~230 MB) in backend/models/.

    python scripts/setup_grammar_model.py

Needs: pip install ctranslate2 transformers torch sentencepiece
The assistant works without this; it just won't offer the GRAMMAR rewrite.
"""

from __future__ import annotations
import os
import sys

REPO = "vennify/t5-base-grammar-correction"
OUT = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..",
    "backend",
    "models",
    "t5-base-grammar-correction-ct2",
)


def main() -> int:
    out = os.path.abspath(OUT)
    if os.path.isfile(os.path.join(out, "model.bin")):
        print(f"Already set up: {out}")
        return 0
    from ctranslate2.converters import TransformersConverter

    print(f"Downloading and converting {REPO} (this takes a few minutes)...")
    TransformersConverter(
        REPO,
        copy_files=["spiece.model", "tokenizer_config.json", "special_tokens_map.json"],
    ).convert(out, quantization="int8", force=True)
    print(f"Done: {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
