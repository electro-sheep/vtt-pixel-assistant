"""
Win32 Keyboard Injection, Active Target Window Tracker, Chunk-Safe In-Place Diff Writer,
Cursor Tracker, Global F8 Hotkey Monitor, Clipboard Manager, and Local TTS Read-Aloud.
"""

from __future__ import annotations
import ctypes
from ctypes import wintypes
import subprocess
import threading
import time
from typing import Callable, Optional, Tuple

user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

INPUT_KEYBOARD = 1
KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_UNICODE = 0x0004
VK_BACK = 0x08
VK_RETURN = 0x0D
VK_CONTROL = 0x11
VK_C = 0x43
VK_V = 0x56
VK_F8 = 0x77
CF_UNICODETEXT = 13
GA_ROOT = 2
GMEM_MOVEABLE = 0x0002

ULONG_PTR = wintypes.WPARAM


class POINT(ctypes.Structure):
    _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long)]


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [
        ("dx", wintypes.LONG),
        ("dy", wintypes.LONG),
        ("mouseData", wintypes.DWORD),
        ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ULONG_PTR),
    ]


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk", wintypes.WORD),
        ("wScan", wintypes.WORD),
        ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ULONG_PTR),
    ]


class HARDWAREINPUT(ctypes.Structure):
    _fields_ = [
        ("uMsg", wintypes.DWORD),
        ("wParamL", wintypes.WORD),
        ("wParamH", wintypes.WORD),
    ]


class _INPUT_UNION(ctypes.Union):
    _fields_ = [
        ("mi", MOUSEINPUT),
        ("ki", KEYBDINPUT),
        ("hi", HARDWAREINPUT),
    ]


class INPUT(ctypes.Structure):
    _anonymous_ = ("_u",)
    _fields_ = [
        ("type", wintypes.DWORD),
        ("_u", _INPUT_UNION),
    ]


user32.GetCursorPos.argtypes = [ctypes.POINTER(POINT)]
user32.GetCursorPos.restype = wintypes.BOOL
user32.WindowFromPoint.argtypes = [POINT]
user32.WindowFromPoint.restype = wintypes.HWND
user32.GetAncestor.argtypes = [wintypes.HWND, wintypes.UINT]
user32.GetAncestor.restype = wintypes.HWND
user32.GetForegroundWindow.argtypes = []
user32.GetForegroundWindow.restype = wintypes.HWND
user32.SetForegroundWindow.argtypes = [wintypes.HWND]
user32.SetForegroundWindow.restype = wintypes.BOOL
user32.BringWindowToTop.argtypes = [wintypes.HWND]
user32.BringWindowToTop.restype = wintypes.BOOL
user32.AttachThreadInput.argtypes = [wintypes.DWORD, wintypes.DWORD, wintypes.BOOL]
user32.AttachThreadInput.restype = wintypes.BOOL
user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
user32.GetWindowThreadProcessId.restype = wintypes.DWORD
user32.GetTopWindow.argtypes = [wintypes.HWND]
user32.GetTopWindow.restype = wintypes.HWND
user32.GetWindow.argtypes = [wintypes.HWND, wintypes.UINT]
user32.GetWindow.restype = wintypes.HWND
user32.IsWindowVisible.argtypes = [wintypes.HWND]
user32.IsWindowVisible.restype = wintypes.BOOL
user32.IsIconic.argtypes = [wintypes.HWND]
user32.IsIconic.restype = wintypes.BOOL
user32.GetWindowTextLengthW.argtypes = [wintypes.HWND]
user32.GetWindowTextLengthW.restype = ctypes.c_int
user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
user32.GetWindowTextW.restype = ctypes.c_int
user32.GetAsyncKeyState.argtypes = [ctypes.c_int]
user32.GetAsyncKeyState.restype = ctypes.c_short
kernel32.GetCurrentThreadId.argtypes = []
kernel32.GetCurrentThreadId.restype = wintypes.DWORD

user32.OpenClipboard.argtypes = [wintypes.HWND]
user32.OpenClipboard.restype = wintypes.BOOL
user32.CloseClipboard.argtypes = []
user32.CloseClipboard.restype = wintypes.BOOL
user32.EmptyClipboard.argtypes = []
user32.EmptyClipboard.restype = wintypes.BOOL
user32.GetClipboardData.argtypes = [wintypes.UINT]
user32.GetClipboardData.restype = wintypes.HANDLE
user32.SetClipboardData.argtypes = [wintypes.UINT, wintypes.HANDLE]
user32.SetClipboardData.restype = wintypes.HANDLE

kernel32.GlobalAlloc.argtypes = [wintypes.UINT, ctypes.c_size_t]
kernel32.GlobalAlloc.restype = wintypes.HGLOBAL
kernel32.GlobalLock.argtypes = [wintypes.HGLOBAL]
kernel32.GlobalLock.restype = ctypes.c_void_p
kernel32.GlobalUnlock.argtypes = [wintypes.HGLOBAL]
kernel32.GlobalUnlock.restype = wintypes.BOOL


