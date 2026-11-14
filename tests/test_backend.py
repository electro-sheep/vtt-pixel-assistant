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

import pytest

from dyslexia_grammar import LocalDyslexiaGrammarEngine, compute_in_place_edit
from live_cleaner import LiveTypingBuffer
from typo_fixer import SmartTypoFixer, is_checkable_token, typo_edit_cost
import vtt_engine

SPELLCHECK = SmartTypoFixer().available
needs_spellcheck = pytest.mark.skipif(
    not SPELLCHECK, reason="Windows spell checker not available on this machine"
)


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

    # Test Next-Gen Word Explorations (sound-alikes, vocabulary upgrades, hedges) & Sentence Variants
    exp_report = engine.generate_grammarly_recommendations(
        "I think that we basically need to make a big change right now."
    )
    explorations = exp_report["word_explorations"]
    kinds = {w["word"].lower(): w["kind"] for w in explorations}
    assert kinds.get("basically") == "hedging"
    assert kinds.get("make") == "upgrade"
    assert kinds.get("big") == "upgrade"
    assert kinds.get("change") == "upgrade"
    assert kinds.get("right") == "confusable"
    assert len(exp_report["sentence_variants"]) >= 1


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


def test_engine_endpoints_and_4_option_tier_progression():
    status = vtt_engine.get_status()
    assert status["engine_version"] == "3.5"
    assert "grammarly_report" in status

    # Tier 0: Pure Text Reviewer (No Transcription / 0GB VRAM)
    s0 = vtt_engine.switch_creature(vtt_engine.CreatureSwitchReq(creature="review"))
    assert s0["creature_tier"] == 0
    assert s0["creature_name"] == "Arcane Text Reviewer"
    assert s0["model_name"] == "No-VTT (Review Only)"
    assert s0["is_listening"] is False

    # Test Pure Text Review (apply_immediately=False: non-destructive review + suggestions)
    rev_res = vtt_engine.review_selection(
        vtt_engine.ReviewSelectionReq(
            apply_immediately=False,
            text="their going to basically make a big change",
        )
    )
    assert rev_res["raw_live_text"] == "their going to basically make a big change"
    assert "They're" in rev_res["polished_live_text"]
    assert len(rev_res["grammarly_report"]["word_explorations"]) >= 5

    # Tier 1: Pterodactyl
    s1 = vtt_engine.switch_creature(vtt_engine.CreatureSwitchReq(creature="ptero"))
    assert s1["creature_tier"] == 1
    assert s1["creature_name"] == "Sky Pterodactyl"

    # Tier 2A: Ember Cultist Scribe (Gungeon style)
    s2 = vtt_engine.switch_creature(vtt_engine.CreatureSwitchReq(creature="cultist"))
    assert s2["creature_tier"] == 2
    assert s2["creature_name"] == "Ember Cultist Scribe"

    # Tier 2B: Lunatic Beak Cultist (Terraria style)
    s2b = vtt_engine.switch_creature(vtt_engine.CreatureSwitchReq(creature="cultist_lunar"))
    assert s2b["creature_tier"] == 2
    assert s2b["creature_name"] == "Lunatic Beak Cultist"

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


# ---------------------------------------------------------------------------
# Smart typo fixing (wrong / missing / extra / swapped letters)
# ---------------------------------------------------------------------------


def test_typo_edit_cost_prefers_real_slips():
    # swapped pair, key next door and dropped ending are cheaper than random edits
    assert typo_edit_cost("hgih", "high") < 1.0
    assert typo_edit_cost("gfo", "go") < typo_edit_cost("gfo", "goo")
    assert typo_edit_cost("wron", "wrong") < 1.0
    assert typo_edit_cost("leter", "letter") < typo_edit_cost("leter", "later")
    assert typo_edit_cost("gungeon", "dungeon") > 1.0  # wrong first letter is costly


