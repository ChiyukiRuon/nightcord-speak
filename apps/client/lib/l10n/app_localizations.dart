import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// Generic dismiss button
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeButton;

  /// Short label for the log section or file, on the start-up failure screen and in settings
  ///
  /// In en, this message translates to:
  /// **'Log'**
  String get logLabel;

  /// Button that reveals the log directory in the file manager
  ///
  /// In en, this message translates to:
  /// **'Open log folder'**
  String get openLogFolder;

  /// Heading of the screen shown when the Rust core could not be loaded at all
  ///
  /// In en, this message translates to:
  /// **'The core failed to start'**
  String get startupFailureTitle;

  /// Label above the raw stack trace on the start-up failure screen
  ///
  /// In en, this message translates to:
  /// **'Stack trace'**
  String get stackTraceLabel;

  /// Explains that the log file may hold the reason the core failed to start
  ///
  /// In en, this message translates to:
  /// **'The record of this start-up (if any) is in this file:'**
  String get startupFailureLogHint;

  /// Title of the settings dialog
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Shown while the core has not answered the settings request yet
  ///
  /// In en, this message translates to:
  /// **'Reading settings…'**
  String get settingsLoading;

  /// Heading of the audio section
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get settingsAudioSection;

  /// Label of the input device dropdown
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get settingsMicrophoneLabel;

  /// Label of the output device dropdown
  ///
  /// In en, this message translates to:
  /// **'Speakers'**
  String get settingsSpeakerLabel;

  /// Label of the transmission mode dropdown
  ///
  /// In en, this message translates to:
  /// **'Transmission'**
  String get settingsTransmissionMode;

  /// Explains that a device change is applied immediately
  ///
  /// In en, this message translates to:
  /// **'Changing a device reopens the audio at once.'**
  String get settingsDeviceChangeNote;

  /// Shown instead of the above when no session is connected
  ///
  /// In en, this message translates to:
  /// **'Connect to test the microphone.'**
  String get settingsConnectFirst;

  /// Button that opens the selected microphone so its level can be watched
  ///
  /// In en, this message translates to:
  /// **'Test microphone'**
  String get settingsTestMicrophone;

  /// The same button while the microphone test is running
  ///
  /// In en, this message translates to:
  /// **'Stop the test'**
  String get settingsStopTest;

  /// Button that plays a test tone through the output device
  ///
  /// In en, this message translates to:
  /// **'Test speakers'**
  String get settingsTestSpeaker;

  /// Heading of the connection section
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get settingsConnectionSection;

  /// Label of the nickname text field
  ///
  /// In en, this message translates to:
  /// **'Default nickname'**
  String get settingsDefaultNickname;

  /// Label of the identity profile text field
  ///
  /// In en, this message translates to:
  /// **'Identity profile'**
  String get settingsIdentityProfile;

  /// Helper text under the identity profile field
  ///
  /// In en, this message translates to:
  /// **'One profile name is one client identity on every server'**
  String get settingsIdentityProfileHelper;

  /// Label of the reconnect dropdown
  ///
  /// In en, this message translates to:
  /// **'After a drop'**
  String get settingsAfterDrop;

  /// Reconnect option: retry forever
  ///
  /// In en, this message translates to:
  /// **'Reconnect (no limit)'**
  String get settingsReconnectUnlimited;

  /// Reconnect option: a bounded number of attempts
  ///
  /// In en, this message translates to:
  /// **'Retry up to {n} times'**
  String settingsReconnectAttempts(int n);

  /// Reconnect option: give up on the first drop
  ///
  /// In en, this message translates to:
  /// **'Do not reconnect'**
  String get settingsReconnectNever;

  /// Heading of the notifications section
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotificationsSection;

  /// Heading of the shortcuts section
  ///
  /// In en, this message translates to:
  /// **'Shortcuts'**
  String get settingsShortcutsSection;

  /// Explains how the shortcut recorder works
  ///
  /// In en, this message translates to:
  /// **'Click the box and press the combination you want. Esc cancels, Delete clears (a cleared shortcut stops firing).'**
  String get settingsShortcutsHelp;

  /// Heading of the interface section (language now, theme later)
  ///
  /// In en, this message translates to:
  /// **'Interface'**
  String get settingsInterfaceSection;

  /// Label of the language dropdown
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageLabel;

  /// Language option: use whatever the operating system asks for
  ///
  /// In en, this message translates to:
  /// **'Follow the system'**
  String get settingsLanguageSystem;

  /// Language option for Chinese, written in its own language
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get settingsLanguageZh;

  /// Language option for English, written in its own language
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEn;

  /// Shown in place of the device-in-use line before the engine runs
  ///
  /// In en, this message translates to:
  /// **'Voice has not started. Once it does, this shows the device actually in use and the microphone level.'**
  String get settingsVoiceNotStarted;

  /// The device the engine actually opened
  ///
  /// In en, this message translates to:
  /// **'In use: {name}'**
  String settingsDeviceInUse(String name);

  /// Stand-in name when the engine reports no input device
  ///
  /// In en, this message translates to:
  /// **'No microphone'**
  String get settingsNoMicrophone;

  /// Warns that a saved input device no longer resolves
  ///
  /// In en, this message translates to:
  /// **'Your chosen microphone is gone; the system default is in use.'**
  String get settingsMicFellBack;

  /// Warns that the running stream lost its device
  ///
  /// In en, this message translates to:
  /// **'The device was unplugged while in use. Starting voice again will restore it.'**
  String get settingsDeviceLost;

  /// Level meter state while audio is being sent
  ///
  /// In en, this message translates to:
  /// **'Transmitting'**
  String get settingsTransmitting;

  /// Level meter state while voice activation is closed
  ///
  /// In en, this message translates to:
  /// **'Below threshold — not transmitting'**
  String get settingsBelowThreshold;

  /// Level meter state before the engine runs
  ///
  /// In en, this message translates to:
  /// **'Microphone level (shown once voice starts)'**
  String get settingsLevelMeterHint;

  /// Notification switch: join/leave events
  ///
  /// In en, this message translates to:
  /// **'Someone joins or leaves'**
  String get settingsNotifyPresence;

  /// Notification switch: pokes
  ///
  /// In en, this message translates to:
  /// **'Someone pokes you'**
  String get settingsNotifyPoke;

  /// Notification switch: channel/server chat
  ///
  /// In en, this message translates to:
  /// **'Channel and server messages'**
  String get settingsNotifyChannelMessage;

  /// Notification switch: direct messages
  ///
  /// In en, this message translates to:
  /// **'Private messages'**
  String get settingsNotifyDirectMessage;

  /// Notification switch: connection state changes
  ///
  /// In en, this message translates to:
  /// **'A connection drops or comes back'**
  String get settingsNotifyConnection;

  /// Notification switch: desktop toasts
  ///
  /// In en, this message translates to:
  /// **'Use system notifications when the window is not in front'**
  String get settingsNotifySystem;

  /// Explains why the focused conversation never raises a notice
  ///
  /// In en, this message translates to:
  /// **'Never for the conversation you are looking at — you can already see it.'**
  String get settingsNotifyNote;

  /// Label of the voice activation slider
  ///
  /// In en, this message translates to:
  /// **'Sensitivity'**
  String get settingsSensitivity;

  /// Explains what the sensitivity value means
  ///
  /// In en, this message translates to:
  /// **'Higher is harder to trigger by room noise, and takes a louder voice.'**
  String get settingsSensitivityHint;

  /// Shown in place of the log path where there is none
  ///
  /// In en, this message translates to:
  /// **'This platform has no writable log directory; records go to standard error only.\n(Android and iOS need the host app to supply a sandbox path.)'**
  String get settingsNoLogDirectory;

  /// Helper text on a device dropdown whose saved choice no longer resolves
  ///
  /// In en, this message translates to:
  /// **'The previously selected device is gone; the system default will be used'**
  String get settingsDeviceMissing;

  /// Device dropdown entry for letting the core pick
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsSystemDefault;

  /// Marks the device the operating system would pick by default
  ///
  /// In en, this message translates to:
  /// **'{name} (default)'**
  String settingsDeviceDefaultSuffix(String name);

  /// Generic cancel button
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButton;

  /// Generic save button
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveButton;

  /// Label of the address field on the connect screen
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get connectAddressLabel;

  /// Example address shown in the connect screen's address field
  ///
  /// In en, this message translates to:
  /// **'example.com or 192.168.1.10:9987'**
  String get connectAddressHint;

  /// Label of the nickname field on the connect screen
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get connectNicknameLabel;

  /// Label of the password field on the connect screen
  ///
  /// In en, this message translates to:
  /// **'Server password'**
  String get connectServerPasswordLabel;

  /// Hint under the server password field
  ///
  /// In en, this message translates to:
  /// **'Leave empty if none'**
  String get connectServerPasswordHint;

  /// Button that stores the typed address as a bookmark
  ///
  /// In en, this message translates to:
  /// **'Save this server'**
  String get connectSaveServer;

  /// The button that starts the connection
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connectButton;

  /// Heading above the bookmark list on the connect screen
  ///
  /// In en, this message translates to:
  /// **'Saved servers'**
  String get connectSavedServers;

  /// Tooltip of a saved server's overflow menu
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get connectMoreTooltip;

  /// Menu entry that renames a saved server
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get connectRename;

  /// Menu entry that removes a saved server
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get connectDelete;

  /// Title of the dialog that names a new bookmark
  ///
  /// In en, this message translates to:
  /// **'Save server'**
  String get connectSaveServerTitle;

  /// Label of the bookmark name field
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get connectNameLabel;

  /// Heading of the offline members section
  ///
  /// In en, this message translates to:
  /// **'Offline — {count}'**
  String sidebarOffline(int count);

  /// Name shown for a session whose server has not named itself yet
  ///
  /// In en, this message translates to:
  /// **'Server {id}'**
  String sidebarSessionFallback(int id);

  /// Heading above the saved-server list in the session switcher
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get sidebarSheetSaved;

  /// Entry that returns to the connect screen
  ///
  /// In en, this message translates to:
  /// **'Add server'**
  String get sidebarAddServer;

  /// Tooltip of the away badge on a member row
  ///
  /// In en, this message translates to:
  /// **'Away'**
  String get memberAway;

  /// Tooltip of the muted badge on a member row
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get memberMuted;

  /// Tooltip of the deafened badge on a member row
  ///
  /// In en, this message translates to:
  /// **'Deafened'**
  String get memberDeafened;

  /// Tooltip of the recording badge on a member row
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get memberRecording;

  /// Session state: connected
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connectionStateConnected;

  /// Session state: connecting
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get connectionStateConnecting;

  /// Session state: reconnecting
  ///
  /// In en, this message translates to:
  /// **'Reconnecting'**
  String get connectionStateReconnecting;

  /// Session state: disconnecting
  ///
  /// In en, this message translates to:
  /// **'Disconnecting'**
  String get connectionStateDisconnecting;

  /// Session state: failed
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get connectionStateFailed;

  /// Session state: disconnected
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get connectionStateDisconnected;

  /// Composer hint when a message can be sent
  ///
  /// In en, this message translates to:
  /// **'Send a message'**
  String get chatHintCompose;

  /// Composer hint while the session is reconnecting
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get chatHintReconnecting;

  /// Composer hint while the session is connecting
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get chatHintConnecting;

  /// Composer hint when the connection is gone
  ///
  /// In en, this message translates to:
  /// **'Connection lost'**
  String get chatHintDisconnected;

  /// Composer hint when not in a channel
  ///
  /// In en, this message translates to:
  /// **'Join a channel to speak'**
  String get chatHintJoinChannel;

  /// Badge next to a private conversation's title, and the fallback title
  ///
  /// In en, this message translates to:
  /// **'Private chat'**
  String get chatPrivateLabel;

  /// Tooltip of the button that leaves a private conversation
  ///
  /// In en, this message translates to:
  /// **'Back to channel'**
  String get chatBackToChannel;

  /// Chat header title when no channel is joined
  ///
  /// In en, this message translates to:
  /// **'Not in a channel'**
  String get chatNotInChannel;

  /// Number of clients online, in the chat header
  ///
  /// In en, this message translates to:
  /// **'{count} online'**
  String chatOnlineCount(int count);

  /// Placeholder in an empty conversation
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get chatEmpty;

  /// Tooltip of an attachment's download button
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get chatDownload;

  /// Tooltip when an attachment cannot be downloaded yet
  ///
  /// In en, this message translates to:
  /// **'File transfer is coming in a later phase'**
  String get chatFileTransferLater;

  /// Message timestamp for today; the clock is 24-hour
  ///
  /// In en, this message translates to:
  /// **'Today {clock}'**
  String timestampToday(String clock);

  /// Message timestamp for yesterday
  ///
  /// In en, this message translates to:
  /// **'Yesterday {clock}'**
  String timestampYesterday(String clock);

  /// Message timestamp for an earlier day in the same year
  ///
  /// In en, this message translates to:
  /// **'{month}/{day} {clock}'**
  String timestampThisYear(int month, int day, String clock);

  /// Message timestamp for another year
  ///
  /// In en, this message translates to:
  /// **'{year}/{month}/{day}'**
  String timestampOtherYear(int year, int month, int day);

  /// Reconnect banner before a delay has been scheduled
  ///
  /// In en, this message translates to:
  /// **'Connection lost — reconnecting…'**
  String get bannerReconnecting;

  /// Reconnect banner with the countdown and attempt number
  ///
  /// In en, this message translates to:
  /// **'Connection lost — retrying in {seconds}s (attempt {attempt})'**
  String bannerRetryCountdown(int seconds, int attempt);

  /// Button that stops the reconnect loop
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get bannerDisconnect;

  /// Tooltip of the microphone button while muted
  ///
  /// In en, this message translates to:
  /// **'Unmute microphone'**
  String get voiceUnmuteMic;

  /// Tooltip of the microphone button while open
  ///
  /// In en, this message translates to:
  /// **'Mute microphone'**
  String get voiceMuteMic;

  /// Tooltip of the speaker button while deafened
  ///
  /// In en, this message translates to:
  /// **'Undeafen'**
  String get voiceUndeafen;

  /// Tooltip of the speaker button while listening
  ///
  /// In en, this message translates to:
  /// **'Deafen (mute speakers)'**
  String get voiceDeafen;

  /// Shown when the session is gone and the page has nothing to draw
  ///
  /// In en, this message translates to:
  /// **'Session ended'**
  String get serverSessionEnded;

  /// Shortcut recorder hint while not recording
  ///
  /// In en, this message translates to:
  /// **'Press the combination you want…'**
  String get chordFieldIdle;

  /// Shortcut recorder placeholder for an unbound action
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get chordFieldUnset;

  /// Shows where the log file lives
  ///
  /// In en, this message translates to:
  /// **'Log: {path}'**
  String shellLogPath(String path);

  /// Button on the error snackbar that reveals the log directory
  ///
  /// In en, this message translates to:
  /// **'Open log'**
  String get shellOpenLog;

  /// Error sentence for the timeout variant
  ///
  /// In en, this message translates to:
  /// **'The operation timed out'**
  String get errorTimeout;

  /// Error sentence when the core dropped events for a slow UI
  ///
  /// In en, this message translates to:
  /// **'The interface fell behind and {count} events were dropped'**
  String errorLagged(int count);

  /// Fallback when a command failed without a reason from the core
  ///
  /// In en, this message translates to:
  /// **'The command failed'**
  String get errorCommandFailed;

  /// Shown when the local permission snapshot refuses a channel join
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to join that channel'**
  String get errorJoinDenied;

  /// Shown when an event from the core could not be decoded
  ///
  /// In en, this message translates to:
  /// **'Could not parse an event: {message}'**
  String errorUnparsable(String message);

  /// Error sentence for a variant that carries only a server-side code
  ///
  /// In en, this message translates to:
  /// **'The server returned error code {code}'**
  String errorServerCode(String code);

  /// Error sentence for a permission variant that names the action
  ///
  /// In en, this message translates to:
  /// **'Permission denied: cannot {action}'**
  String errorPermissionAction(String action);

  /// Error sentence for a variant that carries a permission id
  ///
  /// In en, this message translates to:
  /// **'Missing permission #{permission}'**
  String errorMissingPermission(String permission);

  /// Error sentence for a variant that names a device
  ///
  /// In en, this message translates to:
  /// **'Device not found: {name}'**
  String errorDeviceMissing(String name);

  /// Notification body when someone joins; the title is their name
  ///
  /// In en, this message translates to:
  /// **'joined the server'**
  String get noticeJoined;

  /// Notification body when someone leaves
  ///
  /// In en, this message translates to:
  /// **'left the server'**
  String get noticeLeft;

  /// Fallback name when a departing client's name is unreadable
  ///
  /// In en, this message translates to:
  /// **'Someone'**
  String get noticeSomeone;

  /// Fallback title when the server has not named itself yet
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get noticeServerFallback;

  /// Notification body after a reconnect succeeded
  ///
  /// In en, this message translates to:
  /// **'Connection restored'**
  String get noticeConnectionRestored;

  /// Notification body while a dropped connection is being retried
  ///
  /// In en, this message translates to:
  /// **'Connection lost — reconnecting'**
  String get noticeReconnecting;

  /// Notification body when the connection failed for good
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get noticeConnectionFailed;

  /// Banner heading shown when the previous run did not exit cleanly
  ///
  /// In en, this message translates to:
  /// **'Last session ended unexpectedly'**
  String get crashBannerTitle;

  /// How much crash evidence is waiting to be bundled
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 crash note} other{{count} crash notes}}'**
  String crashBannerNotes(int count);

  /// Button that bundles logs, notes and markers into one text file
  ///
  /// In en, this message translates to:
  /// **'Generate report'**
  String get crashGenerateReport;

  /// Button that reveals the crash evidence directory
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get crashOpenFolder;

  /// Button that hides the crash banner for this session
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get crashDismiss;

  /// Snack bar after a crash report was generated
  ///
  /// In en, this message translates to:
  /// **'Report written: {path}'**
  String crashReportWritten(String path);

  /// Snack bar when the crash report could not be written
  ///
  /// In en, this message translates to:
  /// **'Could not generate the report; see the log'**
  String get crashReportFailed;

  /// Error sentence for the dead-worker variant
  ///
  /// In en, this message translates to:
  /// **'The core has crashed. Restart the application.'**
  String get errorCoreGone;

  /// Transmission mode: only while the key is held
  ///
  /// In en, this message translates to:
  /// **'Push to talk'**
  String get modePushToTalk;

  /// Transmission mode: opens on voice above the threshold
  ///
  /// In en, this message translates to:
  /// **'Voice activation'**
  String get modeVoiceActivation;

  /// Transmission mode: always open
  ///
  /// In en, this message translates to:
  /// **'Continuous'**
  String get modeContinuous;

  /// Transmission mode: closed
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get modeMuted;

  /// Shortcut action: toggle the microphone
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get shortcutMute;

  /// Shortcut action: toggle the speakers
  ///
  /// In en, this message translates to:
  /// **'Deafen'**
  String get shortcutDeafen;

  /// Shortcut action: hold to transmit
  ///
  /// In en, this message translates to:
  /// **'Push to talk'**
  String get shortcutPushToTalk;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
