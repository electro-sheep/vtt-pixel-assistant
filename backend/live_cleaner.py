"""
Live Clean — fixes typos in ANY app while you type, word by word.

When enabled, a low-level keyboard listener keeps a short in-memory copy of the
last few words typed. Each time a word is finished (space or . , ! ? ; :) the last
few words are run through the grammar engine; if something needs fixing, the
wrong characters are backspaced and the right ones typed in their place.

Safety rules:
- Nothing typed is ever written to disk or sent anywhere; the buffer holds at most
  ~200 characters and is wiped on Enter, Tab, arrows, mouse clicks, shortcuts and
  window switches (anything that could move the caret).
- A fix never fires on Enter/Tab, so it can't interfere with sending a message.
- Pressing Backspace right after a fix undoes it and stops that word being
  "fixed" again this session.
- Code editors, terminals and password managers are skipped.

`LiveTypingBuffer` is the pure logic (unit-tested); `LiveCleaner` adds the
Windows keyboard hook around it.
"""

from __future__ import annotations
import ctypes
import os
import threading
from collections import deque
from ctypes import wintypes
from typing import Callable, Deque, Dict, List, Optional, Set, Tuple

Edit = Tuple[int, str]  # (backspaces, text to type)
CleanFn = Callable[[str], Tuple[str, List[Dict]]]

TRIGGER_CHARS = " .,!?;:"
MAX_BUFFER = 200
REGION_WORDS = 4

# Apps where prose autocorrect does more harm than good.
EXCLUDED_PROCESSES = {
    "code.exe", "cursor.exe", "devenv.exe", "windsurf.exe", "zed.exe",
    "pycharm64.exe", "idea64.exe", "studio64.exe", "webstorm64.exe", "rider64.exe",
    "clion64.exe", "sublime_text.exe", "notepad++.exe", "vim.exe", "gvim.exe",
    "nvim.exe", "windowsterminal.exe", "wt.exe", "powershell.exe", "pwsh.exe",
    "cmd.exe", "conhost.exe", "openconsole.exe", "mintty.exe", "bash.exe",
    "wezterm-gui.exe", "alacritty.exe", "putty.exe",
    "keepass.exe", "keepassxc.exe", "1password.exe", "bitwarden.exe",
    "lastpass.exe", "dashlane.exe", "vtt_assistant.exe",
}


def _common_prefix_edit(current: str, target: str) -> Edit:
    n = 0
    limit = min(len(current), len(target))
    while n < limit and current[n] == target[n]:
        n += 1
    return len(current) - n, target[n:]


class LiveTypingBuffer:
    """Tracks the text just left of the caret and decides when/how to fix it."""

    def __init__(self, clean_fn: CleanFn) -> None:
        self._clean = clean_fn
        self.text = ""
        self._undo: Optional[Tuple[str, str, List[str]]] = None  # (old, new, originals)
        self.suppressed: Set[str] = set()
        self.last_fixes: List[Dict] = []

    def reset(self) -> None:
        self.text = ""
        self._undo = None

    def _region_start(self) -> int:
        """Index where the last REGION_WORDS words (plus trailing chars) begin."""
        i = len(self.text)
        words = 0
        while i > 0:
            while i > 0 and self.text[i - 1].isspace():
                i -= 1
            if i == 0:
                break
            j = i
            while j > 0 and not self.text[j - 1].isspace():
                j -= 1
            words += 1
            if words >= REGION_WORDS:
                return j
            i = j
        return 0

    def on_char(self, ch: str, pending_tail: str = "") -> Optional[Edit]:
        """
        Record a typed character. Returns an edit when a finished word needs fixing.
        `pending_tail` is anything typed after `ch` that is already on screen but
        not yet in the buffer; it is retyped after the fix so nothing is lost.
        """
        self._undo = None
        self.text = (self.text + ch)[-MAX_BUFFER:]
        if ch not in TRIGGER_CHARS:
            return None

        start = self._region_start()
        region = self.text[start:]
        if not any(c.isalpha() for c in region):
            return None
        try:
            cleaned, fixes = self._clean(region)
        except Exception:
            return None
        if cleaned == region or not fixes or "\n" in cleaned:
            return None
        originals = [str(f.get("original", "")).lower() for f in fixes]
        if any(o in self.suppressed for o in originals):
            return None

        backspaces, typed = _common_prefix_edit(region, cleaned)
        self.text = self.text[:start] + cleaned
        self._undo = (region, cleaned, originals)
        self.last_fixes = fixes
        return backspaces + len(pending_tail), typed + pending_tail

    def on_backspace(self) -> Optional[Edit]:
        """Backspace straight after a fix restores what the user originally typed."""
        undo, self._undo = self._undo, None
        if undo and self.text.endswith(undo[1]):
            old, new, originals = undo
            self.suppressed.update(o for o in originals if o)
            # The user's own Backspace already removed the final (trigger) char.
            edit = _common_prefix_edit(new[:-1], old[:-1])
            self.text = self.text[: len(self.text) - len(new)] + old[:-1]
            return edit
        self.text = self.text[:-1]
        return None


