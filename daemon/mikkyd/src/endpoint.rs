//! How the app finds and trusts `mikkyd` (spec §5): it listens on
//! 127.0.0.1 only, on a free port, and wants a random token. Port and token
//! go to the Windows credential store for the user's session (rule: no
//! secret on disk), where the app reads them. One `mikkyd` per session.

/// Where the app reads the endpoint (a generic credential).
#[cfg(windows)]
const CREDENTIAL: &str = "Mikky/mikkyd";

/// 32 random bytes, in hex.
pub fn new_token() -> String {
    let mut bytes = [0u8; 32];
    getrandom::fill(&mut bytes).expect("no system randomness");
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// `a == b` in a time that does not depend on where they differ.
pub fn same_token(a: &str, b: &str) -> bool {
    a.len() == b.len() && a.bytes().zip(b.bytes()).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

/// What the app needs to connect, as JSON.
pub fn describe(port: u16, token: &str) -> String {
    serde_json::json!({"port": port, "token": token, "pid": std::process::id()}).to_string()
}

#[cfg(windows)]
fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

/// False if another `mikkyd` already runs in this session.
#[cfg(windows)]
pub fn single_instance() -> bool {
    use windows_sys::Win32::Foundation::{ERROR_ALREADY_EXISTS, GetLastError};
    use windows_sys::Win32::System::Threading::CreateMutexW;
    let name = wide("Local\\MikkyDaemon");
    // Kept open until the process ends.
    let handle = unsafe { CreateMutexW(std::ptr::null(), 0, name.as_ptr()) };
    !handle.is_null() && unsafe { GetLastError() } != ERROR_ALREADY_EXISTS
}

/// Puts `describe(port, token)` in the credential store for this session.
#[cfg(windows)]
pub fn publish(port: u16, token: &str) -> std::io::Result<()> {
    use windows_sys::Win32::Security::Credentials::{CRED_PERSIST_SESSION, CRED_TYPE_GENERIC, CREDENTIALW, CredWriteW};
    let mut blob = describe(port, token).into_bytes();
    let mut target = wide(CREDENTIAL);
    let mut user = wide("mikkyd");
    let mut cred: CREDENTIALW = unsafe { std::mem::zeroed() };
    cred.Type = CRED_TYPE_GENERIC;
    cred.TargetName = target.as_mut_ptr();
    cred.UserName = user.as_mut_ptr();
    cred.CredentialBlobSize = blob.len() as u32;
    cred.CredentialBlob = blob.as_mut_ptr();
    cred.Persist = CRED_PERSIST_SESSION;
    if unsafe { CredWriteW(&cred, 0) } == 0 {
        return Err(std::io::Error::last_os_error());
    }
    Ok(())
}

#[cfg(not(windows))]
pub fn single_instance() -> bool {
    true
}

/// Off Windows, not yet (R2): use `--stdout-endpoint`.
#[cfg(not(windows))]
pub fn publish(_port: u16, _token: &str) -> std::io::Result<()> {
    Err(std::io::Error::other("no credential store yet off Windows: use --stdout-endpoint"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tokens_are_long_random_hex() {
        let (a, b) = (new_token(), new_token());
        assert_eq!(a.len(), 64);
        assert!(a.chars().all(|c| c.is_ascii_hexdigit()));
        assert_ne!(a, b);
        assert!(same_token(&a, &a.clone()));
        assert!(!same_token(&a, &b));
        assert!(!same_token(&a, &a[1..]));
    }
}
