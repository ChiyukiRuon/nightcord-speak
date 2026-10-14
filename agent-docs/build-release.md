# Build, Test, and Release

## Bootstrap

Run from the repository root:

```sh
git submodule update --init --recursive
bash scripts/fetch-fonts.sh
cargo build -p ts-ffi
```

Rust is pinned in `rust-toolchain.toml`; Flutter is pinned in release/Pages configuration and must satisfy `apps/client/pubspec.yaml`. Fonts are downloaded and SHA-256 checked; `bash scripts/fetch-fonts.sh --check` validates without downloading. All declared fonts/licenses must exist before Flutter checks.

Native audio requires CMake and a C/C++ toolchain. Linux needs `libasound2-dev` and `pkg-config`. Windows requires Visual Studio's C++ workload; on this workstation select installed VS 2019 BuildTools:

```powershell
$env:CMAKE_GENERATOR = 'Visual Studio 16 2019'
cargo build -p ts-ffi
```

Do not hardcode that generator into shared configuration or macOS commands. Preserve `.cargo/config.toml`'s `CMAKE_POLICY_VERSION_MINIMUM=3.5` for Opus with CMake 4, and the `audiopus_sys` dev optimization override preventing MSVC debug/release CRT mismatch. The vendor `audio` feature is required for voice packet transport.

## Commands and Verification

| Directory     | Command                                                                | Purpose                       |
|---------------|------------------------------------------------------------------------|-------------------------------|
| Root          | `cargo run -p nightcord-cli -- --address <host> --nickname <name>`     | Headless client               |
| Root          | `cargo run -p nightcord-gateway`                                       | Loopback gateway on port 8787 |
| Root          | `bash scripts/fmt.sh --check`                                          | Maintained Rust packages only |
| Root          | `cargo clippy --workspace --all-targets --all-features -- -D warnings` | Rust lint gate                |
| Root          | `cargo test --workspace --all-features`                                | Rust suite                    |
| Root          | `python -m unittest discover -s scripts/tests`                         | Release-helper tests          |
| `apps/client` | `flutter pub get`                                                      | Flutter dependencies          |
| `apps/client` | `dart format lib test`                                                 | Dart formatting               |
| `apps/client` | `flutter analyze` / `flutter test`                                     | Static checks / Flutter suite |
| `apps/client` | `flutter run -d windows` / `flutter run -d macos`                      | Native client                 |
| Root          | `python scripts/build-web.py`                                          | Web deployment build          |

FFI tests load the real Rust library. The loader searches ancestor `target/debug` before `target/release`; rebuild debug FFI after ABI/core changes so an older library cannot mask a release build. Native platform builds copy the library into the bundle automatically.

Rust uses four-space indentation and 100-column rustfmt; Dart uses two spaces and `flutter_lints`. Files use snake_case, types PascalCase, Dart members camelCase, and Flutter tests `*_test.dart`. Add regression coverage for behavior fixes and protocol/error/state boundaries. Keep tests independent and real-server validation in separate smoke tools. No numeric coverage threshold is configured.

Analyze before building. Close Windows applications before overwriting binaries (`MSB3073` can mean locked EXE/DLL). New `Icons.*` additions can leave a stale release subset: use `flutter clean` when needed, rebuild, and inspect release UI. Verify actual executable/plugin DLL paths and timestamps before attributing results to new code.

## macOS and Native Validation

Build on a Mac with Xcode, CMake, CocoaPods, compatible Flutter, and pinned Rust. Verify `xcode-select -p`, UTF-8 locale, and noninteractive PATH (cargo, Flutter, Homebrew). The documented LAN node is `agent@192.168.31.33`, checkout `~/workspace/nightcord-speak`; confirm the current address. An SSH-only account may lack a GUI session.

Both Debug and Release require network-client, network-server (UDP), and audio-input entitlements. Preserve `NSMicrophoneUsageDescription` and localized resources; missing microphone usage text can terminate the process.

The Xcode Rust build phase matches Flutter mode/architecture, copies the dylib into `Contents/Frameworks`, and quotes product paths with spaces. Debug Cargo output is `target/debug`, not `target/dev`. Main-window/menu exit finishes core shutdown; child-window close ends only that viewing session.

Windows screenshot/DPI probes must set PerMonitorV2 awareness before measuring. Logical Flutter units differ from physical pixels; a DPI-unaware capture can falsely suggest clipping.

## Desktop Update Diagnostics

Desktop updates use the core log (`desktop update:` prefix) and persistent `updates/update-<attempt>.log` files below `coreLogDirectory()`. Helpers keep writing after core shutdown; Windows also preserves the Inno installer log alongside the helper trace. If persistent logging is unavailable, helpers fall back to the transaction directory; failed transactions remain available for recovery. Log phases, elapsed time, HTTP status, byte counts, helper PIDs, exit codes, elevation and rollback outcomes. Never log signed CDN URLs, configuration payloads, or user secrets. Diagnostic failures must not interrupt installation or rollback. Verify persistence and unavailable sinks with the isolated Windows smoke tool and macOS updater tests.

