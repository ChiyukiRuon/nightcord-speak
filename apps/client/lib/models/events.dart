// The events the Rust core publishes, and the envelopes they arrive in.
//
// `ClientEvent` mirrors `ts_events::ClientEvent` one variant per variant, so
// the widget layer can switch exhaustively and the compiler catches a variant
// that a newer core adds.

import 'domain.dart';

/// An error, in the unified vocabulary from `ts-model` (§37).
///
/// Pure data: the sentence the user reads is built at render time by
/// `l10n/errors.dart::describe`, so an error raised before a language switch
/// cannot show the old language afterwards — and the model keeps no strings of
/// its own.
class ClientError {
  const ClientError({required this.kind, this.detail});

  /// The variant name, e.g. `network`, `permission`, `timeout`.
  ///
  /// Besides the core's own variants there are a few Dart-side kinds for
  /// failures the core never sees: `command_failed`, `lagged`, `unparsable`,
  /// `join_denied`. `l10n/errors.dart` is the one place that knows them all.
  final String kind;

  /// The variant's payload exactly as it arrived.
  ///
  /// Shaped differently per variant — a struct with a `message`, a bare
  /// string, or nothing at all for unit variants — and kept raw because what
  /// it means is only decided when the sentence is built.
  final Object? detail;

  /// Whether trying again could plausibly work.
  bool get isRetryable => kind == 'network' || kind == 'timeout';

  factory ClientError.fromJson(Map<String, dynamic> json) => ClientError(
    kind: json['kind'] as String? ?? 'unknown',
    detail: json['detail'],
  );

  /// The core's own words when it sent any — for logs and tests, not the UI.
  ///
  /// Whatever the core wrote is already the most specific thing about this
  /// error and is English by construction; the UI renders a translated
  /// sentence instead (`l10n/errors.dart`).
  String get debugMessage => switch (detail) {
    final String text => text,
    final Map<Object?, Object?> map when map['message'] is String =>
      map['message']! as String,
    _ => kind,
  };

  @override
  String toString() => debugMessage;
}

/// Something that happened on a session.
sealed class ClientEvent {
  const ClientEvent();

  /// Parses the `serde` encoding `ts-events` produces.
  ///
  /// Unknown names become [UnknownEvent] rather than throwing: a newer core
  /// talking to an older UI must not crash it (§18).
  factory ClientEvent.fromJson(Map<String, dynamic> json) {
    final name = json['event'] as String?;
    final payload = json['payload'];

    Map<String, dynamic> map(Object? value) =>
        (value as Map?)?.cast<String, dynamic>() ?? const {};

    return switch (name) {
      'own_avatar_changed' => OwnAvatarChangedEvent(map(payload)),
      'screen' => ScreenEvent(map(payload)),
      'connected' => ConnectedEvent(
        server: Server.fromJson(
          map(payload)['server'] as Map<String, dynamic>? ?? const {},
        ),
        info: ServerInfo.fromJson(
          map(payload)['info'] as Map<String, dynamic>? ?? const {},
        ),
      ),
      'disconnected' => const DisconnectedEvent(),
      'connection_state_changed' => ConnectionStateChangedEvent(
        ConnectionState.fromWire(payload as String?),
      ),
      'reconnect_scheduled' => ReconnectScheduledEvent(
        attempt: map(payload)['attempt'] as int? ?? 0,
        delayMs: map(payload)['delay_ms'] as int? ?? 0,
      ),
      'own_client_identified' => OwnClientIdentifiedEvent(
        clientId: map(payload)['client_id'] as int? ?? 0,
        channelId: map(payload)['channel_id'] as int? ?? 0,
      ),
      'server_info_changed' => ServerInfoChangedEvent(
        ServerInfo.fromJson(map(payload)),
      ),
      'permissions_changed' => PermissionsChangedEvent(
        Permissions.fromJson(map(payload)),
      ),
      'capabilities_changed' => CapabilitiesChangedEvent(
        Capabilities.fromJson(map(payload)),
      ),
      'channel_created' => ChannelCreatedEvent(Channel.fromJson(map(payload))),
      'channel_updated' => ChannelUpdatedEvent(Channel.fromJson(map(payload))),
      'channel_removed' => ChannelRemovedEvent(payload as int),
      'client_joined' => ClientJoinedEvent(Client.fromJson(map(payload))),
      'client_updated' => ClientUpdatedEvent(Client.fromJson(map(payload))),
      'client_left' => ClientLeftEvent(payload as int),
      'client_moved' => ClientMovedEvent(
        clientId: map(payload)['client_id'] as int? ?? 0,
        channelId: map(payload)['channel_id'] as int? ?? 0,
      ),
      'message_received' => MessageReceivedEvent(
        Message.fromJson(map(payload)),
      ),
      'poked' => PokedEvent(
        clientId: map(payload)['client_id'] as int? ?? 0,
        senderName: map(payload)['sender_name'] as String? ?? '',
        message: map(payload)['message'] as String? ?? '',
      ),
      'speaking' => SpeakingEvent(
        clientId: map(payload)['client_id'] as int? ?? 0,
        speaking: map(payload)['speaking'] as bool? ?? false,
      ),
      'voice_state_changed' => VoiceStateChangedEvent(
        VoiceState.fromJson(map(payload)),
      ),
      'error' => ErrorEvent(ClientError.fromJson(map(payload))),
      _ => UnknownEvent(name ?? 'unknown'),
    };
  }
}

