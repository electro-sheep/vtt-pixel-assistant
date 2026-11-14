"""
Comprehensive Pytest Suite for VTT Pixel Assistant Backend v3.3.
Tests:
- Dyslexia letter-reversal, transposition & phonetic spelling corrections
- Context-aware homophone disambiguation (their/there/they're, your/you're, to/too/two, etc.)
- Grammarly-style 4-Pillar Clarity & Conciseness rules + Interactive Recommendations
- 3-Tier Creature & Whisper Model Progression (Pterodactyl -> Cultist -> T-Rex)
- Spoken filler & phrase-level stutter removal
- Intelligent question vs. statement punctuation
- Writing tone modes (clear, formal, casual) & rule toggles
- In-place screen diff calculator (compute_in_place_edit)
- FastAPI v3.3 engine endpoints including /apply_recommendation
"""

from __future__ import annotations
import os
import sys

os.environ["VTT_TEST_MODE"] = "1"
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

from dyslexia_grammar import LocalDyslexiaGrammarEngine, compute_in_place_edit
import vtt_engine


def test_dyslexia_reversals_and_transpositions():
    engine = LocalDyslexiaGrammarEngine()
    raw = "this is better as a proto type can we take thisd to teh next level and improve how the test isd witten and makje this a finished product"
    corrected, fixes = engine.process_text(raw, is_final_clause=True)
    assert "prototype" in corrected.lower()
    assert "take this to the next level" in corrected.lower()
    assert "test is written" in corrected.lower()
    assert "make this a finished product" in corrected.lower()
    assert len(fixes) >= 6

    raw2 = "the box abouve the charachter worlks but the text writend dosne workl keep implimenting improvments and preform more tests"
    corrected2, fixes2 = engine.process_text(raw2, is_final_clause=True)
    assert "the box above the character works" in corrected2.lower()
    assert "the text written doesn't work" in corrected2.lower()
    assert "keep implementing improvements and perform more tests." in corrected2.lower()
    assert len(fixes2) >= 8

    raw3 = "thats fine we need to fix the wya of it getting from point a to be also kee improveing the animations maker it more life like in the same art stule"
    corrected3, fixes3 = engine.process_text(raw3, is_final_clause=True)
    assert "that's fine" in corrected3.lower()
    assert "fix the way of it getting from point a to b" in corrected3.lower()
    assert "keep improving the animations make it more lifelike in the same art style." in corrected3.lower()
    assert len(fixes3) >= 7


def test_pterodactyl_and_dinosaur_phonetic_spellings():
    engine = LocalDyslexiaGrammarEngine()
    c, fixes = engine.process_text(
        "change the stegostaurus to a peridactyl for lightweight speed",
        is_final_clause=True,
    )
    assert "Stegosaurus" in c
    assert "Pterodactyl" in c
    assert len(fixes) >= 2


def test_grammarly_4_pillar_clarity_and_recommendations():
    engine = LocalDyslexiaGrammarEngine()
    raw = "in order to finish due to the fact that it is really good we have a lot of tests"
    corrected, fixes = engine.process_text(raw, is_final_clause=True)
    assert "To finish because it is really good we have a lot of tests." == corrected
    categories = {f["category"] for f in fixes}
    assert "clarity" in categories

    report = engine.generate_grammarly_recommendations(corrected, fixes)
    assert "writing_score" in report
    assert 60 <= report["writing_score"] <= 100
    assert "pillar_scores" in report
    assert set(report["pillar_scores"].keys()) == {
        "correctness",
        "clarity",
        "engagement",
        "delivery",
    }
    recs = report["recommendations"]
    assert len(recs) >= 2
    originals = {r["original"].lower() for r in recs}
    assert "really good" in originals
    assert "a lot of" in originals


def test_contextual_homophones_their_there_theyre():
    engine = LocalDyslexiaGrammarEngine()

    c1, _ = engine.process_text("their going to love there new project over they're", is_final_clause=True)
    assert c1 == "They're going to love their new project over there."

    c2, _ = engine.process_text("they're are to many errors in there code", is_final_clause=True)
    assert c2 == "There are too many errors in their code."


