"""
Whole-sentence grammar suggestions from a small local model.

The rule engine (dyslexia_grammar.py) can only fix what a pattern describes. It
cannot reorder words ("to the shop go"), fix plurals and tenses in general, or
find where a run-on sentence should break. This module adds a T5 grammar model,
run locally through CTranslate2 (the same runtime Whisper already uses), to
propose a corrected version of the text.

Design rules:
- It only ever SUGGESTS. The rewrite is offered as a one-click option; nothing
  here types into the user's document.
- Every rewrite is checked before it is offered: if the model dropped a name,
  number, link or file name, or changed too many words, that part of the text is
  kept as the user wrote it.
- It never blocks: `suggest()` returns immediately with a cached answer or None
  and computes in a background thread.
- If the model folder is missing, `available` is False and nothing else changes.

Model: vennify/t5-base-grammar-correction (CC BY-NC-SA 4.0, non-commercial),
converted with `scripts/setup_grammar_model.py` into backend/models/.
"""

from __future__ import annotations
import os
import re
import threading
from collections import OrderedDict
from typing import Callable, List, Optional, Tuple

MODEL_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "models",
    "t5-base-grammar-correction-ct2",
)
PROMPT_PREFIX = "grammar: "
MAX_WORDS_TOTAL = 220  # longer texts are left to the rule engine
MAX_WORDS_PER_CHUNK = 60

BatchFn = Callable[[List[str]], List[str]]

_BULLET_RE = re.compile(r"^([ \t]*(?:[-*•][ \t]+|\d+[.)][ \t]+)?)(.*)$", re.DOTALL)
_EDGE_PUNCT = ".,!?;:\"'()[]"


def _stem(word: str) -> str:
    return re.sub(r"[^a-z0-9]", "", word.lower())[:3]


def is_safe_rewrite(source: str, rewrite: str) -> bool:
    """
    True when `rewrite` is a plausible correction of `source` rather than a
    different sentence: similar length, mostly the same words, and every name,
    number, link and file name still present.
    """
    src_words, out_words = source.split(), rewrite.split()
    if not src_words or not out_words:
        return False
    ratio = len(out_words) / len(src_words)
    if not 0.75 <= ratio <= 1.35:
        return False

    out_lower = rewrite.lower()
    for i, tok in enumerate(src_words):
        core = tok.strip(_EDGE_PUNCT)
        if not core:
            continue
        looks_literal = bool(re.search(r"[\d@/\\_]|\w\.\w", core))
        mid_sentence_name = (
            i > 0
            and core[0].isupper()
            and core.lower() != "i"
            and not core.lower().startswith("i'")
            and src_words[i - 1][-1:] not in ".!?"
        )
        if looks_literal and core not in rewrite:
            return False
        if mid_sentence_name and core.lower() not in out_lower:
            return False

    src_stems = [s for s in (_stem(w) for w in src_words) if s]
    out_stems = [s for s in (_stem(w) for w in out_words) if s]
    if not src_stems or not out_stems:
        return False
    kept = sum(1 for s in src_stems if s in out_stems) / len(src_stems)
    known = sum(1 for s in out_stems if s in src_stems) / len(out_stems)
    return kept >= 0.7 and known >= 0.7


def split_into_chunks(text: str) -> List[Tuple[str, str]]:
    """
    Break `text` into (prefix, body) pieces the model can handle one at a time.
    Line breaks and list markers go in `prefix` so the layout survives exactly.
    """
    chunks: List[Tuple[str, str]] = []
    lines = text.split("\n")
    for n, line in enumerate(lines):
        newline = "\n" if n > 0 else ""
        m = _BULLET_RE.match(line)
        marker, body = (m.group(1), m.group(2)) if m else ("", line)
        if not body.strip():
            chunks.append((newline + line, ""))
            continue
        words = body.split()
        if len(words) <= MAX_WORDS_PER_CHUNK:
            chunks.append((newline + marker, body))
            continue
        # Long line: cut at sentence ends into pieces the model can hold.
        sentences = re.split(r"(?<=[.!?])\s+", body)
        piece: List[str] = []
        first = True
        for sentence in sentences:
            if piece and len(" ".join(piece + [sentence]).split()) > MAX_WORDS_PER_CHUNK:
                chunks.append(((newline + marker) if first else " ", " ".join(piece)))
                first, piece = False, []
            piece.append(sentence)
        if piece:
            chunks.append(((newline + marker) if first else " ", " ".join(piece)))
    return chunks


