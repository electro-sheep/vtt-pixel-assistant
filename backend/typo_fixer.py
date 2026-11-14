"""
Smart Typo Fixer — catches *any* wrong-letter, missing-letter, extra-letter or
swapped-letter slip, not just the fixed list in `dyslexia_grammar.spelling_map`.

How it works:
1. Windows' built-in spell checker (ISpellChecker, ships with Windows 8+) says
   whether a word is misspelled and proposes candidates. 100% local, no download.
2. Candidates are re-ranked with a keyboard-aware edit distance (adjacent-key
   slips, doubled letters, swapped letters and dropped endings are "cheap") plus
   a common-word bonus, so "wron" becomes "wrong" rather than "worn".
3. A fix is only auto-applied when one candidate clearly wins. Otherwise the word
   is returned as "unsure" with choices, so the UI can offer them on click.

If the Windows spell checker is unavailable the fixer reports `available = False`
and every word is treated as correct (the static spelling map still works).
"""

from __future__ import annotations
import json
import os
import re
import threading
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from typing import Dict, Iterable, List, Optional, Set, Tuple

# Roughly frequency-ordered everyday English. Used only to break ties between
# spell-checker candidates (a common word beats a rare one).
_COMMON_WORDS = """
the be to of and a in that have i it for not on with he as you do at this but his by from they we
say her she or an will my one all would there their what so up out if about who get which go me
when make can like time no just him know take people into year your good some could them see other
than then now look only come its over think also back after use two how our work first well way
even new want because any these give day most us is are was were been has had did does am being
said made went got came took saw knew thought told found gave left felt put kept let began seemed
helped showed heard played ran moved lived believed brought happened wrote sat stood lost paid met
very much many more such own same too here where why while should may might must shall each every
both few those still again never always often sometimes usually really already almost maybe yes
thing things man woman child children world life hand part place case week company system program
question number night point home water room mother area money story fact month lot right study book
eye job word business issue side kind head house service friend father power hour game line end
member law car city community name president team minute idea kid body information parent face
others level office door health person art war history party result change morning reason research
girl guy moment air teacher force education foot boy age policy music market sense nation plan
college interest death experience effect class control field development role effort rate heart
drug show leader light voice wife police mind price report decision son view relationship town road
arm difference value building action season society tax director position player record paper
space ground form event official matter center couple site project activity star table need court
american oil situation cost industry figure street image phone data picture practice piece land
product doctor wall patient worker news test movie north love step film tree source letter letters
find tell ask seem feel try leave call keep provide hold turn follow begin bring start run write
set move play pay hear include believe allow meet lead live stand happen carry talk appear produce
sit offer consider expect suggest read require continue lose add remember buy speak stop send
receive decide win understand describe develop agree open reach build involve spend return draw die
hope create walk sell wait cause pass lie accept watch raise base apply break explain learn
increase cover grow claim report support cut kill stay contain reduce establish join wish achieve
seek choose deal face fail serve end occur drive represent rise discuss place prove wear argue
catch enjoy improve review clean fix check type click save close help
great little old different small large big high long young important bad able early late best
better sure free true whole clear full special easy hard strong possible real major personal
current national natural physical short general public common simple recent certain single open
red blue green white black dark light hot cold low wrong right ready happy nice fine poor serious
similar final main available likely necessary difficult various entire close local social human
political economic medical financial private legal past present future modern popular huge
together away around through during before between under against without within along across
behind toward upon among until since though although however therefore instead perhaps probably
actually finally especially certainly simply quickly recently exactly nearly clearly suddenly
today tomorrow yesterday tonight once twice soon later ago ever yet else quite rather enough
something anything nothing everything someone anyone everyone nobody somebody anybody myself
yourself himself herself itself ourselves themselves another whatever whether either neither
three four five six seven eight nine ten hundred thousand million second third last next half
function functionality feature features text code button screen window app application file files
page pages message email computer keyboard mouse internet website online video audio image photo
user users account password setting settings option options update version error problem problems
answer example list item items note notes document documents sentence sentences paragraph spelling
grammar animation animations interface design color size speed quality model voice transcription
missing using going doing having making getting looking working trying coming taking saying
thinking writing reading running talking cleaning typing checking fixing improving building
don't can't won't didn't doesn't isn't aren't wasn't weren't i'm i've i'll i'd it's that's
there's they're you're we're he's she's what's let's couldn't wouldn't shouldn't haven't hasn't
food family school student students group country state government problem night week weeks days
years months hours minutes times ways words lines names places friends parents children members
please thanks thank sorry hello okay welcome definitely played letter weather whether
""".split()

