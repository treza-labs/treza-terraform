use std::env;
use std::time::Duration;

use serde_json::json;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio::sync::watch;

use crate::logging::send_log;
use crate::protocol::{self, Message, PendingMap, SharedWriter, next_request_id};

/// Determine the user command from environment variables.
/// Checks TREZA_USER_CMD first, then combines TREZA_USER_ENTRYPOINT + TREZA_USER_CMD_ARGS.
pub fn resolve_user_command() -> Option<String> {
    if let Ok(cmd) = env::var("TREZA_USER_CMD") {
        if !cmd.is_empty() {
            return Some(cmd);
        }
    }

    let ep = env::var("TREZA_USER_ENTRYPOINT").unwrap_or_default();
    let args = env::var("TREZA_USER_CMD_ARGS").unwrap_or_default();

    match (ep.is_empty(), args.is_empty()) {
        (false, false) => Some(format!("{ep} {args}")),
        (false, true) => Some(ep),
        (true, false) => Some(args),
        (true, true) => None,
    }
}

/// Build the environment for the user process with proxy settings.
fn build_user_env() -> Vec<(String, String)> {
    let mut env_vars: Vec<(String, String)> = env::vars().collect();

    let proxy_url = "http://127.0.0.1:3128";
    let kms_url = "http://127.0.0.1:8000";
    let no_proxy = "127.0.0.1,localhost";

    let overrides = [
        ("HTTP_PROXY", proxy_url),
        ("HTTPS_PROXY", proxy_url),
        ("http_proxy", proxy_url),
        ("https_proxy", proxy_url),
        ("TREZA_KMS_ENDPOINT", kms_url),
        ("NO_PROXY", no_proxy),
        ("no_proxy", no_proxy),
    ];

    for (key, val) in &overrides {
        if let Some(entry) = env_vars.iter_mut().find(|(k, _)| k == key) {
            entry.1 = val.to_string();
        } else {
            env_vars.push((key.to_string(), val.to_string()));
        }
    }

    env_vars
}

/// Supervise the user process: spawn it, stream output, handle lifecycle
/// based on workload type (batch, service, daemon).
pub async fn run(
    writer: SharedWriter,
    _pending: PendingMap,
    user_cmd: &str,
    workload_type: &str,
    health_interval: u64,
    mut shutdown: watch::Receiver<bool>,
    shutdown_tx: watch::Sender<bool>,
) {
    let env_vars = build_user_env();

    send_log(&writer, "info", &format!("Starting user application: {user_cmd}")).await;

    // Use /bin/sh if available, fall back to direct execution
    let mut child = match Command::new("/bin/sh")
        .arg("-c")
        .arg(user_cmd)
        .envs(env_vars.clone())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
    {
        Ok(c) => c,
        Err(e) => {
            // If /bin/sh is not available (scratch image), try direct execution
            eprintln!("[supervisor] /bin/sh failed ({e}), trying direct execution");
            let parts: Vec<&str> = user_cmd.split_whitespace().collect();
            if parts.is_empty() {
                send_log(&writer, "error", "Empty user command").await;
                return;
            }
            match Command::new(parts[0])
                .args(&parts[1..])
                .envs(env_vars)
                .stdout(std::process::Stdio::piped())
                .stderr(std::process::Stdio::piped())
                .spawn()
            {
                Ok(c) => c,
                Err(e2) => {
                    send_log(&writer, "error", &format!("Failed to start user app: {e2}")).await;
                    return;
                }
            }
        }
    };

    // Stream stdout
    if let Some(stdout) = child.stdout.take() {
        let w = writer.clone();
        tokio::spawn(async move {
            let reader = BufReader::new(stdout);
            let mut lines = reader.lines();
            while let Ok(Some(line)) = lines.next_line().await {
                if !line.is_empty() {
                    send_log(&w, "app", &line).await;
                }
            }
        });
    }

    // Stream stderr
    if let Some(stderr) = child.stderr.take() {
        let w = writer.clone();
        tokio::spawn(async move {
            let reader = BufReader::new(stderr);
            let mut lines = reader.lines();
            while let Ok(Some(line)) = lines.next_line().await {
                if !line.is_empty() {
                    send_log(&w, "app_err", &line).await;
                }
            }
        });
    }

    match workload_type {
        "batch" => run_batch(&writer, &mut child, &mut shutdown).await,
        "service" | "daemon" => {
            run_service(&writer, &mut child, health_interval, &mut shutdown).await
        }
        other => {
            send_log(&writer, "warn", &format!("Unknown workload type '{other}', treating as batch")).await;
            run_batch(&writer, &mut child, &mut shutdown).await;
        }
    }

    // Ensure shutdown is signaled
    let _ = shutdown_tx.send(true);
}

async fn run_batch(
    writer: &SharedWriter,
    child: &mut tokio::process::Child,
    shutdown: &mut watch::Receiver<bool>,
) {
    tokio::select! {
        result = child.wait() => {
            match result {
                Ok(status) => {
                    let code = status.code().unwrap_or(-1);
                    send_log(writer, "info", &format!("Application exited with code {code}")).await;
                    send_health_report(writer, "completed", Some(code), "batch").await;
                    // Give time for logs to flush
                    tokio::time::sleep(Duration::from_secs(5)).await;
                }
                Err(e) => {
                    send_log(writer, "error", &format!("Failed to wait for process: {e}")).await;
                }
            }
        }
        _ = wait_shutdown(shutdown) => {
            send_log(writer, "info", "Shutdown signal received, terminating process").await;
            let _ = child.kill().await;
        }
    }
}

async fn run_service(
    writer: &SharedWriter,
    child: &mut tokio::process::Child,
    health_interval: u64,
    shutdown: &mut watch::Receiver<bool>,
) {
    let mut interval = tokio::time::interval(Duration::from_secs(health_interval));

    loop {
        tokio::select! {
            _ = interval.tick() => {
                // Check if process is still running
                match child.try_wait() {
                    Ok(Some(status)) => {
                        let code = status.code().unwrap_or(-1);
                        send_log(writer, "error", &format!("Service exited unexpectedly with code {code}")).await;
                        send_health_report(writer, "crashed", Some(code), "service").await;
                        return;
                    }
                    Ok(None) => {
                        // Still running, send health report
                        send_health_report(writer, "running", None, "service").await;
                    }
                    Err(e) => {
                        send_log(writer, "error", &format!("Failed to check process: {e}")).await;
                    }
                }
            }
            _ = wait_shutdown(shutdown) => {
                send_log(writer, "info", "Shutdown signal received, terminating service").await;
                let _ = child.kill().await;
                return;
            }
        }
    }
}

async fn send_health_report(writer: &SharedWriter, status: &str, exit_code: Option<i32>, workload_type: &str) {
    let mut payload = json!({
        "status": status,
        "workload_type": workload_type,
    });
    if let Some(code) = exit_code {
        payload["exit_code"] = json!(code);
    }

    let msg = Message {
        msg_type: "health_report".to_string(),
        id: next_request_id(),
        payload,
    };

    if let Err(e) = protocol::send(writer, &msg).await {
        eprintln!("[supervisor] Failed to send health report: {e}");
    }
}

async fn wait_shutdown(rx: &mut watch::Receiver<bool>) {
    while !*rx.borrow() {
        if rx.changed().await.is_err() {
            return;
        }
    }
}
