"""
Production Dyslexia, Homophone, & Spoken-to-Written Rewriting Engine v3.0.
Designed specifically to help people with dyslexia get ideas from their head
onto the page clearly, accurately, and in real time (<1ms execution).

Features:
- 140+ Dyslexia letter-reversal, transposition, and phonetic spelling corrections
- 30+ Context-aware homophone & confusable word disambiguation patterns
- Phrase-level stutter & false-start removal ("I think I think" -> "I think")
- Intelligent question detection ("How does this work" -> "How does this work?")
- Discourse comma insertion & 3 selectable writing tones (clear, formal, casual)
- Word-boundary-safe in-place screen diff computation
"""

from __future__ import annotations
import re
from dataclasses import dataclass, asdict
from typing import List, Dict, Optional, Tuple

from typo_fixer import (
    COMMON_WORD_RANK,
    SmartTypoFixer,
    WORD_RE,
    is_checkable_token,
)

# ---------------------------------------------------------------------------
# Small helpers for the contextual rules
# ---------------------------------------------------------------------------

def _keep_case(source: str, target: str) -> str:
    return target.capitalize() if source[:1].isupper() else target


def _guarded(m: "re.Match", blocked_leads: set, replacement: str) -> str:
    """Apply `replacement` unless the word before the match makes it valid as is
    (e.g. "does he have", "one of you is", "have they seen")."""
    lead = m.group(1)
    if lead:
        low = lead.lower().strip(".,;:!?\"'()")
        if low in blocked_leads or low.endswith("n't"):
            return m.group(0)
        return f"{lead} {replacement}"
    return replacement


_PARTICIPLES = {
    "went": "gone", "ate": "eaten", "wrote": "written", "took": "taken",
    "came": "come", "did": "done", "ran": "run", "began": "begun",
    "drank": "drunk", "broke": "broken", "spoke": "spoken", "chose": "chosen",
    "gave": "given", "saw": "seen", "fell": "fallen", "drove": "driven",
    "rode": "ridden", "sang": "sung", "swam": "swum", "threw": "thrown",
    "knew": "known", "grew": "grown", "flew": "flown", "wore": "worn",
    "tore": "torn", "stole": "stolen", "froze": "frozen", "woke": "woken",
    "shook": "shaken",
}
_PERFECT_LEADS = {
    "have", "has", "had", "having", "be", "been", "being", "is", "are", "was",
    "were", "get", "got", "gets", "i've", "we've", "you've", "they've",
}
_BARE_VERB_LEADS = {
    "do", "does", "did", "can", "could", "will", "would", "should", "shall",
    "may", "might", "must", "let", "lets", "let's", "make", "made", "makes",
    "help", "see", "saw", "watch", "to", "if", "that", "rather",
}
# "a" stays "a" before a vowel LETTER with a consonant SOUND, or a function word
_A_KEEP = re.compile(
    r"^(?:uni|use|usu|uti|eur|ubiq|ura|uke|ewe|one$|once$|ones$|user|"
    r"and$|or$|in$|is$|at$|on$|of$|if$|as$|are$|it$|its$|into$|onto$|up$|us$|"
    r"either$|each$|every$|all$|any$|also$|only$|even$|after$|about$|above$|"
    r"across$|around$|among$|until$|under$|unless$|over$|out$|off$|other)",
    re.IGNORECASE,
)
_AN_KEEP = re.compile(r"^(?:hour|honest|honor|honour|heir|herb)", re.IGNORECASE)

_NUMBER_WORDS = {
    "zero", "oh", "one", "two", "three", "four", "five", "six", "seven", "eight",
    "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
    "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty",
    "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "thousand",
    "million", "billion", "double", "triple",
}
# Repeats that are meant ("had had", "twenty twenty", "no no", "bye bye")
_REPEAT_OK = _NUMBER_WORDS | {"had", "that", "very", "so", "no", "bye", "ha", "knock", "really", "blah", "night"}

_FILE_ENDINGS = {
    "com", "org", "net", "io", "co", "uk", "gov", "edu", "ai", "dev", "app", "txt",
    "py", "js", "ts", "dart", "json", "md", "exe", "png", "jpg", "gif", "pdf",
    "doc", "docx", "xls", "xlsx", "csv", "html", "css", "zip", "bat", "yaml", "yml",
}
_DAYS_MONTHS = re.compile(
    r"\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|"
    r"april|june|july|september|october|november|december)\b"
)
_AMBIGUOUS_MONTH = re.compile(
    r"\b((?:in|of|on|since|until|by|last|next|this|early|late|mid|during|before|after)\s+)"
    r"(march|may|august)\b(?=\s+(?:\d|the\s+\d|first|second|third|\w+th\b|"
    + "|".join(sorted(_NUMBER_WORDS))
    + r")|[.,!?]|\s*$)",
    re.IGNORECASE,
)
# Words a finished sentence practically never ends on. If a dictated chunk ends
# on one, the speaker only paused: don't put a full stop there.
_DANGLING = {
    "to", "the", "a", "an", "and", "or", "but", "so", "because", "of", "at",
    "for", "with", "from", "by", "as", "if", "when", "while", "than", "into",
    "my", "your", "our", "their", "his", "will", "would", "can", "could",
    "should", "very", "really", "about", "which", "who", "that's", "it's",
    "i'm", "we're", "they're", "you're", "we", "i", "they",
}


def _tidy_punctuation(text: str) -> str:
    """Put punctuation where it belongs: no space before it, one space after it,
    and an apostrophe where a comma was hit by mistake ("it,s")."""
    text = re.sub(r"\b([A-Za-z]+),(s|t|re|ve|ll|d|m)\b", r"\1'\2", text)
    text = re.sub(r"(?<=\w)[ \t]+([,!?;])", r"\1", text)
    text = re.sub(r"(?<=\w)[ \t]+:(?=\s|$)", ":", text)
    text = re.sub(r"(?<=\w)[ \t]+\.(?=\s|$)", ".", text)
    # "try .i hope": the stop belongs to the word before it
    text = re.sub(
        r"(?<=[A-Za-z])[ \t]+\.(?=([A-Za-z']+))",
        lambda m: "." if m.group(1).lower() in COMMON_WORD_RANK else m.group(0),
        text,
    )

    def fix_token(m: "re.Match") -> str:
        tok = m.group(0)
        if re.search(r"[/\\@_=&#]|www\.|\d", tok):
            return tok  # URL, path, e-mail, number: leave exactly as typed
        tok = re.sub(r"([,;!?])(?=[A-Za-z])", r"\1 ", tok)

        def split_stop(d: "re.Match") -> str:
            left, right = d.group(1), d.group(2)
            r_low = right.lower()
            if r_low in _FILE_ENDINGS:
                return d.group(0)
            if (len(right) >= 2 or r_low == "i") and r_low in COMMON_WORD_RANK:
                return f"{left}. {right}"
            return d.group(0)

        return re.sub(r"([A-Za-z']{2,})\.([A-Za-z']+)", split_stop, tok)

    return re.sub(r"\S+", fix_token, text)



@dataclass
class GrammarFix:
    original: str
    replacement: str
    reason: str
    category: str  # "homophone", "spelling", "speech_cleanup", "grammar", "punctuation"


