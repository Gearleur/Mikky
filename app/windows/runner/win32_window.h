#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// A class abstraction for a high DPI-aware Win32 Window. Intended to be
// inherited from by classes that wish to specialize with custom
// rendering and input handling
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // Creates Mikky's overlay window: borderless, transparent, always on top,
  // hidden from the taskbar and Alt+Tab, never activated, and click-through
  // until a hit rect is set. |size| is in logical pixels; the window is glued
  // to the top edge of the primary monitor, horizontally centered.
  // With |overlay| false: an ordinary window centered on the primary monitor
  // (the tuning screen). The window is invisible until |Show| is called.
  // Returns true on success.
  bool Create(const std::wstring& title, const Size& size, bool overlay = true);

  // Show the current window; the overlay without activating it.
  bool Show();

  bool is_overlay() const { return overlay_; }

  // Screen edge the overlay is glued to.
  enum class Edge { kTop, kRight };

  // Changes the edge and the logical size, then re-places the window.
  void SetPlacement(Edge edge, const Size& size);

  // Moves and resizes the window on the primary monitor, using that
  // monitor's current scale factor: top center for Edge::kTop, against the
  // right edge and vertically centered in the work area for Edge::kRight.
  void PlaceOnPrimaryMonitor();

  // Scale factor (DPI / 96) of the monitor the window was last placed on.
  double scale_factor() const { return scale_factor_; }

  // Top-left corner of the window, in physical screen pixels.
  POINT origin() const { return origin_; }

  // Release OS resources associated with window.
  void Destroy();

  // Inserts |content| into the window tree.
  void SetChildContent(HWND content);

  // Returns the backing Window handle to enable clients to set icon and other
  // window properties. Returns nullptr if the window has been destroyed.
  HWND GetHandle();

  // If true, closing this window will quit the application.
  void SetQuitOnClose(bool quit_on_close);

  // Return a RECT representing the bounds of the current client area.
  RECT GetClientArea();

 protected:
  // Processes and route salient window messages for mouse handling,
  // size change and DPI. Delegates handling of these to member overloads that
  // inheriting classes can handle.
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // Called when CreateAndShow is called, allowing subclass window-related
  // setup. Subclasses should return false if setup fails.
  virtual bool OnCreate();

  // Called when Destroy is called.
  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  // OS callback called by message pump. Handles the WM_NCCREATE message which
  // is passed when the non-client area is being created and enables automatic
  // non-client DPI scaling so that the non-client area automatically
  // responds to changes in DPI. All other messages are handled by
  // MessageHandler.
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // Retrieves a class instance pointer for |window|
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // Update the window frame's theme to match the system theme.
  static void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;

  // Logical size and edge requested at creation or by SetPlacement.
  Size logical_size_{0, 0};
  Edge edge_ = Edge::kTop;
  bool overlay_ = true;
  double scale_factor_ = 1.0;
  POINT origin_{0, 0};

  // window handle for top level window.
  HWND window_handle_ = nullptr;

  // window handle for hosted content.
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