_COMMON_RANK: Dict[str, int] = {}
COMMON_WORD_RANK = _COMMON_RANK  # public alias (read-only use elsewhere)
for _i, _w in enumerate(_COMMON_WORDS):
    _COMMON_RANK.setdefault(_w, _i)
_TOP_CUTOFF = 420  # words ranked above this get the larger "very common" bonus

_VOWELS = set("aeiouy")


def _build_key_neighbors() -> Dict[str, Set[str]]:
    rows = [("qwertyuiop", 0.0), ("asdfghjkl", 0.3), ("zxcvbnm", 0.8)]
    pos: Dict[str, Tuple[float, float]] = {}
    for y, (row, shift) in enumerate(rows):
        for x, ch in enumerate(row):
            pos[ch] = (x + shift, float(y))
    neighbors: Dict[str, Set[str]] = {c: set() for c in pos}
    for a, (ax, ay) in pos.items():
        for b, (bx, by) in pos.items():
            if a != b and ((ax - bx) ** 2 + (ay - by) ** 2) ** 0.5 <= 1.3:
                neighbors[a].add(b)
    return neighbors


_KEY_NEIGHBORS = _build_key_neighbors()


def _adjacent(a: str, b: str) -> bool:
    return b in _KEY_NEIGHBORS.get(a, ())


def typo_edit_cost(typo: str, cand: str) -> float:
    """
    Keyboard-aware Damerau-Levenshtein (optimal string alignment) cost of turning
    `typo` into `cand`. Slips people really make are cheaper than random edits.
    """
    a, b = typo.lower(), cand.lower()
    la, lb = len(a), len(b)
    d = [[0.0] * (lb + 1) for _ in range(la + 1)]

    def extra_cost(i: int) -> float:  # typo has a stray letter a[i]
        ch = a[i]
        prev_ch = a[i - 1] if i > 0 else ""
        next_ch = a[i + 1] if i + 1 < la else ""
        if ch == prev_ch or ch == next_ch:
            return 0.6  # doubled letter
        if _adjacent(ch, prev_ch) or _adjacent(ch, next_ch):
            return 0.6  # fat-fingered the key next door
        return 0.9

    def missing_cost(j: int) -> float:  # typo dropped the letter b[j]
        ch = b[j]
        if j == lb - 1:
            return 0.7  # dropped the ending
        if (j > 0 and b[j - 1] == ch) or (j + 1 < lb and b[j + 1] == ch):
            return 0.5  # dropped one half of a double letter
        if not ch.isalpha():
            return 0.6  # missing apostrophe / space
        return 0.9

    def sub_cost(x: str, y: str) -> float:
        if x == y:
            return 0.0
        if _adjacent(x, y):
            return 0.65
        if x in _VOWELS and y in _VOWELS:
            return 0.85
        return 1.0

    for i in range(1, la + 1):
        d[i][0] = d[i - 1][0] + extra_cost(i - 1)
    for j in range(1, lb + 1):
        d[0][j] = d[0][j - 1] + missing_cost(j - 1)
    for i in range(1, la + 1):
        for j in range(1, lb + 1):
            best = min(
                d[i - 1][j] + extra_cost(i - 1),
                d[i][j - 1] + missing_cost(j - 1),
                d[i - 1][j - 1] + sub_cost(a[i - 1], b[j - 1]),
            )
            if (
                i > 1
                and j > 1
                and a[i - 1] == b[j - 2]
                and a[i - 2] == b[j - 1]
                and a[i - 1] != a[i - 2]
            ):
                best = min(best, d[i - 2][j - 2] + 0.7)  # swapped pair
            d[i][j] = best

    cost = d[la][lb]
    if a and b and a[0] != b[0]:
        swapped_start = la > 1 and lb > 1 and a[0] == b[1] and a[1] == b[0]
        if not swapped_start:
            cost += 0.5  # people nearly always get the first letter right
    return cost


def _max_auto_cost(length: int) -> float:
    if length <= 3:
        return 0.7
    if length == 4:
        return 1.0
    if length <= 6:
        return 1.25
    if length <= 8:
        return 1.7
    return 2.4


@dataclass
class TypoVerdict:
    """Result for one misspelled word."""

    word: str
    best: Optional[str]  # set only when confident enough to auto-fix
    candidates: List[str] = field(default_factory=list)  # ranked, best first

    @property
    def confident(self) -> bool:
        return self.best is not None


