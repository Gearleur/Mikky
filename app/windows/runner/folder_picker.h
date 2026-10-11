#ifndef RUNNER_FOLDER_PICKER_H_
#define RUNNER_FOLDER_PICKER_H_

#include <windows.h>

#include <string>

// Windows' folder picker, owned by |owner|, titled |title|: the folder
// chosen, in UTF-8; empty if cancelled.
std::string PickFolder(HWND owner, const std::string& title);

#endif  // RUNNER_FOLDER_PICKER_H_
