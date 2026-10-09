//! Bounded avatar I/O runs beside the connection's polling loop, never inside it.
use crate::actor::{Command, Reply};
use base64::{Engine as _, engine::general_purpose::STANDARD};
use md5::{Digest as _, Md5};
use std::{
    collections::HashMap,
    time::{Duration, Instant},
};
use tokio::{
    io::{AsyncReadExt as _, AsyncWriteExt as _},
    sync::oneshot,
    task::JoinSet,
};
use ts_model::{AvatarImage, ClientError, ClientId, NetworkError, ProtocolError};
use tsclientlib::prelude::M2BClientUpdateExt as _;
use tsclientlib::{Connection, FiletransferHandle, MessageHandle, OutCommandExt as _, StreamItem};

pub const MAX_UPLOAD_BYTES: usize = 200 * 1024;
const MAX_DOWNLOAD_BYTES: usize = 2 * 1024 * 1024;
const TIMEOUT: Duration = Duration::from_secs(12);

/// Only a temporary file lock is retryable; permission and transport failures
/// must keep their original meaning. The caller also bounds the whole command.
pub async fn retry_upload<F, Fut>(mut upload: F) -> Result<(), ClientError>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Result<(), ClientError>>,
{
    let mut attempt = 0;
    loop {
        let result = upload().await;
        let busy = matches!(&result, Err(ClientError::Protocol(error))
            if error.server_code == Some(tsclientlib::TsError::FileAlreadyInUse as u32));
        if !busy || attempt == 4 {
            return result;
        }
        tracing::debug!(attempt = attempt + 1, "avatar file busy; retrying upload");
        tokio::time::sleep(Duration::from_millis(150 << attempt)).await;
        attempt += 1;
    }
}
pub type ImageReply = oneshot::Sender<Result<AvatarImage, ClientError>>;

pub fn invalid(message: &str) -> ClientError {
    ClientError::Protocol(ProtocolError::new(message))
}

pub fn hash(bytes: &[u8]) -> String {
    format!("{:x}", Md5::digest(bytes))
}

/// Only the observed public myTS object namespace is accepted. A server cannot
/// turn a gateway into an arbitrary URL fetcher; redirects are disabled too.
pub fn cloud_url(reference: Option<&str>) -> Option<String> {
    let reference = reference?;
    let (_, text) = reference.split_once(',')?;
    let url = reqwest::Url::parse(text).ok()?;
    (url.scheme() == "https"
        && url.host_str() == Some("storage.googleapis.com")
        && url.port().is_none()
        && url.username().is_empty()
        && url.password().is_none()
        && url.query().is_none()
        && url.fragment().is_none()
        && url.path().starts_with("/ts-sys-myts-avatars/")
        && url.path().len() > "/ts-sys-myts-avatars/".len())
    .then(|| url.to_string())
}

pub fn version(client: &tsclientlib::data::Client) -> Option<String> {
    if valid_hash(&client.avatar_hash) && client.uid.is_some() {
        Some(format!(
            "uploaded:{}",
            client.avatar_hash.to_ascii_lowercase()
        ))
    } else {
        cloud_url(client.my_team_speak_avatar.as_deref())
            .map(|url| format!("hosted:{}", hash(url.as_bytes())))
    }
}

fn valid_hash(value: &str) -> bool {
    value.len() == 32 && value.bytes().all(|b| b.is_ascii_hexdigit())
}

pub fn validate_upload(bytes: &[u8]) -> Result<(), ClientError> {
    if bytes.is_empty() || bytes.len() > MAX_UPLOAD_BYTES {
        return Err(invalid("avatar must contain 1 to 204800 bytes"));
    }
    if !is_upload_image(bytes) {
        return Err(invalid("avatar must be a PNG or JPEG image"));
    }
    Ok(())
}

fn is_upload_image(bytes: &[u8]) -> bool {
    bytes.starts_with(b"\x89PNG\r\n\x1a\n") || bytes.starts_with(&[0xff, 0xd8, 0xff])
}

fn is_image(bytes: &[u8]) -> bool {
    is_upload_image(bytes)
        || bytes.starts_with(b"GIF87a")
        || bytes.starts_with(b"GIF89a")
        || (bytes.starts_with(b"RIFF") && bytes.get(8..12) == Some(b"WEBP"))
}