def test_contextual_homophones_your_youre_its_to_too_two():
    engine = LocalDyslexiaGrammarEngine()

    c1, _ = engine.process_text("your going to fast with you're car", is_final_clause=True)
    assert c1 == "You're going too fast with your car."

    c2, _ = engine.process_text("its a great idea and it's tail wags for to days", is_final_clause=True)
    assert c2 == "It's a great idea and its tail wags for two days."


def test_more_homophones_and_confusables():
    engine = LocalDyslexiaGrammarEngine()

    c1, _ = engine.process_text("this is better then before so don't loose hope", is_final_clause=True)
    assert c1 == "This is better than before so don't lose hope."

    c2, _ = engine.process_text("weather or not it has a big affect we can read allowed", is_final_clause=True)
    assert c2 == "Whether or not it has a big effect we can read aloud."

    c3, _ = engine.process_text("he walked passed the door for a peace of cake", is_final_clause=True)
    assert c3 == "He walked past the door for a piece of cake."


def test_stutter_and_filler_cleanup():
    engine = LocalDyslexiaGrammarEngine()
    raw = "um I think I think that the the dinosaur could of helped"
    corrected, fixes = engine.process_text(raw, is_final_clause=True)
    assert corrected == "I think that the dinosaur could have helped."
    categories = {f["category"] for f in fixes}
    assert "speech_cleanup" in categories
    assert "homophone" in categories


def test_intelligent_question_detection():
    engine = LocalDyslexiaGrammarEngine()

    q1, _ = engine.process_text("how does the live transcription work", is_final_clause=True)
    assert q1 == "How does the live transcription work?"

    q2, _ = engine.process_text("can we take this to the next level", is_final_clause=True)
    assert q2 == "Can we take this to the next level?"

    s1, _ = engine.process_text("the green dinosaur is walking around", is_final_clause=True)
    assert s1 == "The green dinosaur is walking around."


def test_writing_tone_formal_vs_clear():
    engine = LocalDyslexiaGrammarEngine()
    engine.set_tone("formal")
    c_formal, _ = engine.process_text("i can't believe we don't have a issue", is_final_clause=True)
    assert c_formal == "I cannot believe we do not have an issue."

    engine.set_tone("clear")
    c_clear, _ = engine.process_text("i can't believe we don't have a issue", is_final_clause=True)
    assert c_clear == "I can't believe we don't have an issue."


def test_compute_in_place_edit():
    bs, to_type = compute_in_place_edit("Hello", "Hello world")
    assert bs == 0
    assert to_type == " world"

    bs, to_type = compute_in_place_edit("Their going", "They're going")
    assert bs == len("ir going")
    assert to_type == "y're going"

    bs, to_type = compute_in_place_edit("Same text", "Same text")
    assert bs == 0
    assert to_type == ""


def test_hallucination_filter():
    assert vtt_engine.is_whisper_hallucination("Thank you.") is True
    assert vtt_engine.is_whisper_hallucination("Thanks for watching.") is True
    assert vtt_engine.is_whisper_hallucination("Doing sphincter and jibbing and jabbing") is True
    assert vtt_engine.is_whisper_hallucination("you") is True
    assert vtt_engine.is_whisper_hallucination("and and and and and and") is True
    assert vtt_engine.is_whisper_hallucination("I would like for it to be live.") is False
    assert vtt_engine.is_whisper_hallucination("Being able to control the grammar rules locally makes sense.") is False


