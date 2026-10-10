import '../core/sounds/sound_pack.dart';
import '../models/domain.dart';
import '../models/events.dart';
import 'notifications.dart' show replayWindow;
import 'server_view.dart';

/// Observes confirmed state before the view is updated, including optimistic mute changes.
class SoundPolicy {
  SoundPolicy({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  final Map<int, DateTime> _connected = {};
  final Set<int> _joined = {};
  final Map<int, VoiceState> _voice = {};

  List<SoundAction> voice(int session, VoiceState next) {
    final previous = _voice[session] ?? const VoiceState();
    _voice[session] = next;
    return [
      if (previous.inputMuted != next.inputMuted)
        next.inputMuted ? SoundAction.microphoneOff : SoundAction.microphoneOn,
      if (previous.outputMuted != next.outputMuted)
        next.outputMuted ? SoundAction.speakersOff : SoundAction.speakersOn,
    ];
  }

  List<SoundAction> leave(int session) {
    _connected.remove(session);
    _voice.remove(session);
    return _joined.remove(session) ? [SoundAction.voiceLeft] : [];
  }

  List<SoundAction> observe(int session, ClientEvent event, ServerView view) {
    final replaying =
        _connected[session] != null && _clock().difference(_connected[session]!) < replayWindow;
    switch (event) {
      case ConnectedEvent():
        _connected[session] = _clock();
        return [];
      case OwnClientIdentifiedEvent():
        return _joined.add(session) ? [SoundAction.voiceJoined] : [];
      case DisconnectedEvent():
        return leave(session);
      case ConnectionStateChangedEvent(:final state):
        if (state == ConnectionState.reconnecting || state == ConnectionState.failed) {
          return leave(session);
        }
        return [];
      case VoiceStateChangedEvent(:final state):
        return voice(session, state);
      case ClientUpdatedEvent(:final client):
        final previous = view.ownClient;
        if (client.id != view.ownClientId ||
            previous == null ||
            previous.flags.away == client.flags.away) {
          return [];
        }
        return [client.flags.away ? SoundAction.awayOn : SoundAction.awayOff];
      case ClientJoinedEvent(:final client):
        if (replaying ||
            !_joined.contains(session) ||
            client.id == view.ownClientId ||
            client.clientType != ClientType.voice ||
            view.clients.containsKey(client.id) ||
            client.channelId != view.ownChannelId) {
          return [];
        }
        return [SoundAction.voiceJoined];
      case ClientLeftEvent(:final clientId):
        if (clientId == view.ownClientId) return leave(session);
        final client = view.clients[clientId];
        if (replaying ||
            !_joined.contains(session) ||
            client?.clientType != ClientType.voice ||
            client?.channelId != view.ownChannelId) {
          return [];
        }
        return [SoundAction.voiceLeft];
      case ClientMovedEvent(:final clientId, :final channelId):
        final previous = view.clients[clientId];
        if (clientId == view.ownClientId) {
          if (view.ownChannelId == channelId) return [];
          return [SoundAction.voiceLeft, SoundAction.voiceJoined];
        }
        if (replaying ||
            !_joined.contains(session) ||
            previous == null ||
            previous.clientType != ClientType.voice ||
            previous.channelId == channelId) {
          return [];
        }
        return [
          if (previous.channelId == view.ownChannelId) SoundAction.voiceLeft,
          if (channelId == view.ownChannelId) SoundAction.voiceJoined,
        ];
      case MessageReceivedEvent(:final message):
        if (message.sender != null && message.sender == view.ownClientId) return [];
        return [SoundAction.message];
      default:
        return [];
    }
  }
}
