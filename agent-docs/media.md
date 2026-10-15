# Audio and Screen Sharing

## Voice Pipeline

`ts-audio` owns native capture, resampling, Opus encoding, VAD/PTT, and playback. The vendor backend owns transport, decryption, jitter/loss handling, decoding, and mixing. `AudioSink` is the boundary; `ts-audio` must not depend on vendor protocol libraries.

| Path | Format per 20 ms |
| --- | --- |
| Native capture/send and decoded receive | 48 kHz, stereo interleaved f32, 1920 samples |
| Browser microphone/gateway upstream | 48 kHz, mono f32, 960 samples |

Use `ts-audio::format` constants. Capture stays stereo regardless of transmit mode; changing send channels must not reopen the microphone. Desktop uses Opus Music, web uses Opus Voice; encoder code owns bitrate and `voice_status` supplies display data.

Playback uses a nonblocking SPSC ring; underrun produces silence. Muted playback still drains decoding so unmuting cannot play old speech. Keep callback work bounded without blocking locks/log writes.

`TransmitPolicy` owns transmit decisions:

- Input mute, deafen, and away close transmission in every mode.
- PTT bypasses VAD; continuous mode sends unless closed by those gates.
- Mode/mute transitions reset gate state; unmuting must pass activation again.
- Input gain applies after raw-level gating, before encoding, so gain does not alter VAD sensitivity.
- `is_resume` marks a transition from not transmitting to transmitting.

Mute/mode before startup is intent, not a missing-device error; apply it when starting the engine. Distinguish requested device from actual fallback (`fell_back`) and transient errors from unavailable/invalidated streams. Poll status instead of adding 50 Hz JSON events.

Per-person volume acts before vendor mixing and survives speaker-queue recreation. Total volume acts after mixing. Stored `output_volume` defaults to 1.0, not f32's 0.0; gain is dB with unity at 0.0.

Microphone transmit gain includes a fixed +15 dB baseline in `ts_audio::microphone_gain`, shared by native and gateway paths. Stored/displayed `input_gain_db` is the user's relative adjustment and defaults to 0 dB; never place the fixed boost in the settings default. Preserve explicit saved adjustments and digital silence.

Speaker output includes a fixed +10 dB baseline at native device playback and browser output gain. Apply it once after mixing, multiplied by the user's existing output-volume fraction; keep zero volume and deafen silent. Gateway PCM remains unboosted to avoid applying compensation twice.

Gain must not hard-clip before limiting. Native/gateway microphone gain and final native/browser output use linked-channel peak limiting at -1 dBFS, with 5 ms lookahead and 80 ms release. A zero gain or privacy reset discards delayed samples. Native output mute flushes the ring on its consumer callback, not by racing its read index from another thread.

Native microphone audio passes through the original C++ WebRTC APM 2.1 noise suppressor in `ts-audio::denoise`, at moderate strength, before VAD and gain. Split each 20 ms stereo frame into two planar 10 ms blocks. Keep processing while VAD is closed so estimates remain continuous. AEC and AGC are disabled; there is no render reference, and gain belongs to the shared Rust path. Browser capture uses its browser NS/AEC, without a second gateway denoiser. The standalone C++ sources and license provenance are under `vendor/webrtc-apm`; its internal pointers never cross the public client FFI.

`VoiceSendBuffer` retains at most 160 ms before voice activation and replays it chronologically when the gate opens. This may add up to that much startup playout buffering. Only the first replayed packet carries the resume flag. PTT/continuous/disabled detection bypass pre-roll. Policy generation changes invalidate history on mute, deafen, away, mode/algorithm changes and reconnect; device changes also reset filter history. Never replay history recorded across these boundaries.

Non-48 kHz capture uses a 64-tap Blackman-windowed polyphase sinc filter with a rate-dependent anti-alias cutoff. Integer phase accumulation makes callback chunking independent and prevents numeric drift; filter delay is about 31 input samples. The 48 kHz path stays bit-exact. Share immutable coefficient tables between channels, never their sample histories.

## Screen Media Boundary

TS6 signaling uses Rust commands/events; picture/audio use independent P2P WebRTC. The gateway does not relay screen media. TS3 lacks this capability; UI checks capabilities rather than protocol names.

`ScreenShareBackend` owns media; `ScreenController` orchestrates it. Keep TS6 wire behavior in `ts-protocol-ts6`.

## Signaling Constraints

- The server assigns stream IDs; `setupstream` has no client-selected ID. Cancelling before the ID arrives must stop a late local-publisher announcement.
- Decode raw unknown-command parameters with `get_str()`, not `get_raw()`; SDP/JSON contain TeamSpeak escapes. Skip an invalid parameter without dropping other valid ones.
- Signal keys are asymmetric: `args.offer`, `args.answer`, and ICE `args.{sdp, mid, mLine}`. Wrong keys can be accepted by the server and ignored by peers.
- Preserve stream enum values and publisher-client-ID versus stream-ID distinctions. Streaming flags drive UI; discovery resolves the ID when viewing.
- Stop/leave for already-ended targets may get no reply. Do not send them after server-stopped/rejected events; stale failures must not dismantle newer established media.
- Retry only explicitly rejected flooding (`0x020c`) with bounded TS6 delays. Do not replay timeout/uncertain-delivery or permission failures.

TS6 commands have an empirically observed boundary around 8 KiB, not an exact standardized limit. Oversized SDP can vanish without error. Preserve compact codec preferences (VP8/rtx and Opus) and BUNDLE candidate compaction; test offer growth for new tracks/codecs. Preserve non-BUNDLE/unique connectivity paths. Batch ICE briefly into SDP to avoid flooding while retaining late/unmatched trickle candidates.

Publisher admission enforces nonpublic approval and automatic viewer limits; the server may only forward requests. Preserve request cancellation/peer cleanup. Advertise audio only when capture produced an audio track, include all captured tracks in the offer, and inspect platform capabilities instead of assuming loopback support.

## Detached Windows

Flutter textures belong to one engine. Detached viewing creates its own peer; release the old viewer before child joining. Wait for submitted SDP and remote media before handoff. Failure closes the child and restores embedded viewing.

Preserve unique per-opening channels, handler/subscription readiness, serialized open/close, and late-result cleanup. Reuse remote streams in `onTrack`; add tracks only to a synthetic stream when none exists. Peer-owned remote tracks are not local capture tracks to stop again.

`windows/cmake/webrtc_multi_engine.cmake` protects messenger ownership and process-global WebRTC lifetime. Keep guards/patches; review upstream changes rather than edit Pub cache. Closing one engine must not terminate SSL/threads still used by others.

Use relevant `apps/client/tool/*smoke*` tools for repeated open/close, native title-bar close, return-to-embedded viewing, and main-engine survival. Widget tests cannot establish real rendering/connectivity, captured sound, or native-engine stability; distinguish these in validation reports.
