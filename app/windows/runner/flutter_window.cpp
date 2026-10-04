#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <shobjidl.h>

#include <iostream>
#include <string>
#include <optional>
#include <set>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT_PTR kCursorTimerId = 1;
// ~60 Hz. Windows timers tick at ~15.6 ms anyway.
constexpr UINT kCursorTimerMs = 16;
// Windows silently drops a low-level hook that once answered too slowly
// (a busy moment, a debug build): Mikky then stops following the mouse
// (user report, 2026-09-30). Every 1.5 s, if the cursor moved without the
// hook hearing it, the hook is put back.
constexpr UINT_PTR kHookWatchTimerId = 2;
// When the sounds playing should be over: their voices are freed, and the
// audio engine stops once none is left.
constexpr UINT_PTR kSoundTimerId = 3;
constexpr UINT kHookWatchMs = 1500;
// Posted by the hook, handled in the window procedure: the hook itself must
// not call into Flutter.
constexpr UINT kOutsideClickMessage = WM_APP + 1;
// From the icon in the notification area.
constexpr UINT kTrayMessage = WM_APP + 2;
// Sent to every window when Explorer restarts: the icon must be added again.
const UINT kTaskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");

// The hook callback is a plain function: it reaches the window through this.
FlutterWindow* g_hook_window = nullptr;

std::string Utf8FromUtf16(const std::wstring& utf16) {
  if (utf16.empty()) {
    return std::string();
  }
  const int length = WideCharToMultiByte(CP_UTF8, 0, utf16.data(),
                                         static_cast<int>(utf16.size()),
                                         nullptr, 0, nullptr, nullptr);
  std::string utf8(length, '\0');
  WideCharToMultiByte(CP_UTF8, 0, utf16.data(),
                      static_cast<int>(utf16.size()), utf8.data(), length,
                      nullptr, nullptr);
  return utf8;
}

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  const int length = MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring utf16(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      utf16.data(), length);
  return utf16;
}

// Windows' folder picker, owned by |owner|. Empty if cancelled.
std::string PickFolder(HWND owner, const std::string& title) {
  std::string chosen;
  IFileOpenDialog* dialog = nullptr;
  if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_ALL,
                              IID_PPV_ARGS(&dialog)))) {
    return chosen;
  }
  DWORD options = 0;
  dialog->GetOptions(&options);
  dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM);
  if (!title.empty()) {
    dialog->SetTitle(Utf16FromUtf8(title).c_str());
  }
  if (SUCCEEDED(dialog->Show(owner))) {
    IShellItem* item = nullptr;
    if (SUCCEEDED(dialog->GetResult(&item))) {
      PWSTR path = nullptr;
      if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) {
        chosen = Utf8FromUtf16(path);
        CoTaskMemFree(path);
      }
      item->Release();
    }
  }
  dialog->Release();
  return chosen;
}

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
  // The tuning screen is an ordinary window: no hook.
  if (is_overlay()) {
    AddTrayIcon();
    g_hook_window = this;
    mouse_hook_ = SetWindowsHookEx(WH_MOUSE_LL, LowLevelMouseProc,
                                   GetModuleHandle(nullptr), 0);
  }
  if (is_overlay() && !mouse_hook_) {
    std::cerr << "mikky: mouse hook failed, error " << GetLastError()
              << std::endl;
    g_hook_window = nullptr;
  }
  if (is_overlay() && mouse_hook_) {
    SetTimer(GetHandle(), kHookWatchTimerId, kHookWatchMs, nullptr);
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

void FlutterWindow::AddTrayIcon() {
  tray_.cbSize = sizeof(tray_);
  tray_.hWnd = GetHandle();
  tray_.uID = 1;
  tray_.uFlags = NIF_ICON | NIF_TIP | NIF_MESSAGE | NIF_SHOWTIP;
  tray_.uCallbackMessage = kTrayMessage;
  tray_.hIcon = static_cast<HICON>(LoadImageW(
      GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
      GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), 0));
  wcscpy_s(tray_.szTip, L"Mikky");
  tray_added_ = Shell_NotifyIconW(NIM_ADD, &tray_) != FALSE;
  if (tray_added_) {
    // Version 4: a left click comes as NIN_SELECT, a right one as
    // WM_CONTEXTMENU, a click on a balloon as NIN_BALLOONUSERCLICK.
    tray_.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &tray_);
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (tray_added_) {
    Shell_NotifyIconW(NIM_DELETE, &tray_);
    tray_added_ = false;
  }
  if (tray_.hIcon) {
    DestroyIcon(tray_.hIcon);
    tray_.hIcon = nullptr;
  }
}

