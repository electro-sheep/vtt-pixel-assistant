"""
Local FastAPI / Uvicorn Sidecar Engine v3.0 for VTT Pixel Assistant.
Features:
- Automatic local CUDA 12 DLL discovery (cublas64_12.dll / cudart64_12.dll) + warmup + CPU int8 fallback
- Sensitive auto-gain microphone normalization for Realtek / laptop mic arrays
- Two-stage Live Streaming Transcription + Continuous In-Place Dyslexia & Grammar Auto-Correction Loop
- Active external window tracking, global F8 hotkey toggle, and real-time cursor coordinates for eye-tracking
- Writing tone control (clear, formal, casual) and session statistics
"""

from __future__ import annotations
import glob
import os
import re
import sys
import time
import threading
from typing import Dict, Any, List, Optional


def _setup_cuda_dll_paths() -> None:
    """Discover local NVIDIA CUDA 12 runtime DLLs (cublas64_12.dll, cudart64_12.dll) and register them."""
    local_app_data = os.environ.get("LOCALAPPDATA", "")
    candidates = glob.glob(
        os.path.join(
            local_app_data,
            "Packages",
            "*",
            "LocalCache",
            "Roaming",
            "lumen",
            "gpu",
            "nvidia",
            "*",
            "bin",
        )
    ) + glob.glob(
        os.path.join(sys.prefix, "Lib", "site-packages", "nvidia", "*", "bin")
    )
    added: List[str] = []
    for path in candidates:
        if os.path.isdir(path):
            try:
                os.add_dll_directory(path)
            except Exception:
                pass
            added.append(path)
    if added:
        os.environ["PATH"] = ";".join(added) + ";" + os.environ.get("PATH", "")


_setup_cuda_dll_paths()

import numpy as np
import sounddevice as sd
import ctranslate2
from faster_whisper import WhisperModel
from fastapi import FastAPI
from pydantic import BaseModel
import uvicorn

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dyslexia_grammar import LocalDyslexiaGrammarEngine, compute_in_place_edit
from win32_typer import (
    apply_in_place_screen_edit,
    capture_highlighted_screen_text,
    capture_screen_text_smart,
    set_clipboard_text,
    speak_text_aloud_async,
    window_tracker,
)

app = FastAPI(title="VTT Pixel Assistant Local Engine v3.4")

CREATURE_MODELS: Dict[str, Dict[str, Any]] = {
    "review": {
        "name": "Arcane Text Reviewer",
        "tier_num": 0,
        "tier": "Tier 0 • Pure Text Review (No VTT)",
        "vram": "0.0 GB VRAM",
        "model_id": "none",
        "fallback_id": "none",
        "compute_type": "none",
        "role": "Tier 0: Pure Current-Text Reviewer & Suggestion Engine (No Transcription)",
    },
    "ptero": {
        "name": "Sky Pterodactyl",
        "tier_num": 1,
        "tier": "Tier 1 • Lightweight Speed",
        "vram": "~0.5 GB VRAM",
        "model_id": "small.en",
        "fallback_id": "base.en",
        "compute_type": "int8_float16",
        "role": "Tier 1: Fast & Lightweight Live Dictation (Whisper Small)",
    },
    "stego": {
        "name": "Sky Pterodactyl",
        "tier_num": 1,
        "tier": "Tier 1 • Lightweight Speed",
        "vram": "~0.5 GB VRAM",
        "model_id": "small.en",
        "fallback_id": "base.en",
        "compute_type": "int8_float16",
        "role": "Tier 1: Fast & Lightweight Live Dictation (Whisper Small)",
    },
    "cultist": {
        "name": "Ember Cultist Scribe",
        "tier_num": 2,
        "tier": "Tier 2 • Grammarly Scribe",
        "vram": "~1.5 GB VRAM",
        "model_id": "medium.en",
        "fallback_id": "small.en",
        "compute_type": "int8_float16",
        "role": "Tier 2: Gungeon Ember Scribe + Full Grammarly & Dyslexia Editor (Whisper Medium)",
    },
    "cultist_lunar": {
        "name": "Lunatic Beak Cultist",
        "tier_num": 2,
        "tier": "Tier 2 • Grammarly Scribe",
        "vram": "~1.5 GB VRAM",
        "model_id": "medium.en",
        "fallback_id": "small.en",
        "compute_type": "int8_float16",
        "role": "Tier 2: Terraria Lunatic Scribe + Full Grammarly & Dyslexia Editor (Whisper Medium)",
    },
    "monster": {
        "name": "Ember Cultist Scribe",
        "tier_num": 2,
        "tier": "Tier 2 • Grammarly Scribe",
        "vram": "~1.5 GB VRAM",
        "model_id": "medium.en",
        "fallback_id": "small.en",
        "compute_type": "int8_float16",
        "role": "Tier 2: Gungeon Ember Scribe + Full Grammarly & Dyslexia Editor (Whisper Medium)",
    },
    "trex": {
        "name": "Apex Green T-Rex",
        "tier_num": 3,
        "tier": "Tier 3 • Apex Power",
        "vram": "~2.0 GB VRAM",
        "model_id": "mobiuslabsgmbh/faster-whisper-large-v3-turbo",
        "fallback_id": "large-v3",
        "compute_type": "int8_float16",
        "role": "Tier 3: Maximum Heavyweight Speech Accuracy (Whisper Large-v3-Turbo)",
    },
    "custom": {
        "name": "Custom Pixel Pet",
        "tier_num": 1,
        "tier": "Custom Companion",
        "vram": "~0.5 GB VRAM",
        "model_id": "small.en",
        "fallback_id": "base.en",
        "compute_type": "int8_float16",
        "role": "Custom Sprite Companion",
    },
}


