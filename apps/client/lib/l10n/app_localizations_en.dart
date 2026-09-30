// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get closeButton => 'Close';

  @override
  String get logLabel => 'Log';

  @override
  String get openLogFolder => 'Open log folder';

  @override
  String get startupFailureTitle => 'The core failed to start';

  @override
  String get stackTraceLabel => 'Stack trace';

  @override
  String get startupFailureLogHint =>
      'The record of this start-up (if any) is in this file:';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLoading => 'Reading settings…';

  @override
  String get settingsAudioSection => 'Audio';

  @override
  String get settingsMicrophoneLabel => 'Microphone';

  @override
  String get settingsSpeakerLabel => 'Speakers';

  @override
  String get settingsTransmissionMode => 'Transmission';

  @override
  String get settingsDeviceChangeNote =>
      'Changing a device reopens the audio at once.';

  @override
  String get settingsConnectFirst => 'Connect to test the microphone.';

  @override
  String get settingsTestMicrophone => 'Test microphone';

  @override
  String get settingsStopTest => 'Stop the test';

  @override
  String get settingsTestSpeaker => 'Test speakers';

  @override
  String get settingsConnectionSection => 'Connection';

  @override
  String get settingsDefaultNickname => 'Default nickname';

  @override
  String get settingsIdentityProfile => 'Identity profile';

  @override
  String get settingsIdentityProfileHelper =>
      'One profile name is one client identity on every server';

  @override
  String get settingsAfterDrop => 'After a drop';

  @override
  String get settingsReconnectUnlimited => 'Reconnect (no limit)';

  @override
  String settingsReconnectAttempts(int n) {
    return 'Retry up to $n times';
  }

  @override
  String get settingsReconnectNever => 'Do not reconnect';

  @override
  String get settingsNotificationsSection => 'Notifications';

  @override
  String get settingsShortcutsSection => 'Shortcuts';

  @override
  String get settingsShortcutsHelp =>
      'Click the box and press the combination you want. Esc cancels, Delete clears (a cleared shortcut stops firing).';

  @override
  String get settingsInterfaceSection => 'Interface';

  @override
  String get settingsLanguageLabel => 'Language';

  @override
  String get settingsLanguageSystem => 'Follow the system';

  @override
  String get settingsLanguageZh => '简体中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsThemeLabel => 'Theme';

  @override
  String get settingsThemeSystem => 'Follow the system';

  @override
  String get settingsThemeNightcord => 'Nightcord';

  @override
  String get settingsThemeBlack => 'Black';

  @override
  String get settingsThemeWhite => 'White';

  @override
  String get settingsVoiceNotStarted =>
      'Voice has not started. Once it does, this shows the device actually in use and the microphone level.';

  @override
  String settingsDeviceInUse(String name) {
    return 'In use: $name';
  }

  @override
  String get settingsNoMicrophone => 'No microphone';

  @override
  String get settingsMicFellBack =>
      'Your chosen microphone is gone; the system default is in use.';

  @override
  String get settingsDeviceLost =>
      'The device was unplugged while in use. Starting voice again will restore it.';

  @override
  String get settingsTransmitting => 'Transmitting';

  @override
  String get settingsBelowThreshold => 'Below threshold — not transmitting';

  @override
  String get settingsLevelMeterHint =>
      'Microphone level (shown once voice starts)';

  @override
  String get settingsNotifyPresence => 'Someone joins or leaves';

  @override
  String get settingsNotifyPoke => 'Someone pokes you';

  @override
  String get settingsNotifyChannelMessage => 'Channel and server messages';

  @override
  String get settingsNotifyDirectMessage => 'Private messages';

  @override
  String get settingsNotifyConnection => 'A connection drops or comes back';

  @override
  String get settingsNotifySystem =>
      'Use system notifications when the window is not in front';

  @override
  String get settingsNotifyNote =>
      'Never for the conversation you are looking at — you can already see it.';

  @override
  String get settingsSensitivity => 'Sensitivity';

  @override
  String get settingsSensitivityHint =>
      'Higher is harder to trigger by room noise, and takes a louder voice.';

  @override
  String get settingsNoLogDirectory =>
      'This platform has no writable log directory; records go to standard error only.\n(Android and iOS need the host app to supply a sandbox path.)';

  @override
  String get settingsDeviceMissing =>
      'The previously selected device is gone; the system default will be used';

  @override
  String get settingsSystemDefault => 'System default';

  @override
  String settingsDeviceDefaultSuffix(String name) {
    return '$name (default)';
  }

  @override
  String get cancelButton => 'Cancel';

  @override
  String get saveButton => 'Save';

  @override
  String get connectAddressLabel => 'Server address';

  @override
  String get connectAddressHint => 'example.com or 192.168.1.10:9987';

  @override
  String get connectNicknameLabel => 'Nickname';

  @override
  String get connectServerPasswordLabel => 'Server password';

  @override
  String get connectServerPasswordHint => 'Leave empty if none';

  @override
  String get connectSaveServer => 'Save this server';

  @override
  String get connectButton => 'Connect';

  @override
  String get connectSavedServers => 'Saved servers';

  @override
  String get connectMoreTooltip => 'More';

  @override
  String get connectRename => 'Rename';

  @override
  String get connectDelete => 'Delete';

  @override
  String get connectSaveServerTitle => 'Save server';

  @override
  String get connectNameLabel => 'Name';

  @override
  String sidebarOffline(int count) {
    return 'Offline — $count';
  }

  @override
  String sidebarSessionFallback(int id) {
    return 'Server $id';
  }

  @override
  String get sidebarSheetSaved => 'Saved';

  @override
  String get sidebarAddServer => 'Add server';

  @override
  String get memberAway => 'Away';

  @override
  String get memberMuted => 'Muted';

  @override
  String get memberDeafened => 'Deafened';

  @override
  String get memberRecording => 'Recording';

  @override
  String get connectionStateConnected => 'Connected';

  @override
  String get connectionStateConnecting => 'Connecting';

  @override
  String get connectionStateReconnecting => 'Reconnecting';

  @override
  String get connectionStateDisconnecting => 'Disconnecting';

  @override
  String get connectionStateFailed => 'Connection failed';

  @override
  String get connectionStateDisconnected => 'Not connected';

  @override
  String get chatHintCompose => 'Send a message';

  @override
  String get chatHintReconnecting => 'Reconnecting…';

  @override
  String get chatHintConnecting => 'Connecting…';

  @override
  String get chatHintDisconnected => 'Connection lost';

  @override
  String get chatHintJoinChannel => 'Join a channel to speak';

  @override
  String get chatPrivateLabel => 'Private chat';

  @override
  String get chatBackToChannel => 'Back to channel';

  @override
  String get chatNotInChannel => 'Not in a channel';

  @override
  String chatOnlineCount(int count) {
    return '$count online';
  }

  @override
  String get chatEmpty => 'No messages yet';

  @override
  String get chatDownload => 'Download';

  @override
  String get chatFileTransferLater =>
      'File transfer is coming in a later phase';

  @override
  String timestampToday(String clock) {
    return 'Today $clock';
  }

  @override
  String timestampYesterday(String clock) {
    return 'Yesterday $clock';
  }

  @override
  String timestampThisYear(int month, int day, String clock) {
    return '$month/$day $clock';
  }

  @override
  String timestampOtherYear(int year, int month, int day) {
    return '$year/$month/$day';
  }

  @override
  String get bannerReconnecting => 'Connection lost — reconnecting…';

  @override
  String bannerRetryCountdown(int seconds, int attempt) {
    return 'Connection lost — retrying in ${seconds}s (attempt $attempt)';
  }

  @override
  String get bannerDisconnect => 'Disconnect';

  @override
  String get voiceUnmuteMic => 'Unmute microphone';

  @override
  String get voiceDisconnect => 'Disconnect from the server';

  @override
  String get voiceMuteMic => 'Mute microphone';

  @override
  String get voiceUndeafen => 'Undeafen';

  @override
  String get voiceDeafen => 'Deafen (mute speakers)';

  @override
  String get serverSessionEnded => 'Session ended';

  @override
  String get chordFieldIdle => 'Press the combination you want…';

  @override
  String get chordFieldUnset => 'Not set';

  @override
  String shellLogPath(String path) {
    return 'Log: $path';
  }

  @override
  String get shellOpenLog => 'Open log';

  @override
  String get errorTimeout => 'The operation timed out';

  @override
  String errorLagged(int count) {
    return 'The interface fell behind and $count events were dropped';
  }

  @override
  String get errorCommandFailed => 'The command failed';

  @override
  String get errorJoinDenied =>
      'You do not have permission to join that channel';

  @override
  String errorUnparsable(String message) {
    return 'Could not parse an event: $message';
  }

  @override
  String errorServerCode(String code) {
    return 'The server returned error code $code';
  }

  @override
  String errorPermissionAction(String action) {
    return 'Permission denied: cannot $action';
  }

  @override
  String errorMissingPermission(String permission) {
    return 'Missing permission #$permission';
  }

  @override
  String errorDeviceMissing(String name) {
    return 'Device not found: $name';
  }

  @override
  String get noticeJoined => 'joined the server';

  @override
  String get noticeLeft => 'left the server';

  @override
  String get noticeSomeone => 'Someone';

  @override
  String get noticeServerFallback => 'Server';

  @override
  String get noticeConnectionRestored => 'Connection restored';

  @override
  String get noticeReconnecting => 'Connection lost — reconnecting';

  @override
  String get noticeConnectionFailed => 'Connection failed';

  @override
  String get crashBannerTitle => 'Last session ended unexpectedly';

  @override
  String crashBannerNotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count crash notes',
      one: '1 crash note',
    );
    return '$_temp0';
  }

  @override
  String get crashGenerateReport => 'Generate report';

  @override
  String get crashOpenFolder => 'Open folder';

  @override
  String get crashDismiss => 'Dismiss';

  @override
  String crashReportWritten(String path) {
    return 'Report written: $path';
  }

  @override
  String get crashReportFailed => 'Could not generate the report; see the log';

  @override
  String get errorCoreGone => 'The core has crashed. Restart the application.';

  @override
  String get modePushToTalk => 'Push to talk';

  @override
  String get modeVoiceActivation => 'Voice activation';

  @override
  String get modeContinuous => 'Continuous';

  @override
  String get modeMuted => 'Muted';

  @override
  String get shortcutMute => 'Mute';

  @override
  String get shortcutDeafen => 'Deafen';

  @override
  String get shortcutPushToTalk => 'Push to talk';
}