def test_adaptive_noise_floor_gate():
    import numpy as np

    eng = vtt_engine.EngineState(start_workers=False)
    eng.is_listening = True

    rng = np.random.default_rng(42)
    for _ in range(30):
        static_chunk = rng.normal(0.0, 0.0038, size=1600).astype(np.float32)
        rms = float(np.sqrt(np.mean(np.square(static_chunk))))
        peak = float(np.max(np.abs(static_chunk)))
        voice_rms_gate = max(0.0075, eng.noise_floor_rms * 2.6)
        voice_peak_gate = max(0.028, eng.noise_floor_rms * 5.2)
        is_speech = (rms > voice_rms_gate) and (peak > voice_peak_gate)
        assert is_speech is False

    t = np.linspace(0, 0.1, 1600, dtype=np.float32)
    speech_chunk = (0.09 * np.sin(2 * np.pi * 180 * t)).astype(np.float32)
    rms_s = float(np.sqrt(np.mean(np.square(speech_chunk))))
    peak_s = float(np.max(np.abs(speech_chunk)))
    assert rms_s > max(0.0075, eng.noise_floor_rms * 2.6)
    assert peak_s > max(0.028, eng.noise_floor_rms * 5.2)


def test_pending_edits_queue_and_recommendation_application():
    st0 = vtt_engine.get_status(ui=1, last_edit_id=0)
    base_id = st0["latest_edit_id"]
    vtt_engine.get_status(ui=1, last_edit_id=base_id)

    vtt_engine.engine.currently_typed_clause = ""
    vtt_engine.engine._sync_screen_text("Their", is_grammar_fix=False)
    vtt_engine.engine._sync_screen_text("They're really good", is_grammar_fix=True)

    st1 = vtt_engine.get_status(ui=1, last_edit_id=base_id)
    edits = st1["pending_edits"]
    assert len(edits) == 1
    assert edits[0]["backspaces"] == 0 and edits[0]["text"] == "They're really good"

    # Acknowledge edit #1 so the queue is clean before applying helper recommendation
    vtt_engine.get_status(ui=1, last_edit_id=st1["latest_edit_id"])

    # Now test interactive helper recommendation application (/apply_recommendation)
    vtt_engine.engine.polished_live_text = "They're really good"
    res_rec = vtt_engine.apply_recommendation(
        vtt_engine.ApplyRecommendationReq(
            original="really good",
            replacement="excellent",
        )
    )
    assert res_rec["polished_live_text"] == "They're excellent"
    st2 = vtt_engine.get_status(ui=1, last_edit_id=st1["latest_edit_id"])
    assert len(st2["pending_edits"]) == 1
    assert st2["pending_edits"][0]["backspaces"] == len("really good")
    assert st2["pending_edits"][0]["text"] == "excellent"


def test_engine_endpoints_and_3_tier_progression():
    status = vtt_engine.get_status()
    assert status["engine_version"] == "3.3"
    assert "grammarly_report" in status

    # Tier 1: Pterodactyl
    s1 = vtt_engine.switch_creature(vtt_engine.CreatureSwitchReq(creature="ptero"))
    assert s1["creature_tier"] == 1
    assert s1["creature_name"] == "Sky Pterodactyl"

    # Tier 2: Cultist Scribe
    s2 = vtt_engine.switch_creature(vtt_engine.CreatureSwitchReq(creature="cultist"))
    assert s2["creature_tier"] == 2
    assert s2["creature_name"] == "Hooded Cultist Scribe"

    # Tier 3: Green T-Rex
    s3 = vtt_engine.switch_creature(vtt_engine.CreatureSwitchReq(creature="trex"))
    assert s3["creature_tier"] == 3
    assert s3["creature_name"] == "Apex Green T-Rex"

    res_tone = vtt_engine.set_tone(vtt_engine.ToneUpdateReq(tone="formal"))
    assert res_tone["writing_tone"] == "formal"
    vtt_engine.set_tone(vtt_engine.ToneUpdateReq(tone="clear"))

    analysis = vtt_engine.analyze_text(
        vtt_engine.TypeTextReq(text="their going to recieve teh file")
    )
    assert analysis["corrected"] == "They're going to receive the file."
    assert len(analysis["fixes"]) >= 3
    assert "grammarly_report" in analysis

    res_clear = vtt_engine.clear_history()
    assert res_clear["raw_live_text"] == ""
