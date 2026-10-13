# Agent Documentation

Read the topic relevant to the task after reading [AGENTS.md](../AGENTS.md).

| Topic | Consult when changing |
| --- | --- |
| [Architecture and protocol](architecture-protocol.md) | Crate boundaries, actor/event flow, TS3/TS6 commands, reconnect or vendor dependencies |
| [Build and release](build-release.md) | Toolchains, native builds, FFI tests, packaging or macOS permissions |
| [Client UI and localization](client-ui.md) | Layout, themes, fonts, translations, notifications or shortcuts |
| [Audio and screen sharing](media.md) | Voice frames, transmit policy, WebRTC, TS6 stream signaling or detached windows |
| [Persistence and gateway](persistence-gateway.md) | Identity, settings, avatars, bookmarks, browser state, gateway auth or deployment |

These notes distill the supplied documentation from `C:\Users\ChiyukiRuon\Downloads\docs`, with repository configuration and relevant implementations checked on 2026-10-13. Development diaries, milestone counts, old verification reports, and speculative roadmaps are omitted.

Some sources describe earlier designs: React Web, shared gateway identity, TS6 screen sharing as unimplemented, or fewer supported languages. Those descriptions must not guide new changes. Flutter is the product UI for native/web; device cores are isolated; TS6 screen sharing exists; localization covers English, Simplified/Traditional Chinese, Japanese, and Korean.

Inspect current code before relying on commands or numeric limits. Toolchain/configuration files determine versions; tests and implementations determine behavior. Update the focused note and relevant tests when changing an invariant. Keep root guidance short and do not accumulate work logs here.
