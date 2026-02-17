mod health;
mod http_proxy;
mod kms_proxy;
mod logging;
mod protocol;
mod supervisor;
mod vsock;

use std::collections::HashMap;
use std::env;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use std::time::Duration;

use serde_json::json;
use tokio::sync::{watch, Mutex};

use protocol::{PendingMap, SharedWriter};

const VSOCK_PORT: u32 = 5000;
const MAX_RETRIES: u32 = 30;
const RETRY_DELAY_SECS: u64 = 10;

#[tokio::main]
async fn main() {
    let enclave_id = env::var("ENCLAVE_ID").unwrap_or_else(|_| "unknown".to_string());
    let workload_type = env::var("TREZA_WORKLOAD_TYPE").unwrap_or_else(|_| "batch".to_string());
    let health_interval: u64 = env::var("TREZA_HEALTH_INTERVAL")
        .unwrap_or_else(|_| "30".to_string())
        .parse()
        .unwrap_or(30);

    eprintln!("[enclave-proxy] Starting for {enclave_id} (workload: {workload_type})");

    // Connect to parent proxy via vsock
    let stream = match connect_with_retry().await {
        Some(s) => s,
        None => {
            eprintln!("[enclave-proxy] FATAL: Could not connect to parent");
            std::process::exit(1);
        }
    };

    let (writer, reader) = protocol::split_connection(stream);
    let pending: PendingMap = Arc::new(Mutex::new(HashMap::new()));
    let vsock_connected = Arc::new(AtomicBool::new(true));

    // Shutdown channel
    let (shutdown_tx, shutdown_rx) = watch::channel(false);

    // Send handshake
    if let Err(e) = send_handshake(&writer, &enclave_id).await {
        eprintln!("[enclave-proxy] Handshake failed: {e}");
        std::process::exit(1);
    }

    // Start response dispatcher
    {
        let pending = pending.clone();
        let shutdown_rx = shutdown_rx.clone();
        tokio::spawn(async move {
            protocol::response_dispatcher(reader, pending, shutdown_rx).await;
        });
    }

    logging::send_log(&writer, "info", &format!("Enclave proxy started for {enclave_id}")).await;

    // Fetch and log PCR values
    if let Some(pcrs) = logging::fetch_pcrs(&writer, &pending).await {
        if let Some(pcr0) = pcrs.get("PCR0").and_then(|v| v.as_str()) {
            logging::send_log(&writer, "info", &format!("PCR0: {pcr0}")).await;
        }
    }

    // Start HTTP proxy server
    {
        let w = writer.clone();
        let p = pending.clone();
        let rx = shutdown_rx.clone();
        tokio::spawn(async move {
            http_proxy::serve(w, p, rx).await;
        });
    }

    // Start KMS proxy server
    {
        let w = writer.clone();
        let p = pending.clone();
        let rx = shutdown_rx.clone();
        tokio::spawn(async move {
            kms_proxy::serve(w, p, rx).await;
        });
    }

    // Start health endpoint
    {
        let connected = vsock_connected.clone();
        let rx = shutdown_rx.clone();
        tokio::spawn(async move {
            health::serve(connected, rx).await;
        });
    }

    // Small delay to let servers bind
    tokio::time::sleep(Duration::from_millis(500)).await;

    // Set up signal handling
    let shutdown_tx_signal = shutdown_tx.clone();
    tokio::spawn(async move {
        let mut sigterm = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("Failed to register SIGTERM");
        let mut sigint = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::interrupt())
            .expect("Failed to register SIGINT");

        tokio::select! {
            _ = sigterm.recv() => {
                eprintln!("[enclave-proxy] Received SIGTERM");
            }
            _ = sigint.recv() => {
                eprintln!("[enclave-proxy] Received SIGINT");
            }
        }

        let _ = shutdown_tx_signal.send(true);
    });

    // Resolve and run user command
    if let Some(user_cmd) = supervisor::resolve_user_command() {
        supervisor::run(
            writer.clone(),
            pending.clone(),
            &user_cmd,
            &workload_type,
            health_interval,
            shutdown_rx.clone(),
            shutdown_tx,
        )
        .await;
    } else {
        logging::send_log(&writer, "warn", "No user command configured; running in standalone mode").await;
        // Wait for shutdown
        let mut rx = shutdown_rx.clone();
        while !*rx.borrow() {
            if rx.changed().await.is_err() {
                break;
            }
        }
    }

    logging::send_log(&writer, "info", "Enclave proxy shutting down").await;
    // Brief delay to flush final logs
    tokio::time::sleep(Duration::from_secs(2)).await;
}

async fn connect_with_retry() -> Option<tokio::net::TcpStream> {
    eprintln!("[enclave-proxy] Waiting for parent proxy...");
    tokio::time::sleep(Duration::from_secs(5)).await;

    for attempt in 1..=MAX_RETRIES {
        match vsock::connect(VSOCK_PORT).await {
            Ok(stream) => {
                eprintln!("[enclave-proxy] Connected on attempt {attempt}");
                return Some(stream);
            }
            Err(e) => {
                eprintln!("[enclave-proxy] Attempt {attempt}/{MAX_RETRIES} failed: {e}");
                if attempt < MAX_RETRIES {
                    tokio::time::sleep(Duration::from_secs(RETRY_DELAY_SECS)).await;
                }
            }
        }
    }

    None
}

async fn send_handshake(writer: &SharedWriter, enclave_id: &str) -> std::io::Result<()> {
    let msg = protocol::Message {
        msg_type: "handshake".to_string(),
        id: protocol::next_request_id(),
        payload: json!({
            "enclave_id": enclave_id,
            "protocol_version": "2.0",
            "capabilities": ["http_proxy", "kms_proxy", "log_stream", "health"],
        }),
    };
    protocol::send(writer, &msg).await
}
