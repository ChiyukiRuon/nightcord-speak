// Raw `dart:ffi` declarations for the Rust core.
//
// Hand-written rather than generated: there are twenty-nine functions and the
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

// --- crash evidence --------------------------------------------------------

typedef _CrashStatusC = Pointer<Utf8> Function();
typedef _CrashStatusDart = Pointer<Utf8> Function();

typedef _CrashReportC = Pointer<Utf8> Function();
typedef _CrashReportDart = Pointer<Utf8> Function();

typedef _MarkCleanExitC = Bool Function(Handle handle);
typedef _MarkCleanExitDart = bool Function(Handle handle);

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

typedef _PokeC = Void Function(
  Handle handle,
  Uint32 session,
  Uint16 clientId,
  Pointer<Utf8> message,
);
typedef _PokeDart = void Function(
  Handle handle,
  int session,
  int clientId,
  Pointer<Utf8> message,
);

typedef _KickC = Void Function(
  Handle handle,
  Uint32 session,
  Uint16 clientId,
  Pointer<Utf8> scope,
  Pointer<Utf8> message,
);
typedef _KickDart = void Function(
  Handle handle,
  int session,
  int clientId,
  Pointer<Utf8> scope,
  Pointer<Utf8> message,
);

typedef _BanC = Void Function(
  Handle handle,
  Uint32 session,
  Uint16 clientId,
  Pointer<Utf8> duration,
  Pointer<Utf8> reason,
);
typedef _BanDart = void Function(
  Handle handle,
  int session,
  int clientId,
  Pointer<Utf8> duration,
  Pointer<Utf8> reason,
);

typedef _SetAwayC = Void Function(
  Handle handle,
  Uint32 session,
  Bool away,
  Pointer<Utf8> message,
);
typedef _SetAwayDart = void Function(
  Handle handle,
  int session,
  bool away,
  Pointer<Utf8> message,
);

