//! TS6 P2P stream vocabulary. Media is handled by the frontend's WebRTC backend.

use std::collections::BTreeMap;
use ts_model::{
    ClientError, ClientId, ScreenAccess, ScreenCommand, ScreenEvent, ScreenMode, ScreenOptions,
    ScreenSignal, ScreenSource,
};
use ts_protocol_tsclient::extension::{ExtensionCommand, ScreenExtension};

pub struct Screen;

const CLIENT_IS_FLOODING: u32 = 0x020c;

fn invalid() -> ClientError {
    ClientError::Unsupported("invalid screen sharing request".into())
}

/// TS6's `type`: what is being captured.
///
/// Recovered from TS6's own UI bundle, not inferred — see the reference
/// implementation's `StreamSource` table.
fn source_of(source: ScreenSource) -> &'static str {
    match source {
        ScreenSource::Camera => "1",
        ScreenSource::Screen => "2",
        ScreenSource::Window => "3",
    }
}

/// TS6's Privacy setting.
fn access_of(access: ScreenAccess) -> &'static str {
    match access {
        ScreenAccess::Public => "1",
        ScreenAccess::Contacts => "2",
        ScreenAccess::Private => "3",
    }
}

/// TS6's Connection Mode.
///
/// `Sfu` is refused rather than encoded: routing through the server needs a
/// client for its media router, and telling the server we are using one we do
/// not have would produce a stream that fails somewhere with no explanation.
fn mode_of(mode: ScreenMode) -> Result<&'static str, ClientError> {
    match mode {
        ScreenMode::P2p => Ok("1"),
        ScreenMode::Sfu => Err(ClientError::Unsupported(
            "screen sharing through the server's media router is not implemented".into(),
        )),
    }
}

/// Rejects values no capture could produce.
///
/// Not policy — which range the UI offers is the UI's business. These are the
/// points past which the number must have come from a mistake, and a stream the
/// server has already been told about is an expensive place to discover one.
fn check(options: &ScreenOptions) -> Result<(), ClientError> {
    let sane = options.height <= 4320
        && options.fps <= 240
        && options.video_bitrate_kbps > 0
        && options.video_bitrate_kbps <= 100_000
        && options.audio_bitrate_kbps <= 512
        && options.viewer_limit <= 1024;
    if sane && !(options.audio && options.audio_bitrate_kbps == 0) {
        Ok(())
    } else {
        Err(invalid())
    }
}

impl ScreenExtension for Screen {
    fn retry_delay(&self, attempt: u32, error: &ClientError) -> Option<std::time::Duration> {
        if attempt >= 2 {
            return None;
        }
        match error {
            ClientError::Protocol(error) if error.server_code == Some(CLIENT_IS_FLOODING) => {
                Some(std::time::Duration::from_secs(if attempt == 0 {
                    3
                } else {
                    6
                }))
            }
            _ => None,
        }
    }
    fn encode(&self, command: ScreenCommand) -> Result<ExtensionCommand, ClientError> {
        let leaving = matches!(&command, ScreenCommand::Leave { .. });
        let mut args = BTreeMap::new();
        let name = match command {
            ScreenCommand::Discover { client_id } => {
                args.insert("clid".into(), client_id.get().to_string());
                "requeststreaminfo"
            }
            ScreenCommand::Start { name, options } => {
                if name.len() > 256 {
                    return Err(invalid());
                }
                check(&options)?;
                args.extend([
                    ("name".into(), name),
                    ("type".into(), source_of(options.source).into()),
                    (
                        "bitrate".into(),
                        (options.video_bitrate_kbps * 1000).to_string(),
                    ),
                    ("accessibility".into(), access_of(options.access).into()),
                    ("mode".into(), mode_of(options.mode)?.into()),
                    ("viewer_limit".into(), options.viewer_limit.to_string()),
                    ("audio".into(), u8::from(options.audio).to_string()),
                ]);
                "setupstream"
            }
            ScreenCommand::Stop { stream_id } => {
                args.insert("id".into(), stream_id);
                args.insert("reason".into(), String::new());
                "stopstream"
            }
            ScreenCommand::Join {
                stream_id,
                client_id,
            }
            | ScreenCommand::Leave {
                stream_id,
                client_id,
            } => {
                args.insert("id".into(), stream_id);
                args.insert("clid".into(), client_id.get().to_string());
                args.insert("msg".into(), String::new());
                args.insert("is_remove".into(), if leaving { "1" } else { "0" }.into());
                "joinstreamrequest"
            }
            ScreenCommand::Respond {
                stream_id,
                client_id,
                accept,
                sdp,
            } => {
                args.insert("id".into(), stream_id);
                args.insert("clid".into(), client_id.get().to_string());
                args.insert("decision".into(), if accept { "1" } else { "0" }.into());
                args.insert("msg".into(), String::new());
                args.insert("offer".into(), sdp);
                "respondjoinstreamrequest"
            }
            ScreenCommand::Signal {
                stream_id,
                client_id,
                signal,
            } => {
                args.insert("id".into(), stream_id);
                args.insert("clid".into(), client_id.get().to_string());
                let payload = match signal {
                    ScreenSignal::Offer { sdp } => {
                        serde_json::json!({"cmd":"offer", "args":{"offer":sdp}})
                    }
                    ScreenSignal::Answer { sdp } => {
                        serde_json::json!({"cmd":"answer", "args":{"answer":sdp}})
                    }
                    ScreenSignal::Candidate {
                        candidate,
                        mid,
                        line,
                    } => {
                        serde_json::json!({"cmd":"iceCandidate", "args":{"sdp":candidate,"mid":mid,"mLine":line}})
                    }
                };
                args.insert("json".into(), payload.to_string());
                "streamsignaling"
            }
        };
        if args
            .get("id")
            .is_some_and(|id| id.is_empty() || id.len() > 256)
            || args
                .values()
                .any(|value| value.len() > 65536 || value.contains('\0'))
        {
            return Err(invalid());
        }
        Ok(ExtensionCommand {
            name,
            arguments: args,
        })
    }

