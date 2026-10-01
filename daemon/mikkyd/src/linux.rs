//! Private Unix socket: WSL agents survive desktop and bridge disconnects.
use crate::api;
use std::os::unix::process::CommandExt;
use std::{
    os::unix::{
        fs::{MetadataExt, PermissionsExt},
        io::AsRawFd,
    },
    path::PathBuf,
    sync::Arc,
};
use tokio::{
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    net::{UnixListener, UnixStream},
    sync::mpsc,
};

fn directory() -> PathBuf {
    PathBuf::from(format!("/tmp/mikky-{}", unsafe { libc::geteuid() }))
}

pub async fn bridge() -> Result<(), Box<dyn std::error::Error>> {
    let path = directory().join("daemon.sock");
    let mut stream = UnixStream::connect(&path).await.ok();
    if stream.is_none() {
        let mut daemon = std::process::Command::new(std::env::current_exe()?);
        daemon
            .arg("--linux-daemon")
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null());
        // A separate session: closing wsl.exe's bridge must not send SIGHUP
        // to the persistent daemon or to the agents it owns.
        unsafe {
            daemon.pre_exec(|| {
                if libc::setsid() < 0 {
                    return Err(std::io::Error::last_os_error());
                }
                Ok(())
            });
        }
        daemon.spawn()?;
        for _ in 0..100 {
            if let Ok(s) = UnixStream::connect(&path).await {
                stream = Some(s);
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(50)).await;
        }
    }
    let stream = stream.ok_or("WSL backend unavailable")?;
    let (mut read, mut write) = stream.into_split();
    let mut input = tokio::io::stdin();
    let mut output = tokio::io::stdout();
    tokio::select! {
        result = tokio::io::copy(&mut input, &mut write) => { result?; }
        result = tokio::io::copy(&mut read, &mut output) => { result?; }
    }
    Ok(())
}

pub async fn serve(daemon: Arc<api::Daemon>) -> Result<(), Box<dyn std::error::Error>> {
    let directory = directory();
    std::fs::create_dir_all(&directory)?;
    let metadata = std::fs::symlink_metadata(&directory)?;
    if !metadata.is_dir() || metadata.uid() != unsafe { libc::geteuid() } {
        return Err("Unsafe Mikky runtime directory".into());
    }
    std::fs::set_permissions(&directory, std::fs::Permissions::from_mode(0o700))?;
    let lock = std::fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(directory.join("daemon.lock"))?;
    if unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        return Ok(());
    }
    let path = directory.join("daemon.sock");
    if path.exists() {
        std::fs::remove_file(&path)?;
    }
    let listener = UnixListener::bind(&path)?;
    loop {
        tokio::select! {
            _ = daemon.wait_shutdown() => break,
            accept = listener.accept() => {
                let (stream, _) = accept?;
                if stream.peer_cred()?.uid() != unsafe { libc::geteuid() } { continue; }
                let daemon = daemon.clone();
                tokio::spawn(async move {
                    let (read, mut write) = stream.into_split();
                    let (out, mut messages) = mpsc::unbounded_channel::<String>();
                    let watching = api::watch_notifications(&daemon, out.clone());
                    let writer = tokio::spawn(async move {
                        while let Some(message) = messages.recv().await {
                            if write.write_all(format!("{message}\n").as_bytes()).await.is_err() { break; }
                        }
                    });
                    let mut lines = BufReader::new(read).lines();
                    while let Ok(Some(line)) = lines.next_line().await {
                        tokio::spawn(api::handle(line, out.clone(), daemon.clone()));
                    }
                    watching.abort();
                    writer.abort();
                });
            }
        }
    }
    daemon.stop_all().await;
    std::fs::remove_file(path)?;
    Ok(())
}
