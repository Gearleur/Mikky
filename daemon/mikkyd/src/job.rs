//! A Windows job object holding one agent and everything it starts (MVP
//! spec §3.5): stopping the agent ends the whole tree at once, and if
//! `mikkyd` ends, Windows ends the agents with it (kill on close).

#[cfg(windows)]
pub use windows::Job;

#[cfg(windows)]
mod windows {
    use std::ffi::c_void;

    use windows_sys::Win32::Foundation::{CloseHandle, HANDLE};
    use windows_sys::Win32::System::JobObjects::{
        AssignProcessToJobObject, CreateJobObjectW, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION, JobObjectExtendedLimitInformation,
        SetInformationJobObject, TerminateJobObject,
    };
    use windows_sys::Win32::System::Threading::{
        OpenProcess, PROCESS_SET_QUOTA, PROCESS_TERMINATE,
    };

    pub struct Job(HANDLE);

    // A kernel handle, usable from any thread.
    unsafe impl Send for Job {}
    unsafe impl Sync for Job {}

    impl Job {
        /// A job for process `pid`, or None if Windows refuses. Right after
        /// start, before the agent is sent anything, so its own children
        /// are born inside.
        pub fn for_process(pid: u32) -> Option<Job> {
            unsafe {
                let handle = CreateJobObjectW(std::ptr::null(), std::ptr::null());
                if handle.is_null() {
                    return None;
                }
                let job = Job(handle);
                let mut info: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = std::mem::zeroed();
                info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
                let size = std::mem::size_of_val(&info) as u32;
                if SetInformationJobObject(
                    job.0,
                    JobObjectExtendedLimitInformation,
                    &info as *const _ as *const c_void,
                    size,
                ) == 0
                {
                    return None;
                }
                let process = OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, 0, pid);
                if process.is_null() {
                    return None;
                }
                let ok = AssignProcessToJobObject(job.0, process) != 0;
                CloseHandle(process);
                ok.then_some(job)
            }
        }

        /// Ends every process of the job.
        pub fn terminate(&self) {
            unsafe {
                TerminateJobObject(self.0, 1);
            }
        }
    }

    impl Drop for Job {
        fn drop(&mut self) {
            unsafe {
                CloseHandle(self.0);
            }
        }
    }
}

/// Off Windows, no job yet (R2: a process group in WSL and on the VPS).
#[cfg(unix)]
pub struct Job(u32);

#[cfg(unix)]
impl Job {
    pub fn for_process(pid: u32) -> Option<Job> {
        Some(Job(pid))
    }

    pub fn terminate(&self) {
        unsafe {
            libc::kill(-(self.0 as i32), libc::SIGKILL);
        }
    }
}

#[cfg(unix)]
impl Drop for Job {
    fn drop(&mut self) {
        self.terminate();
    }
}