void FlutterWindow::ShowNotification(const std::wstring& title,
                                     const std::wstring& body) {
  if (!tray_added_) {
    return;
  }
  NOTIFYICONDATAW info = tray_;
  info.uFlags = NIF_INFO;
  wcsncpy_s(info.szInfoTitle, title.c_str(), _TRUNCATE);
  wcsncpy_s(info.szInfo, body.c_str(), _TRUNCATE);
  info.dwInfoFlags = NIIF_USER | NIIF_LARGE_ICON;
  info.hBalloonIcon = static_cast<HICON>(LoadImageW(
      GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
      GetSystemMetrics(SM_CXICON), GetSystemMetrics(SM_CYICON), 0));
  Shell_NotifyIconW(NIM_MODIFY, &info);
  if (info.hBalloonIcon) {
    DestroyIcon(info.hBalloonIcon);
  }
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  for (const int id : hotkeys_) UnregisterHotKey(GetHandle(), id);
  hotkeys_.clear();
  KillTimer(GetHandle(), kHookWatchTimerId);
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
  if (code == HC_ACTION && g_hook_window) {
    // Physical screen coordinates: the process is per-monitor DPI aware (v2).
    const POINT pt = reinterpret_cast<MSLLHOOKSTRUCT*>(lparam)->pt;
    if (wparam == WM_MOUSEMOVE) {
      g_hook_window->OnGlobalCursor(pt);
    } else if (wparam == WM_LBUTTONDOWN || wparam == WM_RBUTTONDOWN ||
               wparam == WM_MBUTTONDOWN) {
      g_hook_window->OnGlobalButton(pt);
    }
  }
  return CallNextHookEx(nullptr, code, wparam, lparam);
}

void FlutterWindow::OnGlobalCursor(POINT screen_point) {
  // Runs before the system dispatches this move, so the window's hit-test
  // state is already right for it.
  UpdateClickThrough(screen_point);
  last_cursor_ = screen_point;
  last_hook_tick_ = GetTickCount();
  if (!cursor_timer_pending_) {
    cursor_timer_pending_ = true;
    SetTimer(GetHandle(), kCursorTimerId, kCursorTimerMs, nullptr);
  }
}

