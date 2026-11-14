#include "flutter_window.h"

#include <dwmapi.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr UINT_PTR kHitTestTimerId = 1001;
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {
  interactive_rects_.push_back({100.0, 100.0, 600.0, 600.0});
}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  HWND child_hwnd = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(child_hwnd);
  MARGINS margins = {-1, -1, -1, -1};
  DwmExtendFrameIntoClientArea(child_hwnd, &margins);

  // Also set WS_EX_NOACTIVATE on child_hwnd so clicking inside Flutter does not
  // steal keyboard focus from the external editor window.
  LONG_PTR child_ex = GetWindowLongPtr(child_hwnd, GWL_EXSTYLE);
  SetWindowLongPtr(child_hwnd, GWL_EXSTYLE, child_ex | WS_EX_NOACTIVATE);

  last_external_hwnd_ = FindTopExternalWindow();

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "vtt_assistant/window",
          &flutter::StandardMethodCodec::GetInstance());

  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setInteractiveRects") {
          const auto* list =
              std::get_if<flutter::EncodableList>(call.arguments());
          if (list) {
            interactive_rects_.clear();
            for (const auto& item : *list) {
              const auto* rect_list =
                  std::get_if<flutter::EncodableList>(&item);
              if (rect_list && rect_list->size() >= 4) {
                auto get_num = [](const flutter::EncodableValue& v) -> double {
                  if (auto* d = std::get_if<double>(&v)) return *d;
                  if (auto* i = std::get_if<int32_t>(&v)) return static_cast<double>(*i);
                  if (auto* l = std::get_if<int64_t>(&v)) return static_cast<double>(*l);
                  return 0.0;
                };
                InteractiveRect r{
                    get_num((*rect_list)[0]),
                    get_num((*rect_list)[1]),
                    get_num((*rect_list)[2]),
                    get_num((*rect_list)[3]),
                };
                interactive_rects_.push_back(r);
              }
            }
            UpdateHitTest();
          }
          result->Success();
        } else if (call.method_name() == "setAllowFocus") {
          if (auto* b = std::get_if<bool>(call.arguments())) {
            allow_window_focus_ = *b;
            HWND hwnd = GetHandle();
            HWND child = flutter_controller_ ? flutter_controller_->view()->GetNativeWindow() : nullptr;
            if (hwnd) {
              LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
              if (allow_window_focus_) {
                SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style & ~WS_EX_NOACTIVATE);
                if (child) {
                  LONG_PTR cex = GetWindowLongPtr(child, GWL_EXSTYLE);
                  SetWindowLongPtr(child, GWL_EXSTYLE, cex & ~WS_EX_NOACTIVATE);
                }
                SetForegroundWindow(hwnd);
                if (child) SetFocus(child);
              } else {
                SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style | WS_EX_NOACTIVATE);
                if (child) {
                  LONG_PTR cex = GetWindowLongPtr(child, GWL_EXSTYLE);
                  SetWindowLongPtr(child, GWL_EXSTYLE, cex | WS_EX_NOACTIVATE);
                }
                RestoreExternalWindowFocus();
              }
            }
          }
          result->Success();
        } else if (call.method_name() == "restoreExternalFocus") {
          RestoreExternalWindowFocus();
          result->Success();
        } else if (call.method_name() == "typeInPlace") {
          int backspaces = 0;
          std::string text;
          if (const auto* map = std::get_if<flutter::EncodableMap>(call.arguments())) {
            auto bs_it = map->find(flutter::EncodableValue("backspaces"));
            if (bs_it != map->end()) {
              if (auto* i = std::get_if<int32_t>(&bs_it->second)) backspaces = *i;
              else if (auto* l = std::get_if<int64_t>(&bs_it->second)) backspaces = static_cast<int>(*l);
            }
            auto txt_it = map->find(flutter::EncodableValue("text"));
            if (txt_it != map->end()) {
              if (auto* s = std::get_if<std::string>(&txt_it->second)) text = *s;
            }
          }
          bool ok = TypeInPlace(backspaces, text);
          result->Success(flutter::EncodableValue(ok));
        } else if (call.method_name() == "pasteToExternal") {
          std::string text;
          if (auto* s = std::get_if<std::string>(call.arguments())) {
            text = *s;
          } else if (const auto* map = std::get_if<flutter::EncodableMap>(call.arguments())) {
            auto txt_it = map->find(flutter::EncodableValue("text"));
            if (txt_it != map->end()) {
              if (auto* str_val = std::get_if<std::string>(&txt_it->second)) text = *str_val;
            }
          }
          bool ok = PasteTextToExternal(text);
          result->Success(flutter::EncodableValue(ok));
        } else if (call.method_name() == "quitApp") {
          PostQuitMessage(0);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  SetTimer(GetHandle(), kHitTestTimerId, 20, nullptr);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  KillTimer(GetHandle(), kHitTestTimerId);
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

HWND FlutterWindow::FindTopExternalWindow() {
  DWORD self_pid = GetCurrentProcessId();
  HWND cur = GetTopWindow(nullptr);
  while (cur) {
    if (IsWindowVisible(cur) && !IsIconic(cur)) {
      DWORD pid = 0;
      GetWindowThreadProcessId(cur, &pid);
      if (pid != 0 && pid != self_pid) {
        LONG_PTR ex = GetWindowLongPtr(cur, GWL_EXSTYLE);
        if ((ex & WS_EX_TOOLWINDOW) == 0) {
          wchar_t cls[64] = {0};
          GetClassNameW(cur, cls, 63);
          std::wstring wcls(cls);
          if (wcls != L"Shell_TrayWnd" && wcls != L"Progman" &&
              wcls != L"WorkerW" && GetWindowTextLengthW(cur) > 0) {
            return cur;
          }
        }
      }
    }
    cur = GetWindow(cur, GW_HWNDNEXT);
  }
  return nullptr;
}

void FlutterWindow::RestoreExternalWindowFocus() {
  if (!last_external_hwnd_ || !IsWindow(last_external_hwnd_)) {
    last_external_hwnd_ = FindTopExternalWindow();
  }
  if (last_external_hwnd_ && IsWindow(last_external_hwnd_)) {
    HWND fg = GetForegroundWindow();
    if (fg != last_external_hwnd_) {
      DWORD cur_thread = GetCurrentThreadId();
      DWORD fg_thread = fg ? GetWindowThreadProcessId(fg, nullptr) : 0;
      DWORD target_thread = GetWindowThreadProcessId(last_external_hwnd_, nullptr);
      bool attached_fg = false;
      bool attached_target = false;
      if (fg_thread && fg_thread != cur_thread) {
        attached_fg = AttachThreadInput(cur_thread, fg_thread, TRUE) != 0;
      }
      if (target_thread && target_thread != cur_thread) {
        attached_target = AttachThreadInput(cur_thread, target_thread, TRUE) != 0;
      }
      BringWindowToTop(last_external_hwnd_);
      SetForegroundWindow(last_external_hwnd_);
      if (attached_target) {
        AttachThreadInput(cur_thread, target_thread, FALSE);
      }
      if (attached_fg) {
        AttachThreadInput(cur_thread, fg_thread, FALSE);
      }
    }
  }
}

bool FlutterWindow::TypeInPlace(int backspaces, const std::string& utf8_text) {
  if (backspaces <= 0 && utf8_text.empty()) {
    return true;
  }
  HWND prev_fg = GetForegroundWindow();
  RestoreExternalWindowFocus();
  if (last_external_hwnd_ && prev_fg != last_external_hwnd_) {
    Sleep(22);
  }

  UINT total_sent = 0;

  // 1. Send backspaces via VK_BACK and wait 25ms so WinUI 3 / RichEdit finishes deleting
  if (backspaces > 0) {
    int remaining = backspaces;
    while (remaining > 0) {
      int batch = (remaining > 8) ? 8 : remaining;
      std::vector<INPUT> bs_inputs;
      bs_inputs.reserve(batch * 2);
      for (int i = 0; i < batch; ++i) {
        INPUT down = {};
        down.type = INPUT_KEYBOARD;
        down.ki.wVk = VK_BACK;
        bs_inputs.push_back(down);

        INPUT up = {};
        up.type = INPUT_KEYBOARD;
        up.ki.wVk = VK_BACK;
        up.ki.dwFlags = KEYEVENTF_KEYUP;
        bs_inputs.push_back(up);
      }
      total_sent += ::SendInput(static_cast<UINT>(bs_inputs.size()),
                                bs_inputs.data(), sizeof(INPUT));
      remaining -= batch;
      if (remaining > 0) {
        Sleep(5);
      }
    }
    if (!utf8_text.empty()) {
      Sleep(25);
    }
  }

  // 2. Inject replacement text atomically via Clipboard Paste (Ctrl+V) so WinUI 3
  // Notepad / Word / browsers never drop, reorder, or garble characters.
  if (!utf8_text.empty()) {
    int wlen = MultiByteToWideChar(CP_UTF8, 0, utf8_text.data(),
                                   static_cast<int>(utf8_text.size()), nullptr, 0);
    if (wlen > 0) {
      bool clipboard_ok = false;
      for (int attempt = 0; attempt < 5; ++attempt) {
        if (OpenClipboard(GetHandle())) {
          EmptyClipboard();
          HGLOBAL h_mem = GlobalAlloc(GMEM_MOVEABLE, (wlen + 1) * sizeof(wchar_t));
          if (h_mem) {
            wchar_t* ptr = static_cast<wchar_t*>(GlobalLock(h_mem));
            if (ptr) {
              MultiByteToWideChar(CP_UTF8, 0, utf8_text.data(),
                                  static_cast<int>(utf8_text.size()), ptr, wlen);
              ptr[wlen] = L'\0';
              GlobalUnlock(h_mem);
              if (SetClipboardData(CF_UNICODETEXT, h_mem)) {
                clipboard_ok = true;
              }
            } else {
              GlobalFree(h_mem);
            }
          }
          CloseClipboard();
          break;
        }
        Sleep(3);
      }

      if (clipboard_ok) {
        Sleep(6);
        INPUT paste_inputs[4] = {};
        paste_inputs[0].type = INPUT_KEYBOARD;
        paste_inputs[0].ki.wVk = VK_CONTROL;
        paste_inputs[1].type = INPUT_KEYBOARD;
        paste_inputs[1].ki.wVk = 'V';
        paste_inputs[2].type = INPUT_KEYBOARD;
        paste_inputs[2].ki.wVk = 'V';
        paste_inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;
        paste_inputs[3].type = INPUT_KEYBOARD;
        paste_inputs[3].ki.wVk = VK_CONTROL;
        paste_inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;
        total_sent += ::SendInput(4, paste_inputs, sizeof(INPUT));
        Sleep(28);
      }
    }
  }

  return total_sent > 0;
}

bool FlutterWindow::PasteTextToExternal(const std::string& utf8_text) {
  if (utf8_text.empty()) return false;
  int wlen = MultiByteToWideChar(CP_UTF8, 0, utf8_text.data(),
                                 static_cast<int>(utf8_text.size()), nullptr, 0);
  if (wlen <= 0) return false;

  if (OpenClipboard(GetHandle())) {
    EmptyClipboard();
    HGLOBAL h_mem = GlobalAlloc(GMEM_MOVEABLE, (wlen + 1) * sizeof(wchar_t));
    if (h_mem) {
      wchar_t* ptr = static_cast<wchar_t*>(GlobalLock(h_mem));
      if (ptr) {
        MultiByteToWideChar(CP_UTF8, 0, utf8_text.data(),
                            static_cast<int>(utf8_text.size()), ptr, wlen);
        ptr[wlen] = L'\0';
        GlobalUnlock(h_mem);
        SetClipboardData(CF_UNICODETEXT, h_mem);
      } else {
        GlobalFree(h_mem);
      }
    }
    CloseClipboard();
  }

  RestoreExternalWindowFocus();
  Sleep(20);

  INPUT inputs[4] = {};
  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = VK_CONTROL;
  inputs[1].type = INPUT_KEYBOARD;
  inputs[1].ki.wVk = 'V';
  inputs[2].type = INPUT_KEYBOARD;
  inputs[2].ki.wVk = 'V';
  inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;
  inputs[3].type = INPUT_KEYBOARD;
  inputs[3].ki.wVk = VK_CONTROL;
  inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;

  UINT sent = ::SendInput(4, inputs, sizeof(INPUT));
  return sent > 0;
}

void FlutterWindow::UpdateHitTest() {
  HWND hwnd = GetHandle();
  if (!hwnd) return;

  // Track active external window by PID and immediately yield focus back if our
  // overlay accidentally became foreground while allow_window_focus_ is false.
  HWND fg = GetForegroundWindow();
  bool lbutton_down = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
  DWORD self_pid = GetCurrentProcessId();
  DWORD fg_pid = 0;
  if (fg) {
    GetWindowThreadProcessId(fg, &fg_pid);
  }
  if (fg && fg_pid != 0 && fg_pid != self_pid) {
    wchar_t cls[64] = {0};
    GetClassNameW(fg, cls, 63);
    std::wstring wcls(cls);
    if (wcls != L"Shell_TrayWnd" && wcls != L"Progman" && wcls != L"WorkerW") {
      last_external_hwnd_ = fg;
    }
  } else if (!allow_window_focus_ && !lbutton_down && fg && fg_pid == self_pid) {
    RestoreExternalWindowFocus();
  }

  POINT cursor;
  if (!GetCursorPos(&cursor)) return;

  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale = (dpi > 0) ? (dpi / 96.0) : 1.0;

  double lx = cursor.x / scale;
  double ly = cursor.y / scale;

  bool inside_interactive = false;
  for (const auto& r : interactive_rects_) {
    if (lx >= r.x && lx <= (r.x + r.width) &&
        ly >= r.y && ly <= (r.y + r.height)) {
      inside_interactive = true;
      break;
    }
  }

  bool should_click_through = !inside_interactive;
  if (should_click_through != is_click_through_) {
    LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
    if (should_click_through) {
      SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style | WS_EX_TRANSPARENT);
    } else {
      SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style & ~WS_EX_TRANSPARENT);
    }
    is_click_through_ = should_click_through;
  }

  if (lbutton_down && !prev_lbutton_down_ && should_click_through && window_channel_) {
    HWND clicked_wnd = WindowFromPoint(cursor);
    if (clicked_wnd) {
      HWND root_wnd = GetAncestor(clicked_wnd, GA_ROOT);
      if (!root_wnd) root_wnd = clicked_wnd;
      DWORD clicked_pid = 0;
      GetWindowThreadProcessId(root_wnd, &clicked_pid);
      if (clicked_pid != 0 && clicked_pid != self_pid) {
        last_external_hwnd_ = root_wnd;
      }
    }
    flutter::EncodableMap args;
    args[flutter::EncodableValue("x")] = flutter::EncodableValue(lx);
    args[flutter::EncodableValue("y")] = flutter::EncodableValue(ly);
    args[flutter::EncodableValue("physX")] =
        flutter::EncodableValue(static_cast<int32_t>(cursor.x));
    args[flutter::EncodableValue("physY")] =
        flutter::EncodableValue(static_cast<int32_t>(cursor.y));
    window_channel_->InvokeMethod(
        "onExternalScreenClick",
        std::make_unique<flutter::EncodableValue>(args));
  }
  prev_lbutton_down_ = lbutton_down;
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_TIMER && wparam == kHitTestTimerId) {
    UpdateHitTest();
    return 0;
  }
  if (message == WM_MOUSEACTIVATE && !allow_window_focus_) {
    return MA_NOACTIVATE;
  }

  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
