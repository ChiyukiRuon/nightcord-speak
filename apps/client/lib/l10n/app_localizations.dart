import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
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
    Locale('ja'),
    Locale('ko'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  /// Tooltip of the button that leaves a page, such as the settings page
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get backButton;

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
  /// **'This start-up\'s log, if there is one, is in this file:'**
  String get startupFailureLogHint;

  /// Title of the settings page, and the tooltip of the buttons that open it
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Shown while the core has not answered the settings request yet
  ///
  /// In en, this message translates to:
  /// **'Loading settings…'**
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
  /// **'Transmission mode'**
  String get settingsTransmissionMode;

  /// Explains that a device change is applied immediately
  ///
  /// In en, this message translates to:
  /// **'Changing a device re-initialises the audio immediately.'**
  String get settingsDeviceChangeNote;

  /// Shown instead of the above when no session is connected
  ///
  /// In en, this message translates to:
  /// **'Connect to a server to test the microphone.'**
  String get settingsConnectFirst;

  /// Button that opens the selected microphone so its level can be watched
  ///
  /// In en, this message translates to:
  /// **'Test microphone'**
  String get settingsTestMicrophone;

  /// The same button while the microphone test is running
  ///
  /// In en, this message translates to:
  /// **'Stop test'**
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
  /// **'The same profile name is the same client identity on every server.'**
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
  /// **'Click the box on the right, then press the combination you want. Esc cancels, Delete clears.'**
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

  /// The language's own name, shown in a picker
  ///
  /// In en, this message translates to:
  /// **'繁體中文'**
  String get settingsLanguageZhHant;

  /// The language's own name, shown in a picker
  ///
  /// In en, this message translates to:
  /// **'日本語'**
  String get settingsLanguageJa;

  /// The language's own name, shown in a picker
  ///
  /// In en, this message translates to:
  /// **'한국어'**
  String get settingsLanguageKo;

  /// Label of the theme dropdown
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsThemeLabel;

  /// Theme option: Black when the system is dark, White when it is light
  ///
  /// In en, this message translates to:
  /// **'Follow the system'**
  String get settingsThemeSystem;

  /// Theme option: the default, and the only one the colour specification defines. A product name, so it is not translated
  ///
  /// In en, this message translates to:
  /// **'Nightcord'**
  String get settingsThemeNightcord;

  /// Theme option: the neutral dark theme
  ///
  /// In en, this message translates to:
  /// **'Pure black'**
  String get settingsThemeBlack;

  /// Theme option: the neutral light theme
  ///
  /// In en, this message translates to:
  /// **'Pure white'**
  String get settingsThemeWhite;

  /// Shown in place of the device-in-use line before the engine runs
  ///
  /// In en, this message translates to:
  /// **'Voice has not started. Once it does, this shows the devices in use and the microphone level.'**
  String get settingsVoiceNotStarted;

  /// The device the engine actually opened
  ///
  /// In en, this message translates to:
  /// **'Current device: {name}'**
  String settingsDeviceInUse(String name);

  /// Stand-in name when the engine reports no input device
  ///
  /// In en, this message translates to:
  /// **'No microphone detected'**
  String get settingsNoMicrophone;

  /// Warns that a saved input device no longer resolves
  ///
  /// In en, this message translates to:
  /// **'The chosen microphone is unavailable; the system default is in use.'**
  String get settingsMicFellBack;

  /// Warns that the running stream lost its device
  ///
  /// In en, this message translates to:
  /// **'The device in use was disconnected. Start voice again to recover.'**
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
  /// **'Members joining or leaving'**
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

  /// Label of the voice activation slider
  ///
  /// In en, this message translates to:
  /// **'Sensitivity'**
  String get settingsSensitivity;

  /// Explains what the sensitivity value means
  ///
  /// In en, this message translates to:
  /// **'The higher the sensitivity, the less room noise triggers it — and the louder you have to speak.'**
  String get settingsSensitivityHint;

  /// Label above the slider that sets how loud others hear us
  ///
  /// In en, this message translates to:
  /// **'Microphone gain'**
  String get settingsMicGain;

  /// Explains the gain slider, including that its bottom position is silence
  ///
  /// In en, this message translates to:
  /// **'How loud everyone else hears you. All the way down is silence.'**
  String get settingsMicGainHint;

  /// Replaces the decibel value when the gain slider sits at the bottom
  ///
  /// In en, this message translates to:
  /// **'Silent'**
  String get settingsMicGainSilent;

  /// Label above the master playback volume slider
  ///
  /// In en, this message translates to:
  /// **'Output volume'**
  String get settingsVolume;

  /// Points at the per-person volume control
  ///
  /// In en, this message translates to:
  /// **'Sets the default volume for everyone. You can still adjust one member on their own from the channel list.'**
  String get settingsVolumeHint;

  /// Shown in place of the log path where there is none
  ///
  /// In en, this message translates to:
  /// **'This platform has no writable log directory.'**
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
  /// **'Optional'**
  String get connectServerPasswordHint;

  /// Button that stores the typed address as a bookmark
  ///
  /// In en, this message translates to:
  /// **'Save server'**
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

  /// Sheet item that saves the connected server
  ///
  /// In en, this message translates to:
  /// **'Bookmark server'**
  String get sidebarBookmarkAdd;

  /// Sheet item that unsaves the connected server
  ///
  /// In en, this message translates to:
  /// **'Remove bookmark'**
  String get sidebarBookmarkRemove;

  /// Menu item that opens the saved-server editor
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get sidebarEditSaved;

  /// Title of the dialog that edits a bookmark
  ///
  /// In en, this message translates to:
  /// **'Edit saved server'**
  String get bookmarkEditTitle;

  /// Entry that returns to the connect screen
  ///
  /// In en, this message translates to:
  /// **'Add server'**
  String get sidebarAddServer;

  /// Accessibility label on a member whose menu opens on right click
  ///
  /// In en, this message translates to:
  /// **'Actions for {name}'**
  String memberMenu(String name);

  /// Menu item that makes the other client beep
  ///
  /// In en, this message translates to:
  /// **'Poke'**
  String get memberPoke;

  /// Title of the poke message prompt
  ///
  /// In en, this message translates to:
  /// **'Poke {name}'**
  String memberPokePrompt(String name);

  /// Label of the optional text sent with a poke
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get memberPokeMessage;

  /// Menu item that moves a member into another channel
  ///
  /// In en, this message translates to:
  /// **'Move to channel…'**
  String get memberMove;

  /// Title of the channel picker
  ///
  /// In en, this message translates to:
  /// **'Move {name}'**
  String memberMoveTitle(String name);

  /// Label of the channel dropdown in the move dialog
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get memberMoveChannel;

  /// Menu item: remove from the current channel only
  ///
  /// In en, this message translates to:
  /// **'Remove from channel'**
  String get memberKickChannel;

  /// Menu item: remove from the server entirely
  ///
  /// In en, this message translates to:
  /// **'Remove from server'**
  String get memberKickServer;

  /// Menu item that opens the ban dialog
  ///
  /// In en, this message translates to:
  /// **'Ban…'**
  String get memberBan;

  /// Title of the ban dialog
  ///
  /// In en, this message translates to:
  /// **'Ban {name}'**
  String memberBanTitle(String name);

  /// Label of the ban length selector
  ///
  /// In en, this message translates to:
  /// **'Ban duration'**
  String get memberBanDuration;

  /// Ban length: until someone lifts it
  ///
  /// In en, this message translates to:
  /// **'Permanently'**
  String get memberBanPermanent;

  /// Ban length in minutes
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1 {One minute} other {{count} minutes}}'**
  String memberBanMinutes(int count);

  /// Ban length in hours
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1 {One hour} other {{count} hours}}'**
  String memberBanHours(int count);

  /// Ban length in days
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1 {One day} other {{count} days}}'**
  String memberBanDays(int count);

  /// Label of the optional explanation sent with a kick or ban
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get memberReason;

  /// Menu item that opens the per-person volume slider
  ///
  /// In en, this message translates to:
  /// **'Adjust volume…'**
  String get memberVolume;

  /// Title of the per-person volume dialog
  ///
  /// In en, this message translates to:
  /// **'{name}\'s volume'**
  String memberVolumeTitle(String name);

  /// Explains that a per-person volume is not remembered
  ///
  /// In en, this message translates to:
  /// **'Applies to this session only. Output volume in the settings sets the default for everyone.'**
  String get memberVolumeHint;

  /// Tooltip on a menu item greyed out by permissions
  ///
  /// In en, this message translates to:
  /// **'Your server permissions do not allow this'**
  String get memberNoPermission;

  /// Title of the panel listing what the server lets us do
  ///
  /// In en, this message translates to:
  /// **'Your permissions'**
  String get permissionsTitle;

  /// Explains where the permission list comes from
  ///
  /// In en, this message translates to:
  /// **'Reported by the server for you, in the channel you are in.'**
  String get permissionsHint;

  /// Permission name
  ///
  /// In en, this message translates to:
  /// **'Join channels'**
  String get permissionsJoinChannel;

  /// Permission name
  ///
  /// In en, this message translates to:
  /// **'Move other members'**
  String get permissionsMoveClients;

  /// Permission name
  ///
  /// In en, this message translates to:
  /// **'Send channel messages'**
  String get permissionsSendChannelMessage;

  /// Permission name
  ///
  /// In en, this message translates to:
  /// **'Send private messages'**
  String get permissionsSendPrivateMessage;

  /// Permission name
  ///
  /// In en, this message translates to:
  /// **'Remove members'**
  String get permissionsKick;

  /// Permission name
  ///
  /// In en, this message translates to:
  /// **'Ban members'**
  String get permissionsBan;

  /// Shown when the server sent no permission hints at all
  ///
  /// In en, this message translates to:
  /// **'This server does not tell clients what they may do, so there is nothing to show.'**
  String get permissionsNotReported;

  /// Shown when the server answered but granted nothing special
  ///
  /// In en, this message translates to:
  /// **'Nothing beyond what every user has by default.'**
  String get permissionsNone;

  /// Tooltip of the away badge on a member row
  ///
  /// In en, this message translates to:
  /// **'Away'**
  String get memberAway;

  /// Tooltip of the muted badge on a member row
  ///
  /// In en, this message translates to:
  /// **'Microphone muted'**
  String get memberMuted;

  /// Tooltip of the deafened badge on a member row
  ///
  /// In en, this message translates to:
  /// **'Speakers off'**
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

  /// A poke with nothing written with it
  ///
  /// In en, this message translates to:
  /// **'{name} poked you'**
  String chatPoked(String name);

  /// A poke carrying a message
  ///
  /// In en, this message translates to:
  /// **'{name} poked you: {message}'**
  String chatPokedWith(String name, String message);

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
  /// **'File transfer is not supported yet'**
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

  /// Tooltip of the button that closes the current server connection
  ///
  /// In en, this message translates to:
  /// **'Disconnect from the server'**
  String get voiceDisconnect;

  /// Title of the dialog that asks before closing a server connection
  ///
  /// In en, this message translates to:
  /// **'Disconnect?'**
  String get voiceDisconnectConfirmTitle;

  /// Says what is actually lost, which is the reason the dialog exists
  ///
  /// In en, this message translates to:
  /// **'You will return to the initial page, and your chat history will be cleared.'**
  String get voiceDisconnectConfirmBody;

  /// Tooltip of the microphone button while open
  ///
  /// In en, this message translates to:
  /// **'Mute microphone'**
  String get voiceMuteMic;

  /// Tooltip of the speaker button while deafened
  ///
  /// In en, this message translates to:
  /// **'Turn speakers on'**
  String get voiceUndeafen;

  /// Tooltip of the speaker button while listening
  ///
  /// In en, this message translates to:
  /// **'Turn speakers off'**
  String get voiceDeafen;

  /// Tooltip of the away button while we are here
  ///
  /// In en, this message translates to:
  /// **'Set yourself away'**
  String get voiceAway;

  /// Tooltip of the away button while we are away
  ///
  /// In en, this message translates to:
  /// **'Come back online'**
  String get voiceBackOnline;

  /// Title of the dialog that sets what we say when we are away
  ///
  /// In en, this message translates to:
  /// **'Away message'**
  String get awayMessageTitle;

  /// Label of the one field in the away message dialog
  ///
  /// In en, this message translates to:
  /// **'What to say'**
  String get awayMessageLabel;

  /// Says that the message is public, and that it is remembered
  ///
  /// In en, this message translates to:
  /// **'Everyone on the server sees this, and the away button will use it again next time.'**
  String get awayMessageNote;

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
  /// **'Log location: {path}'**
  String shellLogPath(String path);

  /// Tooltip of the button that closes the error bar
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get shellDismissError;

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
  /// **'Could not generate the report; see the log for details'**
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
      <String>['en', 'ja', 'ko', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
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