typedef _SetClientVolumeC = Void Function(
  Handle handle,
  Uint32 session,
  Uint16 clientId,
  Float volume,
);
typedef _SetClientVolumeDart = void Function(
  Handle handle,
  int session,
  int clientId,
  double volume,
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

typedef _VoiceSetBoolC = Void Function(Handle handle, Bool value);
typedef _VoiceSetBoolDart = void Function(Handle handle, bool value);

typedef _VoiceStatusC = Void Function(Handle handle);
typedef _VoiceStatusDart = void Function(Handle handle);

typedef _VoiceTestOutputC = Void Function(Handle handle);
typedef _VoiceTestOutputDart = void Function(Handle handle);

// --- events ----------------------------------------------------------------

typedef _PollEventsC = Pointer<Utf8> Function(Handle handle);
typedef _PollEventsDart = Pointer<Utf8> Function(Handle handle);

typedef _FreeStringC = Void Function(Pointer<Utf8> text);
typedef _FreeStringDart = void Function(Pointer<Utf8> text);

// --- settings --------------------------------------------------------------

typedef _SettingsGetC = Void Function(Handle handle);
typedef _SettingsGetDart = void Function(Handle handle);

typedef _SettingsUpdateC = Void Function(Handle handle, Pointer<Utf8> settingsJson);
typedef _SettingsUpdateDart = void Function(Handle handle, Pointer<Utf8> settingsJson);

typedef _BookmarksGetC = Void Function(Handle handle);
typedef _BookmarksGetDart = void Function(Handle handle);

typedef _BookmarksUpdateC = Void Function(Handle handle, Pointer<Utf8> bookmarksJson);
typedef _BookmarksUpdateDart = void Function(Handle handle, Pointer<Utf8> bookmarksJson);

typedef _BookmarkAddC = Void Function(Handle handle, Pointer<Utf8> requestJson);
typedef _BookmarkAddDart = void Function(Handle handle, Pointer<Utf8> requestJson);

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
      crashStatus = library.lookupFunction<_CrashStatusC, _CrashStatusDart>(
        'nightcord_crash_status',
      ),
      crashReport = library.lookupFunction<_CrashReportC, _CrashReportDart>(
        'nightcord_crash_report',
      ),
      markCleanExit = library.lookupFunction<_MarkCleanExitC, _MarkCleanExitDart>(
        'nightcord_mark_clean_exit',
      ),
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
      poke = library.lookupFunction<_PokeC, _PokeDart>('nightcord_poke'),
      kick = library.lookupFunction<_KickC, _KickDart>('nightcord_kick'),
      ban = library.lookupFunction<_BanC, _BanDart>('nightcord_ban'),
      setAway = library.lookupFunction<_SetAwayC, _SetAwayDart>('nightcord_set_away'),
      setClientVolume = library.lookupFunction<_SetClientVolumeC, _SetClientVolumeDart>(
        'nightcord_voice_set_client_volume',
      ),
      audioDevices = library.lookupFunction<_AudioDevicesC, _AudioDevicesDart>(
        'nightcord_audio_devices',
      ),
      voiceStart = library.lookupFunction<_VoiceStartC, _VoiceStartDart>('nightcord_voice_start'),
      voiceStop = library.lookupFunction<_VoiceStopC, _VoiceStopDart>('nightcord_voice_stop'),
      voiceSetInputMuted = library.lookupFunction<_VoiceSetBoolC, _VoiceSetBoolDart>(
        'nightcord_voice_set_input_muted',
      ),
      voiceSetOutputMuted = library.lookupFunction<_VoiceSetBoolC, _VoiceSetBoolDart>(
        'nightcord_voice_set_output_muted',
      ),
      voicePushToTalk = library.lookupFunction<_VoiceSetBoolC, _VoiceSetBoolDart>(
        'nightcord_voice_push_to_talk',
      ),
      voiceStatus = library.lookupFunction<_VoiceStatusC, _VoiceStatusDart>(
        'nightcord_voice_status',
      ),
      voiceTestOutput = library.lookupFunction<_VoiceTestOutputC, _VoiceTestOutputDart>(
        'nightcord_voice_test_output',
      ),
      pollEvents = library.lookupFunction<_PollEventsC, _PollEventsDart>(
        'nightcord_poll_events',
      ),
      freeString = library.lookupFunction<_FreeStringC, _FreeStringDart>(
        'nightcord_free_string',
      ),
      settingsGet = library.lookupFunction<_SettingsGetC, _SettingsGetDart>(
        'nightcord_settings',
      ),
      settingsUpdate = library.lookupFunction<_SettingsUpdateC, _SettingsUpdateDart>(
        'nightcord_update_settings',
      ),
      bookmarksGet = library.lookupFunction<_BookmarksGetC, _BookmarksGetDart>('nightcord_bookmarks'),
      bookmarksUpdate = library.lookupFunction<_BookmarksUpdateC, _BookmarksUpdateDart>(
        'nightcord_update_bookmarks',
      ),
      bookmarkAdd = library.lookupFunction<_BookmarkAddC, _BookmarkAddDart>(
        'nightcord_add_bookmark',
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

  /// What the previous runs left behind, as JSON.
  ///
  /// Takes no handle, for the same reason as [log] — the question is asked
  /// exactly when the core is dead or never started.
  final Pointer<Utf8> Function() crashStatus;

  /// Builds a crash report and answers with its path (or why not), as JSON.
  ///
  /// Takes no handle; see [crashStatus].
  final Pointer<Utf8> Function() crashReport;

  /// Marks the run as a clean exit, so the next start does not report a crash.
  ///
  /// Returns false when the core's worker is already gone — the run was not
  /// clean, and the evidence is kept on purpose.
  final bool Function(Handle) markCleanExit;

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

  /// Pokes another client.
  final void Function(Handle, int, int, Pointer<Utf8>) poke;

  /// Removes another client; `scope` is serialised `KickScope` JSON.
  final void Function(Handle, int, int, Pointer<Utf8>, Pointer<Utf8>) kick;

  /// Bans another client; `duration` is serialised `BanDuration` JSON.
  final void Function(Handle, int, int, Pointer<Utf8>, Pointer<Utf8>) ban;

  /// Marks us away or back; `message` is what to say, and is ignored when
  /// `away` is false.
  final void Function(Handle, int, bool, Pointer<Utf8>) setAway;

  /// Scales one client's audio within the mix.
  final void Function(Handle, int, int, double) setClientVolume;

  /// Requests the device list for `"input"` or `"output"`.
  final void Function(Handle, Pointer<Utf8>) audioDevices;

  /// Opens devices and binds voice to a session.
  final void Function(Handle, int, Pointer<Utf8>, Pointer<Utf8>) voiceStart;

  /// Closes the devices.
  final void Function(Handle) voiceStop;

  /// Mutes the microphone.
  final void Function(Handle, bool) voiceSetInputMuted;

  /// Mutes the speakers.
  final void Function(Handle, bool) voiceSetOutputMuted;

  /// Push-to-talk key down or up.
  final void Function(Handle, bool) voicePushToTalk;

  /// Asks what the audio engine is doing. The answer arrives as a
  /// `voice_status` `CommandResult`.
  final void Function(Handle) voiceStatus;

  /// Plays a short tone through the speakers.
  final void Function(Handle) voiceTestOutput;

  /// Drains queued events as a JSON array. The result must be freed with
  /// [freeString].
  final Pointer<Utf8> Function(Handle) pollEvents;

  /// Frees a string returned by [pollEvents].
  final void Function(Pointer<Utf8>) freeString;

  /// Asks for the preferences. The answer arrives as a `settings`
  /// `CommandResult` whose `data` is the settings object.
  final void Function(Handle) settingsGet;

  /// Replaces the preferences. The answer arrives as `settings_update`.
  final void Function(Handle, Pointer<Utf8>) settingsUpdate;

  /// Asks for the saved servers. The answer arrives as a `bookmarks`
  /// `CommandResult` whose `data` is `{"version": 1, "bookmarks": [...]}`.
  ///
  /// The entries carry server passwords, so unlike the rest of this file the
  /// payload is a credential. Nothing here logs it.
  final void Function(Handle) bookmarksGet;

  /// Replaces the saved servers. The answer arrives as `bookmarks_update`.
  final void Function(Handle, Pointer<Utf8>) bookmarksUpdate;

  /// Saves a server from a raw address. The answer arrives as `bookmark_add`,
  /// carrying the list as it now stands.
  final void Function(Handle, Pointer<Utf8>) bookmarkAdd;
}