class _WindowsSpellBackend:
    """Owns the ISpellChecker COM object on one dedicated worker thread."""

    def __init__(self, language: str = "en-US") -> None:
        self._language = language
        self._checker = None
        self._pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="spellcheck")
        self.available = False
        try:
            self.available = bool(self._pool.submit(self._init).result(timeout=6.0))
        except Exception:
            self.available = False

    def _init(self) -> bool:
        import comtypes
        from comtypes import COMMETHOD, GUID, HRESULT, IUnknown
        from ctypes import POINTER, c_int, c_wchar_p
        from ctypes.wintypes import BOOL, LPCWSTR, ULONG

        try:
            comtypes.CoInitializeEx(0)  # multithreaded apartment for this worker
        except OSError:
            pass

        class IEnumString(IUnknown):
            _iid_ = GUID("{00000101-0000-0000-C000-000000000046}")
            _methods_ = [
                COMMETHOD(
                    [],
                    HRESULT,
                    "Next",
                    (["in"], ULONG, "celt"),
                    (["out"], POINTER(c_wchar_p), "rgelt"),
                    (["out"], POINTER(ULONG), "fetched"),
                ),
            ]

        class ISpellingError(IUnknown):
            _iid_ = GUID("{B7C82D61-FBE8-4B47-9B27-6C0D2E0DE0A3}")
            _methods_ = [
                COMMETHOD(["propget"], HRESULT, "StartIndex", (["out", "retval"], POINTER(ULONG), "v")),
                COMMETHOD(["propget"], HRESULT, "Length", (["out", "retval"], POINTER(ULONG), "v")),
                COMMETHOD(["propget"], HRESULT, "CorrectiveAction", (["out", "retval"], POINTER(c_int), "v")),
                COMMETHOD(["propget"], HRESULT, "Replacement", (["out", "retval"], POINTER(c_wchar_p), "v")),
            ]

        class IEnumSpellingError(IUnknown):
            _iid_ = GUID("{803E3BD4-2828-4410-8290-418D1D73C762}")
            _methods_ = [
                COMMETHOD([], HRESULT, "Next", (["out", "retval"], POINTER(POINTER(ISpellingError)), "v")),
            ]

        class ISpellChecker(IUnknown):
            _iid_ = GUID("{B6FD0B71-E2BC-4653-8D05-F197E412770B}")
            _methods_ = [
                COMMETHOD(["propget"], HRESULT, "LanguageTag", (["out", "retval"], POINTER(c_wchar_p), "v")),
                COMMETHOD(
                    [],
                    HRESULT,
                    "Check",
                    (["in"], LPCWSTR, "text"),
                    (["out", "retval"], POINTER(POINTER(IEnumSpellingError)), "v"),
                ),
                COMMETHOD(
                    [],
                    HRESULT,
                    "Suggest",
                    (["in"], LPCWSTR, "word"),
                    (["out", "retval"], POINTER(POINTER(IEnumString)), "v"),
                ),
            ]

        class ISpellCheckerFactory(IUnknown):
            _iid_ = GUID("{8E018A9D-2415-4677-BF08-794EA61F94BB}")
            _methods_ = [
                COMMETHOD(
                    ["propget"],
                    HRESULT,
                    "SupportedLanguages",
                    (["out", "retval"], POINTER(POINTER(IEnumString)), "v"),
                ),
                COMMETHOD(
                    [],
                    HRESULT,
                    "IsSupported",
                    (["in"], LPCWSTR, "tag"),
                    (["out", "retval"], POINTER(BOOL), "v"),
                ),
                COMMETHOD(
                    [],
                    HRESULT,
                    "CreateSpellChecker",
                    (["in"], LPCWSTR, "tag"),
                    (["out", "retval"], POINTER(POINTER(ISpellChecker)), "v"),
                ),
            ]

        factory = comtypes.CoCreateInstance(
            GUID("{7AB36653-1796-484B-BDFA-E74F1DB7C1DC}"),
            interface=ISpellCheckerFactory,
        )
        for tag in (self._language, "en-US", "en-GB", "en"):
            if factory.IsSupported(tag):
                self._checker = factory.CreateSpellChecker(tag)
                return True
        return False

    def _lookup(self, word: str) -> Tuple[bool, List[str]]:
        checker = self._checker
        if checker is None:
            return False, []
        errors = checker.Check(word)
        try:
            first = errors.Next()
        except Exception:
            first = None
        if not first:
            return False, []
        suggestions: List[str] = []
        enum = checker.Suggest(word)
        while len(suggestions) < 8:
            try:
                value, fetched = enum.Next(1)
            except Exception:
                break
            if not fetched or not value:
                break
            suggestions.append(value)
        return True, suggestions

    def lookup(self, word: str) -> Tuple[bool, List[str]]:
        if not self.available:
            return False, []
        try:
            return self._pool.submit(self._lookup, word).result(timeout=1.5)
        except Exception:
            return False, []


