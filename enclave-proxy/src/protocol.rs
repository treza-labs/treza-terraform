use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use tokio::io;
use tokio::net::tcp::{OwnedReadHalf, OwnedWriteHalf};
use tokio::net::TcpStream;
use tokio::sync::{oneshot, Mutex};

static REQUEST_COUNTER: AtomicU64 = AtomicU64::new(0);

pub fn next_request_id() -> String {
    let id = REQUEST_COUNTER.fetch_add(1, Ordering::SeqCst) + 1;
    format!("req-{id}")
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    #[serde(rename = "type")]
    pub msg_type: String,
    pub id: String,
    pub payload: Value,
}

/// Shared writer half, protected by a mutex for concurrent sends.
pub type SharedWriter = Arc<Mutex<OwnedWriteHalf>>;

/// Map of request IDs to oneshot senders waiting for responses.
pub type PendingMap = Arc<Mutex<HashMap<String, oneshot::Sender<Message>>>>;

/// Split a TcpStream (vsock) into a shared writer and the reader half.
pub fn split_connection(stream: TcpStream) -> (SharedWriter, OwnedReadHalf) {
    let (read, write) = stream.into_split();
    (Arc::new(Mutex::new(write)), read)
}

/// Send a message through the shared writer.
pub async fn send(writer: &SharedWriter, msg: &Message) -> io::Result<()> {
    let payload = serde_json::to_vec(msg).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    let mut w = writer.lock().await;
    // Re-assemble into a TcpStream-like write via the OwnedWriteHalf
    use tokio::io::AsyncWriteExt;
    let len = payload.len() as u32;
    w.write_all(&len.to_be_bytes()).await?;
    w.write_all(&payload).await?;
    w.flush().await
}

/// Read one message from the reader half.
pub async fn recv(reader: &mut OwnedReadHalf) -> io::Result<Option<Message>> {
    use tokio::io::AsyncReadExt;

    let mut header = [0u8; 4];
    match reader.read_exact(&mut header).await {
        Ok(_) => {}
        Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => return Ok(None),
        Err(e) => return Err(e),
    }

    let length = u32::from_be_bytes(header) as usize;
    if length > 10 * 1024 * 1024 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("Message too large: {length}"),
        ));
    }

    let mut buf = vec![0u8; length];
    reader.read_exact(&mut buf).await?;

    let msg: Message = serde_json::from_slice(&buf)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    Ok(Some(msg))
}

/// Response dispatcher: reads messages from parent and routes responses
/// to pending request waiters by ID.
pub async fn response_dispatcher(
    mut reader: OwnedReadHalf,
    pending: PendingMap,
    shutdown: tokio::sync::watch::Receiver<bool>,
) {
    loop {
        tokio::select! {
            result = recv(&mut reader) => {
                match result {
                    Ok(Some(msg)) => {
                        let mut map = pending.lock().await;
                        if let Some(sender) = map.remove(&msg.id) {
                            let _ = sender.send(msg);
                        }
                    }
                    Ok(None) => {
                        eprintln!("[enclave-proxy] Parent connection closed");
                        break;
                    }
                    Err(e) => {
                        eprintln!("[enclave-proxy] Read error: {e}");
                        break;
                    }
                }
            }
            _ = shutdown_recv(&shutdown) => {
                break;
            }
        }
    }
}

async fn shutdown_recv(rx: &tokio::sync::watch::Receiver<bool>) {
    let mut rx = rx.clone();
    while !*rx.borrow() {
        if rx.changed().await.is_err() {
            return;
        }
    }
}

/// Send a request and wait for the matching response by ID.
pub async fn request(
    writer: &SharedWriter,
    pending: &PendingMap,
    msg_type: &str,
    payload: Value,
    timeout_secs: u64,
) -> io::Result<Message> {
    let id = next_request_id();
    let (tx, rx) = oneshot::channel();

    {
        let mut map = pending.lock().await;
        map.insert(id.clone(), tx);
    }

    let msg = Message {
        msg_type: msg_type.to_string(),
        id: id.clone(),
        payload,
    };
    send(writer, &msg).await?;

    match tokio::time::timeout(std::time::Duration::from_secs(timeout_secs), rx).await {
        Ok(Ok(response)) => Ok(response),
        Ok(Err(_)) => {
            let mut map = pending.lock().await;
            map.remove(&id);
            Err(io::Error::new(io::ErrorKind::BrokenPipe, "Response channel closed"))
        }
        Err(_) => {
            let mut map = pending.lock().await;
            map.remove(&id);
            Err(io::Error::new(io::ErrorKind::TimedOut, format!("Request {id} timed out")))
        }
    }
}