def get_cursor_pos() -> Tuple[int, int]:
    pt = POINT()
    if user32.GetCursorPos(ctypes.byref(pt)):
        return int(pt.x), int(pt.y)
    return 0, 0


def get_window_title(hwnd: Optional[int]) -> str:
    if not hwnd:
        return ""
    length = user32.GetWindowTextLengthW(hwnd)
    if length <= 0:
        return ""
    buf = ctypes.create_unicode_buffer(length + 1)
    user32.GetWindowTextW(hwnd, buf, length + 1)
    return buf.value.strip()


class TargetWindowTracker:
    """
    Continuously tracks the last active external application window, mouse cursor
    coordinates, and the global F8 dictation hotkey.
    """

    def __init__(self) -> None:
        self.last_external_hwnd: Optional[int] = None
        self.last_external_title: str = "Active Window"
        self.cursor_x: int = 500
        self.cursor_y: int = 500
        self.on_hotkey_f8: Optional[Callable[[], None]] = None
        self._prev_f8_down: bool = False
        self._running = True
        self._discover_initial_window()
        self._thread = threading.Thread(target=self._poll_loop, daemon=True)
        self._thread.start()

    def _is_assistant_window(self, hwnd: Optional[int], title: str) -> bool:
        if not hwnd:
            return True
        low = title.lower().strip()
        if not low:
            return True
        return (
            "vtt_assistant" in low
            or "vtt pixel assistant" in low
            or low in ("program manager", "task switching", "windows input experience")
        )

    def _discover_initial_window(self) -> None:
        try:
            cur = user32.GetTopWindow(None)
            while cur:
                if user32.IsWindowVisible(cur) and not user32.IsIconic(cur):
                    title = get_window_title(cur)
                    if title and not self._is_assistant_window(cur, title):
                        self.last_external_hwnd = cur
                        self.last_external_title = title[:42]
                        return
                cur = user32.GetWindow(cur, 2)  # GW_HWNDNEXT = 2
        except Exception:
            pass

    def _poll_loop(self) -> None:
        while self._running:
            time.sleep(0.06)
            self.cursor_x, self.cursor_y = get_cursor_pos()

            # Check F8 global hotkey toggle
            f8_down = (user32.GetAsyncKeyState(VK_F8) & 0x8000) != 0
            if f8_down and not self._prev_f8_down and self.on_hotkey_f8:
                try:
                    self.on_hotkey_f8()
                except Exception:
                    pass
            self._prev_f8_down = f8_down

            hwnd = user32.GetForegroundWindow()
            if hwnd:
                title = get_window_title(hwnd)
                if not self._is_assistant_window(hwnd, title):
                    self.last_external_hwnd = hwnd
                    if title:
                        self.last_external_title = title[:42]

    def lock_window_at_point(self, x: int, y: int) -> Tuple[Optional[int], str]:
        pt = POINT(x=int(x), y=int(y))
        hwnd = user32.WindowFromPoint(pt)
        if hwnd:
            root = user32.GetAncestor(hwnd, GA_ROOT) or hwnd
            title = get_window_title(root) or get_window_title(hwnd)
            if not self._is_assistant_window(root, title):
                self.last_external_hwnd = root
                self.last_external_title = (title or "Selected Text Area")[:42]
                return root, self.last_external_title
        return self.last_external_hwnd, self.last_external_title

    def ensure_external_focused(self) -> None:
        if not self.last_external_hwnd:
            self._discover_initial_window()
        if not self.last_external_hwnd:
            return
        fg = user32.GetForegroundWindow()
        if fg != self.last_external_hwnd:
            cur_thread = kernel32.GetCurrentThreadId()
            fg_thread = user32.GetWindowThreadProcessId(fg, None) if fg else 0
            target_thread = user32.GetWindowThreadProcessId(self.last_external_hwnd, None)
            attached_fg = False
            attached_target = False
            if fg_thread and fg_thread != cur_thread:
                attached_fg = bool(user32.AttachThreadInput(cur_thread, fg_thread, True))
            if target_thread and target_thread != cur_thread:
                attached_target = bool(user32.AttachThreadInput(cur_thread, target_thread, True))
            user32.BringWindowToTop(self.last_external_hwnd)
            user32.SetForegroundWindow(self.last_external_hwnd)
            if attached_target:
                user32.AttachThreadInput(cur_thread, target_thread, False)
            if attached_fg:
                user32.AttachThreadInput(cur_thread, fg_thread, False)
            time.sleep(0.020)


window_tracker = TargetWindowTracker()


def _make_vk_input(vk: int, key_up: bool = False) -> INPUT:
    flags = KEYEVENTF_KEYUP if key_up else 0
    return INPUT(
        type=INPUT_KEYBOARD,
        ki=KEYBDINPUT(wVk=vk, wScan=0, dwFlags=flags, time=0, dwExtraInfo=0),
    )