    fn decode(&self, name: &str, args: &BTreeMap<String, String>) -> Option<ScreenEvent> {
        let stream_id = args.get("id")?.clone();
        if stream_id.is_empty() || stream_id.len() > 256 {
            return None;
        }
        if name == "notifystreamstopped" {
            return Some(ScreenEvent::Stopped { stream_id });
        }
        let client_id = ClientId::new(args.get("clid")?.parse().ok()?);
        Some(match name {
            "notifystreaminfo" | "notifystreamstarted" => ScreenEvent::Available {
                stream_id,
                client_id,
                name: args.get("name").cloned().unwrap_or_default(),
            },
            "notifyjoinstreamrequest" => ScreenEvent::JoinRequested {
                stream_id,
                client_id,
                leaving: args.get("is_remove").is_some_and(|v| v == "1"),
            },
            "notifyrespondjoinstreamrequest" => ScreenEvent::JoinAnswered {
                stream_id,
                client_id,
                accepted: args.get("decision").is_some_and(|v| v == "1"),
                sdp: args.get("offer").cloned().unwrap_or_default(),
            },
            "notifystreamclientleft" => ScreenEvent::PeerLeft {
                stream_id,
                client_id,
            },
            "notifystreamsignaling" => {
                let json = args.get("json")?;
                if json.len() > 65536 {
                    return None;
                }
                let value: serde_json::Value = serde_json::from_str(json).ok()?;
                let a = &value["args"];
                let signal = match value["cmd"].as_str()? {
                    "offer" | "reconnectOffer" => ScreenSignal::Offer {
                        sdp: a["offer"].as_str()?.into(),
                    },
                    "answer" => ScreenSignal::Answer {
                        sdp: a["answer"].as_str()?.into(),
                    },
                    "iceCandidate" => ScreenSignal::Candidate {
                        candidate: a["sdp"].as_str()?.into(),
                        mid: a["mid"].as_str()?.into(),
                        line: a["mLine"].as_u64()?.try_into().ok()?,
                    },
                    _ => return None,
                };
                ScreenEvent::Signal {
                    stream_id,
                    client_id,
                    signal,
                }
            }
            _ => return None,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn flood_refusal_retries_are_bounded_and_other_errors_are_not_replayed() {
        // Rapid window handovers used to fail on the server's flood budget.
        let flood = ClientError::Protocol(ts_model::ProtocolError::from_server(
            CLIENT_IS_FLOODING,
            "client is flooding",
        ));
        assert_eq!(
            Screen.retry_delay(0, &flood),
            Some(std::time::Duration::from_secs(3))
        );
        assert_eq!(
            Screen.retry_delay(1, &flood),
            Some(std::time::Duration::from_secs(6))
        );
        assert_eq!(Screen.retry_delay(2, &flood), None);
        assert_eq!(Screen.retry_delay(0, &ClientError::Timeout), None);
        let other = ClientError::Protocol(ts_model::ProtocolError::from_server(1, "other"));
        assert_eq!(Screen.retry_delay(0, &other), None);
    }

    #[test]
    fn answer_uses_the_peer_expected_key_and_redacts_credentials() {
        let command = ScreenCommand::Signal {
            stream_id: "stream".into(),
            client_id: ClientId::new(7),
            signal: ScreenSignal::Answer {
                sdp: "secret-sdp".into(),
            },
        };
        assert!(!format!("{command:?}").contains("secret-sdp"));
        let packet = Screen.encode(command).unwrap();
        let json: serde_json::Value = serde_json::from_str(&packet.arguments["json"]).unwrap();
        assert_eq!(json["args"]["answer"], "secret-sdp");
        assert!(json["args"].get("sdp").is_none());
    }

    #[test]
    fn inbound_requests_and_stop_without_client_are_supported() {
        let args = BTreeMap::from([
            ("id".into(), "stream".into()),
            ("clid".into(), "7".into()),
            ("is_remove".into(), "1".into()),
        ]);
        assert!(matches!(
            Screen.decode("notifyjoinstreamrequest", &args),
            Some(ScreenEvent::JoinRequested { leaving: true, .. })
        ));
        assert!(matches!(
            Screen.decode(
                "notifystreamstopped",
                &BTreeMap::from([("id".into(), "stream".into())])
            ),
            Some(ScreenEvent::Stopped { .. })
        ));
        assert!(Screen.decode("notifystreamsignaling", &args).is_none());
    }

    #[test]
    fn leave_and_start_preserve_the_required_wire_fields() {
        let packet = Screen
            .encode(ScreenCommand::Leave {
                stream_id: "s".into(),
                client_id: ClientId::new(2),
            })
            .unwrap();
        assert_eq!(packet.name, "joinstreamrequest");
        assert_eq!(packet.arguments["is_remove"], "1");
    }

    /// The settings a publisher chose, as they reach the server.
    fn options() -> ScreenOptions {
        ScreenOptions {
            source: ScreenSource::Window,
            height: 1080,
            fps: 30,
            video_bitrate_kbps: 4000,
            audio: false,
            audio_bitrate_kbps: 128,
            access: ScreenAccess::Public,
            viewer_limit: 4,
            mode: ScreenMode::P2p,
            detail: false,
        }
    }

    fn start(options: ScreenOptions) -> BTreeMap<String, String> {
        Screen
            .encode(ScreenCommand::Start {
                name: "Screen".into(),
                options,
            })
            .unwrap()
            .arguments
    }

    #[test]
    fn every_choice_reaches_its_own_wire_argument() {
        // One field per assertion, so a mix-up between two of them cannot pass
        // by both being wrong in the same direction.
        let args = start(options());
        assert_eq!(args["type"], "3");
        assert_eq!(args["bitrate"], "4000000");
        assert_eq!(args["accessibility"], "1");
        assert_eq!(args["mode"], "1");
        assert_eq!(args["viewer_limit"], "4");
        assert_eq!(args["audio"], "0");
        //  is deliberately absent: the encoder it steers is the
        // front-end's, and the server has no use for it.
        assert!(!args.contains_key("detail"));

        let args = start(ScreenOptions {
            source: ScreenSource::Screen,
            access: ScreenAccess::Private,
            viewer_limit: 0,
            ..options()
        });
        assert_eq!(args["type"], "2");
        assert_eq!(args["accessibility"], "3");
        // Zero is how the wire says "as many as the server will carry".
        assert_eq!(args["viewer_limit"], "0");

        let args = start(ScreenOptions {
            source: ScreenSource::Camera,
            access: ScreenAccess::Contacts,
            audio: true,
            video_bitrate_kbps: 2500,
            ..options()
        });
        assert_eq!(args["type"], "1");
        assert_eq!(args["accessibility"], "2");
        assert_eq!(args["audio"], "1");
        assert_eq!(args["bitrate"], "2500000");
    }

    #[test]
    fn a_server_routed_stream_is_refused_rather_than_faked() {
        // There is no client for the server's media router here. Saying
        // otherwise would produce a stream that never connects and says
        // nothing about why.
        let result = Screen.encode(ScreenCommand::Start {
            name: "Screen".into(),
            options: ScreenOptions {
                mode: ScreenMode::Sfu,
                ..options()
            },
        });
        assert!(matches!(result, Err(ClientError::Unsupported(_))));
    }

    #[test]
    fn values_no_capture_could_produce_are_rejected() {
        for broken in [
            ScreenOptions {
                video_bitrate_kbps: 0,
                ..options()
            },
            ScreenOptions {
                height: 4321,
                ..options()
            },
            ScreenOptions {
                fps: 241,
                ..options()
            },
            ScreenOptions {
                viewer_limit: 1025,
                ..options()
            },
            // Audio with no bitrate for it: the two disagree, and one of them
            // is a mistake.
            ScreenOptions {
                audio: true,
                audio_bitrate_kbps: 0,
                ..options()
            },
        ] {
            assert!(
                Screen
                    .encode(ScreenCommand::Start {
                        name: "Screen".into(),
                        options: broken,
                    })
                    .is_err(),
                "{broken:?} should not have been accepted"
            );
        }
    }

    #[test]
    fn oversized_and_empty_stream_requests_are_rejected() {
        assert!(
            Screen
                .encode(ScreenCommand::Stop {
                    stream_id: String::new()
                })
                .is_err()
        );
        assert!(
            Screen
                .encode(ScreenCommand::Respond {
                    stream_id: "s".into(),
                    client_id: ClientId::new(2),
                    accept: true,
                    sdp: "a".repeat(65537)
                })
                .is_err()
        );
    }
}