HALLUCINATION_PHRASES = {
    "thank you",
    "thank you.",
    "thanks for watching",
    "thanks for watching.",
    "thank you for watching",
    "thank you for watching.",
    "please subscribe",
    "subtitles by",
    "amara.org",
    "you",
    "you.",
    "bye",
    "bye.",
    "the",
    "a",
    "so",
    "oh",
    "hm",
    "hmm",
}


def is_whisper_hallucination(text: str) -> bool:
    """Filter out known Whisper silence/static hallucinations and repetitive loops."""
    if not text:
        return True
    cleaned = text.strip()
    low = cleaned.lower().strip(" .,!?\"'-…")
    if not low:
        return True
    if low in HALLUCINATION_PHRASES:
        return True
    if "doing sphincter" in low or "jibbing and jabbing" in low or "amara.org" in low:
        return True
    # Reject single-character or non-alphabetic noise
    alpha_count = sum(1 for c in low if c.isalpha())
    if alpha_count < 2:
        return True
    # Reject severe word-repetition loops (e.g. "and and and and")
    words = low.split()
    if len(words) >= 6 and len(set(words)) <= 2:
        return True
    return False


class EngineState:
    def __init__(self, start_workers: bool = True) -> None:
        self.lock = threading.Lock()
        self.grammar = LocalDyslexiaGrammarEngine()
        self.active_creature: str = "trex"
        self.active_model_name: str = "large-v3-turbo"
        self.compute_backend: str = "CUDA"
        self.model_loading: bool = False
        self.loaded_models: Dict[str, Any] = {}

        # Dictation & screen-target state
        self.is_listening: bool = False
        self.target_selected: bool = True
        self.target_coords: Optional[Dict[str, int]] = None

        # Rolling audio, adaptive noise floor & live typing state
        self.sample_rate: int = 16000
        self.preroll_chunks: List[np.ndarray] = []
        self.audio_chunks: List[np.ndarray] = []
        self.noise_floor_rms: float = 0.0035
        self.last_voice_time: float = 0.0
        self.has_voice_in_utterance: bool = False
        self.audio_level: float = 0.0

        # Native C++ edit queue for loss-free typing in vtt_assistant.exe
        self.next_edit_id: int = 1
        self.pending_edits: List[Dict[str, Any]] = []
        self.last_ui_poll_time: float = 0.0

        # Active clause & full session transcript
        self.currently_typed_clause: str = ""
        self.last_review_capture_mode: str = "live"
        self.raw_live_text: str = ""
        self.polished_live_text: str = ""
        self.session_history: List[str] = []
        self.recent_fixes: List[Dict[str, str]] = []
        self.total_words_written: int = 0
        self.total_fixes_applied: int = 0
        self.status_message: str = "Ready! Click creature, ● REC, or 🔍 REVIEW."
        self.pet_anim_state: str = "idle"

        self.stream: Optional[sd.InputStream] = None
        self.running = True
        window_tracker.on_hotkey_f8 = self.toggle_listening_state
        if start_workers:
            self.worker_thread = threading.Thread(
                target=self._transcription_loop, daemon=True
            )
            self.worker_thread.start()

    def _enqueue_screen_edit(self, backspaces: int, text_to_type: str) -> None:
        if backspaces <= 0 and not text_to_type:
            return
        with self.lock:
            edit_id = self.next_edit_id
            self.next_edit_id += 1
            if self.pending_edits:
                # Coalesce with the latest unacknowledged edit so the UI executes
                # a single atomic (backspaces + paste) operation with zero race conditions!
                prev = self.pending_edits[-1]
                bs1 = int(prev["backspaces"])
                txt1 = str(prev["text"])
                bs2 = int(backspaces)
                txt2 = text_to_type
                if bs2 <= len(txt1):
                    net_bs = bs1
                    net_txt = (txt1[:-bs2] if bs2 > 0 else txt1) + txt2
                else:
                    net_bs = bs1 + (bs2 - len(txt1))
                    net_txt = txt2
                prev["id"] = edit_id
                prev["backspaces"] = net_bs
                prev["text"] = net_txt
            else:
                self.pending_edits.append(
                    {
                        "id": edit_id,
                        "backspaces": int(backspaces),
                        "text": text_to_type,
                    }
                )
            ui_connected = (time.time() - self.last_ui_poll_time) < 2.0

        # If running standalone without the Flutter C++ runner polling, type via Python Win32
        if not ui_connected:
            apply_in_place_screen_edit(backspaces, text_to_type)

    def review_current_screen_text(
        self, apply_immediately: bool = False, custom_text: str = ""
    ) -> None:
        if custom_text and custom_text.strip():
            captured = custom_text.strip()
            mode = "custom"
        else:
            captured, mode = capture_screen_text_smart()

        if not captured or not captured.strip():
            captured = self.polished_live_text or " ".join(self.session_history)
            mode = "history"

        if not captured or not captured.strip():
            self.status_message = (
                "Click inside any text box or highlight text, then click 🔍 REVIEW!"
            )
            return

        captured = captured.strip()
        corrected, fixes = self.grammar.process_text(captured, is_final_clause=False)

        with self.lock:
            self.raw_live_text = captured
            self.polished_live_text = corrected
            self.last_review_capture_mode = mode
            if fixes:
                self.recent_fixes = fixes[-6:]

            if apply_immediately:
                self.total_fixes_applied += len(fixes)
                self.pet_anim_state = "fixing" if fixes else "happy"
                self.currently_typed_clause = corrected
            else:
                # Non-destructive review mode: keep track of what is currently on
                # the screen (`captured`) so clicking any word suggestion or
                # [✓ APPLY FIXES] updates the screen cleanly from `captured` -> `new_text`!
                self.currently_typed_clause = captured
                self.pet_anim_state = "curious" if not fixes else "fixing"

        if apply_immediately:
            if mode == "selection":
                self._enqueue_screen_edit(0, corrected)
                with self.lock:
                    self.last_review_capture_mode = "document"
            else:
                bs, to_type = compute_in_place_edit(captured, corrected)
                if bs > 0 or to_type:
                    self._enqueue_screen_edit(bs, to_type)
            self.status_message = (
                f"Applied {len(fixes)} fix(es) to [{window_tracker.last_external_title}]!"
                if fixes
                else "Reviewed text is already clean — click any word for synonyms!"
            )
        else:
            word_count = len(captured.split())
            self.status_message = (
                f"Reviewed {word_count} words from [{window_tracker.last_external_title}] "
                f"({len(fixes)} auto-fix(es) + word suggestions ready)!"
            )

    def toggle_listening_state(self) -> None:
        if self.active_creature == "review":
            self.review_current_screen_text(apply_immediately=False)
            return

        with self.lock:
            self.is_listening = not self.is_listening
            self.preroll_chunks.clear()
            self.audio_chunks.clear()
            self.has_voice_in_utterance = False
            self.currently_typed_clause = ""
            self.last_review_capture_mode = "live"
            if self.is_listening:
                self.target_selected = True
                self.pet_anim_state = "listen"
                self.status_message = (
                    f"Listening → [{window_tracker.last_external_title}] (F8 or Click to stop)"
                )
            else:
                self.pet_anim_state = "idle"
                self.status_message = (
                    f"{CREATURE_MODELS[self.active_creature]['name']} paused. Click or F8 to talk!"
                )

    def start_audio_stream(self) -> None:
        if self.stream is not None:
            return

        def _audio_callback(
            indata: np.ndarray, frames: int, time_info: Any, status: Any
        ) -> None:
            mono = indata[:, 0].copy()
            rms = float(np.sqrt(np.mean(np.square(mono))))
            peak = float(np.max(np.abs(mono))) if len(mono) > 0 else 0.0

            # Dynamically track ambient mic noise floor so fans/static never trigger speech
            voice_rms_gate = max(0.0075, self.noise_floor_rms * 2.6)
            voice_peak_gate = max(0.028, self.noise_floor_rms * 5.2)
            is_speech_chunk = (rms > voice_rms_gate) and (peak > voice_peak_gate)

            if not is_speech_chunk:
                self.noise_floor_rms = float(
                    np.clip(
                        0.96 * self.noise_floor_rms + 0.04 * rms,
                        0.0020,
                        0.0220,
                    )
                )

            net_rms = max(0.0, rms - self.noise_floor_rms * 1.35)
            self.audio_level = min(1.0, net_rms * 28.0)

            if not self.is_listening:
                return

            with self.lock:
                if is_speech_chunk:
                    if not self.has_voice_in_utterance and self.preroll_chunks:
                        self.audio_chunks.extend(self.preroll_chunks)
                        self.preroll_chunks.clear()
                    self.audio_chunks.append(mono)
                    self.last_voice_time = time.time()
                    self.has_voice_in_utterance = True
                else:
                    if self.has_voice_in_utterance:
                        self.audio_chunks.append(mono)
                    else:
                        self.preroll_chunks.append(mono)
                        if len(self.preroll_chunks) > 3:
                            self.preroll_chunks.pop(0)

        try:
            self.stream = sd.InputStream(
                samplerate=self.sample_rate,
                channels=1,
                dtype="float32",
                blocksize=1600,
                callback=_audio_callback,
            )
            self.stream.start()
        except Exception as e:
            self.status_message = f"Mic error: {e}"

    def _load_and_verify_model(
        self, model_id: str, fallback_id: str, compute_type: str
    ) -> Any:
        dummy_audio = np.zeros(16000, dtype=np.float32)

        # 1. Try CUDA first if available
        if ctranslate2.get_cuda_device_count() > 0:
            for candidate in (model_id, fallback_id):
                try:
                    m = WhisperModel(
                        candidate,
                        device="cuda",
                        compute_type=compute_type,
                        local_files_only=True,
                    )
                    m.encode(m.feature_extractor(dummy_audio))
                    self.compute_backend = "CUDA GPU"
                    self.active_model_name = candidate.split("/")[-1]
                    return m
                except Exception:
                    continue

        # 2. Automatic fallback to fast multi-threaded int8 CPU
        for candidate in (model_id, fallback_id, "small.en", "base.en"):
            try:
                m = WhisperModel(
                    candidate,
                    device="cpu",
                    compute_type="int8",
                    cpu_threads=8,
                    local_files_only=True,
                )
                m.encode(m.feature_extractor(dummy_audio))
                self.compute_backend = "CPU int8"
                self.active_model_name = candidate.split("/")[-1]
                return m
            except Exception:
                continue

        raise RuntimeError("No local Whisper models could be loaded.")

    def get_or_load_whisper(self, creature_key: str) -> Any:
        info = CREATURE_MODELS.get(creature_key, CREATURE_MODELS["stego"])
        model_id = info["model_id"]
        if model_id == "none":
            self.active_model_name = "No-VTT (Review Only)"
            self.compute_backend = "0GB Local"
            self.model_loading = False
            return None
        if model_id in self.loaded_models:
            self.active_model_name = model_id.split("/")[-1]
            return self.loaded_models[model_id]

        self.model_loading = True
        short_name = model_id.split("/")[-1]
        self.status_message = f"Warming up {info['name']} ({short_name})..."
        try:
            model = self._load_and_verify_model(
                model_id, info["fallback_id"], info["compute_type"]
            )
            self.loaded_models[model_id] = model
            return model
        finally:
            self.model_loading = False

    def switch_creature(self, creature_key: str) -> None:
        if creature_key not in CREATURE_MODELS:
            creature_key = "stego"
        self.active_creature = creature_key
        if creature_key == "review":
            with self.lock:
                self.is_listening = False
                self.active_model_name = "No-VTT (Review Only)"
                self.compute_backend = "0GB Local"
                self.model_loading = False
                self.pet_anim_state = "curious"
                self.status_message = (
                    "Pure Text Reviewer [No-VTT • 0GB] ready! Click creature or 🔍 REVIEW to inspect current text."
                )
            return
        threading.Thread(
            target=self._preload_creature_model, args=(creature_key,), daemon=True
        ).start()

    def _preload_creature_model(self, creature_key: str) -> None:
        try:
            self.get_or_load_whisper(creature_key)
            info = CREATURE_MODELS[creature_key]
            if not self.is_listening:
                self.status_message = (
                    f"{info['name']} [{self.active_model_name} • {self.compute_backend}] ready!"
                )
        except Exception as e:
            self.status_message = f"Model load error: {e}"

    def _sync_screen_text(
        self, new_clause_text: str, is_grammar_fix: bool = False
    ) -> None:
        if not self.target_selected:
            return
        if new_clause_text == self.currently_typed_clause:
            return

        backspaces, to_type = compute_in_place_edit(
            self.currently_typed_clause, new_clause_text
        )
        if backspaces > 0 or to_type:
            self.pet_anim_state = "fixing" if is_grammar_fix else "typing"
            self._enqueue_screen_edit(backspaces, to_type)
            self.currently_typed_clause = new_clause_text

    def _transcription_loop(self) -> None:
        self.start_audio_stream()
        self._preload_creature_model(self.active_creature)

        while self.running:
            try:
                time.sleep(0.20)
                if not self.is_listening:
                    continue

                with self.lock:
                    if not self.audio_chunks or not self.has_voice_in_utterance:
                        continue
                    audio_data = np.concatenate(self.audio_chunks, axis=0)
                    silence_duration = time.time() - self.last_voice_time

                if len(audio_data) < int(self.sample_rate * 0.30):
                    continue

                peak = float(np.max(np.abs(audio_data)))
                if peak > 0.025:
                    gain = min(3.5, 0.78 / max(peak, 0.035))
                    norm_audio = np.clip(audio_data * gain, -1.0, 1.0).astype(np.float32)
                else:
                    if silence_duration >= 0.90:
                        with self.lock:
                            self.audio_chunks.clear()
                            self.has_voice_in_utterance = False
                    continue

                model = self.get_or_load_whisper(self.active_creature)
                segments, _ = model.transcribe(
                    norm_audio,
                    language="en",
                    beam_size=1,
                    best_of=1,
                    vad_filter=True,
                    vad_parameters=dict(
                        threshold=0.50,
                        min_speech_duration_ms=200,
                        min_silence_duration_ms=280,
                    ),
                    no_speech_threshold=0.60,
                    log_prob_threshold=-0.85,
                    compression_ratio_threshold=2.1,
                    condition_on_previous_text=False,
                )
                valid_parts: List[str] = []
                for seg in segments:
                    if getattr(seg, "no_speech_prob", 0.0) > 0.65:
                        continue
                    if getattr(seg, "avg_logprob", 0.0) < -0.95:
                        continue
                    txt = seg.text.strip()
                    if txt:
                        valid_parts.append(txt)

                raw_text = " ".join(valid_parts).strip()
                if not raw_text or is_whisper_hallucination(raw_text):
                    if silence_duration >= 0.85:
                        with self.lock:
                            self.audio_chunks.clear()
                            self.has_voice_in_utterance = False
                            self.currently_typed_clause = ""
                    continue

                self.raw_live_text = raw_text
                is_clause_done = (
                    silence_duration >= 0.72
                    or len(audio_data) > self.sample_rate * 9
                )

                # Compute Point A (the polished Yellow Box text) immediately
                corrected_text, fixes = self.grammar.process_text(
                    raw_text, is_final_clause=is_clause_done
                )
                self.polished_live_text = corrected_text
                if fixes:
                    self.recent_fixes = fixes[-6:]

                # Sync Point A (Yellow Box) -> Point B (the external page) cleanly:
                # Never type uncleaned raw_text and backspace it; only sync stable
                # words during active speech, and sync the complete corrected_text + " "
                # when the clause finishes!
                if self.target_selected:
                    if not is_clause_done:
                        clean_mid = corrected_text.rstrip(".?!, ")
                        words = clean_mid.split()
                        stable_words = (
                            words[:-1] if silence_duration < 0.35 else words
                        )
                        if stable_words:
                            stable_clause = " ".join(stable_words)
                            bs, _ = compute_in_place_edit(
                                self.currently_typed_clause, stable_clause
                            )
                            if bs <= 14:
                                self._sync_screen_text(
                                    stable_clause, is_grammar_fix=bool(fixes)
                                )
                        self.status_message = (
                            f"Live → {window_tracker.last_external_title}"
                        )
                    else:
                        final_clause = corrected_text + " "
                        self._sync_screen_text(
                            final_clause, is_grammar_fix=bool(fixes)
                        )
                        if fixes:
                            last_fix = fixes[-1]
                            self.status_message = (
                                f"Fixed: \"{last_fix['original']}\" → \"{last_fix['replacement']}\""
                            )
                        else:
                            self.status_message = (
                                f"Wrote → {window_tracker.last_external_title}"
                            )

                # Commit clause on natural speech pause
                if is_clause_done:
                    with self.lock:
                        if corrected_text:
                            self.session_history.append(corrected_text)
                            self.total_words_written += len(corrected_text.split())
                            self.total_fixes_applied += len(fixes)
                            if len(self.session_history) > 25:
                                self.session_history = self.session_history[-25:]
                        self.audio_chunks.clear()
                        self.has_voice_in_utterance = False
                        self.currently_typed_clause = ""
                    self.pet_anim_state = "listen"
            except Exception as e:
                self.status_message = f"Engine note: {str(e)[:55]}"


