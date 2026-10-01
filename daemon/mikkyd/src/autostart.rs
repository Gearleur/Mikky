//! User-session startup, never a privileged Windows service.
use mikky_acp::RpcError;
use serde_json::{Value, json};

#[cfg(windows)]
pub async fn configure(enabled: Option<bool>) -> Result<Value, RpcError> {
    let executable = std::env::current_exe().map_err(|e| RpcError::new(-32000, e.to_string()))?;
    let path = executable.to_string_lossy().replace('\'', "''");
    let script = match enabled {
        None => "if (Get-ScheduledTask -TaskName 'Mikky-mikkyd' -ErrorAction SilentlyContinue) { 'true' } else { 'false' }".to_owned(),
        Some(false) => "Get-ScheduledTask -TaskName 'Mikky-mikkyd' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false; 'false'".to_owned(),
        Some(true) => format!("$ErrorActionPreference='Stop'; \
            $mikkyUser=[System.Security.Principal.WindowsIdentity]::GetCurrent().Name; \
            $mikkyAction=New-ScheduledTaskAction -Execute '{path}'; \
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
