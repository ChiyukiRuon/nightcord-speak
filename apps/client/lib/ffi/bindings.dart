// Raw `dart:ffi` declarations for the Rust core.
//
// Hand-written rather than generated: there are twenty functions and the
// signatures are the contract, so a generator would add a build step and a
// dependency without removing much work.
//
// Nothing outside this file and `native.dart` should name these directly — the
// wrapper in `rust_client.dart` is what the rest of the app talks to.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// The opaque client handle. Never dereferenced on the Dart side; it exists
/// only to be passed back to Rust.
typedef Handle = Pointer<Void>;

// --- lifecycle -------------------------------------------------------------

typedef _CreateC = Handle Function();
typedef _CreateDart = Handle Function();

typedef _DestroyC = Void Function(Handle handle);
typedef _DestroyDart = void Function(Handle handle);

typedef _VersionC = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();

// --- logging ---------------------------------------------------------------

typedef _LogDirC = Pointer<Utf8> Function();
typedef _LogDirDart = Pointer<Utf8> Function();

typedef _LogC = Void Function(Pointer<Utf8> level, Pointer<Utf8> message);
typedef _LogDart = void Function(Pointer<Utf8> level, Pointer<Utf8> message);

// --- commands --------------------------------------------------------------

typedef _ConnectC = Void Function(Handle handle, Pointer<Utf8> requestJson);
typedef _ConnectDart = void Function(Handle handle, Pointer<Utf8> requestJson);

typedef _DisconnectC = Void Function(Handle handle, Uint32 session);
typedef _DisconnectDart = void Function(Handle handle, int session);

typedef _JoinChannelC = Void Function(Handle handle, Uint32 session, Uint64 channelId);
typedef _JoinChannelDart = void Function(Handle handle, int session, int channelId);

typedef _LeaveChannelC = Void Function(Handle handle, Uint32 session);
typedef _LeaveChannelDart = void Function(Handle handle, int session);

typedef _SendMessageC = Void Function(
  Handle handle,
  Uint32 session,
  Pointer<Utf8> targetJson,
  Pointer<Utf8> text,
);
typedef _SendMessageDart = void Function(
  Handle handle,
  int session,
  Pointer<Utf8> targetJson,
  Pointer<Utf8> text,
);

typedef _MoveClientC = Void Function(
  Handle handle,
  Uint32 session,
  Uint16 clientId,
  Uint64 channelId,
);
typedef _MoveClientDart = void Function(
  Handle handle,
  int session,
  int clientId,
  int channelId,
);

// --- audio -----------------------------------------------------------------

typedef _AudioDevicesC = Void Function(Handle handle, Pointer<Utf8> direction);
typedef _AudioDevicesDart = void Function(Handle handle, Pointer<Utf8> direction);

typedef _VoiceStartC = Void Function(
  Handle handle,
  Uint32 session,
  Pointer<Utf8> inputDevice,
  Pointer<Utf8> outputDevice,
);
typedef _VoiceStartDart = void Function(
  Handle handle,
  int session,
  Pointer<Utf8> inputDevice,
  Pointer<Utf8> outputDevice,
);

typedef _VoiceStopC = Void Function(Handle handle);
typedef _VoiceStopDart = void Function(Handle handle);

typedef _VoiceSetModeC = Void Function(Handle handle, Pointer<Utf8> mode);
typedef _VoiceSetModeDart = void Function(Handle handle, Pointer<Utf8> mode);

typedef _VoiceSetBoolC = Void Function(Handle handle, Bool value);
typedef _VoiceSetBoolDart = void Function(Handle handle, bool value);

// --- events ----------------------------------------------------------------

typedef _PollEventsC = Pointer<Utf8> Function(Handle handle);
typedef _PollEventsDart = Pointer<Utf8> Function(Handle handle);

typedef _FreeStringC = Void Function(Pointer<Utf8> text);
typedef _FreeStringDart = void Function(Pointer<Utf8> text);

