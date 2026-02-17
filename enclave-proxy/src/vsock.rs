use std::io;
use std::os::unix::io::{FromRawFd, RawFd};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

const AF_VSOCK: i32 = 40;
const VMADDR_CID_HOST: u32 = 3;

#[repr(C)]
struct SockaddrVm {
    svm_family: libc::sa_family_t,
    svm_reserved1: u16,
    svm_port: u32,
    svm_cid: u32,
    svm_zero: [u8; 4],
}

/// Create a vsock connection to the host (CID 3) on the given port.
/// Returns a tokio TcpStream wrapping the raw vsock fd.
pub async fn connect(port: u32) -> io::Result<TcpStream> {
    let fd = unsafe { libc::socket(AF_VSOCK, libc::SOCK_STREAM, 0) };
    if fd < 0 {
        return Err(io::Error::last_os_error());
    }

    let addr = SockaddrVm {
        svm_family: AF_VSOCK as libc::sa_family_t,
        svm_reserved1: 0,
        svm_port: port,
        svm_cid: VMADDR_CID_HOST,
        svm_zero: [0; 4],
    };

    let ret = unsafe {
        libc::connect(
            fd,
            &addr as *const SockaddrVm as *const libc::sockaddr,
            std::mem::size_of::<SockaddrVm>() as libc::socklen_t,
        )
    };

    if ret < 0 {
        let err = io::Error::last_os_error();
        unsafe { libc::close(fd); }
        return Err(err);
    }

    // Set non-blocking for tokio
    unsafe {
        let flags = libc::fcntl(fd, libc::F_GETFL);
        libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK);
    }

    let std_stream = unsafe { std::net::TcpStream::from_raw_fd(fd as RawFd) };
    TcpStream::from_std(std_stream)
}

/// Send a length-prefixed JSON message over the stream.
pub async fn send_message(stream: &mut TcpStream, payload: &[u8]) -> io::Result<()> {
    let len = payload.len() as u32;
    stream.write_all(&len.to_be_bytes()).await?;
    stream.write_all(payload).await?;
    stream.flush().await
}

/// Receive a length-prefixed JSON message from the stream.
/// Returns None if the connection is closed.
pub async fn recv_message(stream: &mut TcpStream) -> io::Result<Option<Vec<u8>>> {
    let mut header = [0u8; 4];
    match stream.read_exact(&mut header).await {
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
    stream.read_exact(&mut buf).await?;
    Ok(Some(buf))
}
