#include "reveal.h"

namespace {

// The windows a user would call « the app's window »: visible, top-level,
// not owned by another, not a tool window, with a title. Same rule as the
// hook's (origin.rs).
bool IsMainWindow(HWND hwnd) {
  if (!IsWindowVisible(hwnd) || GetWindow(hwnd, GW_OWNER) != nullptr) {
    return false;
  }
  if (GetWindowLongW(hwnd, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) return false;
  return GetWindowTextLengthW(hwnd) > 0;
}

struct Search {
  DWORD pid;
  HWND found;
};

BOOL CALLBACK FindWindowOf(HWND hwnd, LPARAM data) {
  auto* search = reinterpret_cast<Search*>(data);
  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (pid == search->pid && IsMainWindow(hwnd)) {
    // The first in Z order: the one used last.
    search->found = hwnd;
    return FALSE;
  }
  return TRUE;
}

HWND WindowOf(DWORD pid, int64_t handle) {
  HWND hint = reinterpret_cast<HWND>(static_cast<intptr_t>(handle));
  if (hint != nullptr && IsWindow(hint)) {
    DWORD owner = 0;
    GetWindowThreadProcessId(hint, &owner);
    // Minimized windows are still visible.
    if (owner == pid && IsWindowVisible(hint)) return hint;
  }
  Search search{pid, nullptr};
  EnumWindows(FindWindowOf, reinterpret_cast<LPARAM>(&search));
  return search.found;
}

}  // namespace

bool RevealWindow(DWORD pid, int64_t handle) {
  if (pid == 0 || pid == GetCurrentProcessId()) return false;
  HWND target = WindowOf(pid, handle);
  if (target == nullptr) return false;
  if (IsIconic(target)) {
    ShowWindow(target, SW_RESTORE);
  }
  // We just got the click, so we may hand the foreground over. When the
  // overlay never took it (clicks through a no-activate window), join the
  // input of the window that has it for the time of the switch.
  AllowSetForegroundWindow(pid);
  if (!SetForegroundWindow(target)) {
    HWND current = GetForegroundWindow();
    const DWORD theirs =
        current ? GetWindowThreadProcessId(current, nullptr) : 0;
    const DWORD ours = GetCurrentThreadId();
    const bool joined =
        theirs != 0 && theirs != ours && AttachThreadInput(ours, theirs, TRUE);
    BringWindowToTop(target);
    SetForegroundWindow(target);
    if (joined) AttachThreadInput(ours, theirs, FALSE);
  }
  return true;
}
