# Architecture and Protocol

## Ownership and Dependencies

- `ts-model` defines protocol-independent data, IDs, capabilities, and `ClientError`. External dependencies are allowed; internal-crate dependencies are not.
- `ts-protocol` defines narrow capabilities and composes them into `Backend`. Unsupported operations return `ClientError::Unsupported` rather than succeeding silently.
- `ts-session` owns session lifecycle; `ts-audio` owns voice processing. They communicate through interfaces such as `AudioSink`, without depending on each other.
- `ts-core` selects backends and manages identity/settings/sessions. Audio engines are attached by FFI/CLI/gateway integration, not the facade.
- `ts-identity` owns storage and application data paths; backends provide cryptographic generation. Logging/crash crates receive paths from callers.
- `ts-protocol-tsclient` converts vendor snapshots/domain events. TS3/TS6 crates declare protocol identity and implement their own extensions.
- `ts-wire` is shared JSON vocabulary, not transport/behavior. Extend native/gateway paths consistently for new commands/events.

## Connection Actor

The vendor connection needs mutable access and continuous event polling even to transmit queued packets. Keep it in one actor with mpsc commands and oneshot replies. Do not place it behind a mutex and await commands without polling.

The select loop reconstructs `connection.events()`, receives an owned outcome, drops the stream borrow, then mutates the connection. Preserve this borrowing/polling pattern.

`send_with_result` enqueues a packet; `StreamItem::MessageResult` is the server result. Keep pending handle-to-reply mappings and release pending senders on actor exit so callers cannot wait forever. Map missing permission IDs into actionable domain errors. Library operational failures return `Result`, not panic.

## Snapshots and Events

- Vendor book updates go through snapshot conversion/diff. Channel moves emit `ClientMoved`, not merely `ClientUpdated`.
- Subscribe to all channels after handshake and permission changes; otherwise changing channels looks like leaving the server.
- Request `servergetvariables` on each connection and after permission changes. Online count uses server-reported clients minus query clients, bounded below by visible non-query clients.
- Permission hints are optional. Missing hints while connected must not disable valid operations; explicit server rejection remains authoritative.
- Broadcast consumers must not block the network loop. New subscribers obtain snapshots, not replayed history. Gateway subscription and snapshot acquisition remain atomic.
- Preserve session IDs and idempotent snapshot application. Dart consumers use `client.events`, not a second FFI queue reader.

## Reconnect and Identity

Only the actor schedules reconnects. The fork's `ReconnectMode::External` disables vendor retry delays; two retry loops would conflict.

Reuse the same configuration/identity. Existing retry delays are 1, 2, 4, 8, 16 seconds, capped at 30. Disconnect interrupts backoff; commands requiring an absent connection fail promptly. Initial handshake failure returns to the caller without duplicate UI errors.

Keep the view during reconnect. `ReconnectScheduled` communicates retries; `Disconnected` is terminal. Successful handshakes update connection state even after the first-connect oneshot was consumed.

Persist identity-level upgrades. Malformed identity files fail explicitly; only a truly absent identity may be generated. Preserve atomic writes and restrictive permissions.

## Vendor Forks

`vendor/tsclientlib` and `vendor/flutter-webrtc` use recorded commits on `nightcord` forks. Protocol declarations are a nested submodule required at compile time; Cargo git dependencies do not initialize them. Keep `vendor` excluded from this workspace.

The protocol fork follows the `webspeak3` lineage, not the older default `master`; it carries unknown-command passthrough, declarations/safety fixes, private-address support, and external reconnect control. Replacing it with crates.io `tsclientlib` loses required behavior.

Private TS/TSDNS targets are allowed by default; `BLOCK_PRIVATE_TARGETS=1` restores strict blocking. Preserve the separate file-transfer redirect protection. Do not mutate environment inside a running Flutter process to bypass resolver checks: Rust 2024 environment mutation is unsafe once threads exist.

Declare Rust versions in workspace dependencies; child crates use `workspace = true`. Review existing dependencies before adding another, and update `scripts/fmt.sh` for new workspace members.