fn image(client_id: ClientId, version: String, bytes: Vec<u8>) -> Result<AvatarImage, ClientError> {
    if bytes.is_empty() || bytes.len() > MAX_DOWNLOAD_BYTES || !is_image(&bytes) {
        return Err(invalid("invalid avatar image"));
    }
    if let Some(expected) = version.strip_prefix("uploaded:") {
        if hash(&bytes) != expected {
            return Err(invalid("avatar checksum mismatch"));
        }
    }
    Ok(AvatarImage {
        client_id,
        version,
        image: STANDARD.encode(bytes),
    })
}

enum Transfer {
    Download {
        client_id: ClientId,
        version: String,
        reply: ImageReply,
    },
    Upload {
        bytes: Vec<u8>,
        reply: Reply,
    },
}
impl Transfer {
    fn fail(self, error: ClientError) {
        match self {
            Self::Download { reply, .. } => {
                let _ = reply.send(Err(error));
            }
            Self::Upload { reply, .. } => {
                let _ = reply.send(Err(error));
            }
        }
    }
}

pub enum Completed {
    Upload {
        result: Result<String, ClientError>,
        reply: Reply,
    },
    Download,
}

#[derive(Default)]
pub struct Transfers {
    pending: HashMap<FiletransferHandle, (Instant, Transfer)>,
    pub tasks: JoinSet<Completed>,
    uploading: bool,
}

impl Transfers {
    pub fn expire(&mut self) {
        let expired: Vec<_> = self
            .pending
            .iter()
            .filter(|(_, (at, _))| at.elapsed() >= TIMEOUT)
            .map(|(id, _)| *id)
            .collect();
        for id in expired {
            if let Some((_, transfer)) = self.pending.remove(&id) {
                if matches!(transfer, Transfer::Upload { .. }) {
                    self.uploading = false;
                }
                transfer.fail(ClientError::Timeout);
            }
        }
    }

    pub fn command(
        &mut self,
        command: Command,
        connection: &mut Connection,
        pending: &mut HashMap<MessageHandle, Reply>,
    ) -> Option<Command> {
        match command {
            Command::GetAvatar { client_id, reply } => {
                let target = connection
                    .get_state()
                    .ok()
                    .and_then(|book| book.clients.get(&tsclientlib::ClientId(client_id.get())))
                    .and_then(|client| {
                        version(client).map(|version| {
                            (
                                version,
                                client
                                    .uid
                                    .as_ref()
                                    .map(|uid| format!("/avatar_{}", uid.as_avatar())),
                                cloud_url(client.my_team_speak_avatar.as_deref()),
                            )
                        })
                    });
                let Some((version, path, url)) = target else {
                    let _ = reply.send(Err(invalid("client has no available avatar")));
                    return None;
                };
                if self.pending.len() + self.tasks.len() >= 8 {
                    let _ = reply.send(Err(invalid("too many avatar transfers")));
                    return None;
                }
                if version.starts_with("uploaded:") {
                    let Some(path) = path else {
                        let _ = reply.send(Err(invalid("avatar identity unavailable")));
                        return None;
                    };
                    match connection.download_file(tsclientlib::ChannelId(0), &path, None, None) {
                        Ok(handle) => {
                            self.pending.insert(
                                handle,
                                (
                                    Instant::now(),
                                    Transfer::Download {
                                        client_id,
                                        version,
                                        reply,
                                    },
                                ),
                            );
                        }
                        Err(error) => {
                            let _ = reply.send(Err(crate::actor::protocol_error(&error)));
                        }
                    }
                } else if let Some(url) = url {
                    self.tasks.spawn(async move {
                        let result = tokio::time::timeout(TIMEOUT, download_cloud(&url))
                            .await
                            .map_err(|_| ClientError::Timeout)
                            .and_then(|result| result)
                            .and_then(|bytes| image(client_id, version, bytes));
                        let _ = reply.send(result);
                        Completed::Download
                    });
                }
                None
            }
            Command::SetAvatar { image, reply } => {
                if self.uploading {
                    let _ = reply.send(Err(invalid("an avatar upload is already running")));
                    return None;
                }
                if let Some(bytes) = image {
                    if let Err(error) = validate_upload(&bytes) {
                        let _ = reply.send(Err(error));
                        return None;
                    }
                    let unchanged = connection
                        .get_state()
                        .ok()
                        .and_then(|book| book.clients.get(&book.own_client))
                        .is_some_and(|client| {
                            client.avatar_hash.eq_ignore_ascii_case(&hash(&bytes))
                        });
                    if unchanged {
                        let _ = reply.send(Ok(()));
                        return None;
                    }
                    match connection.upload_file(
                        tsclientlib::ChannelId(0),
                        "/avatar",
                        None,
                        bytes.len() as u64,
                        true,
                        false,
                    ) {
                        Ok(handle) => {
                            self.uploading = true;
                            self.pending.insert(
                                handle,
                                (Instant::now(), Transfer::Upload { bytes, reply }),
                            );
                        }
                        Err(error) => {
                            let _ = reply.send(Err(crate::actor::protocol_error(&error)));
                        }
                    }
                } else {
                    // Clearing the public reference is authoritative; an old file
                    // need not be downloadable for removal to succeed.
                    let mut delete = tsproto_packets::packets::OutCommand::new(
                        tsproto_packets::packets::Direction::C2S,
                        tsproto_packets::packets::Flags::empty(),
                        tsproto_packets::packets::PacketType::Command,
                        "ftdeletefile",
                    );
                    delete.write_arg("cid", &0);
                    delete.write_arg("cpw", &"");
                    delete.write_arg("name", &"/avatar");
                    let _ = delete.send(connection);
                    announce(connection, "", reply, pending);
                }
                None
            }
            other => Some(other),
        }
    }