/// Screen-sharing negotiation, already reduced by the core to the domain
/// vocabulary.
///
/// Kept as a map rather than a closed set of classes: the core owns the shape
/// (`ScreenCommand` in `ts-model`) and the only reader is the screen controller,
/// which switches on `type` anyway. Nothing else in the app — the server view,
/// the notification rules, the message list — looks at it.
class ScreenEvent extends ClientEvent {
  const ScreenEvent(this.data);
  final Map<String, dynamic> data;
}

/// The handshake finished.
class ConnectedEvent extends ClientEvent {
  const ConnectedEvent({required this.server, required this.info});
  final Server server;

  /// Counts here are provisional — the server describes itself before it sends
  /// its lists — and are corrected by a later [ServerInfoChangedEvent].
  final ServerInfo info;
}

/// The session ended.
class DisconnectedEvent extends ClientEvent {
  const DisconnectedEvent();
}

/// The lifecycle state changed.
class ConnectionStateChangedEvent extends ClientEvent {
  const ConnectionStateChangedEvent(this.state);
  final ConnectionState state;
}

/// A retry has been scheduled.
class ReconnectScheduledEvent extends ClientEvent {
  const ReconnectScheduledEvent({required this.attempt, required this.delayMs});
  final int attempt;
  final int delayMs;
}

/// Shared by all sessions; the enclosing session only identifies its origin.
class OwnAvatarChangedEvent extends ClientEvent {
  const OwnAvatarChangedEvent(this.data);
  final Map<String, dynamic> data;
}

/// The server told us which client and channel are ours.
class OwnClientIdentifiedEvent extends ClientEvent {
  const OwnClientIdentifiedEvent({
    required this.clientId,
    required this.channelId,
  });
  final int clientId;
  final int channelId;
}

/// The server's self-description changed.
class ServerInfoChangedEvent extends ClientEvent {
  const ServerInfoChangedEvent(this.info);
  final ServerInfo info;
}

/// Our permissions changed.
class PermissionsChangedEvent extends ClientEvent {
  const PermissionsChangedEvent(this.permissions);
  final Permissions permissions;
}

/// What the server can do at all.
class CapabilitiesChangedEvent extends ClientEvent {
  const CapabilitiesChangedEvent(this.capabilities);
  final Capabilities capabilities;
}

/// A channel appeared.
class ChannelCreatedEvent extends ClientEvent {
  const ChannelCreatedEvent(this.channel);
  final Channel channel;
}

/// A channel's properties changed.
class ChannelUpdatedEvent extends ClientEvent {
  const ChannelUpdatedEvent(this.channel);
  final Channel channel;
}

/// A channel was deleted.
class ChannelRemovedEvent extends ClientEvent {
  const ChannelRemovedEvent(this.channelId);
  final int channelId;
}

/// A client connected.
class ClientJoinedEvent extends ClientEvent {
  const ClientJoinedEvent(this.client);
  final Client client;
}