/// The bound C functions.
///
/// Built by [NativeLibrary] once the shared library is loaded.
class NightcordBindings {
  /// Wraps a loaded library.
  NightcordBindings(DynamicLibrary library)
    : create = library.lookupFunction<_CreateC, _CreateDart>('nightcord_create'),
      destroy = library.lookupFunction<_DestroyC, _DestroyDart>('nightcord_destroy'),
      version = library.lookupFunction<_VersionC, _VersionDart>('nightcord_version'),
      logDir = library.lookupFunction<_LogDirC, _LogDirDart>('nightcord_log_dir'),
      log = library.lookupFunction<_LogC, _LogDart>('nightcord_log'),
      connect = library.lookupFunction<_ConnectC, _ConnectDart>('nightcord_connect'),
      disconnect = library.lookupFunction<_DisconnectC, _DisconnectDart>('nightcord_disconnect'),
      joinChannel = library.lookupFunction<_JoinChannelC, _JoinChannelDart>(
        'nightcord_join_channel',
      ),
      leaveChannel = library.lookupFunction<_LeaveChannelC, _LeaveChannelDart>(
        'nightcord_leave_channel',
      ),
      sendMessage = library.lookupFunction<_SendMessageC, _SendMessageDart>(
        'nightcord_send_message',
      ),
      moveClient = library.lookupFunction<_MoveClientC, _MoveClientDart>('nightcord_move_client'),
      audioDevices = library.lookupFunction<_AudioDevicesC, _AudioDevicesDart>(
        'nightcord_audio_devices',
      ),
      voiceStart = library.lookupFunction<_VoiceStartC, _VoiceStartDart>('nightcord_voice_start'),
      voiceStop = library.lookupFunction<_VoiceStopC, _VoiceStopDart>('nightcord_voice_stop'),
      voiceSetMode = library.lookupFunction<_VoiceSetModeC, _VoiceSetModeDart>(
        'nightcord_voice_set_mode',
      ),
      voiceSetInputMuted = library.lookupFunction<_VoiceSetBoolC, _VoiceSetBoolDart>(
        'nightcord_voice_set_input_muted',
      ),
      voiceSetOutputMuted = library.lookupFunction<_VoiceSetBoolC, _VoiceSetBoolDart>(
        'nightcord_voice_set_output_muted',
      ),
      voicePushToTalk = library.lookupFunction<_VoiceSetBoolC, _VoiceSetBoolDart>(
        'nightcord_voice_push_to_talk',
      ),
      pollEvents = library.lookupFunction<_PollEventsC, _PollEventsDart>(
        'nightcord_poll_events',
      ),
      freeString = library.lookupFunction<_FreeStringC, _FreeStringDart>(
        'nightcord_free_string',
      );

  /// Starts the core. Returns `null` on failure, which is fatal.
  final Handle Function() create;

  /// Stops the core. Must be called exactly once per successful [create].
  final void Function(Handle) destroy;

  /// The library version. The returned pointer is static and must not be freed.
  final Pointer<Utf8> Function() version;

  /// The directory log files are written to, or an empty string when records
  /// only reach stderr. Takes no handle, so it answers even when the core
  /// failed to start. Free the result with [freeString].
  final Pointer<Utf8> Function() logDir;

  /// Records a line from Dart. `level` is one of `trace`, `debug`, `info`,
  /// `warn`, `error`; anything else is recorded as `info`.
  ///
  /// Takes no handle: this is the call an error handler makes, and it must work
  /// whatever state the core is in.
  final void Function(Pointer<Utf8>, Pointer<Utf8>) log;

  /// Sends a serialised `ConnectRequest`.
  final void Function(Handle, Pointer<Utf8>) connect;

  /// Closes a connection.
  final void Function(Handle, int) disconnect;

  /// Moves us into a channel.
  final void Function(Handle, int, int) joinChannel;

  /// Returns to the server's default channel.
  final void Function(Handle, int) leaveChannel;

  /// Sends a chat message; `target` is serialised `MessageTarget` JSON.
  final void Function(Handle, int, Pointer<Utf8>, Pointer<Utf8>) sendMessage;

  /// Moves another client.
  final void Function(Handle, int, int, int) moveClient;

  /// Requests the device list for `"input"` or `"output"`.
  final void Function(Handle, Pointer<Utf8>) audioDevices;

  /// Opens devices and binds voice to a session.
  final void Function(Handle, int, Pointer<Utf8>, Pointer<Utf8>) voiceStart;

  /// Closes the devices.
  final void Function(Handle) voiceStop;

  /// Sets the transmission mode.
  final void Function(Handle, Pointer<Utf8>) voiceSetMode;

  /// Mutes the microphone.
  final void Function(Handle, bool) voiceSetInputMuted;

  /// Mutes the speakers.
  final void Function(Handle, bool) voiceSetOutputMuted;

  /// Push-to-talk key down or up.
  final void Function(Handle, bool) voicePushToTalk;

  /// Drains queued events as a JSON array. The result must be freed with
  /// [freeString].
  final Pointer<Utf8> Function(Handle) pollEvents;

  /// Frees a string returned by [pollEvents].
  final void Function(Pointer<Utf8>) freeString;
}