engine = EngineState(
    start_workers=(os.environ.get("VTT_TEST_MODE") != "1")
)


class CreatureSwitchReq(BaseModel):
    creature: str


class TargetClickReq(BaseModel):
    x: int
    y: int


class RulesUpdateReq(BaseModel):
    rules: Dict[str, bool]


class ToneUpdateReq(BaseModel):
    tone: str


class SpeakReq(BaseModel):
    text: str


class TypeTextReq(BaseModel):
    text: str


class ReviewSelectionReq(BaseModel):
    apply_immediately: bool = False
    text: str = ""


class ApplyRecommendationReq(BaseModel):
    original: str = ""
    replacement: str = ""
    word_index: int = -1
    replace_all: bool = False


@app.get("/status")
def get_status(ui: int = 0, last_edit_id: int = 0) -> Dict[str, Any]:
    with engine.lock:
        if ui == 1:
            engine.last_ui_poll_time = time.time()
            if last_edit_id > 0:
                engine.pending_edits = [
                    e for e in engine.pending_edits if e["id"] > last_edit_id
                ]
        pending = [e for e in engine.pending_edits if e["id"] > last_edit_id]
        latest_id = engine.next_edit_id - 1

    active_info = CREATURE_MODELS.get(
        engine.active_creature, CREATURE_MODELS["trex"]
    )
    eval_text = engine.polished_live_text or " ".join(engine.session_history[-3:])
    grammarly_report = engine.grammar.generate_grammarly_recommendations(
        eval_text, recent_fixes_count=len(engine.recent_fixes)
    )

    return {
        "engine_version": "3.4",
        "creature": engine.active_creature,
        "creature_name": active_info["name"],
        "creature_tier": int(active_info.get("tier_num", 3)),
        "creature_tier_label": active_info.get("tier", "Tier 3 • Apex Power"),
        "creature_vram": active_info.get("vram", "~2.0 GB VRAM"),
        "creature_role": active_info["role"],
        "model_name": engine.active_model_name,
        "compute_backend": engine.compute_backend,
        "model_loading": engine.model_loading,
        "is_listening": engine.is_listening,
        "target_selected": engine.target_selected,
        "target_window": window_tracker.last_external_title,
        "target_coords": engine.target_coords,
        "cursor_x": window_tracker.cursor_x,
        "cursor_y": window_tracker.cursor_y,
        "audio_level": round(engine.audio_level, 3),
        "raw_live_text": engine.raw_live_text,
        "polished_live_text": engine.polished_live_text,
        "session_transcript": " ".join(engine.session_history),
        "recent_fixes": engine.recent_fixes,
        "grammarly_report": grammarly_report,
        "total_words_written": engine.total_words_written,
        "total_fixes_applied": engine.total_fixes_applied,
        "writing_tone": engine.grammar.writing_tone,
        "status_message": engine.status_message,
        "pet_anim_state": (
            "listen"
            if engine.is_listening and engine.pet_anim_state == "idle"
            else engine.pet_anim_state
        ),
        "rules": engine.grammar.rules_enabled,
        "latest_edit_id": latest_id,
        "pending_edits": pending,
    }


