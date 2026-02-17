use std::convert::Infallible;
use std::net::SocketAddr;

use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Request, Response};
use serde_json::json;
use tokio::net::TcpListener;
use tokio::sync::watch;

use crate::protocol::{self, PendingMap, SharedWriter};

const LISTEN_PORT: u16 = 8000;

/// Start the KMS proxy server on 127.0.0.1:8000.
/// Forwards POST requests as kms_request to the parent via vsock.
pub async fn serve(
    writer: SharedWriter,
    pending: PendingMap,
    mut shutdown: watch::Receiver<bool>,
) {
    let addr = SocketAddr::from(([127, 0, 0, 1], LISTEN_PORT));
    let listener = match TcpListener::bind(addr).await {
        Ok(l) => l,
        Err(e) => {
            eprintln!("[kms-proxy] Failed to bind {addr}: {e}");
            return;
        }
    };

    loop {
        tokio::select! {
            result = listener.accept() => {
                match result {
                    Ok((stream, _)) => {
                        let w = writer.clone();
                        let p = pending.clone();
                        tokio::spawn(async move {
                            let svc = service_fn(move |req| {
                                handle_request(req, w.clone(), p.clone())
                            });
                            if let Err(e) = http1::Builder::new()
                                .serve_connection(hyper_util::rt::TokioIo::new(stream), svc)
                                .await
                            {
                                if !e.to_string().contains("connection closed") {
                                    eprintln!("[kms-proxy] Connection error: {e}");
                                }
                            }
                        });
                    }
                    Err(e) => {
                        eprintln!("[kms-proxy] Accept error: {e}");
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
    req: Request<hyper::body::Incoming>,
    writer: SharedWriter,
    pending: PendingMap,
) -> Result<Response<Full<Bytes>>, Infallible> {
    // Extract path before consuming the body
    let path = req.uri().path().trim_matches('/').to_string();

    // Read body
    let body_bytes = match req.collect().await {
        Ok(collected) => collected.to_bytes(),
        Err(e) => {
            return Ok(json_response(500, json!({"error": format!("Body read error: {e}")})));
        }
    };

    let data: serde_json::Value = match serde_json::from_slice(&body_bytes) {
        Ok(v) => v,
        Err(_) => json!({}),
    };

    let payload = json!({
        "operation": path,
        "data": data,
    });

    match protocol::request(&writer, &pending, "kms_request", payload, 30).await {
        Ok(resp_msg) => {
            let p = &resp_msg.payload;
            if let Some(err) = p.get("error").and_then(|v| v.as_str()) {
                Ok(json_response(400, json!({"error": err})))
            } else {
                let result = p.get("result").cloned().unwrap_or(json!({}));
                Ok(json_response(200, result))
            }
        }
        Err(e) => {
            Ok(json_response(500, json!({"error": format!("KMS error: {e}")})))
        }
    }
}

fn json_response(status: u16, body: serde_json::Value) -> Response<Full<Bytes>> {
    let body_bytes = serde_json::to_vec(&body).unwrap_or_default();
    Response::builder()
        .status(status)
        .header("content-type", "application/json")
        .header("content-length", body_bytes.len().to_string())
        .body(Full::new(Bytes::from(body_bytes)))
        .unwrap()
}

async fn wait_shutdown(rx: &mut watch::Receiver<bool>) {
    while !*rx.borrow() {
        if rx.changed().await.is_err() {
            return;
        }
    }
}
