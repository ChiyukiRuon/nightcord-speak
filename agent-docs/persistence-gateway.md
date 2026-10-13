# Persistence, Diagnostics, and Gateway

## User Data

Use `ts_identity::app_data_root()` instead of duplicating OS paths. Mobile sandbox roots come from the host app. Keep identity, settings, bookmarks, avatars, logs, and crash evidence responsibilities distinct.

- Generate identity only when absent; preserve it across reconnect and persist level upgrades. Malformed identity is an error, not a fresh start.
- Settings use field defaults/atomic writes; unknown fields remain compatible. On corruption, warn and use defaults while retaining the source file.
- Native `bookmarks.json` is separate from shareable settings because it contains plaintext passwords. Preserve redacted Debug and restrictive file permissions.
- Evolve Rust/Dart settings together or Rust may discard frontend fields. Preserve nullable/absent semantics and nonzero defaults such as output volume.
- Voice settings persist intent and apply to active engines where supported; unrelated edits must not reopen streams.

## Avatars

Valid server MD5 avatars precede public myTeamSpeak avatars. Classic filenames use UID raw bytes with a–p nibble encoding, not literal Base64; validate MD5.

Cloud URLs stay inside the adapter, restricted to the existing Google Storage namespace without redirects. Preserve size/concurrency/cache limits; do not enable arbitrary-URL fetching. Frontends receive opaque versions/image bytes and fall back to initials.

Own avatar is global across servers. Keep original image/edit transforms local, upload only the bounded PNG, and update `client_flag_avatar` after transfer succeeds. Removal clears stored source/edit state. Do not write myTeamSpeak cloud-account avatars or upload original images.

## Logging and Crash Evidence

User-visible failures use existing logging hooks with secrets/chat redacted. `NIGHTCORD_LOG` overrides `RUST_LOG`; empty `NIGHTCORD_LOG_DIR` means stderr only. Keep bounded nonblocking writes and process-lifetime guard.

Crash notes use direct synchronous writes because asynchronous queues can lose final records. Failed workers/forced exit retain abnormal markers; successful shutdown clears them. Preserve existing console behavior when installing Dart handlers. Reports must exclude passwords, private keys, and raw chats.

## Device Isolation

Gateway devices have isolated cores; tabs of one device share sessions/events/voice, while different devices cannot control one another. Browser `shutdown` must not terminate the gateway process.

Browser recovery credentials are random public ID plus secret, scoped by browser profile/page Origin/gateway URL. TS private keys stay server-side under `<data-dir>/devices/<public-id>/`. Validate recovery secret before attachment; use only validated public ID in paths. Never log credentials or place them in URLs.

Final-tab closure releases PTT and preserves the existing short refresh grace period. Keep identity/settings after core eviction. Complete cleanup before rebuilding a device core. Preserve live-device limits, bounded queues, and atomic snapshot/subscription.

## Browser Bookmarks

Web bookmarks live in page-Origin localStorage (`nightcord.bookmarks.v1`), independent of gateway selection; identity/settings remain on the gateway. Keep one-time per-gateway legacy merge: local identical-address entries win, deleted entries cannot reappear, and old server files remain intact.

`bookmark_prepare` validates through Rust without writing a gateway bookmark. Success/failure retain the random request ID so only the originating tab handles a broadcast response. Storage refusal/quota errors are save failures. Preserve storage-event tab synchronization; browser passwords remain plaintext and must not enter diagnostics.

## Handshake and Web Deployment

`hello` negotiates protocol/auth/device requirements. Initial client frame is `attach` without gateway auth or `auth` with Token, including device credentials; validated welcome/snapshots precede commands. Preserve handshake timeouts and message limits.

Only nonempty `NIGHTCORD_GATEWAY_TOKEN` enables authentication. Token controls entry; device secret controls ownership. Token travels in the initial WebSocket frame, never query parameters. Origin checks do not replace authentication.

Bindings default to loopback port 8787. Explicit `--allow-origin` replaces defaults; current checks compare scheme/host, not port. No-Origin native clients still follow Token policy.

Gateway serves `/ws` and diagnostic assets, not Flutter hosting. `python scripts/build-web.py` consumes deployment environment; direct Flutter commands do not automatically read it. Product output is `apps/client/build/web`; Pages uses `bash scripts/build-pages.sh` without requiring Rust.

HTTPS pages require WSS. Microphone/AudioWorklet require secure contexts: localhost is an exception; LAN HTTP is not. Audio startup needs a user gesture. Successful LAN HTTP chat does not validate phone audio.

Preconfigured URLs auto-connect and prevent target overrides/manual fallback. A preconfigured Token is readable in browser code; use a build without preconfigured gateway when credentials must be entered manually. Build-system secret flags cannot make shipped credentials private.

## Containers

Compose runs Rust gateway only. Browser audio needs neither host sound-device mounting nor privileged containers. `.env.example` documents runtime configuration; actual `.env` secrets stay excluded from Git/build context.

Preserve `/data`, UID/GID 10001 write access, read-only root, and signal-driven shutdown. `docker compose down --volumes` deletes identities/settings; ordinary updates must retain the volume. Back up stopped-service data with ownership intact.

`python scripts/gateway-docker-smoke.py --image <local-image>` tests isolated projects/volumes. Health indicates HTTP availability, not TS connection. Proxies/tunnels preserve Origin and WebSocket Upgrade; configure browser-reachable WSS rather than a Compose service name.
