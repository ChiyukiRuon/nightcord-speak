// The one boundary between the app and a client core.
//
// Everything above this file — providers, state, features, widgets — is
// written against this interface and does not know what is below it. There are
// two kinds of answer, and the *kind* is what the names describe:
//
// * `EmbeddedTransport` — a core in the same process, reached through FFI
//   (`ffi/rust_client.dart`, the desktop and mobile implementation).
// * `RemoteTransport` — a core behind a WebSocket gateway
//   (`docs/gateway.md`, the web implementation; a desktop talking to a gateway
//   on a NAS or a home server would use the same one).
//
// Deliberately not named after platforms. A Windows client can use either
// transport, and an interface called `FfiTransport` at the top would smuggle
// "desktop" into every decision that should only be about "which core".
//
// The commands are fire-and-poll by design, mirroring the core: each returns
// nothing, and the outcome arrives on [events] as a `command_result`
// envelope — the same envelope whichever transport carried it, because both
// speak the vocabulary in `ts-wire`.

import '../../models/bookmarks.dart';
import '../../models/connect_request.dart';
import '../../models/domain.dart';
import '../../models/events.dart';
import '../../models/settings.dart';

/// What the app may ask of a client core, and what the core reports back.
abstract interface class ClientTransport {
  /// Every envelope the core publishes: domain events, command results, and
  /// the occasional `lagged` marker.
  Stream<FfiEvent> get events;

  /// Opens a connection. The session handle arrives as a `connect` result.
  void connect(ConnectRequest request);

  /// Closes a connection.
  void disconnect(int session);

  /// Moves us into a channel.
  void joinChannel(int session, int channelId);

  /// Returns to the server's default channel.
  void leaveChannel(int session);

  /// Sends a chat message.
  void sendMessage(int session, MessageTarget target, String text);

  /// Moves another client into a channel.
  void moveClient(int session, int clientId, int channelId);

  /// Pokes another client, which typically makes their client beep.
  void poke(int session, int clientId, String message);

  /// Removes another client from a channel or from the server.
  ///
  /// `message` is an optional explanation; `null` means none was given. The
  /// server decides whether we may — a refusal arrives as a permission error
  /// naming what was missing, not as silence.
  void kick(int session, int clientId, KickScope scope, String? message);

  /// Bans another client.
  void ban(int session, int clientId, BanDuration duration, String? reason);

  /// Marks us away, or back at the keyboard.
  ///
  /// `away` is the switch and `message` is what to say about it. Both are
  /// needed because the server tells apart three states, not two: away with a
  /// message, away without one, and here. A single nullable message would have
  /// made "away, nothing to say" indistinguishable from "back".
  void setAway(int session, {required bool away, String? message});

  /// Scales one client's audio within the mix.
  ///
  /// Local to this client: nothing is sent to the server, and what everyone
  /// else receives is unchanged. A remote transport applies it on the machine
  /// running the core, where the mixing happens.
  void setClientVolume(int session, int clientId, double volume);

  /// Asks for the audio devices for `"input"` or `"output"`.
  ///
  /// A remote transport may answer with an empty list: the devices that matter
  /// to a browser belong to the browser, not to the machine running the core.
  void requestAudioDevices(String direction);

  /// Opens audio devices and binds voice to a session.
  ///
  /// The device arguments are the embedded transport's; a remote transport
  /// ignores them, because it has no devices of its own to name.
  void voiceStart(int session, {String? inputDevice, String? outputDevice});

  /// Closes the audio devices.
  void voiceStop();

  /// Mutes or unmutes the microphone.
  void setInputMuted(bool muted);

  /// Mutes or unmutes the speakers.
  void setOutputMuted(bool muted);

  /// Push-to-talk key down or up (§30).
  void setPushToTalk(bool held);

  /// Asks what the audio engine is doing; the answer is a `voice_status`
  /// result.
  void requestVoiceStatus();

  /// Plays a short tone through the speakers.
  void testOutput();

  /// Asks for the preferences; the answer is a `settings` result.
  void requestSettings();

  /// Replaces the preferences, and writes them down.
  void updateSettings(Settings settings);

  /// Asks for the saved servers; the answer is a `bookmarks` result.
  void requestBookmarks();

  /// Replaces the saved servers, and writes them down.
  void updateBookmarks(BookmarkList bookmarks);

  /// Saves a server; the answer is a `bookmark_add` result carrying the list.
  void addBookmark(NewBookmark bookmark);

  /// Releases whatever the transport holds — a library handle, a socket.
  ///
  /// After this the transport is dead: [events] closes and commands are
  /// refused. Callers must not use it again.
  void dispose();
}
