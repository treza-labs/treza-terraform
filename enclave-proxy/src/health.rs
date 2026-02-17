use std::convert::Infallible;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use bytes::Bytes;
use http_body_util::Full;
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Request, Response};
use serde_json::json;
use tokio::net::TcpListener;
use tokio::sync::watch;

const LISTEN_PORT: u16 = 8888;

/// Start the health endpoint on 127.0.0.1:8888.
pub async fn serve(
    vsock_connected: Arc<AtomicBool>,
    mut shutdown: watch::Receiver<bool>,
) {
    let addr = SocketAddr::from(([127, 0, 0, 1], LISTEN_PORT));
    let listener = match TcpListener::bind(addr).await {
        Ok(l) => l,
        Err(e) => {
            eprintln!("[health] Failed to bind {addr}: {e}");
            return;
        }
    };

    loop {
        tokio::select! {
            result = listener.accept() => {
                match result {
                    Ok((stream, _)) => {
                        let connected = vsock_connected.clone();
                        tokio::spawn(async move {
                            let svc = service_fn(move |req| {
                                handle_request(req, connected.clone())
                            });
                            let _ = http1::Builder::new()
                                .serve_connection(hyper_util::rt::TokioIo::new(stream), svc)
                                .await;
                        });
                    }
                    Err(e) => {
                        eprintln!("[health] Accept error: {e}");
                    }
                }
            }
            _ = wait_shutdown(&mut shutdown) => {
                break;
            }
        }
    }
}

async fn handle_request(
    _req: Request<hyper::body::Incoming>,
    vsock_connected: Arc<AtomicBool>,
) -> Result<Response<Full<Bytes>>, Infallible> {
    let connected = vsock_connected.load(Ordering::Relaxed);
    let body = json!({
        "status": "healthy",
        "proxy": "running",
        "vsock": if connected { "connected" } else { "disconnected" },
    });

    let body_bytes = serde_json::to_vec(&body).unwrap_or_default();
    Ok(Response::builder()
        .status(200)
        .header("content-type", "application/json")
        .header("content-length", body_bytes.len().to_string())
        .body(Full::new(Bytes::from(body_bytes)))
        .unwrap())
}

async fn wait_shutdown(rx: &mut watch::Receiver<bool>) {
    while !*rx.borrow() {
        if rx.changed().await.is_err() {
            return;
        }
    }
}