def _make_unicode_input(char_code: int, key_up: bool = False) -> INPUT:
    flags = KEYEVENTF_UNICODE | (KEYEVENTF_KEYUP if key_up else 0)
    return INPUT(
        type=INPUT_KEYBOARD,
        ki=KEYBDINPUT(wVk=0, wScan=char_code, dwFlags=flags, time=0, dwExtraInfo=0),
    )


def _send_input_batch(inputs: list[INPUT], chunk_size: int = 32) -> None:
    """
    Dispatches INPUT structures in paced chunks of `chunk_size` (16 keystrokes)
    so modern Chromium/Electron/Word text buffers never drop characters during
    fast backspacing and rewriting.
    """
    if not inputs:
        return
    for i in range(0, len(inputs), chunk_size):
        chunk = inputs[i : i + chunk_size]
        array_type = INPUT * len(chunk)
        input_array = array_type(*chunk)
        user32.SendInput(len(chunk), ctypes.byref(input_array), ctypes.sizeof(INPUT))
        if i + chunk_size < len(inputs):
            time.sleep(0.002)


def apply_in_place_screen_edit(backspaces: int, text_to_type: str) -> None:
    """
    Ensures the target external window has focus, then sends `backspaces` VK_BACK
    keystrokes followed by atomic Clipboard Paste (Ctrl+V) for `text_to_type`.
    """
    window_tracker.ensure_external_focused()

    # 1. Send backspaces first so the target editor processes deletions cleanly
    if backspaces > 0:
        bs_inputs: list[INPUT] = []
        for _ in range(backspaces):
            bs_inputs.append(_make_vk_input(VK_BACK, key_up=False))
            bs_inputs.append(_make_vk_input(VK_BACK, key_up=True))
        _send_input_batch(bs_inputs, chunk_size=16)
        if text_to_type:
            time.sleep(0.025)

    # 2. Paste replacement text atomically via Clipboard (Ctrl+V)
    if text_to_type:
        set_clipboard_text(text_to_type)
        time.sleep(0.006)
        paste_inputs = [
            _make_vk_input(VK_CONTROL, key_up=False),
            _make_vk_input(VK_V, key_up=False),
            _make_vk_input(VK_V, key_up=True),
            _make_vk_input(VK_CONTROL, key_up=True),
        ]
        _send_input_batch(paste_inputs)
        time.sleep(0.028)


def get_clipboard_text() -> str:
    """Read current Unicode text from the Windows clipboard."""
    try:
        if not user32.OpenClipboard(None):
            return ""
        try:
            handle = user32.GetClipboardData(CF_UNICODETEXT)
            if not handle:
                return ""
            ptr = kernel32.GlobalLock(handle)
            if not ptr:
                return ""
            try:
                return ctypes.wstring_at(ptr)
            finally:
                kernel32.GlobalUnlock(handle)
        finally:
            user32.CloseClipboard()
    except Exception:
        return ""


def set_clipboard_text(text: str) -> None:
    """Write Unicode text to the Windows clipboard."""
    if not text:
        return
    try:
        if not user32.OpenClipboard(None):
            return
        try:
            user32.EmptyClipboard()
            data = text.encode("utf-16-le") + b"\x00\x00"
            h_mem = kernel32.GlobalAlloc(GMEM_MOVEABLE, len(data))
            if not h_mem:
                return
            ptr = kernel32.GlobalLock(h_mem)
            if ptr:
                ctypes.memmove(ptr, data, len(data))
                kernel32.GlobalUnlock(h_mem)
                user32.SetClipboardData(CF_UNICODETEXT, h_mem)
        finally:
            user32.CloseClipboard()
    except Exception:
        pass


def capture_highlighted_screen_text() -> str:
    """Focus external window, send Ctrl+C, and return the copied text."""
    window_tracker.ensure_external_focused()
    inputs = [
        _make_vk_input(VK_CONTROL, key_up=False),
        _make_vk_input(VK_C, key_up=False),
        _make_vk_input(VK_C, key_up=True),
        _make_vk_input(VK_CONTROL, key_up=True),
    ]
    _send_input_batch(inputs)
    time.sleep(0.09)
    return get_clipboard_text()


def speak_text_aloud_async(text: str) -> None:
    """Speak text aloud using Windows built-in SpeechSynthesizer in a background thread."""
    clean = text.replace("'", " ").replace('"', " ").strip()
    if not clean:
        return

    def _run() -> None:
        cmd = (
            "Add-Type -AssemblyName System.Speech; "
            "$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; "
            "$s.Rate = 1; "
            f"$s.Speak('{clean}')"
        )
        subprocess.run(
            ["powershell", "-NoProfile", "-WindowStyle", "Hidden", "-Command", cmd],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )

    threading.Thread(target=_run, daemon=True).start()
