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

// True when |part| is one of the " - " separated parts of |hwnd|'s title,
// whatever the case (« ● file.dart - mikky - Visual Studio Code »).
bool TitleHas(HWND hwnd, const std::wstring& part) {
  const int length = GetWindowTextLengthW(hwnd);
  if (length <= 0) return false;
  std::wstring title(static_cast<size_t>(length) + 1, L'\0');
  title.resize(GetWindowTextW(hwnd, title.data(), length + 1));
  const std::wstring separator = L" - ";
  size_t start = 0;
  while (start <= title.size()) {
    size_t end = title.find(separator, start);
    if (end == std::wstring::npos) end = title.size();
    if (end - start == part.size() &&
        _wcsnicmp(title.c_str() + start, part.c_str(), part.size()) == 0) {
      return true;
    }
    start = end + separator.size();
  }
  return false;
}

struct Search {
  DWORD pid;
  const std::wstring* title;
  HWND found;
};

BOOL CALLBACK FindWindowOf(HWND hwnd, LPARAM data) {
  auto* search = reinterpret_cast<Search*>(data);
  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (pid == search->pid && IsMainWindow(hwnd) &&
      (search->title == nullptr || TitleHas(hwnd, *search->title))) {
    // The first in Z order: the one used last.
    search->found = hwnd;
    return FALSE;
  }
  return TRUE;
}

HWND WindowOf(DWORD pid, int64_t handle, const std::wstring& title) {
  if (!title.empty()) {
    Search named{pid, &title, nullptr};
    EnumWindows(FindWindowOf, reinterpret_cast<LPARAM>(&named));
    if (named.found != nullptr) return named.found;
  }
  HWND hint = reinterpret_cast<HWND>(static_cast<intptr_t>(handle));
  if (hint != nullptr && IsWindow(hint)) {
    DWORD owner = 0;
    GetWindowThreadProcessId(hint, &owner);
    // Minimized windows are still visible.
    if (owner == pid && IsWindowVisible(hint)) return hint;
  }
  Search search{pid, nullptr, nullptr};
  EnumWindows(FindWindowOf, reinterpret_cast<LPARAM>(&search));
  return search.found;
}

}  // namespace

bool RevealWindow(DWORD pid, int64_t handle, const std::wstring& title) {
  if (pid == 0 || pid == GetCurrentProcessId()) return false;
  HWND target = WindowOf(pid, handle, title);
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
