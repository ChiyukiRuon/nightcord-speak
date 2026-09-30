//! The non-WebSocket half of the single port.
//!
//! One listener serves two things: the WebSocket upgrade on `/ws`, and a
//! handful of static files for the debug page. That is the whole HTTP layer —
//! a framework would be a dependency and a router for four routes.
//!
//! The routing cannot live in the upgrade callback: `tungstenite` only accepts
//! a non-2xx response from there, so a page could never be served through it
//! (its `ProtocolError::CustomResponseSuccessful`). Instead the request line
//! is *peeked* — `peek` does not consume, so the stream is untouched when it is
//! handed to the WebSocket handshake.

use std::io;
use std::path::Path;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

/// The path the WebSocket lives on.
pub const WS_PATH: &str = "/ws";

/// How much of a request line the peek will buffer before giving up.
///
/// A request line is a few dozen bytes; this only has to be small enough that
/// a hostile client cannot make the gateway allocate without bound.
const MAX_REQUEST_LINE: usize = 8 * 1024;

/// The embedded debug page.
///
/// The same two files a Cloudflare Pages deployment uploads
/// (`crates/ts-gateway/web/`), compiled in so the gateway is one file to run.
const INDEX_EMBEDDED: &str = include_str!("../web/index.html");
const WORKLET_EMBEDDED: &str = include_str!("../web/pcm-worklet.js");

/// What a request should be answered with.
#[derive(Debug, PartialEq, Eq)]
pub enum Route {
    /// Hand the (still unread) stream to the WebSocket handshake.
    WebSocket,
    /// Serve a file from the page directory or the embedded copy.
    Page,
    /// Nothing here.
    NotFound,
}

/// Reads the request line without consuming it.
///
/// Loops because `peek` may return a partial line — a TCP segment boundary can
/// land anywhere, and a one-shot peek would route on half a URL.
pub async fn peek_request_line(stream: &TcpStream) -> io::Result<String> {
    let mut buffered = Vec::with_capacity(256);
    loop {
        let mut chunk = [0u8; 256];
        let read = stream.peek(&mut chunk).await?;
        if read == 0 {
            return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof,
                "the client closed before sending a request",
            ));
        }
        buffered.extend_from_slice(&chunk[..read]);
        if let Some(end) = find_crlf(&buffered) {
            // Lossy on purpose: a non-UTF-8 request line is not worth an
            // error, and it can only fail to match a route.
            return Ok(String::from_utf8_lossy(&buffered[..end]).into_owned());
        }
        if buffered.len() >= MAX_REQUEST_LINE {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "request line too long",
            ));
        }
    }
}

fn find_crlf(bytes: &[u8]) -> Option<usize> {
    bytes.windows(2).position(|pair| pair == b"\r\n")
}

/// Decides what `request_line` asks for.
///
/// Anything that is not a plain `GET` is a 404: this server has no other
/// verbs, and saying so with a status rather than an error keeps browsers
/// honest.
#[must_use]
pub fn route(request_line: &str) -> Route {
    let mut parts = request_line.split_whitespace();
    let (Some("GET"), Some(target)) = (parts.next(), parts.next()) else {
        return Route::NotFound;
    };
    // The query string is the page's business (`?gw=`), not the router's.
    let path = target.split('?').next().unwrap_or(target);

    match path {
        WS_PATH => Route::WebSocket,
        "/" | "/index.html" | "/pcm-worklet.js" => Route::Page,
        _ => Route::NotFound,
    }
}

/// The body and content type for one of the page's files.
///
/// `web_root` is the directory someone is editing; without it the embedded
/// copy is served, which is what a deployed gateway uses. A read failure falls
/// back to the embedded copy rather than 404ing — the page is what makes the
/// gateway usable, and the embedded one is never wrong, only older.
async fn page_file(path: &str, web_root: Option<&Path>) -> (&'static str, Vec<u8>) {
    let name = if path == "/" || path == "/index.html" {
        "index.html"
    } else {
        "pcm-worklet.js"
    };
    let content_type = if name.ends_with(".js") {
        "text/javascript; charset=utf-8"
    } else {
        "text/html; charset=utf-8"
    };

    if let Some(root) = web_root {
        match tokio::fs::read(root.join(name)).await {
            Ok(body) => return (content_type, body),
            Err(error) => {
                tracing::warn!(%error, file = name, "could not read the page file; serving the embedded copy");
            }
        }
    }

    let embedded = if name == "index.html" {
        INDEX_EMBEDDED
    } else {
        WORKLET_EMBEDDED
    };
    (content_type, embedded.as_bytes().to_vec())
}