    pub fn item(&mut self, item: StreamItem) -> Option<StreamItem> {
        match item {
            StreamItem::FileDownload(handle, mut result) => {
                if let Some((
                    _,
                    Transfer::Download {
                        client_id,
                        version,
                        reply,
                    },
                )) = self.pending.remove(&handle)
                {
                    self.tasks.spawn(async move {
                        let read = async {
                            if result.size == 0 || result.size > MAX_DOWNLOAD_BYTES as u64 {
                                return Err(invalid("avatar exceeds download size limit"));
                            }
                            let mut bytes = vec![0; result.size as usize];
                            result
                                .stream
                                .read_exact(&mut bytes)
                                .await
                                .map_err(|_| network_error())?;
                            image(client_id, version, bytes)
                        };
                        let result = tokio::time::timeout(TIMEOUT, read)
                            .await
                            .unwrap_or(Err(ClientError::Timeout));
                        let _ = reply.send(result);
                        Completed::Download
                    });
                }
                None
            }
            StreamItem::FileUpload(handle, mut result) => {
                if let Some((_, Transfer::Upload { bytes, reply })) = self.pending.remove(&handle) {
                    self.tasks.spawn(async move {
                        let write = async {
                            if result.seek_position != 0 {
                                return Err(invalid("unexpected avatar upload offset"));
                            }
                            result
                                .stream
                                .write_all(&bytes)
                                .await
                                .map_err(|_| network_error())?;
                            result
                                .stream
                                .shutdown()
                                .await
                                .map_err(|_| network_error())?;
                            // shutdown only closes our writing half. Await the
                            // server's EOF before announcing the new hash, so
                            // downloads and subsequent edits do not race its
                            // still-open upload file.
                            let mut extra = [0; 1];
                            if result
                                .stream
                                .read(&mut extra)
                                .await
                                .map_err(|_| network_error())?
                                != 0
                            {
                                return Err(invalid("unexpected avatar upload response"));
                            }
                            Ok(hash(&bytes))
                        };
                        let result = tokio::time::timeout(TIMEOUT, write)
                            .await
                            .unwrap_or(Err(ClientError::Timeout));
                        Completed::Upload { result, reply }
                    });
                }
                None
            }
            StreamItem::FiletransferFailed(handle, error) => {
                if let Some((_, transfer)) = self.pending.remove(&handle) {
                    if matches!(transfer, Transfer::Upload { .. }) {
                        self.uploading = false;
                    }
                    transfer.fail(crate::actor::protocol_error(&error));
                }
                None
            }
            other => Some(other),
        }
    }

    pub fn complete(
        &mut self,
        completed: Completed,
        connection: &mut Connection,
        pending: &mut HashMap<MessageHandle, Reply>,
    ) {
        if let Completed::Upload { result, reply } = completed {
            self.uploading = false;
            match result {
                Ok(hash) if !reply.is_closed() => announce(connection, &hash, reply, pending),
                Ok(_) => {}
                Err(error) => {
                    let _ = reply.send(Err(error));
                }
            }
        }
    }
}