class SentenceFixer:
    def __init__(
        self,
        model_dir: str = MODEL_DIR,
        batch_fn: Optional[BatchFn] = None,
    ) -> None:
        self._model_dir = model_dir
        self._batch_fn = batch_fn  # injected in tests; loaded lazily otherwise
        self._load_lock = threading.Lock()
        self._load_failed = False
        self.device = ""
        self._cache: "OrderedDict[str, str]" = OrderedDict()
        self._pending: Optional[str] = None
        self._cond = threading.Condition()
        self._worker: Optional[threading.Thread] = None
        self.version = 0  # bumps whenever a new suggestion becomes ready

    @property
    def available(self) -> bool:
        if self._batch_fn is not None:
            return True
        return not self._load_failed and os.path.isfile(
            os.path.join(self._model_dir, "model.bin")
        )

    # ---- model ---------------------------------------------------------------
    def _ensure_loaded(self) -> Optional[BatchFn]:
        if self._batch_fn is not None or self._load_failed:
            return self._batch_fn
        with self._load_lock:
            if self._batch_fn is not None or self._load_failed:
                return self._batch_fn
            try:
                import ctranslate2
                import sentencepiece as spm

                sp = spm.SentencePieceProcessor(
                    model_file=os.path.join(self._model_dir, "spiece.model")
                )
                translator = None
                attempts = [("cpu", "int8")]
                if ctranslate2.get_cuda_device_count() > 0:
                    attempts.insert(0, ("cuda", "int8_float16"))
                for device, compute in attempts:
                    try:
                        translator = ctranslate2.Translator(
                            self._model_dir, device=device, compute_type=compute
                        )
                        translator.translate_batch([["▁Hi", "</s>"]], max_decoding_length=4)
                        self.device = device
                        break
                    except Exception:
                        translator = None
                if translator is None:
                    raise RuntimeError("grammar model could not be loaded")

                def run(batch: List[str]) -> List[str]:
                    tokens = [
                        sp.encode(PROMPT_PREFIX + s, out_type=str) + ["</s>"]
                        for s in batch
                    ]
                    results = translator.translate_batch(
                        tokens,
                        beam_size=4,
                        max_decoding_length=256,
                        repetition_penalty=1.05,
                    )
                    return [sp.decode(r.hypotheses[0]) for r in results]

                self._batch_fn = run
            except Exception:
                self._load_failed = True
        return self._batch_fn

    # ---- rewriting -----------------------------------------------------------
    def rewrite(self, text: str) -> Optional[str]:
        """Blocking. Returns the improved text, or None if there is nothing safe
        to suggest (or the text is too long / the model is unavailable)."""
        if not text.strip() or len(text.split()) > MAX_WORDS_TOTAL:
            return None
        run = self._ensure_loaded()
        if run is None:
            return None
        chunks = split_into_chunks(text)
        bodies = [body for _, body in chunks if body.strip()]
        if not bodies:
            return None
        try:
            outputs = iter(run(bodies))
        except Exception:
            return None
        parts: List[str] = []
        changed = False
        for prefix, body in chunks:
            if not body.strip():
                parts.append(prefix + body)
                continue
            out = (next(outputs, "") or "").strip()
            # The model ends everything with a full stop; headings and list
            # items that had none keep it that way.
            if out.endswith(".") and body.strip()[-1:] not in ".!?":
                out = out[:-1].rstrip()
            if out and out != body.strip() and is_safe_rewrite(body, out):
                parts.append(prefix + out)
                changed = True
            else:
                parts.append(prefix + body)
        return "".join(parts) if changed else None

    def suggest(self, text: str) -> Optional[str]:
        """
        Non-blocking. Returns a ready suggestion for exactly this text, or None
        (and starts working one out in the background; ask again shortly).
        An empty string in the cache means "checked: nothing to suggest".
        """
        if not self.available or not text.strip():
            return None
        with self._cond:
            if text in self._cache:
                self._cache.move_to_end(text)
                return self._cache[text] or None
            self._pending = text
            if self._worker is None:
                self._worker = threading.Thread(
                    target=self._work, daemon=True, name="sentence-fixer"
                )
                self._worker.start()
            self._cond.notify()
        return None

    def _work(self) -> None:
        while True:
            with self._cond:
                while self._pending is None:
                    self._cond.wait()
                text, self._pending = self._pending, None
            result = self.rewrite(text) or ""
            with self._cond:
                self._cache[text] = result
                while len(self._cache) > 48:
                    self._cache.popitem(last=False)
                self.version += 1
