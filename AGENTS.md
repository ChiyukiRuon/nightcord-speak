# Repository Guidelines

## Working Agreements

- Inspect existing code and conventions before editing. Write human-facing documentation/comments in Chinese and agent-facing guidance in English.
- Never commit, push, tag, or publish without explicit user authorization. Authorized commits use concise Conventional Commits: `type(scope): description` (Chinese descriptions match history).
- Keep this file limited to essential constraints; put task-specific guidance in [agent-docs/README.md](agent-docs/README.md). Do not add development diaries or historical test counts.

## Architecture Boundaries

- `crates/ts-*` owns the Rust core; `apps/cli` and `apps/gateway` are its executables; `apps/client` owns the shared Flutter UI, tests, assets, and localization.
- Keep dependencies downward. `ts-model` has no internal-crate dependencies; domain values must not expose vendor protocol types. Keep TS6 extensions out of core/session logic.
- TS3/TS6 share `ts-protocol-tsclient`; do not duplicate their base protocol implementation. Only that adapter may depend directly on `tsclientlib`.
- Native FFI and the Web gateway share core behavior and `ts-wire` command/event vocabulary. Use opaque numeric handles across C ABI; never expose Rust object pointers or block ordinary commands on the Dart UI thread.
- Native voice PCM stays in Rust, outside JSON/FFI. Screen media uses `ScreenShareBackend`/WebRTC; Rust handles its signaling. Browser voice uses its separate WebSocket audio bridge.
- UI depends on domain models, capabilities, and `ClientTransport`, not vendor protocol details. Keep shared design/features/state; choose adaptive layout by viewport/input capability, and isolate platform services behind adapters.

## State, Identity, and Safety

- The protocol actor exclusively owns the connection and must keep polling its event stream; awaiting a command while stopping polling can deadlock transmission.
- The actor owns reconnect policy (`ReconnectMode::External`). Reuse identity and connection configuration; identity corruption is an error, never permission to generate a replacement.
- `Disconnected` is terminal: never emit it during reconnect attempts. Every session event carries its `SessionId`; consume the Dart event stream instead of adding a competing FFI queue reader.
- Missing permission hints mean unknown, not denied; the server remains authoritative. Do not report queued commands as accepted before their server result, except documented stream-command handling.
- Keep private keys out of FFI; redact passwords, tokens, device recovery secrets, and chat text from logs/Debug. Required password command payloads must not be copied into diagnostics.
- Persist through existing stores and `ts_identity::app_data_root()`; preserve atomic writes and distinguish identity corruption from recoverable settings corruption. Never reset user data to fix a development problem.
- Route user-visible failures into the existing logging path. Explicitly shut down the core on main-window exit; provider disposal alone does not run reliably.

## Build and Verification Traps

- Initialize recursive submodules: `git submodule update --init --recursive`. Keep `vendor/` outside the workspace and preserve fork patches; crates.io/upstream replacements lose required behavior.
- Before Flutter analyze/test/build, run `bash scripts/fetch-fonts.sh`; declared fonts are gitignored and missing assets fail checks. Use pinned Rust and Flutter versions from toolchain/workflows.
- Native builds require CMake and a C++ toolchain. On this Windows machine use `$env:CMAKE_GENERATOR='Visual Studio 16 2019'`; do not hardcode that machine-specific choice into shared configuration.
- Use `bash scripts/fmt.sh --check`, never `cargo fmt --all` (it reformats vendor path dependencies). Add every new workspace crate to the script's explicit package list.
- Build real FFI first: `cargo build -p ts-ffi`; then, from `apps/client`, run `flutter analyze` and `flutter test`. Analyze before building; close the running Windows app before overwriting its EXE/DLL.
- Rust checks: `cargo clippy --workspace --all-targets --all-features -- -D warnings` and `cargo test --workspace --all-features`. Run checks relevant to the change; keep real-server smoke tests separate from unit tests.
- After changing ARB keys, update all five languages and run `flutter gen-l10n` in `apps/client`; keep generated Dart files in the change because analyze/test do not regenerate them.
- After adding release icons, invalidate the stale icon subset (`flutter clean` if needed) and inspect a fresh release build. Debug/widget tests cannot detect this issue.

## Read Before Changing These Areas

- [Architecture and protocol](agent-docs/architecture-protocol.md): actor ownership, command replies, reconnect, subscription, fork boundaries.
- [Build and release](agent-docs/build-release.md): native prerequisites, FFI loading, macOS permissions, packaging and release triggers.
- [Client UI and localization](agent-docs/client-ui.md): design tokens, rejected layouts, language/font synchronization, notifications and PTT.
- [Audio and screen sharing](agent-docs/media.md): PCM format/gating, TS6 signaling, SDP size, multi-engine lifecycle.
- [Persistence and gateway](agent-docs/persistence-gateway.md): store compatibility, device isolation, browser bookmarks, authentication and secure contexts.
