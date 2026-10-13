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
#include <vector>

#include "sound.h"
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
//                   playSound [name, volume]  a sound of assets/sounds,
//                                            volume 0..1 (sound.h)
//                   preloadSounds [name, ...]
//                   setHotkeys [[id, modifiers, key], ...]  global
//                                            shortcuts (RegisterHotKey),
//                                            the old ones dropped. Returns
//                                            the ids Windows refused.
//                   pickFolder title         Windows' folder picker;
//                                            the folder, null if cancelled
//                   notify [title, body]     a notification from the
//                                            icon in the notification area
//                   revealWindow [pid, handle]  brings an agent's window
//                                            to the front (reveal.cpp)
//                   quit
//   native -> Dart  cursor [x, y]            logical px, window-relative;
//                                            may be outside the window.
//                   hotkey id                a global shortcut was pressed
//                   outsideClick             a click outside the island
//                   trayClick, trayMenu      the icon in the notification
//                                            area, left or right click
//                   notificationClick        a click on a notification
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

  using MethodResult = flutter::MethodResult<flutter::EncodableValue>;
  using MethodHandler = void (FlutterWindow::*)(
      const flutter::EncodableValue* arguments, MethodResult& result);

  // The calls of the channel, one method each (overlay_methods.cpp).
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<MethodResult> result);
  void OnSetHitRect(const flutter::EncodableValue* arguments, MethodResult& result);
  void OnSetPlacement(const flutter::EncodableValue* arguments, MethodResult& result);
  void OnShowMenu(const flutter::EncodableValue* arguments, MethodResult& result);
  void OnActivate(const flutter::EncodableValue* arguments, MethodResult& result);
  void OnPickFolder(const flutter::EncodableValue* arguments, MethodResult& result);
  void OnNotify(const flutter::EncodableValue* arguments, MethodResult& result);
  void OnPlaySound(const flutter::EncodableValue* arguments, MethodResult& result);
  void OnPreloadSounds(const flutter::EncodableValue* arguments, MethodResult& result);
  void OnSetHotkeys(const flutter::EncodableValue* arguments, MethodResult& result);
  void OnRevealWindow(const flutter::EncodableValue* arguments, MethodResult& result);
  void OnControlDown(const flutter::EncodableValue* arguments, MethodResult& result);
  void OnQuit(const flutter::EncodableValue* arguments, MethodResult& result);

  // When the sounds playing should be over: their voices are freed, and
  // the audio engine stops once none is left.
  static constexpr UINT_PTR kSoundTimerId = 3;

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  HHOOK mouse_hook_ = nullptr;

  SoundPlayer sound_;

  // Ids of the global shortcuts registered now.
  std::vector<int> hotkeys_;

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
