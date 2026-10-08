//! Where the session runs (2026-10-08): the first of the relay's parent
//! processes that has a window of its own — Windows Terminal, a console,
//! VS Code (its main process, above the extension host and the shell). The
//! app brings that window forward on Ctrl + click (`reveal.cpp`).
//!
//! The walk stops at Explorer (a shell opened from the desktop: its windows
//! are the desktop's, not the session's) and after a few parents. Nothing
//! found: nothing said, the app opens VS Code on the folder instead.

/// A top-level window and the process that owns it.
pub struct Window {
    pub pid: u32,
    /// The window handle, as a number (it may be gone by the time it is
    /// used: the app checks it still belongs to [pid]).
    pub handle: i64,
    /// The executable's file name (`WindowsTerminal.exe`, `Code.exe`…).
    pub exe: String,
}

/// Parents looked at, at most.
#[cfg(windows)]
const DEPTH: usize = 16;

/// Processes whose windows are never a session's.
#[cfg(windows)]
const STOP: &[&str] = &[
    "explorer.exe",
    "svchost.exe",
    "services.exe",
    "wininit.exe",
    "winlogon.exe",
];

#[cfg(windows)]
pub fn window() -> Option<Window> {
    let parents = processes()?;
    let windows = windows();
    let mut pid = std::process::id();
    let mut seen = Vec::new();
    for _ in 0..DEPTH {
        let (parent, _) = parents.get(&pid)?;
        pid = *parent;
        if pid == 0 || seen.contains(&pid) {
            return None;
        }
        seen.push(pid);
        let (_, exe) = parents.get(&pid)?;
        if STOP.iter().any(|s| exe.eq_ignore_ascii_case(s)) {
            return None;
        }
        if let Some((_, handle)) = windows.iter().find(|(p, _)| *p == pid) {
            return Some(Window {
                pid,
                handle: *handle,
                exe: exe.clone(),
            });
        }
    }
    None
}

#[cfg(not(windows))]
pub fn window() -> Option<Window> {
    None
}

/// Every process: its parent and its executable's name.
#[cfg(windows)]
fn processes() -> Option<std::collections::HashMap<u32, (u32, String)>> {
    use windows_sys::Win32::Foundation::{CloseHandle, INVALID_HANDLE_VALUE};
    use windows_sys::Win32::System::Diagnostics::ToolHelp::{
        CreateToolhelp32Snapshot, PROCESSENTRY32W, Process32FirstW, Process32NextW,
        TH32CS_SNAPPROCESS,
    };
    let snapshot = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) };
    if snapshot == INVALID_HANDLE_VALUE || snapshot.is_null() {
        return None;
    }
    let mut out = std::collections::HashMap::new();
    let mut entry = PROCESSENTRY32W {
        dwSize: std::mem::size_of::<PROCESSENTRY32W>() as u32,
        ..Default::default()
    };
    let mut ok = unsafe { Process32FirstW(snapshot, &mut entry) } != 0;
    while ok {
        let len = entry
            .szExeFile
            .iter()
            .position(|c| *c == 0)
            .unwrap_or(entry.szExeFile.len());
        out.insert(
            entry.th32ProcessID,
            (
                entry.th32ParentProcessID,
                String::from_utf16_lossy(&entry.szExeFile[..len]),
            ),
        );
        ok = unsafe { Process32NextW(snapshot, &mut entry) } != 0;
    }
    unsafe { CloseHandle(snapshot) };
    Some(out)
}

/// The windows a user would call « the app's window »: visible, top-level,
/// not owned by another, not a tool window, with a title. In Z order.
#[cfg(windows)]
fn windows() -> Vec<(u32, i64)> {
    use windows_sys::Win32::Foundation::{HWND, LPARAM};
    use windows_sys::Win32::UI::WindowsAndMessaging::{
        EnumWindows, GW_OWNER, GWL_EXSTYLE, GetWindow, GetWindowLongW, GetWindowTextLengthW,
        GetWindowThreadProcessId, IsWindowVisible, WS_EX_TOOLWINDOW,
    };

    unsafe extern "system" fn each(hwnd: HWND, data: LPARAM) -> windows_sys::core::BOOL {
        let found = unsafe { &mut *(data as *mut Vec<(u32, i64)>) };
        let shown = unsafe {
            IsWindowVisible(hwnd) != 0
                && GetWindow(hwnd, GW_OWNER).is_null()
                && (GetWindowLongW(hwnd, GWL_EXSTYLE) as u32 & WS_EX_TOOLWINDOW) == 0
                && GetWindowTextLengthW(hwnd) > 0
        };
        if shown {
            let mut pid = 0u32;
            unsafe { GetWindowThreadProcessId(hwnd, &mut pid) };
            found.push((pid, hwnd as i64));
        }
        1
    }

    let mut found: Vec<(u32, i64)> = Vec::new();
    unsafe { EnumWindows(Some(each), &mut found as *mut _ as LPARAM) };
    found
}

#[cfg(all(test, windows))]
mod tests {
    #[test]
    fn processes_know_their_parents() {
        let all = super::processes().unwrap();
        let me = all.get(&std::process::id()).unwrap();
        assert!(me.1.to_ascii_lowercase().contains("mikky_hook"));
        assert!(all.contains_key(&me.0) || me.0 != 0);
        // Not asserted: a window above the test runner depends on how the
        // tests are started (a terminal, an editor, a service).
        let _ = super::window();
    }
}