/// Consumes the request head — the part `peek_request_line` deliberately left
/// in the socket.
///
/// Not optional housekeeping: closing a socket with unread data still in its
/// receive buffer makes Windows answer with RST, and the RST can beat the
/// response to the client. The reader then sees `ConnectionReset` instead of
/// the page. Reading to the end of the headers first is what makes the close
/// orderly.
pub async fn consume_request_head(stream: &mut TcpStream) -> io::Result<()> {
    const MAX_HEAD: usize = 64 * 1024;
    let mut seen = 0usize;
    let mut window = Vec::with_capacity(4);
    let mut chunk = [0u8; 1024];
    loop {
        let read = stream.read(&mut chunk).await?;
        if read == 0 {
            return Ok(());
        }
        for byte in &chunk[..read] {
            window.push(*byte);
            if window.len() > 4 {
                window.remove(0);
            }
            if window == b"\r\n\r\n" {
                return Ok(());
            }
        }
        seen += read;
        if seen >= MAX_HEAD {
            return Ok(());
        }
    }
}

/// Answers `path` with the page.
pub async fn serve_page(
    stream: &mut TcpStream,
    path: &str,
    web_root: Option<&Path>,
) -> io::Result<()> {
    consume_request_head(stream).await?;
    let (content_type, body) = page_file(path, web_root).await;
    write_response(stream, "200 OK", content_type, &body).await
}

/// Answers with a refusal the browser can read.
pub async fn serve_error(stream: &mut TcpStream, status: &str) -> io::Result<()> {
    write_response(stream, status, "text/plain", b"refused\n").await
}

/// Writes a minimal HTTP/1.1 response and closes.
///
/// `Connection: close` on purpose: every response here is one file, and
/// keep-alive would only add a state machine to get wrong.
async fn write_response(
    stream: &mut TcpStream,
    status: &str,
    content_type: &str,
    body: &[u8],
) -> io::Result<()> {
    let head = format!(
        "HTTP/1.1 {status}\r\n\
         Content-Type: {content_type}\r\n\
         Content-Length: {}\r\n\
         Cache-Control: no-store\r\n\
         Connection: close\r\n\
         \r\n",
        body.len(),
    );
    stream.write_all(head.as_bytes()).await?;
    stream.write_all(body).await?;
    stream.flush().await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_get_is_a_route() {
        assert_eq!(route("GET / HTTP/1.1"), Route::Page);
        assert_eq!(route("GET /index.html HTTP/1.1"), Route::Page);
        assert_eq!(route("GET /pcm-worklet.js HTTP/1.1"), Route::Page);
        assert_eq!(route("GET /ws HTTP/1.1"), Route::WebSocket);
        // The query string is the page's, not the router's.
        assert_eq!(route("GET /?gw=ws://x/ws HTTP/1.1"), Route::Page);
        assert_eq!(route("GET /ws?v=1 HTTP/1.1"), Route::WebSocket);

        assert_eq!(route("POST /ws HTTP/1.1"), Route::NotFound);
        assert_eq!(route("GET /etc/passwd HTTP/1.1"), Route::NotFound);
        assert_eq!(route("GET /../secret HTTP/1.1"), Route::NotFound);
        assert_eq!(route("garbage"), Route::NotFound);
        assert_eq!(route(""), Route::NotFound);
    }

    #[tokio::test]
    async fn a_peeked_request_line_leaves_the_stream_untouched() {
        // The whole routing scheme depends on this: after the peek, the
        // handshake must still see every byte the client sent.
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let sent = "GET /ws HTTP/1.1\r\nHost: x\r\n\r\nbody-bytes";

        let client = tokio::spawn(async move {
            let mut stream = tokio::net::TcpStream::connect(addr).await.unwrap();
            tokio::io::AsyncWriteExt::write_all(&mut stream, sent.as_bytes())
                .await
                .unwrap();
            // Hold the connection open while the server peeks.
            tokio::time::sleep(std::time::Duration::from_millis(200)).await;
            drop(stream);
        });

        let (stream, _) = listener.accept().await.unwrap();
        let line = peek_request_line(&stream).await.unwrap();
        assert_eq!(line, "GET /ws HTTP/1.1");
        assert_eq!(route(&line), Route::WebSocket);

        // Everything is still readable in order.
        let mut readable = stream;
        let mut buffer = vec![0u8; sent.len()];
        tokio::io::AsyncReadExt::read_exact(&mut readable, &mut buffer)
            .await
            .unwrap();
        assert_eq!(String::from_utf8_lossy(&buffer), sent);

        client.await.unwrap();
    }
}
