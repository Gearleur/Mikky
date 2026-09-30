#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <climits>
#include <windows.h>
#include <shellapi.h>

#include <memory>

#include "win32_window.h"

// Mikky's overlay: hosts the Flutter view, lets clicks through everywhere
// except on the island, and streams the global cursor position to Dart.
//
// Channel "mikky/overlay":
//   Dart -> native  setHitRect [x, y, w, h]  logical px, window-relative;
//                                            w or h <= 0 means no hit area.
//                   setPlacement [top|right, w, h]  logical size; moves
//                                            and resizes the window
//                   showMenu [[id, label, checked], ...]  native context
//                                            menu at the cursor; id 0 is a
//                                            separator. Returns the chosen
//                                            id, 0 if dismissed.
//                   activate                 take the keyboard focus (only
//                                            after a click on the island)
//                   quit
//   native -> Dart  cursor [x, y]            logical px, window-relative;
//                                            may be outside the window.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  static LRESULT CALLBACK LowLevelMouseProc(int code, WPARAM wparam,
                                            LPARAM lparam);

  // Called from the mouse hook: must stay very cheap, every mouse event of
  // the whole system waits for it.
  void OnGlobalCursor(POINT screen_point);

  // A mouse button went down somewhere on screen (from the hook): if it is
  // outside the island and outside Mikky's own windows (menus, dialogs),
  // Dart hears "outsideClick" (the island may close, like a popover).
  void OnGlobalButton(POINT screen_point);

  // The icon in the notification area (Mikky), and its balloons, which
  // Windows 10 / 11 show as notifications.
  void AddTrayIcon();
  void RemoveTrayIcon();
  void ShowNotification(const std::wstring& title, const std::wstring& body);

  // Sends the latest cursor position to Dart, at most once per timer tick.
  void FlushCursor();

  // Puts the mouse hook back if Windows dropped it.
  void WatchHook();

  // Adds or removes WS_EX_TRANSPARENT depending on |screen_point|.
  void UpdateClickThrough(POINT screen_point);

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  HHOOK mouse_hook_ = nullptr;

  NOTIFYICONDATAW tray_ = {};
  bool tray_added_ = false;

  // Island hit area, logical px, window-relative. Empty: fully click-through.
  double hit_x_ = 0, hit_y_ = 0, hit_w_ = 0, hit_h_ = 0;
  bool click_through_ = true;

  POINT last_cursor_{0, 0};
  POINT sent_cursor_{LONG_MIN, LONG_MIN};
  bool cursor_timer_pending_ = false;

  // When the hook last heard the mouse (GetTickCount).
  DWORD last_hook_tick_ = 0;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
