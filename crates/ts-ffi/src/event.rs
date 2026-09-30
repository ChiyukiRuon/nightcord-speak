//! The JSON envelopes that cross into Dart.
//!
//! Two kinds of thing arrive at the front-end: domain events, forwarded
//! unchanged from [`ts_events::ClientEvent`], and the outcome of a command the
//! user asked for.
//!
//! Command results exist because a bare [`ClientEvent::Error`] cannot say
//! *which* action failed. Without them a UI could only report "something went
//! wrong" when a channel join is refused, which is not actionable.
//!
//! [`ClientEvent::Error`]: ts_events::ClientEvent::Error

use serde::Serialize;
use ts_events::ClientEvent;
use ts_model::{ClientError, SessionId};

/// One thing the front-end should react to.
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum FfiEvent {
    /// A domain event, forwarded unchanged (§18).
    Event {
        /// Which session produced it.
        session: SessionId,
        /// What happened.
        event: ClientEvent,
    },

    /// The outcome of a command.
    CommandResult {
        /// Stable command name, e.g. `"connect"`. Matches the FFI function's
        /// subject rather than its full C name, so the UI does not have to know
        /// the ABI prefix.
        command: String,
        /// The session the command acted on, if any. For `connect` this is the
        /// *new* session's handle, which is how the caller learns it.
        session: Option<SessionId>,
        /// Whether it worked.
        outcome: CommandOutcome,
        /// Extra payload some commands return, e.g. the device list.
        #[serde(skip_serializing_if = "Option::is_none")]
        data: Option<serde_json::Value>,
    },

    /// The event subscriber fell behind and the oldest events were dropped.
    ///
    /// Reported rather than swallowed: a UI silently missing a
    /// `ChannelRemoved` would keep drawing a channel that no longer exists.
    Lagged {
        /// How many events were dropped.
        missed: u64,
    },
}

impl FfiEvent {
    /// Forwards a domain event.
    #[must_use]
    pub(crate) fn client(session: SessionId, event: ClientEvent) -> Self {
        Self::Event { session, event }
    }

    /// A command that succeeded, with no payload.
    #[must_use]
    pub(crate) fn ok(command: &str, session: Option<SessionId>) -> Self {
        Self::CommandResult {
            command: command.to_string(),
            session,
            outcome: CommandOutcome::Ok,
            data: None,
        }
    }

    /// A command that succeeded and returned something.
    #[must_use]
    pub(crate) fn with_data(
        command: &str,
        session: Option<SessionId>,
        data: serde_json::Value,
    ) -> Self {
        Self::CommandResult {
            command: command.to_string(),
            session,
            outcome: CommandOutcome::Ok,
            data: Some(data),
        }
    }

    /// A command that failed.
    #[must_use]
    pub(crate) fn failed(command: &str, session: Option<SessionId>, error: ClientError) -> Self {
        Self::CommandResult {
            command: command.to_string(),
            session,
            outcome: CommandOutcome::Failed { error },
            data: None,
        }
    }
}

/// Whether a command worked.
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum CommandOutcome {
    /// It worked.
    Ok,
    /// It did not, and why.
    Failed {
        /// The unified error vocabulary the UI already knows (§37).
        error: ClientError,
    },
}

#[cfg(test)]
mod tests {
    use super::*;
    use ts_model::{ChannelId, ClientId, MessageTarget, ProtocolError};

    #[test]
    fn a_forwarded_event_keeps_its_own_shape() {
        // Dart matches on `kind`, then hands `event` to the same parser it uses
        // for every other domain event.
        let json = serde_json::to_value(FfiEvent::client(
            SessionId::new(3),
            ClientEvent::ChannelRemoved(ChannelId::new(9)),
        ))
        .unwrap();

        assert_eq!(json["kind"], "event");
        assert_eq!(json["session"], 3);
        assert_eq!(json["event"]["event"], "channel_removed");
        assert_eq!(json["event"]["payload"], 9);
    }

    #[test]
    fn a_successful_command_reports_its_session() {
        let json = serde_json::to_value(FfiEvent::ok("connect", Some(SessionId::new(7)))).unwrap();

        assert_eq!(json["kind"], "command_result");
        assert_eq!(json["command"], "connect");
        assert_eq!(json["session"], 7);
        assert_eq!(json["outcome"]["status"], "ok");
        // No payload, and the key is absent rather than null.
        assert!(json.get("data").is_none());
    }

    #[test]
    fn a_failed_command_carries_the_reason() {
        let json = serde_json::to_value(FfiEvent::failed(
            "join_channel",
            Some(SessionId::new(1)),
            ClientError::Protocol(ProtocolError::new("no such channel")),
        ))
        .unwrap();

        assert_eq!(json["outcome"]["status"], "failed");
        assert_eq!(json["outcome"]["error"]["kind"], "protocol");
        assert_eq!(
            json["outcome"]["error"]["detail"]["message"],
            "no such channel"
        );
    }

    #[test]
    fn a_command_without_a_session_omits_it_rather_than_lying() {
        // `audio_devices` is not scoped to a session; reporting session 0 would
        // be worse than reporting nothing.
        let json = serde_json::to_value(FfiEvent::ok("audio_devices", None)).unwrap();
        assert!(json["session"].is_null());
    }

    #[test]
    fn a_device_list_travels_as_data() {
        let json = serde_json::to_value(FfiEvent::with_data(
            "audio_devices",
            None,
            serde_json::json!([{ "id": "wasapi:x", "name": "Speakers" }]),
        ))
        .unwrap();

        assert_eq!(json["outcome"]["status"], "ok");
        assert_eq!(json["data"][0]["name"], "Speakers");
    }

    #[test]
    fn lag_is_reported_as_its_own_kind() {
        // A UI that cannot tell "the server is quiet" from "I dropped events"
        // will show a stale channel tree forever.
        let json = serde_json::to_value(FfiEvent::Lagged { missed: 42 }).unwrap();
        assert_eq!(json["kind"], "lagged");
        assert_eq!(json["missed"], 42);
    }

    #[test]
    fn every_kind_is_distinguishable_by_the_tag_alone() {
        let kinds = [
            FfiEvent::client(SessionId::new(1), ClientEvent::Disconnected),
            FfiEvent::ok("x", Some(SessionId::new(1))),
            FfiEvent::Lagged { missed: 1 },
        ];

        let tags: Vec<String> = kinds
            .iter()
            .map(|e| {
                serde_json::to_value(e).unwrap()["kind"]
                    .as_str()
                    .unwrap()
                    .to_string()
            })
            .collect();

        assert_eq!(tags, ["event", "command_result", "lagged"]);
    }

    #[test]
    fn a_message_target_survives_nesting() {
        // Dart parses this out of `data` or a command argument, so the tagged
        // shape has to stay put through the envelope.
        let target = MessageTarget::Client(ClientId::new(5));
        let json = serde_json::to_value(target).unwrap();
        assert_eq!(json["kind"], "client");
        assert_eq!(json["id"], 5);
    }
}