@app.post("/toggle_listen")
def toggle_listen() -> Dict[str, Any]:
    engine.toggle_listening_state()
    return get_status()


@app.post("/target_clicked")
def target_clicked(req: TargetClickReq) -> Dict[str, Any]:
    _, win_title = window_tracker.lock_window_at_point(req.x, req.y)
    with engine.lock:
        engine.target_selected = True
        engine.target_coords = {"x": req.x, "y": req.y}
        engine.currently_typed_clause = ""
        if engine.is_listening:
            engine.pet_anim_state = "listen"
            engine.status_message = f"Target locked: [{win_title}] — Speak now!"
    return get_status()


@app.post("/switch_creature")
def switch_creature(req: CreatureSwitchReq) -> Dict[str, Any]:
    engine.switch_creature(req.creature)
    return get_status()


@app.post("/update_rules")
def update_rules(req: RulesUpdateReq) -> Dict[str, Any]:
    engine.grammar.set_rules(req.rules)
    engine.status_message = "Updated local dyslexia & grammar rules!"
    return get_status()


@app.post("/set_tone")
def set_tone(req: ToneUpdateReq) -> Dict[str, Any]:
    tone = engine.grammar.set_tone(req.tone)
    engine.status_message = f"Writing tone set to: {tone.upper()}"
    return get_status()