def test_typo_fixer_leaves_code_paths_and_acronyms_alone():
    text = "mail bob@exmaple.com open main.dart call fooBar use the NASA api_key"
    checkable = {
        text[m.start():m.end()]
        for m in __import__("re").finditer(r"[A-Za-z]+", text)
        if is_checkable_token(text, m.start(), m.end())
    }
    for skipped in ("exmaple", "main", "dart", "fooBar", "NASA", "api", "key", "bob"):
        assert skipped not in checkable
    assert {"mail", "open", "call", "use", "the"} <= checkable


@needs_spellcheck
def test_smart_typo_fix_wrong_and_missing_letters():
    engine = LocalDyslexiaGrammarEngine()
    raw = (
        "improve the review functinality as i will offen use the wron lewtters "
        "or miss them i want ti to be cleaning text up as we gfo"
    )
    corrected, fixes = engine.process_text(raw, source="typed")
    assert corrected == (
        "Improve the review functionality as I will often use the wrong letters "
        "or miss them I want it to be cleaning text up as we go"
    )
    fixed = {f["original"]: f["replacement"] for f in fixes}
    assert fixed["wron"] == "wrong" and fixed["gfo"] == "go" and fixed["ti"] == "it"

    # Unsure words are NOT guessed: they stay put and become clickable choices.
    c2, _ = engine.process_text("the cnt of pytest runs in Gungeon", source="typed")
    assert "cnt" in c2 and "pytest" in c2 and "Gungeon" in c2
    report = engine.generate_grammarly_recommendations(c2)
    kinds = {w["word"]: w for w in report["word_explorations"]}
    assert kinds["cnt"]["kind"] == "spelling" and kinds["cnt"]["alternatives"]
    assert kinds["Gungeon"]["kind"] == "normal"  # capitalised name: left alone

    # Voice text skips fuzzy fixing; a learned word is never touched again.
    v, _ = engine.process_text("we gfo now", source="voice")
    assert "gfo" in v
    engine.typo_fixer.learn_word("gfo")
    t, _ = engine.process_text("we gfo now", source="typed")
    assert "gfo" in t


def test_typed_text_keeps_spoken_punctuation_words():
    engine = LocalDyslexiaGrammarEngine()
    typed, _ = engine.process_text("the trial period ended um yesterday", source="typed")
    assert "trial period ended" in typed and "um" in typed
    voice, _ = engine.process_text("the trial ended period", source="voice")
    assert voice == "The trial ended."


def test_live_source_preserves_whitespace_and_chunk_start():
    engine = LocalDyslexiaGrammarEngine()
    out, fixes = engine.process_text("  and teh cat  ", source="live")
    assert out == "  and the cat  "  # no trim, no capital on a mid-sentence chunk
    assert fixes and fixes[0]["original"] == "teh"
    out2, _ = engine.process_text("in order to go ", source="live")
    assert out2 == "in order to go "  # phrases are never rewritten mid-typing


def _type(buf: LiveTypingBuffer, text: str):
    edits = []
    for ch in text:
        e = buf.on_char(ch)
        if e:
            edits.append(e)
    return edits


def _apply(screen: str, edit) -> str:
    bs, typed = edit
    return (screen[:-bs] if bs else screen) + typed


def test_live_typing_buffer_fixes_finished_words_only():
    grammar = LocalDyslexiaGrammarEngine()
    buf = LiveTypingBuffer(lambda r: grammar.process_text(r, source="live"))

    assert _type(buf, "i saw te") == []  # word still being typed: hands off
    assert _type(buf, "h") == []
    edits = _type(buf, " ")
    assert len(edits) == 1
    assert _apply("i saw teh ", edits[0]) == "I saw the "
    assert buf.text == "I saw the "

    # contextual homophone needs the next word, then both get fixed together
    buf.reset()
    screen = ""
    for ch in "their going ":
        screen += ch
        e = buf.on_char(ch)
        if e:
            screen = _apply(screen, e)
    assert screen == "they're going "

    # characters typed after the trigger (but before the fix lands) are retyped
    buf.reset()
    _type(buf, "teh")
    edit = buf.on_char(" ", pending_tail="ca")
    assert _apply("teh ca", edit) == "the ca"


