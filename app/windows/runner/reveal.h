#ifndef RUNNER_REVEAL_H_
#define RUNNER_REVEAL_H_

#include <windows.h>

#include <cstdint>

// Ctrl + click on an agent (2026-10-08): brings forward the window its
// session runs in — a terminal, VS Code — found by `mikky-hook` among its
// parent processes (`daemon/mikky-hook/src/origin.rs`).
//
// |handle| is the window the hook saw; if it is gone or no longer belongs
// to |pid|, any visible top-level window of |pid| is used. A minimized
// window is restored. Only called right after a click on Mikky: Windows
// lets the app that got the last input give the foreground away.
//
// Returns false when |pid| has no window to show.
bool RevealWindow(DWORD pid, int64_t handle);

#endif  // RUNNER_REVEAL_H_