@app.post("/analyze_text")
def analyze_text(req: TypeTextReq) -> Dict[str, Any]:
    corrected, fixes = engine.grammar.process_text(req.text, is_final_clause=True)
    engine.raw_live_text = req.text
    engine.polished_live_text = corrected
    if fixes:
        engine.recent_fixes = fixes[-6:]
        engine.total_fixes_applied += len(fixes)
        engine.pet_anim_state = "fixing"
        engine.status_message = f"Fixed {len(fixes)} issue(s) in Scratchpad!"
    else:
        engine.pet_anim_state = "happy"
        engine.status_message = "Text is crystal clear!"
    return {
        "original": req.text,
        "corrected": corrected,
        "fixes": fixes,
        "grammarly_report": engine.grammar.generate_grammarly_recommendations(
            corrected, fixes
        ),
        "status": get_status(),
    }


@app.post("/review_selection")
def review_selection(
    req: Optional[ReviewSelectionReq] = None,
) -> Dict[str, Any]:
    apply_now = req.apply_immediately if req is not None else False
    custom_txt = req.text if req is not None else ""
    engine.review_current_screen_text(
        apply_immediately=apply_now, custom_text=custom_txt
    )
    return get_status()


@app.post("/type_text")
def type_text(req: TypeTextReq) -> Dict[str, Any]:
    corrected, fixes = engine.grammar.process_text(req.text, is_final_clause=True)
    engine.raw_live_text = req.text
    engine.polished_live_text = corrected
    if fixes:
        engine.recent_fixes = fixes[-6:]
        engine.total_fixes_applied += len(fixes)
    engine.total_words_written += len(corrected.split())
    engine._enqueue_screen_edit(0, corrected + " ")
    engine.pet_anim_state = "fixing" if fixes else "typing"
    engine.status_message = f"Typed into [{window_tracker.last_external_title}]!"
    return get_status()