def test_live_typing_buffer_backspace_undoes_and_suppresses():
    grammar = LocalDyslexiaGrammarEngine()
    buf = LiveTypingBuffer(lambda r: grammar.process_text(r, source="live"))
    edit = _type(buf, "teh ")[0]
    screen = _apply("teh ", edit)
    assert screen == "the "

    screen = screen[:-1]  # the user's own Backspace
    undo = buf.on_backspace()
    assert undo is not None
    screen = _apply(screen, undo)
    assert screen == "teh" and buf.text == "teh"
    assert _type(buf, " ") == []  # not "fixed" again after being rejected

    buf.reset()
    _type(buf, "cat")
    assert buf.on_backspace() is None and buf.text == "ca"


def test_clean_live_scratchpad_keeps_caret_and_word_in_progress():
    text = "teh cat adn te"
    res = vtt_engine.clean_live(vtt_engine.CleanLiveReq(text=text, caret=len(text)))
    assert res["text"] == "The cat and te"  # "te" is still being typed
    assert res["caret"] == len("The cat and te")
    assert res["changed"] is True and len(res["fixes"]) == 2

    # caret in the middle: text after it is untouched, caret shifts with the fix
    res2 = vtt_engine.clean_live(vtt_engine.CleanLiveReq(text="alot of teh", caret=5))
    assert res2["text"] == "A lot of teh"
    assert res2["caret"] == 6


def test_review_modes_never_backspace_text_that_is_not_on_screen():
    eng = vtt_engine.engine
    st = vtt_engine.get_status(ui=1, last_edit_id=0)
    vtt_engine.get_status(ui=1, last_edit_id=st["latest_edit_id"])
    base = st["latest_edit_id"]

    # Custom / clipboard text is preview-only ("detached")
    vtt_engine.review_selection(
        vtt_engine.ReviewSelectionReq(apply_immediately=True, text="teh cat")
    )
    assert eng.last_review_capture_mode == "detached"
    assert eng.polished_live_text == "The cat"
    vtt_engine.apply_recommendation(
        vtt_engine.ApplyRecommendationReq(original="cat", replacement="dog")
    )
    assert eng.polished_live_text == "The dog"
    assert vtt_engine.get_status(ui=1, last_edit_id=base)["pending_edits"] == []

    # A captured document keeps its surrounding whitespace in the diff baseline
    eng.last_review_capture_mode = "document"
    eng.review_lead, eng.review_trail = "", "\n"
    eng.polished_live_text = "The dog"
    eng.currently_typed_clause = "The dog\n"
    vtt_engine.apply_recommendation(
        vtt_engine.ApplyRecommendationReq(original="dog", replacement="fox")
    )
    edits = vtt_engine.get_status(ui=1, last_edit_id=base)["pending_edits"]
    assert len(edits) == 1
    assert edits[0]["backspaces"] == len("dog\n") and edits[0]["text"] == "fox\n"
    eng.last_review_capture_mode = "live"
    eng.review_lead = eng.review_trail = ""
    eng.currently_typed_clause = ""


def test_status_reports_live_clean_and_fix_events():
    before = vtt_engine.get_status()
    assert before["live_clean"] is False
    assert "smart_typos_available" in before
    vtt_engine.clean_live(vtt_engine.CleanLiveReq(text="i recieve "))
    after = vtt_engine.get_status()
    assert after["fix_event_id"] > before["fix_event_id"]
    assert after["latest_fix"]["replacement"] in ("receive", "I")


# ---------------------------------------------------------------------------
# Rule-level review fixes: punctuation, lists, real-word mix-ups, verb forms
# ---------------------------------------------------------------------------


def _typed(text: str) -> str:
    return LocalDyslexiaGrammarEngine().process_text(
        text, is_final_clause=True, source="typed"
    )[0]


