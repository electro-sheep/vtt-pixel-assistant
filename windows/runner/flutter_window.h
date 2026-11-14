#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <vector>

#include "win32_window.h"

struct InteractiveRect {
  double x;
  double y;
  double width;
  double height;
};

// A window that hosts a transparent full-screen click-through Flutter view.
class FlutterWindow : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void UpdateHitTest();
  HWND FindTopExternalWindow();
  void RestoreExternalWindowFocus();
  bool TypeInPlace(int backspaces, const std::string& utf8_text);
  bool PasteTextToExternal(const std::string& utf8_text);

  flutter::DartProject project_;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> window_channel_;
  std::vector<InteractiveRect> interactive_rects_;
  bool is_click_through_ = false;
  bool prev_lbutton_down_ = false;
  bool allow_window_focus_ = false;
  HWND last_external_hwnd_ = nullptr;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
