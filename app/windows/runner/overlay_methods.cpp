// The calls Dart makes on the channel "mikky/overlay" (see flutter_window.h),
// one method each.

#include <flutter/standard_method_codec.h>

#include <map>
#include <set>
#include <string>

#include "flutter_window.h"
#include "folder_picker.h"
#include "reveal.h"
#include "utils.h"

void FlutterWindow::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<MethodResult> result) {
  static const std::map<std::string, MethodHandler> handlers = {
      {"setHitRect", &FlutterWindow::OnSetHitRect},
      {"setPlacement", &FlutterWindow::OnSetPlacement},
      {"showMenu", &FlutterWindow::OnShowMenu},
      {"activate", &FlutterWindow::OnActivate},
      {"pickFolder", &FlutterWindow::OnPickFolder},
      {"notify", &FlutterWindow::OnNotify},
      {"playSound", &FlutterWindow::OnPlaySound},
      {"preloadSounds", &FlutterWindow::OnPreloadSounds},
      {"setHotkeys", &FlutterWindow::OnSetHotkeys},
      {"revealWindow", &FlutterWindow::OnRevealWindow},
      {"quit", &FlutterWindow::OnQuit},
  };
  const auto handler = handlers.find(call.method_name());
  if (handler == handlers.end()) {
    result->NotImplemented();
    return;
  }
  (this->*handler->second)(call.arguments(), *result);
}

void FlutterWindow::OnSetHitRect(const flutter::EncodableValue* arguments,
                                 MethodResult& result) {
  const auto* args = std::get_if<flutter::EncodableList>(arguments);
  if (!args || args->size() != 4) {
    result.Error("bad_args", "setHitRect expects [x, y, w, h]");
    return;
  }
  double values[4];
  for (size_t i = 0; i < 4; ++i) {
    const auto* v = std::get_if<double>(&(*args)[i]);
    if (!v) {
      result.Error("bad_args", "setHitRect expects doubles");
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
  result.Success();
}

void FlutterWindow::OnSetPlacement(const flutter::EncodableValue* arguments,
                                   MethodResult& result) {
  const auto* args = std::get_if<flutter::EncodableList>(arguments);
  const std::string* edge =
      args && args->size() == 3 ? std::get_if<std::string>(&(*args)[0])
                                : nullptr;
  const double* width = edge ? std::get_if<double>(&(*args)[1]) : nullptr;
  const double* height = edge ? std::get_if<double>(&(*args)[2]) : nullptr;
  if (!edge || !width || !height || (*edge != "top" && *edge != "right")) {
    result.Error("bad_args", "setPlacement expects [top|right, w, h]");
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
  result.Success();
}

void FlutterWindow::OnShowMenu(const flutter::EncodableValue* arguments,
                               MethodResult& result) {
  const auto* entries = std::get_if<flutter::EncodableList>(arguments);
  if (!entries) {
    result.Error("bad_args", "showMenu expects [[id, label, checked]]");
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
  result.Success(flutter::EncodableValue(chosen));
}

void FlutterWindow::OnActivate(const flutter::EncodableValue* /*arguments*/,
                               MethodResult& result) {
  // Only after a click on the island: the user asked for it, so taking
  // the keyboard (Escape, N, Y) is expected. Never on its own.
  HWND hwnd = GetHandle();
  SetForegroundWindow(hwnd);
  if (flutter_controller_) {
    SetFocus(flutter_controller_->view()->GetNativeWindow());
  }
  result.Success();
}

void FlutterWindow::OnPickFolder(const flutter::EncodableValue* arguments,
                                 MethodResult& result) {
  // The new agent's folder. Modal: the dialog comes on top of the island.
  std::string title;
  if (const auto* s = std::get_if<std::string>(arguments)) {
    title = *s;
  }
  const std::string chosen = PickFolder(GetHandle(), title);
  if (chosen.empty()) {
    result.Success();
  } else {
    result.Success(flutter::EncodableValue(chosen));
  }
}

void FlutterWindow::OnNotify(const flutter::EncodableValue* arguments,
                             MethodResult& result) {
  // [title, body]: a notification, from the icon in the notification area.
  const auto* args = std::get_if<flutter::EncodableList>(arguments);
  if (args && args->size() == 2) {
    const auto* title = std::get_if<std::string>(&(*args)[0]);
    const auto* body = std::get_if<std::string>(&(*args)[1]);
    if (title && body) {
      ShowNotification(Utf16FromUtf8(*title), Utf16FromUtf8(*body));
    }
  }
  result.Success();
}

void FlutterWindow::OnPlaySound(const flutter::EncodableValue* arguments,
                                MethodResult& result) {
  const auto* args = std::get_if<flutter::EncodableList>(arguments);
  if (args && args->size() == 2) {
    const auto* name = std::get_if<std::string>(&(*args)[0]);
    const auto* volume = std::get_if<double>(&(*args)[1]);
    if (name && volume) {
      const int ms = sound_.Play(*name, *volume);
      if (ms > 0) SetTimer(GetHandle(), kSoundTimerId, ms + 60, nullptr);
    }
  }
  result.Success();
}

void FlutterWindow::OnPreloadSounds(const flutter::EncodableValue* arguments,
                                    MethodResult& result) {
  std::set<std::string> names;
  if (const auto* args = std::get_if<flutter::EncodableList>(arguments)) {
    for (const auto& v : *args) {
      if (const auto* name = std::get_if<std::string>(&v)) names.insert(*name);
    }
  }
  sound_.Preload(names);
  result.Success();
}

void FlutterWindow::OnSetHotkeys(const flutter::EncodableValue* arguments,
                                 MethodResult& result) {
  // Only the overlay has global shortcuts.
  HWND hwnd = GetHandle();
  for (const int id : hotkeys_) UnregisterHotKey(hwnd, id);
  hotkeys_.clear();
  flutter::EncodableList refused;
  const auto* args = std::get_if<flutter::EncodableList>(arguments);
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
  result.Success(flutter::EncodableValue(refused));
}

void FlutterWindow::OnRevealWindow(const flutter::EncodableValue* arguments,
                                   MethodResult& result) {
  // [pid, handle]: the window an agent's session runs in (reveal.cpp).
  bool shown = false;
  const auto* args = std::get_if<flutter::EncodableList>(arguments);
  if (args && args->size() == 2) {
    const auto number = [](const flutter::EncodableValue& v) -> int64_t {
      if (const auto* i = std::get_if<int32_t>(&v)) return *i;
      if (const auto* l = std::get_if<int64_t>(&v)) return *l;
      return 0;
    };
    shown = RevealWindow(static_cast<DWORD>(number((*args)[0])),
                         number((*args)[1]));
  }
  result.Success(flutter::EncodableValue(shown));
}

void FlutterWindow::OnQuit(const flutter::EncodableValue* /*arguments*/,
                           MethodResult& result) {
  result.Success();
  PostMessage(GetHandle(), WM_CLOSE, 0, 0);
}