class LocalDyslexiaGrammarEngine:
    def __init__(self, typo_fixer: Optional[SmartTypoFixer] = None) -> None:
        # General wrong/missing/extra/swapped-letter fixer (Windows spell checker
        # + keyboard-aware ranking). Falls back to the static map when unavailable.
        self.typo_fixer: SmartTypoFixer = typo_fixer or SmartTypoFixer()
        self.rules_enabled: Dict[str, bool] = {
            "homophones": True,
            "dyslexia_spelling": True,
            "smart_typos": True,
            "speech_cleanup": True,
            "grammar_structure": True,
            "auto_punctuation": True,
            "clarity_conciseness": True,
            "sentence_model": True,
        }
        # Writing tone: "clear" (default), "formal" (expands contractions), "casual", "concise"
        self.writing_tone: str = "clear"

        # Comprehensive Dyslexia Reversal, Transposition & Phonetic Spelling Map
        self.spelling_map: Dict[str, Tuple[str, str]] = {
            # Common reversals & transpositions
            "teh": ("the", "Letter reversal fix (teh → the)"),
            "hte": ("the", "Letter reversal fix (hte → the)"),
            "adn": ("and", "Letter transposition fix (adn → and)"),
            "nad": ("and", "Letter transposition fix (nad → and)"),
            "taht": ("that", "Letter transposition fix (taht → that)"),
            "thta": ("that", "Letter transposition fix (thta → that)"),
            "wiht": ("with", "Letter transposition fix (wiht → with)"),
            "wtih": ("with", "Letter transposition fix (wtih → with)"),
            "baout": ("about", "Letter reversal fix (baout → about)"),
            "abuot": ("about", "Letter transposition fix (abuot → about)"),
            "becuase": ("because", "Vowel order fix (becuase → because)"),
            "beacuse": ("because", "Letter order fix (beacuse → because)"),
            "becasue": ("because", "Letter order fix (becasue → because)"),
            "freind": ("friend", "i-before-e order in friend"),
            "freinds": ("friends", "i-before-e order in friends"),
            "wierd": ("weird", "e-i exception in weird"),
            "thier": ("their", "e-i order in their"),
            "thiers": ("theirs", "e-i order in theirs"),
            "recieve": ("receive", "c-e-i rule in receive"),
            "recieved": ("received", "c-e-i rule in received"),
            "recieving": ("receiving", "c-e-i rule in receiving"),
            "beleive": ("believe", "i-before-e in believe"),
            "beleived": ("believed", "i-before-e in believed"),
            "acheive": ("achieve", "i-before-e in achieve"),
            "acheived": ("achieved", "i-before-e in achieved"),
            "peice": ("piece", "i-before-e in piece (pie)"),
            "cheif": ("chief", "i-before-e in chief"),
            "feild": ("field", "i-before-e in field"),
            "yeild": ("yield", "i-before-e in yield"),
            "nieghbor": ("neighbor", "e-i-g-h in neighbor"),
            "foriegn": ("foreign", "e-i in foreign"),
            "hieght": ("height", "e-i in height"),
            # Keyboard / dyslexic motor slips
            "jsut": ("just", "Transposition fix (jsut → just)"),
            "juts": ("just", "Transposition fix (juts → just)"),
            "knwo": ("know", "Transposition fix (knwo → know)"),
            "konw": ("know", "Transposition fix (konw → know)"),
            "woudl": ("would", "l-d transposition fix (would)"),
            "shoudl": ("should", "l-d transposition fix (should)"),
            "coudl": ("could", "l-d transposition fix (could)"),
            "thign": ("thing", "n-g transposition fix (thing)"),
            "thigns": ("things", "n-g transposition fix (things)"),
            "peopel": ("people", "l-e transposition fix (people)"),
            "poeple": ("people", "o-e transposition fix (people)"),
            "whcih": ("which", "c-h transposition fix (which)"),
            "wich": ("which", "Missing 'h' in which"),
            "waht": ("what", "a-h transposition fix (what)"),
            "whta": ("what", "h-t-a transposition fix (what)"),
            "ahve": ("have", "a-h transposition fix (have)"),
            "hvae": ("have", "v-a transposition fix (have)"),
            "frome": ("from", "Extra 'e' removed (from)"),
            "fomr": ("from", "r-m transposition fix (from)"),
            "tihs": ("this", "i-h transposition fix (this)"),
            "thsi": ("this", "s-i transposition fix (this)"),
            "htis": ("this", "h-t transposition fix (this)"),
            "thisd": ("this", "Stray key fix (thisd → this)"),
            "isd": ("is", "Stray key fix (isd → is)"),
            "makje": ("make", "Stray key fix (makje → make)"),
            "witten": ("written", "Missing 'r' in written"),
            "writen": ("written", "Double 't' in written"),
            "writend": ("written", "Phonetic suffix fix (writend → written)"),
            "abouve": ("above", "Vowel fix (abouve → above)"),
            "worlks": ("works", "Stray key fix (worlks → works)"),
            "workl": ("work", "Stray key fix (workl → work)"),
            "dosne": ("doesn't", "Transposition fix (dosne → doesn't)"),
            "dosent": ("doesn't", "Spelling fix (dosent → doesn't)"),
            "doesnt": ("doesn't", "Missing apostrophe in doesn't"),
            "dont": ("don't", "Missing apostrophe in don't"),
            "cant": ("can't", "Missing apostrophe in can't"),
            "wont": ("won't", "Missing apostrophe in won't"),
            "didnt": ("didn't", "Missing apostrophe in didn't"),
            "isnt": ("isn't", "Missing apostrophe in isn't"),
            "arent": ("aren't", "Missing apostrophe in aren't"),
            "wasnt": ("wasn't", "Missing apostrophe in wasn't"),
            "werent": ("weren't", "Missing apostrophe in weren't"),
            "impliment": ("implement", "Spelled im-ple-ment (with an 'e')"),
            "implimented": ("implemented", "Spelled im-ple-mented (with an 'e')"),
            "implimenting": ("implementing", "Spelled im-ple-menting (with an 'e')"),
            "improvment": ("improvement", "Keep 'e' in improve-ment"),
            "improvments": ("improvements", "Keep 'e' in improve-ments"),
            "preform": ("perform", "r-e transposition fix (preform → perform)"),
            "preformed": ("performed", "r-e transposition fix (preformed → performed)"),
            "preforming": ("performing", "r-e transposition fix (preforming → performing)"),
            "performence": ("performance", "Ends with -ance (performance)"),
            "charachter": ("character", "No 'h' after second 'c' (character)"),
            "charachters": ("characters", "No 'h' after second 'c' (characters)"),
            "wya": ("way", "a-y transposition fix (wya → way)"),
            "kee": ("keep", "Missing 'p' in keep (kee → keep)"),
            "improveing": ("improving", "Drop silent 'e' before -ing (improving)"),
            "makeing": ("making", "Drop silent 'e' before -ing (making)"),
            "takeing": ("taking", "Drop silent 'e' before -ing (taking)"),
            "writeing": ("writing", "Drop silent 'e' before -ing (writing)"),
            "useing": ("using", "Drop silent 'e' before -ing (using)"),
            "comeing": ("coming", "Drop silent 'e' before -ing (coming)"),
            "haveing": ("having", "Drop silent 'e' before -ing (having)"),
            "giveing": ("giving", "Drop silent 'e' before -ing (giving)"),
            "stule": ("style", "u-y neighbor key fix (stule → style)"),
            "thats": ("that's", "Missing apostrophe in that's"),
            "whats": ("what's", "Missing apostrophe in what's"),
            "heres": ("here's", "Missing apostrophe in here's"),
            "theres": ("there's", "Missing apostrophe in there's"),
            "stegostaurus": ("Stegosaurus", "Spelling fix (Stegosaurus)"),
            "peridactyl": ("Pterodactyl", "Silent 'P' in Pterodactyl"),
            "terodactyl": ("Pterodactyl", "Silent 'P' in Pterodactyl"),
            "pteradactyl": ("Pterodactyl", "Spelled Pter-o-dactyl"),
            # Phonetic & vowel-confusion words
            "seperate": ("separate", "Spelled sep-a-rate (with an 'a')"),
            "seperated": ("separated", "Spelled sep-a-rated (with an 'a')"),
            "definately": ("definitely", "Root word 'finite' (definitely)"),
            "definatly": ("definitely", "Spelled def-i-nite-ly"),
            "definetly": ("definitely", "Spelled def-i-nite-ly"),
            "probaly": ("probably", "Includes both 'b's (prob-ab-ly)"),
            "probly": ("probably", "Full spelling: probably"),
            "basicly": ("basically", "Ends with -ally (basically)"),
            "actully": ("actually", "Includes 'a' (act-u-ally)"),
            "actualy": ("actually", "Double 'l' in actually"),
            "especally": ("especially", "Includes 'i' (especially)"),
            "especialy": ("especially", "Double 'l' in especially"),
            "usally": ("usually", "Includes second 'u' (u-su-ally)"),
            "usualy": ("usually", "Double 'l' in usually"),
            "finaly": ("finally", "Double 'l' in finally"),
            "realy": ("really", "Double 'l' in really"),
            "untill": ("until", "Single 'l' at end of until"),
            "alot": ("a lot", "Two separate words (a lot)"),
            "occured": ("occurred", "Double 'c' and double 'r'"),
            "occuring": ("occurring", "Double 'c' and double 'r'"),
            "occassion": ("occasion", "Double 'c', single 's'"),
            "accomodate": ("accommodate", "Double 'c' and double 'm'"),
            "neccessary": ("necessary", "One 'c', two 's's (necessary)"),
            "necesary": ("necessary", "One 'c', two 's's (necessary)"),
            "enviroment": ("environment", "Silent 'n' before 'm'"),
            "goverment": ("government", "Silent 'n' before 'm'"),
            "tommorow": ("tomorrow", "One 'm', double 'r' (tomorrow)"),
            "tomorow": ("tomorrow", "One 'm', double 'r' (tomorrow)"),
            "begining": ("beginning", "Double 'n' in beginning"),
            "buisness": ("business", "Spelled bus-i-ness"),
            "calender": ("calendar", "Ends with -ar (calendar)"),
            "collegue": ("colleague", "Spelled col-league"),
            "concious": ("conscious", "Spelled con-scious"),
            "embarass": ("embarrass", "Double 'r' and double 's'"),
            "existance": ("existence", "Ends with -ence"),
            "fourty": ("forty", "No 'u' in forty"),
            "grammer": ("grammar", "Ends with -ar (grammar)"),
            "immediatly": ("immediately", "Keep 'e' before -ly"),
            "independant": ("independent", "Ends with -ent"),
            "knowlege": ("knowledge", "Includes 'd' (knowledge)"),
            "maintainance": ("maintenance", "Spelled main-ten-ance"),
            "noticable": ("noticeable", "Keep 'e' in noticeable"),
            "persistant": ("persistent", "Ends with -ent"),
            "posession": ("possession", "Double 's' twice"),
            "prefered": ("preferred", "Double 'r' in preferred"),
            "priviledge": ("privilege", "No 'd' in privilege"),
            "pronounciation": ("pronunciation", "Spelled pro-nun-ciation"),
            "recomend": ("recommend", "Single 'c', double 'm'"),
            "relevent": ("relevant", "Ends with -ant (relevant)"),
            "succesful": ("successful", "Double 'c', double 's', single 'l'"),
            "sucess": ("success", "Double 'c', double 's'"),
            "suprise": ("surprise", "First 'r' in surprise (sur-prise)"),
            "tendancy": ("tendency", "Ends with -ency"),
            "therefor": ("therefore", "Ends with silent 'e'"),
            "truely": ("truly", "Drop 'e' in truly"),
            "unfortunatly": ("unfortunately", "Keep 'e' before -ly"),
            "diffrent": ("different", "Includes 'e' (dif-fer-ent)"),
            "intresting": ("interesting", "Includes 'e' (in-ter-est-ing)"),
            "restaraunt": ("restaurant", "Spelled res-tau-rant"),
            "gaurantee": ("guarantee", "g-u-a in guarantee"),
            "rythm": ("rhythm", "r-h-y-t-h-m spelling"),
        }

        # Regular "-ed" endings put on irregular verbs ("payed" -> "paid"). These
        # are listed because the nearest dictionary word is usually a different
        # verb altogether ("payed" is one letter from "played").
        for wrong, right in {
            "payed": "paid", "layed": "laid", "catched": "caught",
            "buyed": "bought", "teached": "taught", "runned": "ran",
            "thinked": "thought", "writed": "wrote", "taked": "took",
            "comed": "came", "maked": "made", "gived": "gave", "finded": "found",
            "telled": "told", "sayed": "said", "knowed": "knew",
            "bringed": "brought", "choosed": "chose", "drived": "drove",
            "eated": "ate", "falled": "fell", "feeled": "felt", "getted": "got",
            "goed": "went", "heared": "heard", "holded": "held", "keeped": "kept",
            "losed": "lost", "meaned": "meant", "meeted": "met", "readed": "read",
            "selled": "sold", "sended": "sent", "sitted": "sat",
            "sleeped": "slept", "speaked": "spoke", "spended": "spent",
            "standed": "stood", "swimmed": "swam", "throwed": "threw",
            "understanded": "understood", "weared": "wore", "winned": "won",
            "builded": "built", "drawed": "drew", "growed": "grew",
            "hurted": "hurt", "cutted": "cut", "hitted": "hit", "shutted": "shut",
            "brang": "brought", "brung": "brought", "boughten": "bought",
        }.items():
            self.spelling_map[wrong] = (right, f"Irregular verb: '{right}', not '{wrong}'")

        # Context-Aware Homophone & Grammar Disambiguation Patterns
        self.contextual_patterns = [
            # 1. Modal + "of" -> "have" ("could of", "would of", "should of", "must of", "might of")
            (
                re.compile(r"\b(could|would|should|must|might)\s+of\b", re.IGNORECASE),
                lambda m: f"{m.group(1)} have",
                "Use 'have' instead of 'of' after modal verbs",
                "homophone",
            ),
            # 2. "their" / "there" -> "they're" before progressive verbs, adjectives, or adverbs
            (
                re.compile(
                    r"\b(their|there)\s+(going|coming|trying|working|looking|making|doing|saying|thinking|running|walking|waiting|building|writing|testing|playing|starting|getting|having|being|ready|happy|excited|great|good|bad|here|not|always|never|still|just|really|very|so|too|about|able|all|both|almost|already)\b",
                    re.IGNORECASE,
                ),
                lambda m: ("They're" if m.group(1)[0].isupper() else "they're")
                + " "
                + m.group(2),
                "Use \"they're\" (they are) before an action or description",
                "homophone",
            ),
            # 3. "their" -> "there" before "is", "are", "was", "were", "will be", "has been"
            (
                re.compile(
                    r"\b(their|they're)\s+(is|are|was|were|isn't|aren't|wasn't|weren't)\b",
                    re.IGNORECASE,
                ),
                lambda m: ("There" if m.group(1)[0].isupper() else "there")
                + " "
                + m.group(2),
                "Use \"there\" for existence ('there is / there are')",
                "homophone",
            ),
            # 4. "over their" / "over they're" -> "over there"
            (
                re.compile(
                    r"\b(over|right|out|up|down|back|in)\s+(their|they're)\b(?!\s+\w+(?:s|ed|ing)\b)",
                    re.IGNORECASE,
                ),
                lambda m: f"{m.group(1)} there",
                "Use \"there\" to refer to a place or location",
                "homophone",
            ),
            # 5. "there" / "they're" -> "their" before clear possessed nouns (with optional adjective)
            (
                re.compile(
                    r"\b(there|they're)\s+((?:(?:new|old|big|small|best|first|last|next|own|favorite|great|good|main|whole|entire|current|latest|final)\s+)?(?:house|home|car|dog|cat|work|idea|ideas|team|project|computer|screen|book|name|names|friends|family|own|way|time|life|job|school|room|hand|hands|head|eyes|voice|parents|kids|children|money|phone|app|code|test|tests|goal))\b",
                    re.IGNORECASE,
                ),
                lambda m: ("Their" if m.group(1)[0].isupper() else "their")
                + " "
                + m.group(2),
                "Use \"their\" to show ownership/possession",
                "homophone",
            ),
            # 6. "your" -> "you're" before progressive verbs or predicates
            (
                re.compile(
                    r"\b(your)\s+(going|coming|welcome|right|wrong|ready|invited|doing|making|looking|working|trying|talking|speaking|writing|running|building|testing|awesome|great|amazing|here|there|not|always|never|still|just|so|very|really|able|sure|done|finished|late|early)\b",
                    re.IGNORECASE,
                ),
                lambda m: ("You're" if m.group(1)[0].isupper() else "you're")
                + " "
                + m.group(2),
                "Use \"you're\" (you are) before an action or state",
                "homophone",
            ),
            # 7. "you're" -> "your" before possessed nouns (with optional adjective)
            (
                re.compile(
                    r"\b(you're)\s+((?:(?:new|old|big|small|best|first|last|next|own|favorite|great|good|main|whole|entire|current|latest|final)\s+)?(?:house|home|car|dog|cat|work|idea|ideas|team|project|computer|screen|book|name|friends|family|own|way|time|life|job|school|room|hand|hands|head|eyes|voice|turn|fault|best|phone|app|code|mind|help))\b",
                    re.IGNORECASE,
                ),
                lambda m: ("Your" if m.group(1)[0].isupper() else "your")
                + " "
                + m.group(2),
                "Use \"your\" to show ownership",
                "homophone",
            ),
            # 8. "its" vs "it's"
            (
                re.compile(
                    r"\b(its)\s+(a|an|the|going|coming|working|looking|making|getting|been|not|really|very|so|too|just|always|never|still|great|good|bad|hard|easy|time|all|about|okay|fine|ready|done|over)\b",
                    re.IGNORECASE,
                ),
                lambda m: ("It's" if m.group(1)[0].isupper() else "it's")
                + " "
                + m.group(2),
                "Use \"it's\" (it is / it has) here",
                "homophone",
            ),
            (
                re.compile(
                    r"\b(it's)\s+(own|tail|head|eyes|mouth|body|color|size|name|place|way|best|side|top|bottom)\b",
                    re.IGNORECASE,
                ),
                lambda m: ("Its" if m.group(1)[0].isupper() else "its")
                + " "
                + m.group(2),
                "Use \"its\" (no apostrophe) for possession",
                "homophone",
            ),
            # 9. "to" -> "too" before degree adjectives/adverbs
            (
                re.compile(
                    r"\b(to)\s+(much|many|fast|slow|hard|easy|late|early|big|small|long|short|far|close|high|low|loud|quiet|hot|cold|good|bad|tired|busy|expensive|heavy|dark|bright|soon|often)\b(?!\s+to\b)",
                    re.IGNORECASE,
                ),
                lambda m: ("Too" if m.group(1)[0].isupper() else "too")
                + " "
                + m.group(2),
                "Use \"too\" to mean 'excessively' or 'also'",
                "homophone",
            ),
            (
                re.compile(r"\b(me|you|us|them)\s+to\s*([.!?]|$)", re.IGNORECASE),
                lambda m: f"{m.group(1)} too{m.group(2)}",
                "Use \"too\" to mean 'also' at the end of a phrase",
                "homophone",
            ),
            # 10. "to" / "too" -> "two" before plural countable nouns
            (
                re.compile(
                    r"\b(to|too)\s+(days|weeks|months|years|hours|minutes|seconds|times|people|things|ways|options|models|dinosaurs|monsters|dogs|cats|cars|books|hands|eyes|words|sentences|pages|points|steps)\b",
                    re.IGNORECASE,
                ),
                lambda m: ("Two" if m.group(1)[0].isupper() else "two")
                + " "
                + m.group(2),
                "Use \"two\" for the number 2",
                "homophone",
            ),
            # 11. Comparative + "then" -> "than"
            (
                re.compile(
                    r"\b(better|worse|more|less|faster|slower|bigger|smaller|higher|lower|older|younger|easier|harder|stronger|weaker|closer|further|farther|rather|other|different|larger|shorter|longer|smarter)\s+then\b",
                    re.IGNORECASE,
                ),
                lambda m: f"{m.group(1)} than",
                "Use \"than\" for comparisons ('then' is for time)",
                "homophone",
            ),
            # 12. "loose" -> "lose" as a verb
            (
                re.compile(
                    r"\b(to|will|would|can|could|don't|didn't|won't|never|might|not|gonna|going to)\s+loose\b",
                    re.IGNORECASE,
                ),
                lambda m: f"{m.group(1)} lose",
                "Use \"lose\" for the verb ('loose' means not tight)",
                "homophone",
            ),
            # 13. "affect" -> "effect" as a noun
            (
                re.compile(
                    r"\b(an|the|big|huge|major|positive|negative|side|no|any|good|bad)\s+affect\b",
                    re.IGNORECASE,
                ),
                lambda m: f"{m.group(1)} effect",
                "Use \"effect\" as a noun (the result)",
                "homophone",
            ),
            # 14. "weather" -> "whether" in conditional clauses
            (
                re.compile(
                    r"\b(weather)\s+(or\s+not|we|you|they|I|he|she|it|this|that|to)\b",
                    re.IGNORECASE,
                ),
                lambda m: ("Whether" if m.group(1)[0].isupper() else "whether")
                + " "
                + m.group(2),
                "Use \"whether\" for choices or possibilities",
                "homophone",
            ),
            # 15. "aloud" vs "allowed"
            (
                re.compile(
                    r"\b(read|reading|speak|speaking|say|saying|said|laugh|laughed|think|thinking|out)\s+allowed\b",
                    re.IGNORECASE,
                ),
                lambda m: f"{m.group(1)} aloud",
                "Use \"aloud\" to mean 'out loud / audibly'",
                "homophone",
            ),
            (
                re.compile(
                    r"\b(not|is|are|was|were|be|been|aren't|isn't)\s+aloud\s+to\b",
                    re.IGNORECASE,
                ),
                lambda m: f"{m.group(1)} allowed to",
                "Use \"allowed\" to mean 'permitted'",
                "homophone",
            ),
            # 16. "passed" -> "past" as a preposition/noun
            (
                re.compile(
                    r"\b(in\s+the|walked|walking|drove|driving|ran|running|went|going|flew|right)\s+passed\b",
                    re.IGNORECASE,
                ),
                lambda m: f"{m.group(1)} past",
                "Use \"past\" for time before now or movement by something",
                "homophone",
            ),
            # 17. "peace" vs "piece"
            (
                re.compile(
                    r"\b(a|one|another|every|each|that|this)\s+peace\s+of\b",
                    re.IGNORECASE,
                ),
                lambda m: f"{m.group(1)} piece of",
                "Use \"piece\" for a part or portion of something",
                "homophone",
            ),
            # 18. "who's" vs "whose"
            (
                re.compile(
                    r"\b(who's)\s+(turn|idea|house|car|book|fault|name|phone|team|job|work|dog|cat)\b",
                    re.IGNORECASE,
                ),
                lambda m: ("Whose" if m.group(1)[0].isupper() else "whose")
                + " "
                + m.group(2),
                "Use \"whose\" to show ownership",
                "homophone",
            ),
            # 19. "were" -> "we're" before progressive verbs
            (
                re.compile(
                    r"\b(were)\s+(going\s+to|trying\s+to|working\s+on|looking\s+for|building|making|doing|ready\s+to|happy\s+to|able\s+to|here\s+to)\b",
                    re.IGNORECASE,
                ),
                lambda m: ("We're" if m.group(1)[0].isupper() else "we're")
                + " "
                + m.group(2),
                "Use \"we're\" (we are) here",
                "homophone",
            ),
            # 20. Split words & phrases commonly merged or confused in fast typing
            (
                re.compile(r"\bproto\s+type\b", re.IGNORECASE),
                lambda m: "Prototype" if m.group(0)[0].isupper() else "prototype",
                "Combined compound word 'prototype'",
                "spelling",
            ),
            (
                re.compile(r"\blife\s+like\b", re.IGNORECASE),
                lambda m: "Lifelike" if m.group(0)[0].isupper() else "lifelike",
                "Combined compound word 'lifelike'",
                "spelling",
            ),
            (
                re.compile(r"\bpoint\s+a\s+to\s+(?:be|b)\b", re.IGNORECASE),
                lambda m: "point A to B",
                "Idiom 'point A to B'",
                "homophone",
            ),
            (
                re.compile(r"\bmaker\s+(it|them|this|that|sure)\b", re.IGNORECASE),
                lambda m: ("Make" if m.group(0)[0].isupper() else "make")
                + " "
                + m.group(1),
                "Use verb 'make' instead of 'maker'",
                "spelling",
            ),
            # 20b. Real words used in place of another real word (a spell checker
            #      can't see these, so each needs a context that makes it certain)
            (
                re.compile(
                    r"\b(too)\s+(the|a|an|my|your|his|her|our|their|be|go|do|see|get|make|have)\b",
                    re.IGNORECASE,
                ),
                lambda m: _keep_case(m.group(1), "to") + " " + m.group(2),
                "Use \"to\" here ('too' means 'also' or 'excessively')",
                "homophone",
            ),
            (
                re.compile(
                    r"\b(don't|didn't|doesn't|do not|did not|does not)\s+no\b"
                    r"(?!\s+(?:one|body|more|longer|good|harm|way|idea|matter)\b)",
                    re.IGNORECASE,
                ),
                lambda m: f"{m.group(1)} know",
                "Use \"know\" (to understand), not \"no\"",
                "homophone",
            ),
            (
                re.compile(
                    r"\b(I|you|we|they|to|should|would|could|might|must|will|never|already)"
                    r"\s+no\s+(if|what|how|why|when|where|who|that|about|whether|anything|nothing|something)\b",
                    re.IGNORECASE,
                ),
                lambda m: f"{m.group(1)} know {m.group(2)}",
                "Use \"know\" (to understand), not \"no\"",
                "homophone",
            ),
            (
                re.compile(
                    r"\b(was|is|are|were|came|come|comes|coming|got|get|went|go|going|back|away|far|"
                    r"apart|different|message|email|letter|call|heard|hear|made|taken|took|received|"
                    r"sent|home|\w+ed)\s+form\s+"
                    r"(the|my|your|his|her|our|their|here|there|me|him|them|us|now|then|home|work|school)\b",
                    re.IGNORECASE,
                ),
                lambda m: f"{m.group(1)} from {m.group(2)}",
                "Swapped letters: 'from', not 'form'",
                "spelling",
            ),
            (
                re.compile(
                    r"\b(to|can|could|will|would|should|must|might|gonna|didn't|don't|can't|won't|"
                    r"I'll|we'll|you'll|they'll)\s+by\s+"
                    r"(some|a|an|the|it|them|this|that|more|new|me|you|us|him|her|one|two|my|your|our)\b",
                    re.IGNORECASE,
                ),
                lambda m: f"{m.group(1)} buy {m.group(2)}",
                "Use \"buy\" (to purchase), not \"by\"",
                "homophone",
            ),
            (
                re.compile(
                    r"\b(and|go|went|going)\s+by\s+(some|more)\b"
                    r"(?!\s+(?:miracle|chance|means|way|measure|margin|accounts?|estimates?)\b)",
                    re.IGNORECASE,
                ),
                lambda m: f"{m.group(1)} buy {m.group(2)}",
                "Use \"buy\" (to purchase), not \"by\"",
                "homophone",
            ),
            (
                re.compile(
                    r"\b(didn't|don't|doesn't|won't|can't|wouldn't|couldn't|shouldn't)\s+of\b",
                    re.IGNORECASE,
                ),
                lambda m: f"{m.group(1)} have",
                "Use 'have', not 'of'",
                "homophone",
            ),
            # 20b-2. Two little words typed in the wrong order
            (
                re.compile(
                    r"\b(go|going|goes|went|come|coming|came|get|got|back|walk|walked|"
                    r"drive|drove|run|ran|move|moved|head|headed)\s+(the|a|my|your|our)\s+to\b",
                    re.IGNORECASE,
                ),
                lambda m: f"{m.group(1)} to {m.group(2)}",
                "Word order: 'to the', not 'the to'",
                "grammar",
            ),
            (
                re.compile(r"\b(the|a)\s+of\s+(?=[a-z])", re.IGNORECASE),
                lambda m: "of " + m.group(1).lower() + " ",
                "Word order: 'of the', not 'the of'",
                "grammar",
            ),
            # 20c. Verb forms
            (
                re.compile(
                    r"((?:\bhave|\bhas|\bhad|\bhaving|'ve))\s+(" + "|".join(_PARTICIPLES) + r")\b",
                    re.IGNORECASE,
                ),
                lambda m: f"{m.group(1)} {_PARTICIPLES[m.group(2).lower()]}",
                "After have/has/had use the past participle",
                "grammar",
            ),
            (
                re.compile(r"(?:(\S+)\s+)?\b(I|we|they|you|he|she)\s+seen\b", re.IGNORECASE),
                lambda m: _guarded(m, _PERFECT_LEADS, f"{m.group(2)} saw"),
                "Use \"saw\" (or \"have seen\")",
                "grammar",
            ),
            (
                re.compile(r"(?:(\S+)\s+)?\bI\s+(has|is)\b"),
                lambda m: _guarded(
                    m, {"letter", "the", "numeral"},
                    "I have" if m.group(2) == "has" else "I am",
                ),
                "Use \"I have\" / \"I am\"",
                "grammar",
            ),
            (
                re.compile(r"(?:(\S+)\s+)?\b(they|we|you)\s+(is|has)\b", re.IGNORECASE),
                lambda m: _guarded(
                    m, {"of"},
                    f"{m.group(2)} " + ("are" if m.group(3).lower() == "is" else "have"),
                ),
                "Use \"are\" / \"have\" with we, they and you",
                "grammar",
            ),
            (
                re.compile(r"(?:(\S+)\s+)?\b(he|she|it)\s+have\b", re.IGNORECASE),
                lambda m: _guarded(m, _BARE_VERB_LEADS, f"{m.group(2)} has"),
                "Use \"has\" with he, she and it",
                "grammar",
            ),
            # 21. Subject-verb agreement
            (
                re.compile(r"\b(we|they|you)\s+was\b", re.IGNORECASE),
                lambda m: f"{m.group(1)} were",
                "Use \"were\" with we, they, and you",
                "grammar",
            ),
            (
                re.compile(r"\b(he|she|it)\s+don't\b", re.IGNORECASE),
                lambda m: f"{m.group(1)} doesn't",
                "Use \"doesn't\" with he, she, and it",
                "grammar",
            ),
            # 22. Article 'a' vs 'an' before clear vowel sounds
            (
                re.compile(
                    r"\b(a)\s+(apple|idea|example|option|hour|honest|issue|error|event|elephant|orange|umbrella|assistant|avatar|animation|area|old|awesome|amazing|important|interesting|easy|update|upgrade|overhaul)\b",
                    re.IGNORECASE,
                ),
                lambda m: ("An" if m.group(1)[0].isupper() else "an")
                + " "
                + m.group(2),
                "Use \"an\" before words starting with a vowel sound",
                "grammar",
            ),
            # 22b. General a / an by the sound of the next word
            (
                re.compile(r"\b(a)\s+([aeiou][a-z]+)\b", re.IGNORECASE),
                lambda m: m.group(0)
                if _A_KEEP.match(m.group(2))
                else _keep_case(m.group(1), "an") + " " + m.group(2),
                "Use \"an\" before a vowel sound",
                "grammar",
            ),
            (
                re.compile(r"\b(a)\s+(hour|hours|honest|honestly|honor|honour|heir)\b", re.IGNORECASE),
                lambda m: _keep_case(m.group(1), "an") + " " + m.group(2),
                "Use \"an\" before a silent 'h'",
                "grammar",
            ),
            (
                re.compile(r"\b(an)\s+([b-df-hj-np-tv-z][a-z]+)\b", re.IGNORECASE),
                lambda m: m.group(0)
                if (m.group(2).isupper() or _AN_KEEP.match(m.group(2)))
                else _keep_case(m.group(1), "a") + " " + m.group(2),
                "Use \"a\" before a consonant sound",
                "grammar",
            ),
            # 23. Grammarly Pillar 2: Clarity & Conciseness (Wordy phrase simplification)
            (
                re.compile(r"\bin\s+order\s+to\b", re.IGNORECASE),
                lambda m: "To" if m.group(0)[0].isupper() else "to",
                "Clarity: 'to' is more concise than 'in order to'",
                "clarity",
            ),
            (
                re.compile(r"\b(?:due\s+to|because\s+of)\s+the\s+fact\s+that\b", re.IGNORECASE),
                lambda m: "Because" if m.group(0)[0].isupper() else "because",
                "Clarity: 'because' is clearer than 'due to the fact that'",
                "clarity",
            ),
            (
                re.compile(r"\bat\s+this\s+point\s+in\s+time\b", re.IGNORECASE),
                lambda m: "Now" if m.group(0)[0].isupper() else "now",
                "Clarity: 'now' is more direct than 'at this point in time'",
                "clarity",
            ),
            (
                re.compile(r"\bin\s+the\s+event\s+that\b", re.IGNORECASE),
                lambda m: "If" if m.group(0)[0].isupper() else "if",
                "Clarity: 'if' is more concise than 'in the event that'",
                "clarity",
            ),
            (
                re.compile(r"\bfor\s+the\s+purpose\s+of\b", re.IGNORECASE),
                lambda m: "For" if m.group(0)[0].isupper() else "for",
                "Clarity: 'for' is more concise than 'for the purpose of'",
                "clarity",
            ),
            (
                re.compile(r"\bhas\s+the\s+ability\s+to\b", re.IGNORECASE),
                lambda m: "Can" if m.group(0)[0].isupper() else "can",
                "Clarity: 'can' is stronger than 'has the ability to'",
                "clarity",
            ),
            (
                re.compile(r"\bon\s+a\s+daily\s+basis\b", re.IGNORECASE),
                lambda m: "Daily" if m.group(0)[0].isupper() else "daily",
                "Clarity: 'daily' is more concise than 'on a daily basis'",
                "clarity",
            ),
            (
                re.compile(r"\bin\s+close\s+proximity\s+to\b", re.IGNORECASE),
                lambda m: "Near" if m.group(0)[0].isupper() else "near",
                "Clarity: 'near' is more concise than 'in close proximity to'",
                "clarity",
            ),
            (
                re.compile(r"\bpast\s+history\b", re.IGNORECASE),
                lambda m: "History" if m.group(0)[0].isupper() else "history",
                "Clarity: remove redundant modifier 'past'",
                "clarity",
            ),
            (
                re.compile(r"\bend\s+result\b", re.IGNORECASE),
                lambda m: "Result" if m.group(0)[0].isupper() else "result",
                "Clarity: remove redundant modifier 'end'",
                "clarity",
            ),
        ]

        # Grammarly Interactive Recommendations (Engagement, Vocabulary & Style Upgrades)
        self.recommendation_patterns = [
            (
                re.compile(r"\b(really|very)\s+good\b", re.IGNORECASE),
                lambda m: "Excellent" if m.group(0)[0].isupper() else "excellent",
                "Engagement: Use a stronger, more vivid adjective",
                "Engagement",
            ),
            (
                re.compile(r"\b(really|very)\s+bad\b", re.IGNORECASE),
                lambda m: "Terrible" if m.group(0)[0].isupper() else "terrible",
                "Engagement: Use a more impactful word",
                "Engagement",
            ),
            (
                re.compile(r"\b(really|very)\s+important\b", re.IGNORECASE),
                lambda m: "Crucial" if m.group(0)[0].isupper() else "crucial",
                "Engagement: 'crucial' carries stronger authority",
                "Engagement",
            ),
            (
                re.compile(r"\b(really|very)\s+big\b", re.IGNORECASE),
                lambda m: "Massive" if m.group(0)[0].isupper() else "massive",
                "Engagement: Replace vague intensifier with 'massive'",
                "Engagement",
            ),
            (
                re.compile(r"\b(really|very)\s+fast\b", re.IGNORECASE),
                lambda m: "Rapid" if m.group(0)[0].isupper() else "rapid",
                "Engagement: 'rapid' is crisper than 'very fast'",
                "Engagement",
            ),
            (
                re.compile(r"\ba\s+lot\s+of\b", re.IGNORECASE),
                lambda m: "Numerous" if m.group(0)[0].isupper() else "numerous",
                "Delivery: 'numerous' sounds more polished than 'a lot of'",
                "Delivery",
            ),
            (
                re.compile(r"\bmake\s+it\s+better\b", re.IGNORECASE),
                lambda m: "Enhance it" if m.group(0)[0].isupper() else "enhance it",
                "Clarity: Stronger action verb",
                "Clarity",
            ),
            (
                re.compile(r"\bkind\s+of\s+struggling\b", re.IGNORECASE),
                lambda m: "Struggling" if m.group(0)[0].isupper() else "struggling",
                "Delivery: Remove hedge phrase 'kind of' for confident tone",
                "Delivery",
            ),
            (
                re.compile(r"\bi\s+think\s+that\s+we\s+should\s+probably\b", re.IGNORECASE),
                lambda m: "We should",
                "Delivery: Sound more confident by cutting 'I think that... probably'",
                "Delivery",
            ),
        ]
        self.sound_alike_map: Dict[str, List[str]] = self._build_sound_alike_map()
        self.word_upgrade_map: Dict[str, List[str]] = self._build_word_upgrade_map()
        self.hedging_words: set[str] = {
            "basically",
            "actually",
            "literally",
            "honestly",
            "just",
            "maybe",
            "perhaps",
            "simply",
            "somehow",
            "virtually",
        }

    def _build_sound_alike_map(self) -> Dict[str, List[str]]:
        """
        Groups of phonetic sound-alikes / homophones / near-homophones where
        voice transcription might pick one word when the speaker meant another.
        """
        groups = [
            ["their", "there", "they're"],
            ["your", "you're", "yore"],
            ["to", "too", "two"],
            ["its", "it's"],
            ["then", "than"],
            ["affect", "effect"],
            ["accept", "except"],
            ["weather", "whether"],
            ["lose", "loose"],
            ["passed", "past"],
            ["aloud", "allowed"],
            ["piece", "peace"],
            ["break", "brake"],
            ["sight", "site", "cite"],
            ["right", "write", "rite"],
            ["new", "knew"],
            ["no", "know"],
            ["role", "roll"],
            ["lead", "led"],
            ["principal", "principle"],
            ["complement", "compliment"],
            ["discrete", "discreet"],
            ["ensure", "insure", "assure"],
            ["adapt", "adopt", "adept"],
            ["farther", "further"],
            ["allusion", "illusion"],
            ["stationary", "stationery"],
            ["council", "counsel"],
            ["capital", "capitol"],
            ["emigrate", "immigrate"],
            ["hear", "here"],
            ["whole", "hole"],
            ["wear", "where", "ware"],
            ["week", "weak"],
            ["wait", "weight"],
            ["way", "weigh"],
        ]
        mapping: Dict[str, List[str]] = {}
        for grp in groups:
            for w in grp:
                mapping[w] = [other for other in grp if other != w]
        return mapping

    def _build_word_upgrade_map(self) -> Dict[str, List[str]]:
        """
        Context-rich vocabulary & precision upgrades for common spoken words
        so the user can click any word in their transcription and swap it.
        """
        return {
            "good": ["excellent", "effective", "solid", "polished"],
            "great": ["outstanding", "exceptional", "remarkable", "superb"],
            "bad": ["flawed", "suboptimal", "poor", "problematic"],
            "big": ["substantial", "significant", "major", "massive"],
            "small": ["compact", "minimal", "lightweight", "modest"],
            "make": ["create", "build", "craft", "engineer"],
            "making": ["creating", "building", "crafting", "designing"],
            "made": ["created", "built", "crafted", "engineered"],
            "change": ["transform", "overhaul", "refine", "modify"],
            "changes": ["improvements", "updates", "revisions", "upgrades"],
            "changing": ["transforming", "updating", "refining", "shifting"],
            "use": ["utilize", "leverage", "employ", "apply"],
            "using": ["utilizing", "leveraging", "employing", "applying"],
            "used": ["utilized", "leveraged", "employed", "applied"],
            "help": ["assist", "empower", "support", "enable"],
            "helping": ["assisting", "empowering", "supporting", "enabling"],
            "show": ["demonstrate", "display", "illustrate", "reveal"],
            "showing": ["demonstrating", "displaying", "highlighting", "revealing"],
            "look": ["appearance", "aesthetic", "design", "style"],
            "looking": ["examining", "inspecting", "exploring", "viewing"],
            "think": ["believe", "consider", "envision", "assess"],
            "need": ["require", "demand", "must have", "depend on"],
            "want": ["aim", "intend", "prefer", "seek"],
            "get": ["obtain", "achieve", "acquire", "reach"],
            "getting": ["achieving", "obtaining", "reaching", "building"],
            "fix": ["resolve", "repair", "correct", "rectify"],
            "fixing": ["resolving", "repairing", "correcting", "polishing"],
            "work": ["function", "operate", "perform", "succeed"],
            "working": ["functioning", "operating", "performing", "running"],
            "fast": ["rapid", "instant", "swift", "responsive"],
            "hard": ["challenging", "complex", "demanding", "difficult"],
            "easy": ["effortless", "intuitive", "seamless", "straightforward"],
            "important": ["crucial", "essential", "vital", "critical"],
            "thing": ["element", "feature", "component", "aspect"],
            "things": ["elements", "features", "components", "details"],
            "stuff": ["material", "content", "features", "components"],
            "problem": ["issue", "challenge", "bottleneck", "obstacle"],
            "problems": ["issues", "challenges", "bottlenecks", "obstacles"],
            "idea": ["concept", "vision", "approach", "strategy"],
            "system": ["architecture", "platform", "engine", "framework"],
            "way": ["method", "approach", "mechanism", "workflow"],
            "happy": ["pleased", "delighted", "thrilled", "satisfied"],
            "improve": ["enhance", "elevate", "refine", "optimize"],
            "improving": ["enhancing", "elevating", "refining", "optimizing"],
            "improvements": ["enhancements", "upgrades", "refinements", "advances"],
            "create": ["architect", "generate", "craft", "develop"],
            "creating": ["architecting", "generating", "crafting", "developing"],
            "start": ["launch", "initiate", "begin", "kick off"],
            "keep": ["maintain", "preserve", "continue", "sustain"],
            "really": ["truly", "genuinely", "significantly", "remarkably"],
            "very": ["highly", "exceptionally", "deeply", "exceedingly"],
            "nice": ["sleek", "refined", "pleasant", "polished"],
            "better": ["superior", "stronger", "sharper", "more effective"],
            "best": ["finest", "optimal", "premier", "top-tier"],
            "talk": ["speak", "dictate", "communicate", "converse"],
            "write": ["compose", "draft", "author", "transcribe"],
            "writing": ["composing", "drafting", "authoring", "transcribing"],
        }

    def _match_case(self, source: str, target: str) -> str:
        if not source or not target:
            return target
        if source.isupper() and len(source) > 1:
            return target.upper()
        if source[0].isupper():
            return target[0].upper() + target[1:]
        return target

    def _build_word_explorations_and_variants(
        self, text: str
    ) -> Tuple[List[Dict[str, object]], List[Dict[str, str]]]:
        """
        Tokenizes `text` into interactive word objects with:
        - `word`: raw token (e.g. 'change')
        - `display`: token with punctuation (e.g. 'change,')
        - `kind`: 'confusable' | 'upgrade' | 'hedging' | 'normal'
        - `alternatives`: list of 1-click replacement strings (plus '[DROP]' for hedges)
        - `hint`: human-readable explanation of why alternatives are offered
        Also generates 1-click full-sentence rewrite variants ('Concise', 'Elevated').
        """
        explorations: List[Dict[str, object]] = []
        raw_tokens = text.split()
        # Long documents: only the most recent words are shown as clickable tokens
        # (indexes stay absolute so a swap still lands on the right word).
        first_shown = max(0, len(raw_tokens) - 160)
        for idx, tok in enumerate(raw_tokens):
            if idx < first_shown:
                continue
            m = re.match(r"^([^A-Za-z']*)([A-Za-z']+)([^A-Za-z']*)$", tok)
            if not m:
                explorations.append(
                    {
                        "index": idx,
                        "word": tok,
                        "display": tok,
                        "kind": "normal",
                        "alternatives": [],
                        "hint": "",
                    }
                )
                continue

            prefix, core, suffix = m.group(1), m.group(2), m.group(3)
            low = core.lower()
            alts: List[str] = []
            kind = "normal"
            hint = ""

            unsure = None
            if self.rules_enabled.get("smart_typos", True) and is_checkable_token(
                tok, len(prefix), len(prefix) + len(core)
            ):
                unsure = self.typo_fixer.check(core, sentence_start=(idx == 0))

            if unsure is not None and unsure.candidates:
                kind = "spelling"
                hint = f"'{core}' looks misspelled — pick the word you meant:"
                alts.extend(unsure.candidates[:4])
            elif low in self.hedging_words:
                kind = "hedging"
                hint = f"Spoken hedge/filler '{core}' — drop it or swap:"
                alts.append("[DROP]")
                if low in self.word_upgrade_map:
                    for cand in self.word_upgrade_map[low][:3]:
                        alts.append(self._match_case(core, cand))
            elif low in self.sound_alike_map and low in self.word_upgrade_map:
                kind = "confusable"
                hint = f"Sound-alike or vocabulary upgrade for '{core}':"
                for sa in self.sound_alike_map[low][:2]:
                    alts.append(self._match_case(core, sa))
                for up in self.word_upgrade_map[low][:3]:
                    alts.append(self._match_case(core, up))
            elif low in self.sound_alike_map:
                kind = "confusable"
                hint = f"Sound-alike check — did you mean one of these instead of '{core}'?"
                for sa in self.sound_alike_map[low][:3]:
                    alts.append(self._match_case(core, sa))
            elif low in self.word_upgrade_map:
                kind = "upgrade"
                hint = f"Stronger or more precise alternatives for '{core}':"
                for up in self.word_upgrade_map[low][:4]:
                    alts.append(self._match_case(core, up))

            explorations.append(
                {
                    "index": idx,
                    "word": core,
                    "display": tok,
                    "prefix": prefix,
                    "suffix": suffix,
                    "kind": kind,
                    "alternatives": alts,
                    "hint": hint,
                }
            )

        variants: List[Dict[str, str]] = []
        concise = text
        concise_patterns = [
            (r"\bI\s+think\s+that\s+", ""),
            (r"\bI\s+feel\s+like\s+", ""),
            (r"\b(?:basically|actually|literally|honestly|just|really|very|sort\s+of|kind\s+of)\s+", ""),
            (r"\bin\s+my\s+opinion[,\s]*", ""),
        ]
        for pat, rep in concise_patterns:
            concise = re.sub(pat, rep, concise, flags=re.IGNORECASE)
        concise = re.sub(r" {2,}", " ", concise).strip()
        if concise:
            concise = concise[0].upper() + concise[1:]
        if concise and concise != text and len(concise.split()) >= 2:
            variants.append(
                {
                    "label": "CONCISE",
                    "description": "Tighter, zero-fluff version",
                    "text": concise,
                }
            )

        elevated = concise or text
        elevated_swaps = [
            (r"\bmake\b", "create"),
            (r"\bbig\b", "substantial"),
            (r"\bgood\b", "excellent"),
            (r"\bbad\b", "suboptimal"),
            (r"\bfix\b", "resolve"),
            (r"\buse\b", "utilize"),
            (r"\bhelp\b", "assist"),
            (r"\bneed\s+to\b", "must"),
            (r"\ba\s+lot\s+of\b", "numerous"),
            (r"\bcan't\b", "cannot"),
            (r"\bdon't\b", "do not"),
        ]
        for pat, rep in elevated_swaps:
            elevated = re.sub(
                pat,
                lambda m, r=rep: self._match_case(m.group(0), r),
                elevated,
                flags=re.IGNORECASE,
            )
        if elevated:
            elevated = elevated[0].upper() + elevated[1:]
        if elevated and elevated != text and elevated != concise:
            variants.append(
                {
                    "label": "ELEVATED",
                    "description": "Polished executive vocabulary",
                    "text": elevated,
                }
            )

        return explorations, variants

    def set_rules(self, updates: Dict[str, bool]) -> Dict[str, bool]:
        for k, v in updates.items():
            if k in self.rules_enabled:
                self.rules_enabled[k] = bool(v)
        return dict(self.rules_enabled)

    def set_tone(self, tone: str) -> str:
        if tone in ("clear", "formal", "casual", "concise"):
            self.writing_tone = tone
        return self.writing_tone

    def generate_grammarly_recommendations(
        self, text: str, recent_fixes_count: object = 0
    ) -> Dict[str, object]:
        """
        Grammarly-style 4-Pillar Writing Analysis & Interactive Recommendation Engine.
        Evaluates:
        - Correctness (Spelling, Homophones, Grammar)
        - Clarity (Conciseness, Wordiness)
        - Engagement (Vocabulary vividness)
        - Delivery (Confidence & Tone)
        Returns interactive recommendation cards that the user or helper can apply!
        """
        if not text or not text.strip():
            return {
                "writing_score": 100,
                "detected_tone": "Ready",
                "pillar_scores": {
                    "correctness": 100,
                    "clarity": 100,
                    "engagement": 100,
                    "delivery": 100,
                },
                "recommendations": [],
                "word_explorations": [],
                "sentence_variants": [],
            }

        recs: List[Dict[str, str]] = []
        for regex, repl_fn, reason, pillar in self.recommendation_patterns:
            for m in regex.finditer(text):
                orig = m.group(0)
                repl = repl_fn(m)
                if orig != repl:
                    recs.append(
                        {
                            "pillar": pillar,
                            "original": orig,
                            "replacement": repl,
                            "reason": reason,
                        }
                    )

        words = text.split()
        word_count = max(1, len(words))
        clarity_deduction = sum(8 for r in recs if r["pillar"] == "Clarity")
        engagement_deduction = sum(7 for r in recs if r["pillar"] == "Engagement")
        delivery_deduction = sum(7 for r in recs if r["pillar"] == "Delivery")

        # Long run-on sentence check (>28 words without punctuation)
        if word_count > 28 and "," not in text and "." not in text[:-1]:
            clarity_deduction += 10

        clarity_score = max(65, 100 - clarity_deduction)
        engagement_score = max(68, 100 - engagement_deduction)
        delivery_score = max(70, 100 - delivery_deduction)
        fix_count = (
            len(recent_fixes_count)
            if isinstance(recent_fixes_count, list)
            else int(recent_fixes_count or 0)
        )
        correctness_score = 98 if fix_count > 0 else 100

        overall = round(
            (correctness_score * 0.35)
            + (clarity_score * 0.25)
            + (engagement_score * 0.20)
            + (delivery_score * 0.20)
        )

        low = text.lower()
        if any(w in low for w in ("please", "happy", "love", "great", "good", "thanks")):
            detected_tone = "Warm & Positive"
        elif any(w in low for w in ("therefore", "cannot", "implement", "configure", "system")):
            detected_tone = "Analytical & Formal"
        elif "?" in text:
            detected_tone = "Inquisitive"
        else:
            detected_tone = "Direct & Clear"

        word_explorations, sentence_variants = (
            self._build_word_explorations_and_variants(text)
        )

        return {
            "writing_score": int(overall),
            "detected_tone": detected_tone,
            "pillar_scores": {
                "correctness": correctness_score,
                "clarity": clarity_score,
                "engagement": engagement_score,
                "delivery": delivery_score,
            },
            "recommendations": recs[:6],
            "word_explorations": word_explorations,
            "sentence_variants": sentence_variants,
        }

    def join_dictated_clause(
        self, text: str, continues_previous: bool, is_final: bool
    ) -> Tuple[str, bool]:
        """
        Dictation arrives in chunks split wherever the speaker paused, and each
        chunk comes back capitalised with a full stop: "We need to. Finish this."
        This stitches chunks back into sentences:
        - if the previous chunk was left open, this one starts in lower case
          (unless it starts with "I" or a word that isn't an everyday word, which
          is probably a name);
        - if this chunk ends on a word no sentence ends on ("to", "the", "and"),
          its full stop is dropped and it is reported as open.
        Returns `(text, is_open)`.
        """
        if not text:
            return text, False
        if continues_previous:
            first = re.match(r"[A-Za-z']+", text)
            if first:
                word = first.group(0)
                low = word.lower()
                if (
                    word[0].isupper()
                    and not word.isupper()
                    and low != "i"
                    and not low.startswith("i'")
                    and self.typo_fixer.is_everyday_word(low)
                ):
                    text = text[0].lower() + text[1:]
        is_open = False
        if is_final and text.endswith(".") and not text.endswith(".."):
            last = re.search(r"([A-Za-z']+)\.$", text)
            lead_in = re.search(
                r"\b(?:thing|point|problem|question|reason|idea|plan|issue) is\.$",
                text,
                re.IGNORECASE,
            )
            if (last and last.group(1).lower() in _DANGLING) or lead_in:
                text = text[:-1]
                is_open = True
        return text, is_open

    def process_text(
        self,
        raw_text: str,
        is_final_clause: bool = False,
        source: str = "auto",
    ) -> Tuple[str, List[Dict]]:
        """
        Clean, disambiguate, and structure `raw_text` according to active local rules.
        Returns `(corrected_text, list_of_fix_dicts)`.

        `source` says where the text came from, because spoken and typed text need
        different cleanup:
        - "voice": dictation. Strips fillers, honours spoken punctuation ("comma"),
          but skips fuzzy typo fixing (Whisper doesn't make keyboard slips, and
          names/jargon it heard correctly must not be "corrected").
        - "typed": keyboard text. Fuzzy typo fixing on; the words "period"/"comma"
          are left alone and "um"/"ah" are not deleted.
        - "live":  typed text being cleaned *while the user is still typing*. Like
          "typed" but never rewrites phrases, never re-capitalises the start of the
          chunk, and preserves all surrounding whitespace exactly.
        - "auto":  everything on (original behaviour).
        """
        if not raw_text or not raw_text.strip():
            return raw_text, []

        is_voice = source == "voice"
        is_live = source == "live"
        is_typed = source in ("typed", "live")

        text = raw_text
        lead_ws = trail_ws = ""
        if is_live:
            lead_ws = text[: len(text) - len(text.lstrip())]
            trail_ws = text[len(text.rstrip()) :]
            text = text.strip()
        fixes: List[GrammarFix] = []

        # 1. Speech cleanup: filler noises, word stutters & 2-3 word phrase stutters
        if self.rules_enabled.get("speech_cleanup", True):
            filler_re = re.compile(r"\b(um+|uh+|erm+|ah+|hmm+)\b[,\s]*", re.IGNORECASE)
            if not is_typed and filler_re.search(text):
                text = filler_re.sub("", text)
                fixes.append(
                    GrammarFix(
                        original="um/uh",
                        replacement="(removed)",
                        reason="Removed spoken filler words",
                        category="speech_cleanup",
                    )
                )

            # Spoken padding set off by commas: ", you know," / ", like," / ", I mean,"
            if not is_typed:
                text = re.sub(
                    r",\s*(?:you know|i mean|like|sort of|kind of),\s*",
                    " ",
                    text,
                    flags=re.IGNORECASE,
                )

            # Collapse 2-word spoken stutters ("I think I think", "we can we can", "want to want to")
            # (number phrases such as "twenty five twenty five" are left alone)
            phrase_dup_re = re.compile(
                r"\b(?!(?:" + "|".join(sorted(_NUMBER_WORDS)) + r"|\d+)\b)(\w+\s+\w+)\s+\1\b",
                re.IGNORECASE,
            )
            for m in phrase_dup_re.finditer(text):
                phrase = m.group(1)
                fixes.append(
                    GrammarFix(
                        original=m.group(0),
                        replacement=phrase,
                        reason=f"Collapsed repeated phrase '{phrase}'",
                        category="speech_cleanup",
                    )
                )
            text = phrase_dup_re.sub(r"\1", text)

            # Collapse single-word stutters ("the the", "I I", "to to")
            # (any number of repeats: "i i i" -> "i"; meant repeats and numbers are kept)
            dup_re = re.compile(r"\b(\w+)(?:\s+\1\b)+", re.IGNORECASE)

            def _keep_repeat(word: str) -> bool:
                return word.lower() in _REPEAT_OK or word.isdigit()

            for m in dup_re.finditer(text):
                word = m.group(1)
                if not _keep_repeat(word):
                    fixes.append(
                        GrammarFix(
                            original=m.group(0),
                            replacement=word,
                            reason=f"Collapsed repeated word '{word}'",
                            category="speech_cleanup",
                        )
                    )
            text = dup_re.sub(
                lambda m: m.group(0) if _keep_repeat(m.group(1)) else m.group(1),
                text,
            )

        # 2. Spoken punctuation commands
        if not is_typed and self.rules_enabled.get("auto_punctuation", True):
            punct_replacements = [
                (r"\s*\b(period|full stop)\b", "."),
                (r"\s*\bsemi-?\s?colon\b", ";"),
                (r"\s*\bcolon\b", ":"),
                (r"\s*\bcomma\b", ","),
                (r"\s*\bquestion mark\b", "?"),
                (r"\s*\bexclamation (mark|point)\b", "!"),
                (r"\s*\bnew paragraph\b[ \t]*", "\n\n"),
                (r"\s*\bnew line\b[ \t]*", "\n"),
                (r"\bopen (?:quotes?|quotation marks?)\b\s*", '"'),
                (r"\s*\b(?:close|end) (?:quotes?|quotation marks?)\b|\s*\bunquote\b", '"'),
                (r"\bopen (?:brackets?|parenthes[ie]s|paren)\b\s*", "("),
                (r"\s*\bclose (?:brackets?|parenthes[ie]s|paren)\b", ")"),
            ]
            for pat, sym in punct_replacements:
                text = re.sub(pat, sym, text, flags=re.IGNORECASE)

        # 3. Dyslexia spelling, letter-reversal & transposition fixes
        if self.rules_enabled.get("dyslexia_spelling", True):
            def replace_spelling(match: re.Match) -> str:
                word = match.group(0)
                lower = word.lower()
                if lower in self.spelling_map:
                    corr, reason = self.spelling_map[lower]
                    if word.isupper() and len(word) > 1:
                        corr = corr.upper()
                    elif word[0].isupper():
                        corr = corr.capitalize()
                    fixes.append(
                        GrammarFix(
                            original=word,
                            replacement=corr,
                            reason=reason,
                            category="spelling",
                        )
                    )
                    return corr
                return word

            text = re.sub(r"\b[A-Za-z']+\b", replace_spelling, text)

        # 3b. Smart typo fixing: any wrong / missing / extra / swapped letter that
        #     has one clear correction (see typo_fixer.py). Unsure words are left
        #     in place and offered as clickable choices in the word explorer.
        if (
            not is_voice
            and self.rules_enabled.get("dyslexia_spelling", True)
            and self.rules_enabled.get("smart_typos", True)
        ):
            text, typo_changes = self.typo_fixer.fix_text(text)
            for old_word, new_word in typo_changes:
                fixes.append(
                    GrammarFix(
                        original=old_word,
                        replacement=new_word,
                        reason=f"Typo fix ({old_word} → {new_word})",
                        category="spelling",
                    )
                )

        # 4. Homophones, Clarity & contextual grammar disambiguation
        if (
            self.rules_enabled.get("homophones", True)
            or self.rules_enabled.get("grammar_structure", True)
            or self.rules_enabled.get("clarity_conciseness", True)
        ):
            for regex, repl_fn, reason, category in self.contextual_patterns:
                if category == "homophone" and not self.rules_enabled.get(
                    "homophones", True
                ):
                    continue
                if category == "grammar" and not self.rules_enabled.get(
                    "grammar_structure", True
                ):
                    continue
                if category == "spelling" and not self.rules_enabled.get(
                    "dyslexia_spelling", True
                ):
                    continue
                if category == "clarity" and (
                    is_live or not self.rules_enabled.get("clarity_conciseness", True)
                ):
                    continue
                for m in regex.finditer(text):
                    orig = m.group(0)
                    new_val = repl_fn(m)
                    if orig != new_val:
                        fixes.append(
                            GrammarFix(
                                original=orig,
                                replacement=new_val,
                                reason=reason,
                                category=category,
                            )
                        )
                text = regex.sub(repl_fn, text)

        # If writing_tone is "concise", also auto-apply all Engagement/Delivery recommendation patterns
        if self.writing_tone == "concise" and not is_live:
            for regex, repl_fn, reason, pillar in self.recommendation_patterns:
                for m in regex.finditer(text):
                    orig = m.group(0)
                    new_val = repl_fn(m)
                    if orig != new_val:
                        fixes.append(
                            GrammarFix(
                                original=orig,
                                replacement=new_val,
                                reason=reason,
                                category="clarity",
                            )
                        )
                text = regex.sub(repl_fn, text)

        # 5. Writing tone adjustments (Formal mode expands contractions)
        if (
            self.writing_tone == "formal"
            and not is_live
            and self.rules_enabled.get("grammar_structure", True)
        ):
            formal_map = [
                (r"\bcan't\b", "cannot"),
                (r"\bwon't\b", "will not"),
                (r"\bdon't\b", "do not"),
                (r"\bdoesn't\b", "does not"),
                (r"\bdidn't\b", "did not"),
                (r"\bisn't\b", "is not"),
                (r"\baren't\b", "are not"),
                (r"\bI'm\b", "I am"),
                (r"\bgonna\b", "going to"),
                (r"\bwanna\b", "want to"),
            ]
            for pat, repl in formal_map:
                text = re.sub(pat, repl, text, flags=re.IGNORECASE)

        # 6. Capitalization & sentence boundary structure
        if self.rules_enabled.get("grammar_structure", True):
            text = re.sub(r"\bi\b", "I", text)
            text = re.sub(
                r"\bi'(m|ve|ll|d)\b",
                lambda m: f"I'{m.group(1).lower()}",
                text,
                flags=re.IGNORECASE,
            )

            if not is_live:
                text = _DAYS_MONTHS.sub(lambda m: m.group(0).capitalize(), text)
                text = _AMBIGUOUS_MONTH.sub(
                    lambda m: m.group(1) + m.group(2).capitalize(), text
                )

        # 6b. Punctuation hygiene: spacing around , . ! ? ; : and "it,s" slips.
        #     Done before capitalising so a rescued sentence break gets its capital.
        if not is_live and self.rules_enabled.get("auto_punctuation", True):
            text = _tidy_punctuation(text)
        if is_voice:
            text = re.sub(r"\n[ \t]+", "\n", text)

        if self.rules_enabled.get("grammar_structure", True):
            if is_live:
                # a live chunk may start mid-sentence: leave its first letter alone
                text = re.sub(
                    r"([.!?]\s+[a-z])", lambda m: m.group(0).upper(), text
                )
            else:
                # First letter of every sentence...
                text = re.sub(
                    r"([.!?][\"')\]]?\s+[a-z])", lambda m: m.group(0).upper(), text
                )
                # ...and of every line, including "- bullet" and "1. numbered"
                # lines (but not lines that start with a link or file name).
                text = re.sub(
                    r"(?m)^([ \t]*(?:[-*•][ \t]+|\d+[.)][ \t]+)?[\"'(]?)"
                    r"(?![a-z]+(?:://|\.[a-z]{2,4}\b|@))([a-z])",
                    lambda m: m.group(1) + m.group(2).upper(),
                    text,
                )

        # Normalize whitespace (indentation at the start of a line is kept)
        if is_live:
            text = lead_ws + text + trail_ws
        else:
            text = re.sub(r"(?<=\S) {2,}", " ", text).strip()

        # 7. Intelligent end-of-clause punctuation (? for questions vs . for statements)
        if (
            is_final_clause
            and not is_live
            and self.rules_enabled.get("auto_punctuation", True)
        ):
            last_line = text.rsplit("\n", 1)[-1]
            is_list_item = bool(re.match(r"[ \t]*(?:[-*•]|\d+[.)])[ \t]+", last_line))
            if text and text[-1] not in ".!?,;:\"')" and not is_list_item:
                question_Starters = re.compile(
                    r"^(what|where|when|why|how|who|whom|whose|which|can\s+(?:i|you|we|they)|could\s+(?:i|you|we|they)|should\s+(?:i|you|we|they)|would\s+(?:i|you|we|they)|do\s+(?:i|you|we|they)|does\s+(?:it|he|she)|did\s+(?:i|you|we|they)|is\s+(?:it|this|that|there)|are\s+(?:you|we|they|there))\b",
                    re.IGNORECASE,
                )
                # Judge only the final sentence, not how the whole text began.
                last_sentence = re.split(r"[.!?]\s+|\n", text)[-1]
                if question_Starters.search(last_sentence):
                    text += "?"
                else:
                    text += "."

        return text, [asdict(f) for f in fixes]


def compute_in_place_edit(currently_typed: str, target_text: str) -> Tuple[int, str]:
    """
    Given the text currently typed into the active screen box (`currently_typed`)
    and the updated/corrected text (`target_text`), compute:
    - `backspaces`: how many characters to delete from the end of `currently_typed`
    - `to_type`: the replacement suffix string to type immediately after backspacing.
    """
    common_len = 0
    max_common = min(len(currently_typed), len(target_text))
    while (
        common_len < max_common
        and currently_typed[common_len] == target_text[common_len]
    ):
        common_len += 1

    backspaces = len(currently_typed) - common_len
    to_type = target_text[common_len:]
    return backspaces, to_type