# A "word" for typo purposes: letters with optional inner apostrophes.
WORD_RE = re.compile(r"[A-Za-z]+(?:'[A-Za-z]+)*")
_GLUE_BEFORE = set("@/\\_#$%&=+<>{}[]|~^`0123456789")
_GLUE_AFTER = set("@/\\_$%&=+<>{}[]|~^`0123456789")


def is_checkable_token(text: str, start: int, end: int) -> bool:
    """False for things that look like code, paths, e-mails, URLs or acronyms."""
    word = text[start:end]
    if len(word) < 2 or len(word) > 24:
        return False
    if start > 0 and text[start - 1] in _GLUE_BEFORE:
        return False
    if end < len(text) and text[end] in _GLUE_AFTER:
        return False
    # file.ext / domain.com / obj.attr
    if end + 1 < len(text) and text[end] == "." and text[end + 1].isalpha():
        return False
    if start > 1 and text[start - 1] == "." and text[start - 2].isalnum():
        return False
    if word.isupper() and len(word) <= 5:
        return False  # acronym
    if any(c.isupper() for c in word[1:]) and not word.isupper():
        return False  # camelCase / McName
    return True


class SmartTypoFixer:
    def __init__(
        self,
        settings_path: Optional[str] = None,
        backend: Optional[object] = None,
    ) -> None:
        self._backend = backend
        self._backend_ready = backend is not None
        self._backend_lock = threading.Lock()
        self._cache: Dict[str, Optional[Tuple[Optional[str], List[str]]]] = {}
        self._settings_path = settings_path
        self.learned_words: Set[str] = set()
        self.session_ignored: Set[str] = set()
        self.version = 0  # bumps whenever learned/ignored words change
        self._load_learned()

    # ---- personal dictionary -------------------------------------------------
    def _load_learned(self) -> None:
        if not self._settings_path or not os.path.isfile(self._settings_path):
            return
        try:
            with open(self._settings_path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
            self.learned_words = {str(w).lower() for w in data.get("learned_words", [])}
        except Exception:
            self.learned_words = set()

    def _save_learned(self) -> None:
        if not self._settings_path:
            return
        try:
            data: Dict[str, object] = {}
            if os.path.isfile(self._settings_path):
                with open(self._settings_path, "r", encoding="utf-8") as fh:
                    data = json.load(fh)
            data["learned_words"] = sorted(self.learned_words)
            with open(self._settings_path, "w", encoding="utf-8") as fh:
                json.dump(data, fh, indent=2)
        except Exception:
            pass

    def learn_word(self, word: str) -> None:
        """Permanently accept `word` as correctly spelled."""
        low = word.strip().lower()
        if low:
            self.learned_words.add(low)
            self.version += 1
            self._save_learned()

    def ignore_for_session(self, word: str) -> None:
        low = word.strip().lower()
        if low:
            self.session_ignored.add(low)
            self.version += 1

    # ---- core ----------------------------------------------------------------
    @property
    def available(self) -> bool:
        return bool(self._get_backend() and self._get_backend().available)

    def _get_backend(self):
        if not self._backend_ready:
            with self._backend_lock:
                if not self._backend_ready:
                    try:
                        self._backend = _WindowsSpellBackend()
                    except Exception:
                        self._backend = None
                    self._backend_ready = True
        return self._backend

    def is_everyday_word(self, word: str) -> bool:
        """True when `word` is a normal lower-case dictionary word (so a capital
        on it is just sentence-start capitalisation, not a name like "Friday")."""
        low = word.lower()
        backend = self._get_backend()
        if backend is None or not backend.available:
            return low in _COMMON_RANK
        if low not in self._cache:
            bad, suggestions = backend.lookup(low)
            self._cache[low] = self._rank(low, suggestions) if bad else None
        return self._cache[low] is None

    def _rank(self, low: str, suggestions: Iterable[str]) -> Tuple[Optional[str], List[str]]:
        # Same letters, different capitals ("london" -> "London", "iphone" ->
        # "iPhone"): the word is a name that just needs its capital letter.
        for sug in suggestions:
            if sug.lower() == low and sug != low:
                return sug, [sug]

        limit = _max_auto_cost(len(low))
        scored: List[Tuple[float, float, str]] = []  # (score, cost, candidate)
        for rank, sug in enumerate(suggestions):
            cand = sug.strip()
            cand_low = cand.lower()
            if not cand or cand_low == low:
                continue
            if " " in cand or "-" in cand:
                parts = re.split(r"[ -]", cand_low)
                # "alot" -> "a lot" is fine; "of fen" is noise
                if not all(p in _COMMON_RANK for p in parts):
                    continue
                cost = 0.9 + typo_edit_cost(low, cand_low.replace(" ", "").replace("-", ""))
                bonus = 0.3
            else:
                if abs(len(cand_low) - len(low)) > 3:
                    continue
                cost = typo_edit_cost(low, cand_low)
                freq = _COMMON_RANK.get(cand_low)
                bonus = 0.0 if freq is None else (0.6 if freq < _TOP_CUTOFF else 0.45)
            score = cost + min(rank, 3) * 0.12 - bonus
            scored.append((score, cost, cand_low))

        if not scored:
            return None, []
        scored.sort(key=lambda t: t[0])
        ranked = [c for _, _, c in scored[:5]]
        best_score, best_cost, best = scored[0]
        if best_cost > limit:
            return None, ranked
        if len(low) <= 3 and _COMMON_RANK.get(best, 10**6) >= _TOP_CUTOFF:
            return None, ranked  # tiny words: only fix to a very common word
        if best_cost > 1.0 and best not in _COMMON_RANK and len(scored) > 1:
            return None, ranked  # multi-slip guess at a rare word: ask instead
        rivals = [s for s in scored[1:] if s[1] <= limit]
        if rivals and rivals[0][0] - best_score < 0.3:
            return None, ranked  # too close to call
        return best, ranked

    def check(self, word: str, sentence_start: bool = True) -> Optional[TypoVerdict]:
        """
        Returns None when `word` is fine (or we should leave it alone), otherwise a
        TypoVerdict. `best` is only set when the fix is safe to apply automatically.
        """
        low = word.lower()
        if low in self.learned_words or low in self.session_ignored:
            return None
        backend = self._get_backend()
        if backend is None or not backend.available:
            return None

        if low not in self._cache:
            bad, suggestions = backend.lookup(low)
            self._cache[low] = self._rank(low, suggestions) if bad else None
            if len(self._cache) > 20000:
                self._cache.clear()
        entry = self._cache[low]
        if entry is None:
            return None
        best, ranked = entry
        if not ranked:
            return None

        capitalised = word[0].isupper()
        if capitalised and not word.isupper():
            # Could be a name. Only touch it for an obvious one-slip typo that keeps
            # its first letter; mid-sentence, don't even flag it otherwise.
            obvious = (
                best is not None
                and typo_edit_cost(low, best) <= 1.0
                and best[0].lower() == low[0]
            )
            if not obvious:
                if not sentence_start:
                    return None
                best = None

        def recase(c: str) -> str:
            if word.isupper() and len(word) > 1:
                return c.upper()
            if capitalised:
                return c[0].upper() + c[1:]
            return c

        fixed = recase(best) if best else None
        choices = [c for c in (recase(c) for c in ranked[:4]) if c != word]
        if fixed == word or not choices:
            return None  # already spelled (and capitalised) correctly
        return TypoVerdict(word=word, best=fixed, candidates=choices)

    def fix_text(self, text: str) -> Tuple[str, List[Tuple[str, str]]]:
        """Auto-fix every confident typo in `text`. Returns (new_text, [(old, new)])."""
        if not self.available:
            return text, []
        changes: List[Tuple[str, str]] = []
        out: List[str] = []
        last = 0
        for m in WORD_RE.finditer(text):
            start, end = m.span()
            if not is_checkable_token(text, start, end):
                continue
            before = text[:start].rstrip()
            at_start = (not before) or before[-1] in ".!?\n"
            verdict = self.check(m.group(0), sentence_start=at_start)
            if verdict is None or verdict.best is None:
                continue
            out.append(text[last:start])
            out.append(verdict.best)
            last = end
            changes.append((m.group(0), verdict.best))
        if not changes:
            return text, []
        out.append(text[last:])
        return "".join(out), changes
