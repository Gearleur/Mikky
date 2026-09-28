#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  // "--tuning": the tuning screen, an ordinary window (Dart sees the flag
  // too and shows the tuning screen instead of the island).
  const bool tuning =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--tuning") != command_line_arguments.end();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  if (tuning) {
    if (!window.Create(L"R\u00e9glage de Mikky", Win32Window::Size(1180, 760),
                       /*overlay=*/false)) {
      return EXIT_FAILURE;
    }
  } else {
    // The island's window; Dart sets its final size and edge at startup.
    if (!window.Create(L"Mikky", Win32Window::Size(560, 320))) {
      return EXIT_FAILURE;
    }
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