void FlutterWindow::OnGlobalButton(POINT screen_point) {
  UpdateClickThrough(screen_point);
  if (!click_through_) {
    return;  // On the island itself.
  }
  // Mikky's own popup menu or folder dialog: not "outside".
  HWND under = WindowFromPoint(screen_point);
  DWORD pid = 0;
  GetWindowThreadProcessId(under, &pid);
  if (pid == GetCurrentProcessId()) {
    return;
  }
  PostMessage(GetHandle(), kOutsideClickMessage, 0, 0);
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

void FlutterWindow::WatchHook() {
  POINT cursor;
  if (!GetCursorPos(&cursor)) return;
  if (cursor.x == last_cursor_.x && cursor.y == last_cursor_.y) return;
  if (GetTickCount() - last_hook_tick_ < kHookWatchMs) return;
  // The cursor moved and the hook heard nothing: put it back.
  if (mouse_hook_) UnhookWindowsHookEx(mouse_hook_);
  mouse_hook_ = SetWindowsHookEx(WH_MOUSE_LL, LowLevelMouseProc,
                                 GetModuleHandle(nullptr), 0);
  OnGlobalCursor(cursor);
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
  } else if (call.method_name() == "setPlacement") {
    const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
    const std::string* edge =
        args && args->size() == 3 ? std::get_if<std::string>(&(*args)[0])
                                  : nullptr;
    const double* width = edge ? std::get_if<double>(&(*args)[1]) : nullptr;
    const double* height = edge ? std::get_if<double>(&(*args)[2]) : nullptr;
    if (!edge || !width || !height || (*edge != "top" && *edge != "right")) {
      result->Error("bad_args", "setPlacement expects [top|right, w, h]");
      return;
    }
    // Nothing is clickable until Dart sends the new island rect.
    hit_w_ = hit_h_ = 0;
    SetPlacement(*edge == "top" ? Edge::kTop : Edge::kRight,
                 Size(static_cast<unsigned int>(*width),
                      static_cast<unsigned int>(*height)));
    POINT cursor;
    if (GetCursorPos(&cursor)) {
      UpdateClickThrough(cursor);
    }
    result->Success();
  } else if (call.method_name() == "showMenu") {
    const auto* entries = std::get_if<flutter::EncodableList>(call.arguments());
    if (!entries) {
      result->Error("bad_args", "showMenu expects [[id, label, checked]]");
      return;
    }
    HMENU menu = CreatePopupMenu();
    for (const auto& entry : *entries) {
      const auto* fields = std::get_if<flutter::EncodableList>(&entry);
      if (!fields || fields->size() != 3) {
        continue;
      }
      const auto* id = std::get_if<int32_t>(&(*fields)[0]);
      const auto* label = std::get_if<std::string>(&(*fields)[1]);
      const auto* checked = std::get_if<bool>(&(*fields)[2]);
      if (!id || !label || !checked) {
        continue;
      }
      if (*id == 0) {
        AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
      } else {
        AppendMenu(menu, MF_STRING | (*checked ? MF_CHECKED : MF_UNCHECKED),
                   *id, Utf16FromUtf8(*label).c_str());
      }
    }
    POINT cursor;
    GetCursorPos(&cursor);
    HWND hwnd = GetHandle();
    // Without this the menu would not close when clicking elsewhere.
    SetForegroundWindow(hwnd);
    const int chosen = TrackPopupMenu(
        menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON, cursor.x,
        cursor.y, 0, hwnd, nullptr);
    PostMessage(hwnd, WM_NULL, 0, 0);
    DestroyMenu(menu);
    result->Success(flutter::EncodableValue(chosen));
  } else if (call.method_name() == "activate") {
    // Only after a click on the island: the user asked for it, so taking
    // the keyboard (Escape, N, Y) is expected. Never on its own.
    HWND hwnd = GetHandle();
    SetForegroundWindow(hwnd);
    if (flutter_controller_) {
      SetFocus(flutter_controller_->view()->GetNativeWindow());
    }
    result->Success();
  } else if (call.method_name() == "pickFolder") {
    // The new agent's folder. Modal: the dialog comes on top of the island.
    std::string title;
    if (const auto* s = std::get_if<std::string>(call.arguments())) {
      title = *s;
    }
    const std::string chosen = PickFolder(GetHandle(), title);
    if (chosen.empty()) {
      result->Success();
    } else {
      result->Success(flutter::EncodableValue(chosen));
    }
  } else if (call.method_name() == "notify") {
    // [title, body]: a notification, from the icon in the notification area.
    const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
    if (args && args->size() == 2) {
      const auto* title = std::get_if<std::string>(&(*args)[0]);
      const auto* body = std::get_if<std::string>(&(*args)[1]);
      if (title && body) {
        ShowNotification(Utf16FromUtf8(*title), Utf16FromUtf8(*body));
      }
    }
    result->Success();
  } else if (call.method_name() == "playSound") {
    const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
    if (args && args->size() == 2) {
      const auto* name = std::get_if<std::string>(&(*args)[0]);
      const auto* volume = std::get_if<double>(&(*args)[1]);
      if (name && volume) {
        const int ms = sound_.Play(*name, *volume);
        if (ms > 0) SetTimer(GetHandle(), kSoundTimerId, ms + 60, nullptr);
      }
    }
    result->Success();
  } else if (call.method_name() == "preloadSounds") {
    std::set<std::string> names;
    if (const auto* args = std::get_if<flutter::EncodableList>(call.arguments())) {
      for (const auto& v : *args) {
        if (const auto* name = std::get_if<std::string>(&v)) names.insert(*name);
      }
    }
    sound_.Preload(names);
    result->Success();
  } else if (call.method_name() == "setHotkeys") {
    // Only the overlay has global shortcuts.
    HWND hwnd = GetHandle();
    for (const int id : hotkeys_) UnregisterHotKey(hwnd, id);
    hotkeys_.clear();
    flutter::EncodableList refused;
    const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
    if (args && is_overlay()) {
      for (const auto& entry : *args) {
        const auto* fields = std::get_if<flutter::EncodableList>(&entry);
        if (!fields || fields->size() != 3) continue;
        const auto* id = std::get_if<int32_t>(&(*fields)[0]);
        const auto* mods = std::get_if<int32_t>(&(*fields)[1]);
        const auto* key = std::get_if<int32_t>(&(*fields)[2]);
        if (!id || !mods || !key) continue;
        if (RegisterHotKey(hwnd, *id, static_cast<UINT>(*mods) | MOD_NOREPEAT,
                           static_cast<UINT>(*key))) {
          hotkeys_.push_back(*id);
        } else {
          refused.push_back(flutter::EncodableValue(*id));
        }
      }
    }
    result->Success(flutter::EncodableValue(refused));
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

  if (message == kTaskbarCreated && is_overlay()) {
    RemoveTrayIcon();
    AddTrayIcon();
    return 0;
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
      if (wparam == kHookWatchTimerId) {
        WatchHook();
        return 0;
      }
      if (wparam == kSoundTimerId) {
        KillTimer(hwnd, kSoundTimerId);
        if (sound_.Reap()) SetTimer(hwnd, kSoundTimerId, 150, nullptr);
        return 0;
      }
      break;
    case kTrayMessage:
      if (channel_) {
        switch (LOWORD(lparam)) {
          case NIN_SELECT:
          case NIN_KEYSELECT:
            channel_->InvokeMethod("trayClick", nullptr);
            break;
          case WM_CONTEXTMENU:
            channel_->InvokeMethod("trayMenu", nullptr);
            break;
          case NIN_BALLOONUSERCLICK:
            channel_->InvokeMethod("notificationClick", nullptr);
            break;
        }
      }
      return 0;
    case WM_HOTKEY:
      if (channel_) {
        channel_->InvokeMethod("hotkey", std::make_unique<flutter::EncodableValue>(
                                             static_cast<int32_t>(wparam)));
      }
      return 0;
    case kOutsideClickMessage:
      if (channel_) {
        channel_->InvokeMethod("outsideClick", nullptr);
      }
      return 0;
    case WM_MOUSEACTIVATE:
      // Clicking the island must not steal focus from the user's app.
      if (is_overlay()) {
        return MA_NOACTIVATE;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