/// A client's properties changed.
class ClientUpdatedEvent extends ClientEvent {
  const ClientUpdatedEvent(this.client);
  final Client client;
}

/// A client disconnected.
class ClientLeftEvent extends ClientEvent {
  const ClientLeftEvent(this.clientId);
  final int clientId;
}

/// A client changed channel.
class ClientMovedEvent extends ClientEvent {
  const ClientMovedEvent({required this.clientId, required this.channelId});
  final int clientId;
  final int channelId;
}

/// A chat message arrived.
class MessageReceivedEvent extends ClientEvent {
  const MessageReceivedEvent(this.message);
  final Message message;
}

/// Someone poked us.
class PokedEvent extends ClientEvent {
  const PokedEvent({
    required this.clientId,
    required this.senderName,
    required this.message,
  });
  final int clientId;
  final String senderName;
  final String message;
}

/// Someone started or stopped talking.
class SpeakingEvent extends ClientEvent {
  const SpeakingEvent({required this.clientId, required this.speaking});
  final int clientId;
  final bool speaking;
}

/// Our own voice configuration changed.
class VoiceStateChangedEvent extends ClientEvent {
  const VoiceStateChangedEvent(this.state);
  final VoiceState state;
}

/// Something failed.
class ErrorEvent extends ClientEvent {
  const ErrorEvent(this.error);
  final ClientError error;
}

/// A variant this build does not know about.
class UnknownEvent extends ClientEvent {
  const UnknownEvent(this.name);
  final String name;
}

/// Whether a command worked.
class CommandOutcome {
  const CommandOutcome({required this.ok, this.error});

  final bool ok;

  /// Why it failed, when it did.
  final ClientError? error;
}

/// The outcome of a command the user asked for.
class CommandResult {
  const CommandResult({
    required this.command,
    required this.session,
    required this.outcome,
    this.data,
  });

  /// Stable name, e.g. `connect`.
  final String command;

  /// The session acted on. For `connect` this is the new session's handle,
  /// which is how the caller learns it.
  final int? session;

  final CommandOutcome outcome;

  /// Extra payload, e.g. the device list.
  final Map<String, dynamic>? data;

  /// Whether it worked.
  bool get ok => outcome.ok;

  /// Why it failed, when it did.
  ClientError? get error => outcome.error;
}

/// One thing the core has to say.
sealed class FfiEvent {
  const FfiEvent();

  /// Parses one element of the array `nightcord_poll_events` returns.
  factory FfiEvent.fromJson(Map<String, dynamic> json) {
    switch (json['kind'] as String?) {
      case 'event':
        return DomainEvent(
          session: json['session'] as int? ?? 0,
          event: ClientEvent.fromJson(
            (json['event'] as Map?)?.cast<String, dynamic>() ?? const {},
          ),
        );
      case 'command_result':
        final outcome =
            (json['outcome'] as Map?)?.cast<String, dynamic>() ?? const {};
        final status = outcome['status'] as String?;
        return CommandResultEvent(
          CommandResult(
            command: json['command'] as String? ?? '',
            session: json['session'] as int?,
            outcome: CommandOutcome(
              ok: status == 'ok',
              error: outcome['error'] == null
                  ? null
                  : ClientError.fromJson(
                      (outcome['error'] as Map).cast<String, dynamic>(),
                    ),
            ),
            data: (json['data'] as Map?)?.cast<String, dynamic>(),
          ),
        );
      case 'lagged':
        return LaggedEvent(json['missed'] as int? ?? 0);
      default:
        return UnknownFfiEvent(json['kind'] as String? ?? 'unknown');
    }
  }
}

/// A domain event from one session.
class DomainEvent extends FfiEvent {
  const DomainEvent({required this.session, required this.event});
  final int session;
  final ClientEvent event;
}

/// The outcome of a command.
class CommandResultEvent extends FfiEvent {
  const CommandResultEvent(this.result);
  final CommandResult result;
}

/// Events were dropped because the UI fell behind.
class LaggedEvent extends FfiEvent {
  const LaggedEvent(this.missed);

  /// How many were dropped.
  final int missed;
}

/// An envelope this build does not know about.
class UnknownFfiEvent extends FfiEvent {
  const UnknownFfiEvent(this.kind);
  final String kind;
}
