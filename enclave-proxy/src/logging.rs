use serde_json::json;

use crate::protocol::{self, Message, PendingMap, SharedWriter, next_request_id};

/// Send a log message to the parent via vsock.
pub async fn send_log(writer: &SharedWriter, level: &str, message: &str) {
    let msg = Message {
        msg_type: "log".to_string(),
        id: next_request_id(),
        payload: json!({
            "level": level,
            "message": message,
            "timestamp": std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs_f64(),
        }),
    };

    if let Err(e) = protocol::send(writer, &msg).await {
        eprintln!("[enclave-proxy] Failed to send log: {e}");
    }

    // Also print locally
    eprintln!("[enclave-proxy] [{level}] {message}");
}

/// Request PCR values from the parent.
pub async fn fetch_pcrs(writer: &SharedWriter, pending: &PendingMap) -> Option<serde_json::Value> {
    match protocol::request(writer, pending, "pcr_request", json!({}), 30).await {
        Ok(resp) => {
            let pcrs = resp.payload.get("pcr_values").cloned().unwrap_or_default();
            Some(pcrs)
        }
        Err(e) => {
            eprintln!("[enclave-proxy] Failed to fetch PCRs: {e}");
            None
        }
    }
}