Windows PowerShell can fail before script execution when launched with Dart's process APIs on this machine; a console-based PowerShell broker smoke does not reproduce the installed GUI environment. `launchWindowsUpdateHelper` calls the main runner's `nightcord/lifecycle` channel, which launches the hidden worker through `ShellExecuteExW` and returns its PID or a numeric Win32 error. Keep the worker independent of the client and preserve the readiness/commit handshake. `tool/windows_update_smoke.ps1` builds a console-free GUI probe using the same native launcher, checks paths with Unicode, spaces and apostrophes, and verifies installation after the probe exits. Do not use PowerShell `Start-Process -Wait` to wait for this probe: it also waits for the updater descendant and blocks the readiness/commit handshake; use the probe process's `WaitForExit` instead.

Before publishing readiness and after the parent exits, the Windows helper must reject other processes running the target installation's executable. Waiting for only the requesting PID does not release DLLs held by another instance. Windows update exit posts `WM_CLOSE` to the main native window through `nightcord/lifecycle`, preserving the normal Dart cleanup callback. Close any application launched for deployment verification before handing control back to the user; a leftover hidden instance can block installation and rollback.

macOS keeps the main app sandboxed. Launch the installer through the private `NightcordUpdateLauncher.xpc` service, not `open --args` or a direct sandboxed `NSWorkspace` call: ad-hoc-signed nested apps can be rejected by Launch Services before entry. The service validates the request's parent PID against its XPC caller and starts only its sealed sibling updater. Preserve separate signatures for the launcher and installer; re-sign only the outer app with its sandbox entitlements. Package both helpers and test the launch/ready/abort handshake from a sandboxed probe, alongside the standalone transaction tests. Direct executable or transaction tests alone miss the startup restriction.

macOS shutdown must keep the ordinary run loop alive until the main isolate
acknowledges core cleanup. Return `terminateCancel` while cleanup is pending,
then schedule the final termination on `RunLoop.main` and return `terminateNow`.
Do not call `NSApp.terminate` from a dispatch callback before asynchronous cleanup:
its `terminateLater` modal loop can block the queued channel callback. The native
exit probe reproduces this with the actual runner delegate; the Flutter update
smoke entry exercises real core shutdown, XPC startup, replacement and restart
using a disposable bundle with a sealed `Contents/Resources/fixture.zip`.
After commit, keep the update controller busy until exit instead of enabling a
second installation. Prefer Launch Services for restart; if it fails, launch the
verified bundle executable and check that the new process remains running.

Every file the sandboxed client writes, including the downloaded package, carries the hard sandbox quarantine (`com.apple.quarantine` flags `0086`). `ditto -x` propagates it to every extracted file, and AppleDouble entries stored in an archive restore it even with `--noqtn`. The kernel then rejects the replacement and its nested helpers with `EPERM` through Launch Services, `open` and direct exec alike, while `codesign --verify` still passes, so the failure surfaces only after the client has exited and the helper rolls back. Clear the attribute from the staged bundle before publishing readiness, and keep the updater tests' fixture package quarantined the same way. An SSH session without a GUI domain cannot use Launch Services (`OSLaunchdErrorDomain 125`); smoke runs there exercise only the direct-exec restart path.

## Release Maintenance

Publishing requires explicit authorization. `release.yml` builds Windows, macOS, and Web on `v*` tags or manual dispatch with an existing version tag. Every job checks out the resolved tag revision; never package the dispatch branch under another tag's version. Ordinary Rust CI runs on PR/manual triggers. Gateway image publishing uses its own workflow/conditions.

Accepted tags are `vX.Y.Z` or `vX.Y.Z-{alpha,beta,rc}.N` (N starts at 1). `desktop-release.py prepare` derives product versions/build numbers; internal Rust versions need not follow every product release. Review `.github/release-platforms.json` for selected platforms.

Use the workflow's current artifact set: Windows bundles/installers, architecture-specific macOS bundles, and the Web universal ZIP, all with hashes/manifests. Web archives put `index.html` at the root and must match the release version/build number in `version.json`. Verify every selected platform before publishing. Server upload is not part of the workflow. Preserve resources, native libraries, permissions/symlinks, and architecture consistency; an EXE alone is not a working package. Keep corresponding symbols for crash analysis.

Submodule commits must be remotely available before pushing a release tag. Publish only after all selected platforms and manifests/hashes validate. Never replace public attachments; fixes need a new patch tag. Inspect signing configuration rather than assuming notarization/publisher signing from build success.

Authorized PRs should explain behavior changes, link relevant issues, state validation and limitations, and include screenshots for UI changes. Keep commits focused and use concise Chinese Conventional Commit descriptions.