@app.post("/apply_recommendation")
def apply_recommendation(req: ApplyRecommendationReq) -> Dict[str, Any]:
    with engine.lock:
        old_text = engine.polished_live_text
        if not old_text:
            return get_status()

        if req.replace_all and req.replacement:
            new_text = req.replacement.strip()
        elif req.word_index >= 0:
            tokens = old_text.split()
            if 0 <= req.word_index < len(tokens):
                tok = tokens[req.word_index]
                m = re.match(r"^([^A-Za-z']*)([A-Za-z']+)([^A-Za-z']*)$", tok)
                if req.replacement == "[DROP]":
                    tokens.pop(req.word_index)
                    new_text = " ".join(tokens)
                elif m:
                    prefix, _, suffix = m.group(1), m.group(2), m.group(3)
                    tokens[req.word_index] = f"{prefix}{req.replacement}{suffix}"
                    new_text = " ".join(tokens)
                else:
                    tokens[req.word_index] = req.replacement
                    new_text = " ".join(tokens)
            else:
                return get_status()
        elif req.original and req.original in old_text:
            if req.replacement == "[DROP]":
                new_text = re.sub(
                    r"\s*\b" + re.escape(req.original) + r"\b\s*",
                    " ",
                    old_text,
                    count=1,
                ).strip()
            else:
                new_text = old_text.replace(req.original, req.replacement, 1)
        else:
            return get_status()

        if new_text:
            new_text = new_text[0].upper() + new_text[1:]

        screen_baseline = engine.currently_typed_clause
        capture_mode = engine.last_review_capture_mode

        engine.polished_live_text = new_text
        engine.raw_live_text = new_text
        if engine.session_history and engine.session_history[-1] == old_text:
            engine.session_history[-1] = new_text
        engine.total_fixes_applied += 1
        engine.recent_fixes.append(
            {
                "original": req.original or (screen_baseline or old_text),
                "replacement": req.replacement,
                "reason": "Applied word-choice / rewrite upgrade on page",
                "category": "clarity",
            }
        )
        engine.recent_fixes = engine.recent_fixes[-6:]
        engine.currently_typed_clause = new_text
        if capture_mode == "selection":
            engine.last_review_capture_mode = "document"

    if capture_mode == "selection":
        bs, to_type = 0, new_text
    elif screen_baseline:
        bs, to_type = compute_in_place_edit(screen_baseline, new_text)
    else:
        bs, to_type = compute_in_place_edit(old_text + " ", new_text + " ")
        with engine.lock:
            engine.currently_typed_clause = ""

    if bs > 0 or to_type:
        engine.pet_anim_state = "fixing"
        engine._enqueue_screen_edit(bs, to_type)
        engine.status_message = (
            f"Helper upgraded: \"{req.original or 'text'}\" → \"{req.replacement}\""
        )
    return get_status()


@app.post("/clear_history")
def clear_history() -> Dict[str, Any]:
    with engine.lock:
        engine.session_history.clear()
        engine.raw_live_text = ""
        engine.polished_live_text = ""
        engine.recent_fixes.clear()
    engine.status_message = "Cleared transcript history."
    return get_status()


@app.post("/speak")
def speak_text(req: SpeakReq) -> Dict[str, Any]:
    text = (
        req.text.strip()
        or engine.polished_live_text
        or " ".join(engine.session_history)
        or engine.status_message
    )
    speak_text_aloud_async(text)
    engine.status_message = f"Reading aloud: \"{text[:42]}...\""
    return get_status()


@app.post("/shutdown")
def shutdown_server() -> Dict[str, str]:
    engine.running = False
    threading.Timer(0.2, lambda: os._exit(0)).start()
    return {"status": "shutting_down"}


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8765, log_level="warning")
