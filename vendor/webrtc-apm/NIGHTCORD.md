# WebRTC APM source provenance

This directory contains the unmodified bundled WebRTC AudioProcessing 2.1
sources from the crates.io `webrtc-audio-processing-sys` 2.1.0 package,
published from tonarino/webrtc-audio-processing commit
`c14d7af1760baff83e8210fee336a0cae0faaa7d`.

Local build patch: do not define `WEBRTC_ENABLE_SYMBOL_EXPORT` when statically
linking the module into the Rust library. This prevents MSVC from exporting
internal WebRTC C++ symbols through the application's FFI DLL.

Abseil 20240722.0 and its Meson build definitions are downloaded using the
SHA-256-pinned upstream `subprojects/abseil-cpp.wrap`. Generated/downloaded
subprojects are ignored. See COPYING, webrtc/PATENTS and individual bundled
third-party licenses. The processing algorithm remains upstream C++.
