#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <iostream>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr UINT_PTR kCursorTimerId = 1;
// ~60 Hz. Windows timers tick at ~15.6 ms anyway.
constexpr UINT kCursorTimerMs = 16;

// The hook callback is a plain function: it reaches the window through this.
FlutterWindow* g_hook_window = nullptr;

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "mikky/overlay",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });

  // Event driven: called on each mouse event, nothing runs when the mouse is
  // still. If it fails the island still works on hover and click, only the
  // gaze stops following the cursor outside the window.
  g_hook_window = this;
  mouse_hook_ = SetWindowsHookEx(WH_MOUSE_LL, LowLevelMouseProc,
                                 GetModuleHandle(nullptr), 0);
  if (!mouse_hook_) {
    std::cerr << "mikky: mouse hook failed, error " << GetLastError()
              << std::endl;
    g_hook_window = nullptr;
  }

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (mouse_hook_) {
    UnhookWindowsHookEx(mouse_hook_);
    mouse_hook_ = nullptr;
  }
  g_hook_window = nullptr;
  channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

// static
LRESULT CALLBACK FlutterWindow::LowLevelMouseProc(int code, WPARAM wparam,
                                                  LPARAM lparam) {
  if (code == HC_ACTION && wparam == WM_MOUSEMOVE && g_hook_window) {
    // Physical screen coordinates: the process is per-monitor DPI aware (v2).
    g_hook_window->OnGlobalCursor(
        reinterpret_cast<MSLLHOOKSTRUCT*>(lparam)->pt);
  }
  return CallNextHookEx(nullptr, code, wparam, lparam);
}

void FlutterWindow::OnGlobalCursor(POINT screen_point) {
  // Runs before the system dispatches this move, so the window's hit-test
  // state is already right for it.
  UpdateClickThrough(screen_point);
  last_cursor_ = screen_point;
  if (!cursor_timer_pending_) {
    cursor_timer_pending_ = true;
    SetTimer(GetHandle(), kCursorTimerId, kCursorTimerMs, nullptr);
  }
}

void FlutterWindow::UpdateClickThrough(POINT screen_point) {
  const double scale = scale_factor();
  const POINT origin = this->origin();
  const double x = (screen_point.x - origin.x) / scale;
  const double y = (screen_point.y - origin.y) / scale;
  const bool inside = hit_w_ > 0 && hit_h_ > 0 && x >= hit_x_ &&
                      x < hit_x_ + hit_w_ && y >= hit_y_ &&
                      y < hit_y_ + hit_h_;
  if (inside == !click_through_) {
    return;
  }
  click_through_ = !inside;
  HWND hwnd = GetHandle();
  LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  if (click_through_) {
    ex_style |= WS_EX_TRANSPARENT;
  } else {
    ex_style &= ~WS_EX_TRANSPARENT;
  }
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);
}

void FlutterWindow::FlushCursor() {
  KillTimer(GetHandle(), kCursorTimerId);
  cursor_timer_pending_ = false;
  if (!channel_ || (last_cursor_.x == sent_cursor_.x &&
                    last_cursor_.y == sent_cursor_.y)) {
    return;
  }
  sent_cursor_ = last_cursor_;
  const double scale = scale_factor();
  const POINT origin = this->origin();
  channel_->InvokeMethod(
      "cursor", std::make_unique<flutter::EncodableValue>(
                    flutter::EncodableList{
                        flutter::EncodableValue((last_cursor_.x - origin.x) /
                                                scale),
                        flutter::EncodableValue((last_cursor_.y - origin.y) /
                                                scale),
                    }));
}

void FlutterWindow::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "setHitRect") {
    const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
    if (!args || args->size() != 4) {
      result->Error("bad_args", "setHitRect expects [x, y, w, h]");
      return;
    }
    double values[4];
    for (size_t i = 0; i < 4; ++i) {
      const auto* v = std::get_if<double>(&(*args)[i]);
      if (!v) {
        result->Error("bad_args", "setHitRect expects doubles");
        return;
      }
      values[i] = *v;
    }
    hit_x_ = values[0];
    hit_y_ = values[1];
    hit_w_ = values[2];
    hit_h_ = values[3];
    // The shape may have moved under a still cursor.
    POINT cursor;
    if (GetCursorPos(&cursor)) {
      UpdateClickThrough(cursor);
    }
    result->Success();
  } else if (call.method_name() == "quit") {
    result->Success();
    PostMessage(GetHandle(), WM_CLOSE, 0, 0);
  } else {
    result->NotImplemented();
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
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
    case WM_TIMER:
      if (wparam == kCursorTimerId) {
        FlushCursor();
        return 0;
      }
      break;
    case WM_MOUSEACTIVATE:
      // Clicking the island must not steal focus from the user's app.
      return MA_NOACTIVATE;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