def _voice(text: str) -> str:
    return LocalDyslexiaGrammarEngine().process_text(
        text, is_final_clause=True, source="voice"
    )[0]


def test_meant_repeats_and_numbers_are_not_collapsed():
    assert "twenty twenty five" in _voice("in may twenty twenty five we met")
    assert _voice("i i i want to to go there") == "I want to go there."
    assert "had had" in _typed("she had had enough")


def test_irregular_verbs_beat_the_nearest_dictionary_word():
    assert _typed("i payed with my card") == "I paid with my card."
    assert _typed("she teached me and i catched it") == "She taught me and I caught it."


def test_punctuation_spacing_and_comma_apostrophe_slips():
    assert _typed("i will try .i hope it,s ok , thanks") == (
        "I will try. I hope it's ok, thanks."
    )
    assert _typed("its good.but maybe not ?yes") == "It's good. But maybe not? Yes."
    # things that only look like punctuation mistakes are left exactly as typed
    kept = _typed("see main.dart and www.site.com/page?id=1 at 3.5 or 1,000")
    for literal in ("main.dart", "www.site.com/page?id=1", "3.5", "1,000"):
        assert literal in kept


def test_lists_and_lines_keep_their_shape():
    out = _typed("shopping list\n- milk\n- two eggs")
    assert out == "Shopping list\n- Milk\n- Two eggs"  # no full stop on a bullet
    assert _typed("  indented line\n    deeper line") == "Indented line\n    Deeper line."


def test_real_word_mix_ups_with_clear_context():
    assert _typed("i dont no if we went too the park") == (
        "I don't know if we went to the park."
    )
    assert _typed("the letter was form the bank") == "The letter was from the bank."
    assert _typed("i need to by some milk") == "I need to buy some milk."
    assert _typed("i didnt of time") == "I didn't have time."
    # ...and the same words used correctly are untouched
    safe = "We walk by the river and by the way I have no idea how atoms form the bond."
    assert _typed(safe) == safe


def test_word_order_slips_for_small_words():
    assert _typed("i want to go the to shop") == "I want to go to the shop."
    assert _typed("it is one the of best") == "It is one of the best."


def test_verb_forms_and_agreement():
    assert _typed("i should of went and we seen a dog") == (
        "I should have gone and we saw a dog."
    )
    assert _typed("I has a cat and they is cute and she have a hat") == (
        "I have a cat and they are cute and she has a hat."
    )
    safe = "Does he have it? One of you is wrong. Have they seen it?"
    assert _typed(safe) == safe


def test_a_an_by_sound():
    assert _typed("a elephant and an dog with a hour to spare") == (
        "An elephant and a dog with an hour to spare."
    )
    safe = "A user met an FBI agent at a one off event in a European university."
    assert _typed(safe) == safe


def test_final_punctuation_judges_the_last_sentence_only():
    assert _typed("can you come? i have a idea") == "Can you come? I have an idea."


@needs_spellcheck
def test_names_days_and_places_get_capitals():
    assert _typed("see you on monday in london") == "See you on Monday in London."


def test_spoken_formatting_commands():
    assert _voice(
        "open quote hello close quote she said new paragraph next point colon first item"
    ) == '"Hello" she said\n\nNext point: first item.'
    assert _voice("we could, you know, go home") == "We could go home."
    assert _voice("hello new line how are you") == "Hello\nHow are you?"


def test_dictation_chunks_are_stitched_into_sentences():
    g = LocalDyslexiaGrammarEngine()
    out, still_open = [], False
    for chunk in ["So.", "The thing is.", "We need to.", "Finish this.", "I agree."]:
        text, _ = g.process_text(chunk, is_final_clause=True, source="voice")
        text, still_open = g.join_dictated_clause(text, still_open, True)
        out.append(text)
    assert " ".join(out) == "So the thing is we need to finish this. I agree."
    # a mid-clause (not final) chunk never loses its full stop early
    assert g.join_dictated_clause("We need to.", False, False) == ("We need to.", False)
