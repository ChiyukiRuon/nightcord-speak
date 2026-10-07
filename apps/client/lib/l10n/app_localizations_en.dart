// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get backButton => 'Back';

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
      'This start-up\'s log, if there is one, is in this file:';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLoading => 'Loading settings…';

  @override
  String get settingsAudioSection => 'Audio';

  @override
  String get settingsMicrophoneLabel => 'Microphone';

  @override
  String get settingsSpeakerLabel => 'Speakers';

  @override
  String get settingsTransmissionMode => 'Transmission mode';

  @override
  String get settingsDeviceChangeNote =>
      'Changing a device re-initialises the audio immediately.';

  @override
  String get settingsConnectFirst =>
      'Connect to a server to test the microphone.';

  @override
  String get settingsTestMicrophone => 'Test microphone';

  @override
  String get settingsStopTest => 'Stop test';

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
      'The same profile name is the same client identity on every server.';

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
      'Click the box on the right, then press the combination you want. Esc cancels, Delete clears.';

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
  String get settingsLanguageZhHant => '繁體中文';

  @override
  String get settingsLanguageJa => '日本語';

  @override
  String get settingsLanguageKo => '한국어';

  @override
  String get settingsThemeLabel => 'Theme';

  @override
  String get settingsThemeSystem => 'Follow the system';

  @override
  String get settingsThemeNightcord => 'Nightcord';

  @override
  String get settingsThemeBlack => 'Pure black';

  @override
  String get settingsThemeWhite => 'Pure white';

  @override
  String get settingsVoiceNotStarted =>
      'Voice has not started. Once it does, this shows the devices in use and the microphone level.';

  @override
  String settingsDeviceInUse(String name) {
    return 'Current device: $name';
  }

  @override
  String get settingsNoMicrophone => 'No microphone detected';

  @override
  String get settingsMicFellBack =>
      'The chosen microphone is unavailable; the system default is in use.';

  @override
  String get settingsDeviceLost =>
      'The device in use was disconnected. Start voice again to recover.';

  @override
  String get settingsTransmitting => 'Transmitting';

  @override
  String get settingsBelowThreshold => 'Below threshold — not transmitting';

  @override
  String get settingsLevelMeterHint =>
      'Microphone level (shown once voice starts)';

  @override
  String get settingsNotifyPresence => 'Members joining or leaving';

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
  String get settingsSensitivity => 'Sensitivity';

  @override
  String get settingsSensitivityHint =>
      'The higher the sensitivity, the less room noise triggers it — and the louder you have to speak.';

  @override
  String get settingsMicGain => 'Microphone gain';

  @override
  String get settingsMicGainHint =>
      'How loud everyone else hears you. All the way down is silence.';

  @override
  String get settingsMicGainSilent => 'Silent';

  @override
  String get settingsVolume => 'Output volume';

  @override
  String get settingsVolumeHint =>
      'Sets the default volume for everyone. You can still adjust one member on their own from the channel list.';

  @override
  String get settingsNoLogDirectory =>
      'This platform has no writable log directory.';

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
  String get connectNicknameLabel => 'Nickname';

  @override
  String get connectServerPasswordLabel => 'Server password';

  @override
  String get connectServerPasswordHint => 'Optional';

  @override
  String get connectSaveServer => 'Save server';

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
  String sidebarSessionFallback(int id) {
    return 'Server $id';
  }

  @override
  String get sidebarSheetSaved => 'Saved';

  @override
  String get sidebarBookmarkAdd => 'Bookmark server';

  @override
  String get sidebarBookmarkRemove => 'Remove bookmark';

  @override
  String get sidebarEditSaved => 'Edit';

  @override
  String get bookmarkEditTitle => 'Edit saved server';

  @override
  String get sidebarAddServer => 'Add server';

  @override
  String memberMenu(String name) {
    return 'Actions for $name';
  }

  @override
  String get memberPoke => 'Poke';

  @override
  String memberPokePrompt(String name) {
    return 'Poke $name';
  }

  @override
  String get memberPokeMessage => 'Message';

  @override
  String get memberMove => 'Move to channel…';

  @override
  String memberMoveTitle(String name) {
    return 'Move $name';
  }

  @override
  String get memberMoveChannel => 'Channel';

  @override
  String get memberKickChannel => 'Remove from channel';

  @override
  String get memberKickServer => 'Remove from server';

  @override
  String get memberBan => 'Ban…';

  @override
  String memberBanTitle(String name) {
    return 'Ban $name';
  }

  @override
  String get memberBanDuration => 'Ban duration';

  @override
  String get memberBanPermanent => 'Permanently';

  @override
  String memberBanMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: 'One minute',
    );
    return '$_temp0';
  }

  @override
  String memberBanHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours',
      one: 'One hour',
    );
    return '$_temp0';
  }

  @override
  String memberBanDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: 'One day',
    );
    return '$_temp0';
  }

  @override
  String get memberReason => 'Reason (optional)';

  @override
  String get memberVolume => 'Adjust volume…';

  @override
  String memberVolumeTitle(String name) {
    return '$name\'s volume';
  }

  @override
  String get memberVolumeHint =>
      'Applies to this session only. Output volume in the settings sets the default for everyone.';

  @override
  String get memberNoPermission => 'Your server permissions do not allow this';

  @override
  String get permissionsTitle => 'Your permissions';

  @override
  String get permissionsHint =>
      'Reported by the server for you, in the channel you are in.';

  @override
  String get permissionsJoinChannel => 'Join channels';

  @override
  String get permissionsMoveClients => 'Move other members';

  @override
  String get permissionsSendChannelMessage => 'Send channel messages';

  @override
  String get permissionsSendPrivateMessage => 'Send private messages';

  @override
  String get permissionsKick => 'Remove members';

  @override
  String get permissionsBan => 'Ban members';

  @override
  String get permissionsNotReported =>
      'This server does not tell clients what they may do, so there is nothing to show.';

  @override
  String get permissionsNone =>
      'Nothing beyond what every user has by default.';

  @override
  String get memberAway => 'Away';

  @override
  String get memberMuted => 'Microphone muted';

  @override
  String get memberDeafened => 'Speakers off';

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
  String chatPoked(String name) {
    return '$name poked you';
  }

  @override
  String chatPokedWith(String name, String message) {
    return '$name poked you: $message';
  }

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
  String get chatFileTransferLater => 'File transfer is not supported yet';

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
  String get voiceDisconnectConfirmTitle => 'Disconnect?';

  @override
  String get voiceDisconnectConfirmBody =>
      'You will return to the initial page, and your chat history will be cleared.';

  @override
  String get voiceMuteMic => 'Mute microphone';

  @override
  String get voiceUndeafen => 'Turn speakers on';

  @override
  String get voiceDeafen => 'Turn speakers off';

  @override
  String get voiceAway => 'Set yourself away';

  @override
  String get voiceBackOnline => 'Come back online';

  @override
  String get awayMessageTitle => 'Away message';

  @override
  String get awayMessageLabel => 'What to say';

  @override
  String get awayMessageNote =>
      'Everyone on the server sees this, and the away button will use it again next time.';

  @override
  String get serverSessionEnded => 'Session ended';

  @override
  String get chordFieldIdle => 'Press the combination you want…';

  @override
  String get chordFieldUnset => 'Not set';

  @override
  String shellLogPath(String path) {
    return 'Log location: $path';
  }

  @override
  String get shellDismissError => 'Close';

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
  String get crashReportFailed =>
      'Could not generate the report; see the log for details';

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

  @override
  String get gatewayTitle => 'Connect to your gateway';

  @override
  String get gatewayDescription =>
      'Enter your gateway address. A token is only needed if the gateway requires one.';

  @override
  String get gatewayUrlLabel => 'Gateway address';

  @override
  String get gatewayTokenLabel => 'Access token';

  @override
  String get gatewayConnect => 'Connect to gateway';

  @override
  String get gatewayInvalidUrl =>
      'Use a ws:// or wss:// address. HTTPS pages require wss://.';

  @override
  String get gatewayTokenRequired => 'Enter the gateway access token.';

  @override
  String get gatewayConnectionFailed =>
      'Could not connect. Check the address, token and gateway allowed origins.';

  @override
  String get webEnableAudio => 'Enable audio';

  @override
  String get webAudioHint =>
      'Allow microphone access and enable audio to join the conversation.';

  @override
  String get navigationChannels => 'Channels';

  @override
  String get voiceHoldToTalk => 'Hold to talk';

  @override
  String get settingsAboutSection => 'About';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get aboutDescription =>
      'This project is an unofficial third-party TeamSpeak 3 / TeamSpeak 6 client and is not affiliated with TeamSpeak.\n\nNightcord is a fictional voice chat application in HATSUNE MIKU: COLORFUL STAGE! This project claims no copyright or other intellectual property rights in the Nightcord name or its icon; those rights belong to their respective rights holders. This project is not affiliated with, partnered with, or authorized by SEGA, Colorful Palette or Nuverse, and does not represent their views.';

  @override
  String get aboutProject => 'Project';

  @override
  String get aboutLicense => 'Project license';

  @override
  String get aboutOpenSource => 'Open-source acknowledgements';

  @override
  String get aboutOpenSourceDescription =>
      'Built with Flutter, Dart, Riverpod, tsclientlib, Tokio, cpal, Opus and other open-source components. The notices include Flutter dependencies, Rust Core and gateway dependencies across platforms, and Noto fonts. Each component retains its own license and copyright.';

  @override
  String get aboutViewLicenses => 'View component licenses';

  @override
  String get screenStart => 'Share screen';

  @override
  String get screenStop => 'Stop sharing';

  @override
  String get screenLeave => 'Stop watching';

  @override
  String get screenWatch => 'Watch';

  @override
  String get screenConnecting => 'Connecting…';

  @override
  String get screenViewers => 'Viewers';

  @override
  String get screenFullscreen => 'Full screen';

  @override
  String get fullscreenExit => 'Exit full screen';

  @override
  String get screenHidePreview => 'Hide preview';

  @override
  String get memberStreaming => 'Sharing their screen';

  @override
  String get screenEnded => 'Screen sharing ended';

  @override
  String get screenCaptureFailed =>
      'Could not capture the screen. Check screen recording permission and try again.';

  @override
  String get screenRefused => 'The sharing request was declined.';

  @override
  String get screenTimeout => 'Screen sharing timed out. Try again.';

  @override
  String get screenConnectionFailed =>
      'Screen sharing connection failed. Try again.';

  @override
  String get screenTitle => 'Screen share';

  @override
  String get screenSetupSources => 'Choose a source';

  @override
  String get screenSetupApps => 'Applications';

  @override
  String get screenSetupScreens => 'Screens';

  @override
  String get screenSetupCameras => 'Camera';

  @override
  String get screenSetupNoSources => 'Nothing to share was found';

  @override
  String get screenSetupNext => 'Next';

  @override
  String get screenSetupBack => 'Back';

  @override
  String get screenSetupGoLive => 'Start streaming';

  @override
  String get screenSetupBasic => 'Basic';

  @override
  String get screenSetupAdvanced => 'Advanced';

  @override
  String get screenSetupPreset => 'Preset';

  @override
  String get screenSetupSource => 'Source';

  @override
  String get screenSetupPresentation => 'Presentation';

  @override
  String get screenSetupCaptureAudio => 'Capture audio';

  @override
  String get screenSetupPrivacy => 'Privacy';

  @override
  String get screenSetupPublic => 'Public';

  @override
  String get screenSetupContacts => 'Contacts';

  @override
  String get screenSetupPrivate => 'Private';

  @override
  String get screenSetupResolution => 'Resolution';

  @override
  String get screenSetupFps => 'FPS';

  @override
  String get screenSetupVideoBitrate => 'Bitrate';

  @override
  String get screenSetupAudioBitrate => 'Audio bitrate';

  @override
  String get screenSetupViewerLimit => 'Viewer limit';

  @override
  String get screenSetupUnlimited => 'Unlimited';

  @override
  String get screenSetupMode => 'Connection';

  @override
  String get screenSetupSfuUnavailable =>
      'Needs the server to relay the media, which this client does not do yet';

  @override
  String get screenSetupHelpPreset =>
      'Sets resolution, frame rate and bitrate together. Change any of them afterwards and this becomes your own set.';

  @override
  String get screenSetupHelpCaptureAudio =>
      'Sends what the shared window plays, alongside its picture.';

  @override
  String get screenSetupHelpPrivacy =>
      'Contacts behaves as private: this client has no contact list to check against.';

  @override
  String get screenSetupHelpResolution =>
      'What the picture is scaled to before it is encoded. The capture itself is always the source’s own size.';

  @override
  String get screenSetupHelpFps =>
      'How many frames a second are sent. Lower costs less bandwidth and looks less smooth.';

  @override
  String get screenSetupHelpVideoBitrate =>
      'The most the encoder may spend on the picture. What watchers see is what this buys.';

  @override
  String get screenSetupHelpAudioBitrate =>
      'The most the encoder may spend on sound. Only used while capture audio is on.';

  @override
  String get screenSetupHelpViewerLimit =>
      'How many people may watch at once. Unlimited leaves it to the server.';

  @override
  String get screenSetupHelpMode =>
      'P2P sends the picture straight to each watcher. Relaying it through the server is not implemented here.';

  @override
  String get screenSetupKbps => 'Kbps';

  @override
  String get screenSetupPreview => 'Preview';

  @override
  String get screenSetupPreviewNote =>
      'Preview uses a snapshot. You can still share a window when its preview is unavailable.';

  @override
  String get screenPopOut => 'Pop out';

  @override
  String get screenReturnInline => 'Back to small window';

  @override
  String get settingsShortcutsReset => 'Restore default';
}
