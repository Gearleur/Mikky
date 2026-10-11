//! User-session startup, never a privileged Windows service.
//!
//! The task starts `mikkyd --latest`: the newest built bundle runs, not the
//! one the task was registered from (2026-10-06: a task registered on
//! 1 October kept starting that engine, without what came after).
use std::path::{Path, PathBuf};

use mikky_acp::RpcError;
use serde_json::{Value, json};

/// The `mikkyd` of the newest bundle, when [exe] sits in a folder of
/// built bundles (`dist\<version>\mikkyd.exe`, the newest named in
/// `dist\current.txt`) and it is another one; null otherwise.
pub fn latest_exe(exe: &Path) -> Option<PathBuf> {
    let bundle = exe.parent()?;
    let dist = bundle.parent()?;
    let version = std::fs::read_to_string(dist.join("current.txt")).ok()?;
    let version = version.trim();
    if version.is_empty() || version.contains(['/', '\\']) || version.contains("..") {
        return None;
    }
    let newest = dist.join(version).join(exe.file_name()?);
    let same = std::fs::canonicalize(&newest).ok()? == std::fs::canonicalize(exe).ok()?;
    (!same).then_some(newest)
}

#[cfg(windows)]
pub async fn configure(enabled: Option<bool>) -> Result<Value, RpcError> {
    let executable = std::env::current_exe().map_err(|e| RpcError::new(-32000, e.to_string()))?;
    let path = executable.to_string_lossy().replace('\'', "''");
    let script = match enabled {
        None => "if (Get-ScheduledTask -TaskName 'Mikky-mikkyd' -ErrorAction SilentlyContinue) { 'true' } else { 'false' }".to_owned(),
        Some(false) => "Get-ScheduledTask -TaskName 'Mikky-mikkyd' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false; 'false'".to_owned(),
        Some(true) => format!("$ErrorActionPreference='Stop'; \
            $mikkyUser=[System.Security.Principal.WindowsIdentity]::GetCurrent().Name; \
            $mikkyAction=New-ScheduledTaskAction -Execute '{path}' -Argument '--latest'; \
            $mikkyTrigger=New-ScheduledTaskTrigger -AtLogOn -User $mikkyUser; \
            $mikkyPrincipal=New-ScheduledTaskPrincipal -UserId $mikkyUser -LogonType Interactive -RunLevel Limited; \
            $mikkySettings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable; \
            Register-ScheduledTask -TaskName 'Mikky-mikkyd' -Action $mikkyAction -Trigger $mikkyTrigger -Principal $mikkyPrincipal -Settings $mikkySettings -Force | Out-Null; 'true'"),
    };
    let output = tokio::process::Command::new("powershell.exe")
        .args(["-NoProfile", "-NonInteractive", "-Command", &script])
        .creation_flags(0x0800_0000)
        .kill_on_drop(true)
        .output()
        .await
        .map_err(|e| RpcError::new(-32000, e.to_string()))?;
    if !output.status.success() {
        return Err(RpcError::new(
            -32000,
            "Windows n’a pas pu modifier le démarrage automatique de Mikky.",
        ));
    }
    Ok(json!({"enabled": String::from_utf8_lossy(&output.stdout).trim() == "true"}))
}

#[cfg(not(windows))]
pub async fn configure(_enabled: Option<bool>) -> Result<Value, RpcError> {
    Ok(json!({"enabled": false, "supported": false}))
}

#[cfg(test)]
mod tests {
    use super::latest_exe;

    #[test]
    fn the_newest_bundle_runs() {
        let dist = std::env::temp_dir().join(format!("mikky-latest-{}", std::process::id()));
        for v in ["Mikky-1", "Mikky-2"] {
            std::fs::create_dir_all(dist.join(v)).unwrap();
            std::fs::write(dist.join(v).join("mikkyd.exe"), b"").unwrap();
        }
        let old = dist.join("Mikky-1").join("mikkyd.exe");
        // No manifest: itself.
        assert_eq!(latest_exe(&old), None);
        std::fs::write(dist.join("current.txt"), "Mikky-2\r\n").unwrap();
        assert_eq!(
            latest_exe(&old),
            Some(dist.join("Mikky-2").join("mikkyd.exe"))
        );
        // Already the newest: itself.
        assert_eq!(latest_exe(&dist.join("Mikky-2").join("mikkyd.exe")), None);
        // A manifest that leaves the folder is not followed.
        std::fs::write(dist.join("current.txt"), "..\\elsewhere").unwrap();
        assert_eq!(latest_exe(&old), None);
        std::fs::remove_dir_all(&dist).ok();
    }
}