fn announce(
    connection: &mut Connection,
    hash: &str,
    reply: Reply,
    pending: &mut HashMap<MessageHandle, Reply>,
) {
    let part = match connection.get_state() {
        Ok(book) => book.client_update().set_avatar_hash(hash),
        Err(_) => {
            let _ = reply.send(Err(crate::not_connected()));
            return;
        }
    };
    crate::actor::settle(part.send_with_result(connection), reply, pending);
    // The library mirrors mute/away locally, but not avatar changes. Query the
    // server after the update, so our own row follows the authoritative value.
    if let Ok(book) = connection.get_state() {
        let mut command = tsproto_packets::packets::OutCommand::new(
            tsproto_packets::packets::Direction::C2S,
            tsproto_packets::packets::Flags::empty(),
            tsproto_packets::packets::PacketType::Command,
            "clientgetvariables",
        );
        command.write_arg("clid", &book.own_client.0);
        let _ = command.send(connection);
    }
}

fn network_error() -> ClientError {
    ClientError::Network(NetworkError::new("avatar transfer failed"))
}

async fn download_cloud(url: &str) -> Result<Vec<u8>, ClientError> {
    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(TIMEOUT)
        .build()
        .map_err(|_| network_error())?;
    let mut response = client.get(url).send().await.map_err(|_| network_error())?;
    if !response.status().is_success() {
        return Err(network_error());
    }
    if response
        .content_length()
        .is_some_and(|length| length > MAX_DOWNLOAD_BYTES as u64)
    {
        return Err(invalid("avatar exceeds download size limit"));
    }
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(|_| network_error())? {
        if bytes.len() + chunk.len() > MAX_DOWNLOAD_BYTES {
            return Err(invalid("avatar exceeds download size limit"));
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn file_busy() -> ClientError {
        ClientError::Protocol(ProtocolError::from_server(
            tsclientlib::TsError::FileAlreadyInUse as u32,
            "FileAlreadyInUse",
        ))
    }

    #[tokio::test]
    async fn a_temporary_file_lock_retries_until_the_upload_succeeds() {
        // Re-editing could fail while a previous transfer still held the file.
        let mut attempts = 0;
        retry_upload(|| {
            attempts += 1;
            std::future::ready(if attempts < 3 {
                Err(file_busy())
            } else {
                Ok(())
            })
        })
        .await
        .unwrap();
        assert_eq!(attempts, 3);
    }

    #[tokio::test]
    async fn persistent_file_locks_stop_after_five_attempts() {
        let mut attempts = 0;
        let result = retry_upload(|| {
            attempts += 1;
            std::future::ready(Err(file_busy()))
        })
        .await;
        assert_eq!(attempts, 5);
        assert_eq!(result, Err(file_busy()));
    }

    #[tokio::test]
    async fn other_upload_errors_are_not_retried() {
        for error in [ClientError::Timeout, invalid("permission denied")] {
            let mut attempts = 0;
            let result = retry_upload(|| {
                attempts += 1;
                std::future::ready(Err(error.clone()))
            })
            .await;
            assert_eq!(attempts, 1);
            assert_eq!(result, Err(error));
        }
    }

    async fn sockets() -> (tokio::net::TcpStream, tokio::net::TcpStream) {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let (client, server) = tokio::join!(
            tokio::net::TcpStream::connect(listener.local_addr().unwrap()),
            listener.accept()
        );
        (client.unwrap(), server.unwrap().0)
    }

    #[tokio::test]
    async fn slow_downloads_do_not_hold_the_connection_polling_loop() {
        // Previously putting read_exact inside handle_item would stall voice
        // and keepalive traffic until all image bytes arrived.
        let bytes = b"\x89PNG\r\n\x1a\ntest".to_vec();
        let (stream, mut writer) = sockets().await;
        let mut transfers = Transfers::default();
        let (reply, mut answer) = oneshot::channel();
        transfers.pending.insert(
            FiletransferHandle(1),
            (
                Instant::now(),
                Transfer::Download {
                    client_id: ClientId::new(2),
                    version: format!("uploaded:{}", hash(&bytes)),
                    reply,
                },
            ),
        );
        assert!(
            transfers
                .item(StreamItem::FileDownload(
                    FiletransferHandle(1),
                    tsclientlib::FileDownloadResult {
                        size: bytes.len() as u64,
                        stream
                    }
                ))
                .is_none()
        );
        assert!(matches!(
            answer.try_recv(),
            Err(oneshot::error::TryRecvError::Empty)
        ));
        writer.write_all(&bytes).await.unwrap();
        let result = answer.await.unwrap().unwrap();
        assert_eq!(STANDARD.decode(result.image).unwrap(), bytes);
    }

    #[tokio::test]
    async fn upload_completion_waits_for_the_server_to_release_the_connection() {
        let bytes = b"\x89PNG\r\n\x1a\ntest".to_vec();
        let (stream, mut reader) = sockets().await;
        let mut transfers = Transfers::default();
        let (reply, mut answer) = oneshot::channel();
        transfers.pending.insert(
            FiletransferHandle(2),
            (
                Instant::now(),
                Transfer::Upload {
                    bytes: bytes.clone(),
                    reply,
                },
            ),
        );
        transfers.item(StreamItem::FileUpload(
            FiletransferHandle(2),
            tsclientlib::FileUploadResult {
                seek_position: 0,
                stream,
            },
        ));
        let mut received = Vec::new();
        reader.read_to_end(&mut received).await.unwrap();
        assert_eq!(received, bytes);
        // A full local write does not imply the server has closed its file.
        assert!(
            tokio::time::timeout(Duration::from_millis(20), transfers.tasks.join_next())
                .await
                .is_err()
        );
        reader.shutdown().await.unwrap();
        let Completed::Upload { result, reply } =
            transfers.tasks.join_next().await.unwrap().unwrap()
        else {
            panic!("expected upload");
        };
        assert_eq!(result.unwrap(), hash(&bytes));
        // The clientupdate has not been sent/acknowledged yet.
        assert!(matches!(
            answer.try_recv(),
            Err(oneshot::error::TryRecvError::Empty)
        ));
        drop(reply);
    }

    #[tokio::test]
    async fn a_transfer_without_a_server_response_expires() {
        let mut transfers = Transfers::default();
        let (reply, answer) = oneshot::channel();
        transfers.pending.insert(
            FiletransferHandle(1),
            (
                Instant::now() - TIMEOUT,
                Transfer::Download {
                    client_id: ClientId::new(2),
                    version: "old".into(),
                    reply,
                },
            ),
        );
        transfers.expire();
        assert_eq!(answer.await.unwrap(), Err(ClientError::Timeout));
        assert!(transfers.pending.is_empty());
    }
    #[test]
    fn hosted_references_cannot_fetch_arbitrary_servers_or_credentials() {
        assert!(
            cloud_url(Some(
                "2,https://storage.googleapis.com/ts-sys-myts-avatars/user/1"
            ))
            .is_some()
        );
        for url in [
            "2,http://storage.googleapis.com/ts-sys-myts-avatars/u/1",
            "2,https://127.0.0.1/a",
            "2,https://storage.googleapis.com/another-bucket/x",
            "2,https://user:secret@storage.googleapis.com/ts-sys-myts-avatars/u/1",
            "2,https://storage.googleapis.com/ts-sys-myts-avatars/u/1?token=secret",
        ] {
            assert!(cloud_url(Some(url)).is_none());
        }
    }
    #[test]
    fn downloaded_bytes_must_match_the_announced_revision() {
        let bytes = b"\x89PNG\r\n\x1a\ntest".to_vec();
        let version = format!("uploaded:{}", hash(&bytes));
        assert!(image(ClientId::new(1), version, bytes.clone()).is_ok());
        assert!(
            image(
                ClientId::new(1),
                "uploaded:00000000000000000000000000000000".into(),
                bytes
            )
            .is_err()
        );
    }
    #[test]
    fn upload_limits_and_formats_are_checked_before_network_io() {
        assert!(validate_upload(b"\x89PNG\r\n\x1a\n").is_ok());
        assert!(validate_upload(b"not an image").is_err());
        assert!(validate_upload(&vec![0; MAX_UPLOAD_BYTES + 1]).is_err());
        assert_eq!(hash(b"hello"), "5d41402abc4b2a76b9719d911017c592");
    }
}
