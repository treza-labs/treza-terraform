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

const LISTEN_PORT: u16 = 3128;

/// Start the HTTP proxy server on 127.0.0.1:3128.
/// Forwards all HTTP requests to the parent via vsock.
pub async fn serve(
    writer: SharedWriter,
    pending: PendingMap,
    mut shutdown: watch::Receiver<bool>,
) {
    let addr = SocketAddr::from(([127, 0, 0, 1], LISTEN_PORT));
    let listener = match TcpListener::bind(addr).await {
        Ok(l) => l,
        Err(e) => {
            eprintln!("[http-proxy] Failed to bind {addr}: {e}");
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
                                    eprintln!("[http-proxy] Connection error: {e}");
                                }
                            }
                        });
                    }
                    Err(e) => {
                        eprintln!("[http-proxy] Accept error: {e}");
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
    let method = req.method().to_string();
    let url = req.uri().to_string();

    // Collect headers, filtering out hop-by-hop headers
    let mut headers = serde_json::Map::new();
    for (name, value) in req.headers() {
        let n = name.as_str().to_lowercase();
        if n != "host" && n != "proxy-connection" && n != "proxy-authorization" {
            if let Ok(v) = value.to_str() {
                headers.insert(name.as_str().to_string(), json!(v));
            }
        }
    }

    // Read body
    let body_bytes = match req.collect().await {
        Ok(collected) => collected.to_bytes(),
        Err(e) => {
            let resp = Response::builder()
                .status(502)
                .body(Full::new(Bytes::from(format!("Body read error: {e}"))))
                .unwrap();
            return Ok(resp);
        }
    };
    let body_str = String::from_utf8_lossy(&body_bytes).to_string();

    let payload = json!({
        "method": method,
        "url": url,
        "headers": headers,
        "body": body_str,
    });

    match protocol::request(&writer, &pending, "http_request", payload, 60).await {
        Ok(resp_msg) => {
            let p = &resp_msg.payload;
            let status = p.get("status").and_then(|v| v.as_u64()).unwrap_or(502) as u16;
            let resp_headers = p.get("headers").and_then(|v| v.as_object());
            let resp_body = p.get("body").and_then(|v| v.as_str()).unwrap_or("");

            let mut builder = Response::builder().status(status);
            if let Some(hdrs) = resp_headers {
                for (k, v) in hdrs {
                    let kl = k.to_lowercase();
                    if kl != "transfer-encoding" && kl != "content-length" {
                        if let Some(s) = v.as_str() {
                            builder = builder.header(k.as_str(), s);
                        }
                    }
                }
            }

            let body_bytes = Bytes::from(resp_body.to_string());
            builder = builder.header("content-length", body_bytes.len().to_string());
            Ok(builder.body(Full::new(body_bytes)).unwrap())
        }
        Err(e) => {
            let status = if e.kind() == std::io::ErrorKind::TimedOut { 504 } else { 502 };
            let msg = if status == 504 { "Gateway Timeout" } else { "Bad Gateway" };
            Ok(Response::builder()
                .status(status)
                .body(Full::new(Bytes::from(format!("{msg}: {e}"))))
                .unwrap())
        }
    }
}

async fn wait_shutdown(rx: &mut watch::Receiver<bool>) {
    while !*rx.borrow() {
        if rx.changed().await.is_err() {
            return;
        }
    }
}