# ---------------------------------------------------------------------------
# Windows keyboard hook wrapper
# ---------------------------------------------------------------------------

WH_KEYBOARD_LL = 13
WM_KEYDOWN = 0x0100
WM_SYSKEYDOWN = 0x0104
WM_QUIT = 0x0012
LLKHF_INJECTED = 0x10
INPUT_MAGIC = 0x56545443  # marks keystrokes this app injects ("VTTC")

_VK_IGNORE = {0x10, 0xA0, 0xA1, 0x14, 0x90, 0x91}  # shift, caps, num/scroll lock
_VK_MODIFIERS = {0x11, 0xA2, 0xA3, 0x12, 0xA4, 0xA5, 0x5B, 0x5C}  # ctrl, alt, win
_VK_BACK = 0x08

LRESULT = ctypes.c_ssize_t
HOOKPROC = ctypes.WINFUNCTYPE(LRESULT, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM)


class KBDLLHOOKSTRUCT(ctypes.Structure):
    _fields_ = [
        ("vkCode", wintypes.DWORD),
        ("scanCode", wintypes.DWORD),
        ("flags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ctypes.c_size_t),
    ]


class LiveCleaner:
    def __init__(
        self,
        clean_fn: CleanFn,
        on_fix: Optional[Callable[[List[Dict]], None]] = None,
        is_paused: Optional[Callable[[], bool]] = None,
    ) -> None:
        self.buffer = LiveTypingBuffer(clean_fn)
        self._on_fix = on_fix
        self._is_paused = is_paused or (lambda: False)
        self._events: Deque[Tuple[str, str]] = deque()
        self._cond = threading.Condition()
        self._hook_thread: Optional[threading.Thread] = None
        self._worker_thread: Optional[threading.Thread] = None
        self._hook_thread_id = 0
        self._running = False
        self._hwnd = None
        self._hwnd_allowed = False
        self.last_error = ""

    @property
    def enabled(self) -> bool:
        return self._running

    # -- public control ------------------------------------------------------
    def start(self) -> bool:
        if self._running:
            return True
        if os.name != "nt":
            self.last_error = "Live Clean needs Windows."
            return False
        self._running = True
        self.buffer.reset()
        self._events.clear()
        ready = threading.Event()
        self._hook_thread = threading.Thread(
            target=self._hook_loop, args=(ready,), daemon=True, name="live-clean-hook"
        )
        self._worker_thread = threading.Thread(
            target=self._worker_loop, daemon=True, name="live-clean-worker"
        )
        self._hook_thread.start()
        ready.wait(2.0)
        if not self._hook_thread_id:
            self._running = False
            self.last_error = self.last_error or "Could not start keyboard listener."
            return False
        self._worker_thread.start()
        return True

    def stop(self) -> None:
        if not self._running:
            return
        self._running = False
        if self._hook_thread_id:
            ctypes.windll.user32.PostThreadMessageW(self._hook_thread_id, WM_QUIT, 0, 0)
            self._hook_thread_id = 0
        with self._cond:
            self._events.clear()
            self._cond.notify_all()
        self.buffer.reset()

    def notify_caret_moved(self) -> None:
        """Call when a mouse click (or anything else) may have moved the caret."""
        self._push("reset", "")

    # -- hook thread: translate keys to events, never block -------------------
    def _push(self, kind: str, value: str) -> None:
        with self._cond:
            self._events.append((kind, value))
            self._cond.notify()

    def _hook_loop(self, ready: threading.Event) -> None:
        user32 = ctypes.WinDLL("user32", use_last_error=True)
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        user32.SetWindowsHookExW.argtypes = [
            ctypes.c_int, HOOKPROC, wintypes.HINSTANCE, wintypes.DWORD,
        ]
        user32.SetWindowsHookExW.restype = wintypes.HHOOK
        user32.CallNextHookEx.argtypes = [
            wintypes.HHOOK, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM,
        ]
        user32.CallNextHookEx.restype = LRESULT
        user32.UnhookWindowsHookEx.argtypes = [wintypes.HHOOK]
        user32.GetKeyboardLayout.argtypes = [wintypes.DWORD]
        user32.GetKeyboardLayout.restype = wintypes.HKL
        user32.ToUnicodeEx.argtypes = [
            wintypes.UINT, wintypes.UINT, ctypes.POINTER(ctypes.c_ubyte),
            wintypes.LPWSTR, ctypes.c_int, wintypes.UINT, wintypes.HKL,
        ]
        user32.GetWindowThreadProcessId.argtypes = [
            wintypes.HWND, ctypes.POINTER(wintypes.DWORD),
        ]
        user32.GetWindowThreadProcessId.restype = wintypes.DWORD
        user32.GetForegroundWindow.restype = wintypes.HWND
        kernel32.GetModuleHandleW.argtypes = [wintypes.LPCWSTR]
        kernel32.GetModuleHandleW.restype = wintypes.HMODULE

        def is_down(vk: int) -> bool:
            return (user32.GetAsyncKeyState(vk) & 0x8000) != 0

        def to_char(vk: int, scan: int) -> str:
            state = (ctypes.c_ubyte * 256)()
            if is_down(0x10):
                state[0x10] = 0x80
            if user32.GetKeyState(0x14) & 1:
                state[0x14] = 0x01
            buf = ctypes.create_unicode_buffer(8)
            fg = user32.GetForegroundWindow()
            layout = user32.GetKeyboardLayout(
                user32.GetWindowThreadProcessId(fg, None) if fg else 0
            )
            # Flag 0x4: translate without disturbing the keyboard's dead-key state.
            n = user32.ToUnicodeEx(vk, scan, state, buf, 8, 0x4, layout)
            return buf.value[0] if n == 1 and buf.value and buf.value.isprintable() else ""

        def callback(n_code: int, w_param: int, l_param: int) -> int:
            try:
                if n_code == 0 and w_param in (WM_KEYDOWN, WM_SYSKEYDOWN):
                    kb = ctypes.cast(l_param, ctypes.POINTER(KBDLLHOOKSTRUCT)).contents
                    vk = int(kb.vkCode)
                    if kb.flags & LLKHF_INJECTED:
                        if kb.dwExtraInfo != INPUT_MAGIC:
                            self._push("reset", "")  # another tool typed something
                    elif vk in _VK_IGNORE:
                        pass
                    elif vk in _VK_MODIFIERS or is_down(0x11) or is_down(0x12) \
                            or is_down(0x5B) or is_down(0x5C):
                        self._push("reset", "")
                    elif vk == _VK_BACK:
                        self._push("back", "")
                    else:
                        ch = to_char(vk, int(kb.scanCode))
                        self._push("char", ch) if ch else self._push("reset", "")
            except Exception:
                pass
            return user32.CallNextHookEx(None, n_code, w_param, l_param)

        proc = HOOKPROC(callback)  # keep a reference for the hook's lifetime
        hook = user32.SetWindowsHookExW(
            WH_KEYBOARD_LL, proc, kernel32.GetModuleHandleW(None), 0
        )
        if not hook:
            self.last_error = f"Keyboard listener failed (error {ctypes.get_last_error()})."
            ready.set()
            return
        self._hook_thread_id = kernel32.GetCurrentThreadId()
        ready.set()
        msg = wintypes.MSG()
        while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
            pass
        user32.UnhookWindowsHookEx(hook)

    # -- worker thread: apply events in order, compute + type fixes ----------
    def _window_allowed(self, hwnd) -> bool:
        from win32_typer import get_process_name, get_window_title, window_tracker

        if not hwnd:
            return False
        title = get_window_title(hwnd)
        if window_tracker._is_assistant_window(hwnd, title):
            return False
        return get_process_name(hwnd) not in EXCLUDED_PROCESSES

    def _worker_loop(self) -> None:
        from win32_typer import send_direct_edit

        user32 = ctypes.windll.user32
        user32.GetForegroundWindow.restype = wintypes.HWND
        mouse_buttons = (0x01, 0x02, 0x04)
        while self._running:
            with self._cond:
                if not self._events:
                    self._cond.wait(0.04)
                event = self._events.popleft() if self._events else None

            # A mouse press may move the caret, so the buffer can't be trusted.
            if any(user32.GetAsyncKeyState(vk) & 0x8000 for vk in mouse_buttons):
                self.buffer.reset()
            if event is None:
                continue

            hwnd = user32.GetForegroundWindow()
            if hwnd != self._hwnd:
                self._hwnd = hwnd
                self._hwnd_allowed = self._window_allowed(hwnd)
                self.buffer.reset()
            if not self._hwnd_allowed or self._is_paused():
                self.buffer.reset()
                continue

            kind, value = event
            edit: Optional[Edit] = None
            if kind == "reset":
                self.buffer.reset()
            elif kind == "back":
                edit = self.buffer.on_backspace()
            elif kind == "char":
                # Keys typed after this one are already on screen; if they are all
                # plain characters we retype them after the fix, otherwise skip it.
                with self._cond:
                    queued = list(self._events)
                if all(k == "char" for k, _ in queued):
                    tail = "".join(v for _, v in queued)
                    edit = self.buffer.on_char(value, pending_tail=tail)
                    if edit and self._on_fix:
                        try:
                            self._on_fix(self.buffer.last_fixes)
                        except Exception:
                            pass
                else:
                    self.buffer.text = (self.buffer.text + value)[-MAX_BUFFER:]

            if edit and (edit[0] > 0 or edit[1]):
                send_direct_edit(edit[0], edit[1], extra_info=INPUT_MAGIC)
