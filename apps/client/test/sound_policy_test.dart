import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/sounds/sound_pack.dart';
import 'package:nightcord_client/models/domain.dart';
import 'package:nightcord_client/models/events.dart';
import 'package:nightcord_client/state/server_view.dart';
import 'package:nightcord_client/state/sound_policy.dart';

void main() {
  late SoundPolicy policy;
  late ServerView view;
  late DateTime now;
  List<SoundAction> observe(ClientEvent event) {
    final actions = policy.observe(1, event, view);
    view.apply(event);
    return actions;
  }

  setUp(() {
    now = DateTime(2026);
    policy = SoundPolicy(clock: () => now);
    view = ServerView(session: 1);
    observe(const OwnClientIdentifiedEvent(clientId: 1, channelId: 10));
    observe(const ClientJoinedEvent(Client(id: 1, name: 'Me', channelId: 10)));
  });

  test('only current-channel voice clients cause presence sounds', () {
    expect(observe(const ClientJoinedEvent(Client(id: 2, name: 'Alice', channelId: 20))), isEmpty);
    expect(observe(const ClientMovedEvent(clientId: 2, channelId: 10)), [SoundAction.voiceJoined]);
    expect(observe(const ClientMovedEvent(clientId: 2, channelId: 10)), isEmpty);
    expect(observe(const ClientMovedEvent(clientId: 2, channelId: 20)), [SoundAction.voiceLeft]);
    expect(observe(const ClientLeftEvent(2)), isEmpty);
    expect(
      observe(
        const ClientJoinedEvent(
          Client(id: 3, name: 'Query', channelId: 10, clientType: ClientType.query),
        ),
      ),
      isEmpty,
    );
    expect(observe(const ClientJoinedEvent(Client(id: 4, name: 'Bob', channelId: 10))), [
      SoundAction.voiceJoined,
    ]);
    expect(observe(const ClientJoinedEvent(Client(id: 4, name: 'Bob', channelId: 10))), isEmpty);
    expect(observe(const ClientLeftEvent(4)), [SoundAction.voiceLeft]);
  });

  test('own connection and switching channels do not duplicate joins or leaves', () {
    expect(observe(const OwnClientIdentifiedEvent(clientId: 1, channelId: 10)), isEmpty);
    expect(observe(const ClientMovedEvent(clientId: 1, channelId: 20)), [
      SoundAction.voiceLeft,
      SoundAction.voiceJoined,
    ]);
    expect(policy.leave(1), [SoundAction.voiceLeft]);
    expect(observe(const DisconnectedEvent()), isEmpty);
  });

  test('handshake replay is silent but subsequent arrivals play', () {
    observe(
      const ConnectedEvent(
        server: Server(id: 1, name: 'Test', address: 'localhost', protocol: ProtocolKind.ts3),
        info: ServerInfo(),
      ),
    );
    expect(observe(const ClientJoinedEvent(Client(id: 2, name: 'Alice', channelId: 10))), isEmpty);
    now = now.add(const Duration(seconds: 3));
    expect(observe(const ClientJoinedEvent(Client(id: 3, name: 'Bob', channelId: 10))), [
      SoundAction.voiceJoined,
    ]);
  });

  test('optimistic mute and its confirmed echo produce one sound', () {
    expect(policy.voice(1, const VoiceState(inputMuted: true)), [SoundAction.microphoneOff]);
    expect(observe(const VoiceStateChangedEvent(VoiceState(inputMuted: true))), isEmpty);
    expect(observe(const VoiceStateChangedEvent(VoiceState())), [SoundAction.microphoneOn]);
    expect(policy.voice(1, const VoiceState(outputMuted: true)), [SoundAction.speakersOff]);
    expect(policy.voice(1, const VoiceState()), [SoundAction.speakersOn]);
  });

  test('AFK changes belong only to our own client', () {
    expect(
      observe(
        const ClientUpdatedEvent(
          Client(id: 2, name: 'Alice', channelId: 10, flags: ClientFlags(away: true)),
        ),
      ),
      isEmpty,
    );
    expect(
      observe(
        const ClientUpdatedEvent(
          Client(id: 1, name: 'Me', channelId: 10, flags: ClientFlags(away: true)),
        ),
      ),
      [SoundAction.awayOn],
    );
    expect(
      observe(
        const ClientUpdatedEvent(
          Client(id: 1, name: 'Me', channelId: 10, flags: ClientFlags(away: true)),
        ),
      ),
      isEmpty,
    );
    expect(observe(const ClientUpdatedEvent(Client(id: 1, name: 'Me', channelId: 10))), [
      SoundAction.awayOff,
    ]);
  });

  test('new messages play even when visible and own echoes are silent', () {
    Message message(int? sender) => Message(
      id: 1,
      sender: sender,
      senderName: 'Alice',
      target: const ChannelTarget(10),
      content: 'Hello',
      timestamp: 0,
    );
    expect(observe(MessageReceivedEvent(message(2))), [SoundAction.message]);
    expect(observe(MessageReceivedEvent(message(1))), isEmpty);
    expect(observe(MessageReceivedEvent(message(null))), [SoundAction.message]);
  });
}
