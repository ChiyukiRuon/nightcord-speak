import 'package:nightcord_client/features/server/chat_panel.dart';
import 'package:nightcord_client/features/settings/sections/audio_section.dart';
import 'package:nightcord_client/features/settings/sections/about_section.dart';
import 'package:nightcord_client/features/settings/sections/notifications_section.dart';
// Every page, built once with plausible data.
//
// The app had no widget tests at all before the design system: the stores and
// the models were covered, and nothing ever built a `Scaffold`. That is how a
// page can reach a state where it throws inside `build` and only a person who
// opened *that* dialog finds out.
//
// No golden files on purpose. They are rendered by the platform's own text
// engine, so a PNG committed from Windows fails on macOS for reasons that have
// nothing to do with the change — and this repository ships six platforms. The
// assertions that matter about the *design* are in `design_test.dart`, where
// they are measured rather than pictured.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/screen/screen_providers.dart';
import 'package:nightcord_client/core/screen/screen_share_backend.dart';
import 'package:nightcord_client/features/screen/screen_pip.dart';
import 'package:nightcord_client/core/transport/client_transport.dart';
import 'package:nightcord_client/design/components/app_logo.dart';
import 'package:nightcord_client/features/server/channel_sidebar.dart';
import 'package:nightcord_client/features/settings/settings_page.dart';
import 'package:nightcord_client/widgets/app_shell.dart';
import 'package:nightcord_client/design/theme/app_theme.dart';
import 'package:nightcord_client/design/tokens/app_palette.dart';
import 'package:nightcord_client/features/connect/connect_page.dart';
import 'package:nightcord_client/features/notifications/notice_stack.dart';
import 'package:nightcord_client/features/server/server_page.dart';
import 'package:nightcord_client/features/voice/voice_bar.dart';
import 'package:nightcord_client/l10n/app_localizations.dart';
import 'package:nightcord_client/models/bookmarks.dart';
import 'package:nightcord_client/models/connect_request.dart';
import 'package:nightcord_client/models/domain.dart';
import 'package:nightcord_client/models/events.dart';
import 'package:nightcord_client/models/screen_options.dart';
import 'package:nightcord_client/models/settings.dart';
import 'package:nightcord_client/models/shortcuts.dart';
import 'package:nightcord_client/models/voice_status.dart';
import 'package:nightcord_client/providers/providers.dart';
import 'package:nightcord_client/providers/sounds.dart';
import 'package:nightcord_client/core/sounds/sound_pack.dart';
import 'package:nightcord_client/state/notifications.dart';
import 'package:nightcord_client/state/server_view.dart';
import 'package:nightcord_client/layout/mobile_shell.dart';
import 'package:nightcord_client/layout/desktop_shell.dart';
import 'package:nightcord_client/util/gain.dart';

/// A filesystem capability that resolves under the widget test's fake clock.
class _RenderSoundLibrary implements SoundLibrary {
  @override
  bool get available => true;
  @override
  Future<String> directory() async => '/app/sounds';
  @override
  Future<List<SoundPack>> scan() async => [
    const SoundPack(name: 'nightcord', files: [], mapping: {}),
  ];
  @override
  Future<void> save(String pack, Map<SoundAction, String?> mapping) async {}
  @override
  Future<void> play(String pack, String file, {String? output, double volume = 1}) async {}
}

/// A transport that answers nothing.
///
/// The pages fire commands on open (`requestSettings`, `requestAudioDevices`)
/// and never expect an answer before drawing; this lets them do that without a
/// core. `noSuchMethod` rather than 20 stubs — the interface is wide and this
/// test only cares that the calls do not throw.
class _SilentTransport implements ClientTransport {
  final StreamController<FfiEvent> _events =
      StreamController<FfiEvent>.broadcast();

  /// The commands this transport was asked to perform.
  ///
  /// Only [disconnect] is recorded: it is the one command a page in this file
  /// *initiates*, as opposed to the ones fired on open that nothing asserts
  /// about. Everything else still falls through to `noSuchMethod`.
  final List<String> calls = [];

  @override
  Stream<FfiEvent> get events => _events.stream;

  @override
  void disconnect(int session) => calls.add('disconnect:$session');
  @override
  void setNickname(int session, String nickname) =>
      calls.add('nickname:$session:$nickname');
  @override
  void setPushToTalk(bool held) => calls.add('ptt:$held');

  @override
  void connect(ConnectRequest request) =>
      calls.add('connect:${request.address}');

  /// Pushes one event as if the core had reported it.
  ///
  /// The screen controller only moves on what the server says back, so a test
  /// that taps "share" and stops there never reaches the state a user sees.
  void emit(FfiEvent event) => _events.add(event);

  /// Recorded because the whole point of the member menu is which of these it
  /// chooses, and with which arguments — a menu that wired "kick from server"
  /// to the channel scope would be invisible otherwise.
  @override
  void poke(int session, int clientId, String message) =>
      calls.add('poke:$clientId:$message');

  @override
  void kick(int session, int clientId, KickScope scope, String? message) =>
      calls.add('kick:${scope.wire}:$clientId:${message ?? ''}');

  @override
  void ban(int session, int clientId, BanDuration duration, String? reason) =>
      calls.add('ban:$clientId:${duration.isPermanent ? "forever" : "timed"}');

  @override
  void setClientVolume(int session, int clientId, double volume) =>
      calls.add('volume:$clientId:${volume.toStringAsFixed(2)}');

  /// Recorded for the same reason as the member menu: an away toggle that sent
  /// the wrong message, or "back" when it meant "away", would look right on
  /// screen and be wrong on the server.
  @override
  void setAway(int session, {required bool away, String? message}) =>
      calls.add('away:${away ? "yes" : "no"}:${message ?? ""}');

  /// The settings each `start` carried, in order.
  ///
  /// Kept apart from [calls] so the assertions about *which* command went out
  /// stay readable — and so a test can ask what the share was set to without
  /// unpicking a string.
  final List<Map<String, dynamic>> starts = [];

  /// Recorded with the peer it names: "watch" and "join" are one word apart,
  /// and only the second one reaches the server once the stream is known.
  @override
  void screen(int session, Map<String, dynamic> command) {
    final options = command['options'];
    if (options is Map) starts.add(options.cast<String, dynamic>());
    calls.add(
      'screen:${command['action']}:${command['client_id'] ?? command['stream_id'] ?? ''}',
    );
  }

  /// Recorded with the row it names: the buttons are per row, and a page that
  /// reset all three from one of them would look identical from the outside.
  /// Only ever *asked* — the defaults are the core's to know.
  @override
  void resetShortcut(ShortcutAction action) =>
      calls.add('resetShortcut:${action.wire}');

  /// Recorded so a test can tell "the slider moved" from "the core was told":
  /// the local state changes either way, and only the second one survives a
  /// restart.
  @override
  void updateSettings(Settings settings) =>
      calls.add('updateSettings:${settings.audio.inputGainDb}');

  /// The address book as the core last reported it.
  ///
  /// Kept here rather than only recorded: saving the connected server sends a
  /// `NewBookmark`, and what comes back is a list — testing the toggle means
  /// holding one.
  BookmarkList bookmarks = const BookmarkList();

  @override
  void addBookmark(NewBookmark bookmark) =>
      calls.add('addBookmark:${bookmark.address}');

  @override
  void updateBookmarks(BookmarkList value) {
    bookmarks = value;
    calls.add('updateBookmarks:${value.bookmarks.length}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FixedSessions extends SessionsNotifier {
  _FixedSessions(this.sessions);
  final Map<int, ServerView> sessions;

  @override
  Map<int, ServerView> build() => sessions;
}

class _FixedActive extends ActiveSessionNotifier {
  @override
  int? build() => 1;
}

class _FixedSettings extends SettingsNotifier {
  _FixedSettings([this.settings = const Settings()]);

  final Settings settings;

  @override
  Settings? build() => settings;
}

class _FixedDevices extends AudioDevicesNotifier {
  @override
  Map<String, List<AudioDevice>> build() => const {
    'input': [AudioDevice(id: 'mic-1', name: '麦克风（ROG CARNYX）')],
    'output': [AudioDevice(id: 'spk-1', name: '扬声器（Realtek）')],
  };
}

/// A running engine, so the sections that only draw when voice is up are
/// exercised rather than skipped.
class _FixedVoiceStatus extends VoiceStatusNotifier {
  @override
  VoiceStatus? build() => const VoiceStatus(
    healthy: true,
    level: 0.42,
    transmitting: true,
    input: DeviceStatus(id: 'mic-1', name: '麦克风（ROG CARNYX）'),
    output: DeviceStatus(id: 'spk-1', name: '扬声器（Realtek）'),
  );
}

/// One saved server, so the connect page has a row to click.
class _FixedBookmarks extends BookmarksNotifier {
  @override
  BookmarkList? build() => const BookmarkList(
    bookmarks: [Bookmark(name: '局域网测试服', host: '192.168.31.128', port: 9987)],
  );
}

class _FixedNotices extends NoticesNotifier {
  @override
  List<Notice> build() => const [
    Notice(
      kind: NoticeKind.directMessage,
      session: 1,
      title: '同事二号',
      body: '你那边听得到吗？',
    ),
    Notice(kind: NoticeKind.presence, session: 1, title: '新来的', body: '加入了服务器'),
  ];
}

/// A screen backend with no platform behind it.
///
/// The real one is `flutter_webrtc`, which has nothing to attach to under
/// `flutter_test`. The entry point needs *a* backend to drive; what is asserted
/// about is the commands it produces, not the picture.
class _FakeScreenBackend implements ScreenShareBackend {
  _FakeScreenBackend({this.available = const []});

  final media = _FakeMedia();
  final peers = <_FakePeer>[];

  /// What the picker is offered. Empty is the ordinary case for these tests —
  /// the platform runs its own dialog — and the wizard still has to work.
  final List<ScreenSource> available;

  @override
  Future<List<ScreenSource>> sources() async => available;

  /// The fake has no renderer to hand out, so a preview is a media that
  /// draws nothing — which is all the picker needs to be exercised.
  @override
  Future<ScreenMedia> preview(ScreenSource source) async => media;

  @override
  Future<ScreenMedia> capture(
    ScreenSource? source,
    ScreenOptions options,
  ) async => media;

  /// Hands back a peer the test can drive.
  ///
  /// The negotiation itself is covered in `screen_controller_test.dart`; what
  /// is being tested here is that a picture, once it exists, gets somewhere to
  /// be drawn.
  @override
  Future<ScreenPeer> peer({
    required void Function(Map<String, dynamic>) onCandidate,
    required void Function(ScreenMedia) onMedia,
    required void Function() onFailed,
    required ScreenOptions? options,
  }) async {
    final peer = _FakePeer(onCandidate, onMedia, onFailed);
    peers.add(peer);
    return peer;
  }
}

class _FakePeer implements ScreenPeer {
  _FakePeer(this.onCandidate, this.onMedia, this.onFailed);
  final void Function(Map<String, dynamic>) onCandidate;
  final void Function(ScreenMedia) onMedia;
  final void Function() onFailed;

  /// A second picture this peer can be told to produce — the remote one, as
  /// opposed to the local capture the backend hands out.
  final remote = _FakeMedia();

  final List<String> calls = [];
  int closes = 0;

  @override
  Future<String> offer(ScreenMedia media) async {
    calls.add('offer');
    return 'local-offer';
  }

  @override
  Future<String> answer(String sdp) async {
    calls.add('answer:$sdp');
    return 'local-answer';
  }

  @override
  Future<void> acceptAnswer(String sdp) async => calls.add('accepted:$sdp');

  @override
  Future<void> candidate(Map<String, dynamic> candidate) async =>
      calls.add('candidate');

  @override
  Future<void> close() async => closes++;

  /// What the encoder reports while this peer is publishing, or null.
  ScreenStats? reading;

  @override
  Future<ScreenStats?> stats() async => reading;
}

class _FakeMedia implements ScreenMedia {
  int closes = 0;
  void Function()? ended;

  /// What this capture produced. Off by default: the ordinary fake is a
  /// picture with no sound, which is what most of these tests want.
  @override
  bool hasAudio = false;

  @override
  set onEnded(void Function() callback) => ended = callback;

  @override
  Future<void> close() async => closes++;

  @override
  Widget view() => const SizedBox();
}

/// A server with everything the page can draw: a nested tree, a locked and an
/// empty channel, an offline section, someone talking, and messages mixing
/// scripts.
///
/// `screen` switches it to TS6 and lights the capability up, which is the only
/// way the sharing entry point draws at all — it is gated on the capability,
/// not on the protocol, so a TS3 view must stay without it.
ServerView _view({bool screen = false}) {
  final view = ServerView(session: 1);
  void send(ClientEvent event) => view.apply(event);

  send(
    ConnectedEvent(
      server: Server(
        id: 1,
        name: 'Nightcord 测试服',
        address: '192.168.31.128:9987',
        protocol: screen ? ProtocolKind.ts6 : ProtocolKind.ts3,
      ),
      info: const ServerInfo(name: 'Nightcord 测试服'),
    ),
  );
  if (screen) {
    // Decoded from the payload the core actually sends, not built by hand:
    // constructing `CapabilitiesChangedEvent` here would let the two sides
    // disagree about the name or the keys and still stay green. The Rust half
    // is pinned by `the_capability_flags_arrive_under_the_names_the_front_ends_read`
    // in `ts-events`.
    send(
      ClientEvent.fromJson(const {
        'event': 'capabilities_changed',
        'payload': {
          'text_chat': true,
          'private_chat': true,
          'voice': true,
          'whisper': true,
          'file_transfer': true,
          'screen_stream': true,
          'poke': true,
        },
      }),
    );
  }
  send(
    const ServerInfoChangedEvent(
      ServerInfo(name: 'Nightcord 测试服', clientsOnline: 4),
    ),
  );
  send(
    const PermissionsChangedEvent(
      Permissions(
        canJoinChannel: true,
        canSendChannelMessage: true,
        canSendPrivateMessage: true,
      ),
    ),
  );
  send(const OwnClientIdentifiedEvent(clientId: 1, channelId: 1));

  send(const ChannelCreatedEvent(Channel(id: 1, name: '大厅', isDefault: true)));
  send(const ChannelCreatedEvent(Channel(id: 2, name: '游戏区', parentId: 1)));
  send(
    const ChannelCreatedEvent(
      Channel(id: 3, name: 'CS2', parentId: 2, hasPassword: true),
    ),
  );
  send(const ChannelCreatedEvent(Channel(id: 4, name: '挂机', parentId: 1)));

  send(
    const ClientJoinedEvent(
      Client(id: 1, name: 'TsukinoAyaka', channelId: 1, isSelf: true),
    ),
  );
  send(
    ClientJoinedEvent(
      Client(
        id: 2,
        name: '同事二号',
        channelId: 1,
        // The flag the server keeps: it is what the watch button is built
        // from, so a client who is not marked as streaming must offer nothing.
        flags: screen
            ? const ClientFlags(streaming: true)
            : const ClientFlags(),
      ),
    ),
  );
  send(
    const ClientJoinedEvent(
      Client(
        id: 3,
        name: '远处的人',
        channelId: 1,
        flags: ClientFlags(away: true, inputMuted: true, outputMuted: true),
      ),
    ),
  );
  // Someone who leaves, so the offline section has a row in it.
  send(const ClientJoinedEvent(Client(id: 4, name: '走掉的人', channelId: 3)));
  send(const ClientLeftEvent(4));

  send(const SpeakingEvent(clientId: 2, speaking: true));

  final base = DateTime.now().millisecondsSinceEpoch;
  send(
    MessageReceivedEvent(
      Message(
        id: 1,
        sender: 2,
        senderName: '同事二号',
        target: const ChannelTarget(1),
        content: '今天的延迟怎么样？我这边一直在 40ms 上下。',
        timestamp: base - 600000,
      ),
    ),
  );
  send(
    MessageReceivedEvent(
      Message(
        id: 2,
        sender: 3,
        senderName: '远处的人',
        target: const ClientTarget(1),
        content: 'Mixed 中英 サーバー Server Settings 混排测试。',
        timestamp: base - 120000,
      ),
    ),
  );
  return view;
}

ProviderContainer _container({
  ServerView? view,
  bool notices = false,
  bool bookmarks = false,
  Settings settings = const Settings(),
  _SilentTransport? transport,
  ScreenShareBackend? screen,
}) => ProviderContainer.test(
  overrides: [
    // Page rendering must not wait for filesystem I/O under the fake clock.
    soundLibraryProvider.overrideWithValue(_RenderSoundLibrary()),
    clientTransportProvider.overrideWithValue(transport ?? _SilentTransport()),
    if (screen != null) screenBackendProvider.overrideWithValue(screen),
    activeSessionProvider.overrideWith(() => _FixedActive()),
    settingsProvider.overrideWith(() => _FixedSettings(settings)),
    audioDevicesProvider.overrideWith(() => _FixedDevices()),
    voiceStatusProvider.overrideWith(() => _FixedVoiceStatus()),
    if (view != null)
      sessionsProvider.overrideWith(() => _FixedSessions({1: view})),
    if (notices) noticesProvider.overrideWith(() => _FixedNotices()),
    if (bookmarks) bookmarksProvider.overrideWith(() => _FixedBookmarks()),
  ],
);

Widget _app(
  ProviderContainer container,
  Widget home, {
  AppPalette palette = AppPalette.nightcord,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: buildAppTheme(palette, const Locale('zh')),
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

/// Whether the menu item labelled `label` is selectable.
///
/// By type predicate rather than by type argument: the menu is built as
/// `PopupMenuItem<_MemberAction>`, and the action enum is private to the widget
/// library — which is the right place for it, so the test looks the item up by
/// the thing the user actually sees.
bool _menuItemEnabled(WidgetTester tester, String label) {
  final item = tester.widget(
    find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
    ),
  );
  return (item as PopupMenuItem<dynamic>).enabled;
}

/// The settings a share starts with, for the tests that only care that *some*
/// were given. The numbers are the default preset's, so a test that cares about
/// one of them overrides just that one.
ScreenOptions screenOptions() => const ScreenOptions(
  source: ScreenSourceKind.screen,
  height: 720,
  fps: 30,
  videoBitrateKbps: 2500,
  audio: false,
  audioBitrateKbps: 128,
  access: ScreenAccess.public,
  viewerLimit: 0,
  mode: ScreenMode.p2p,
  detail: false,
);

/// Answers the macOS system-picker probe with "no picker here".
///
/// That probe is a platform channel, and under `flutter test` on macOS nobody
/// answers it: the future it returns never completes, so the share button stops
/// before the wizard can open. Nothing fails in the app itself — the runner
/// registers the handler — but these tests drive the in-app wizard, so the
/// channel has to answer like every other platform does.
void _useInAppPicker(WidgetTester tester) {
  const channel = MethodChannel('nightcord/screen_picker');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    (call) async => call.method == 'available' ? false : null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    ),
  );
}

/// Walks the share wizard, which every start goes through: the bar button opens
/// it, and nothing is published until 开始直播.
Future<void> startThroughSetup(WidgetTester tester) async {
  _useInAppPicker(tester);
  await tester.tap(find.byTooltip('共享屏幕'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('下一个'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('开始直播'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'the bottom avatar opens viewing and editing actions on desktop and mobile',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final size in [const Size(1200, 800), const Size(320, 700)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          _app(
            _container(view: _view(screen: true)),
            const ServerPage(session: 1),
          ),
        );
        await tester.pumpAndSettle();
        final entry = find.byKey(const ValueKey('own-avatar-button'));
        expect(
          find.descendant(of: find.byType(VoiceBar), matching: entry),
          findsOneWidget,
        );
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.text('个人资料'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('profile-nickname-field')),
          findsOneWidget,
        );
        expect(find.text('上传头像'), findsOneWidget);
        expect(find.text('编辑头像'), findsOneWidget);
        expect(find.text('移除头像'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('own-profile-name')));
        await tester.pumpAndSettle();
        expect(find.text('个人资料'), findsOneWidget);
        expect(find.textContaining('所有服务器使用同一个头像'), findsNothing);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        // Avatar management no longer lives in the member context menu.
        final self = find.descendant(
          of: find.byType(ChannelSidebar),
          matching: find.text('TsukinoAyaka'),
        );
        await tester.longPress(self);
        await tester.pumpAndSettle();
        expect(find.text('上传头像'), findsNothing);
        expect(find.text('移除头像'), findsNothing);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('profile saves a nonblank name to the current session', (
    tester,
  ) async {
    final transport = _SilentTransport();
    await tester.pumpWidget(
      _app(
        _container(view: _view(), transport: transport),
        const ServerPage(session: 1),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('own-profile-name')));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('profile-nickname-field'));
    await tester.tap(field);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(
      transport.calls.where((call) => call.startsWith('nickname:')),
      isEmpty,
    );
    await tester.enterText(field, '   ');
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('profile-save-button')),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(field, ' New Name ');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('profile-save-button')));
    await tester.pumpAndSettle();
    expect(transport.calls, contains('nickname:1:New Name'));
    expect(find.text('个人资料'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  setUp(() {
    // A window rather than the test's default 800x600, so a page that only
    // overflows when it has room to lay out is not silently skipped.
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets(
    'touch PTT releases on cancellation and when the app loses focus',
    (tester) async {
      // A touch interface cannot rely on the desktop keyboard, and losing the
      // pointer or page focus must never leave the transmit gate held open.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final transport = _SilentTransport();
      final settings = const Settings().copyWith(
        audio: const AudioSettings().copyWith(
          mode: VoiceActivationMode.pushToTalk,
        ),
      );
      await tester.pumpWidget(
        _app(
          _container(view: _view(), transport: transport, settings: settings),
          const ServerPage(session: 1),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.text('按住说话');
      final gesture = await tester.startGesture(tester.getCenter(button));
      expect(transport.calls.last, 'ptt:true');
      await gesture.cancel();
      expect(transport.calls.last, 'ptt:false');
      final next = await tester.startGesture(tester.getCenter(button));
      expect(transport.calls.last, 'ptt:true');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(transport.calls.last, 'ptt:false');
      await next.up();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a narrow desktop window uses the mobile shell without overflow',
    (tester) async {
      // The old fixed sidebar left less than 100px for chat on a phone.
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = _container(view: _view());
      await tester.pumpWidget(_app(container, const ServerPage(session: 1)));
      await tester.pumpAndSettle();
      expect(find.byType(MobileShell), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.byType(Drawer), findsNothing);
      expect(find.byType(ChannelSidebar), findsOneWidget);
      expect(find.byType(ChatPanel), findsNothing);
      await tester.tap(find.text('大厅').first);
      await tester.pumpAndSettle();
      expect(find.byType(ChatPanel), findsOneWidget);
      expect(find.byType(ChannelSidebar), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(ChannelSidebar), findsOneWidget);
      await tester.tap(find.text('同事二号').first);
      await tester.pumpAndSettle();
      expect(find.byType(ChatPanel), findsOneWidget);
      expect(
        container.read(sessionsProvider)[1]!.shownConversation,
        ConversationKey.client(2),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ChannelSidebar), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pumpAndSettle();
      expect(find.byType(DesktopShell), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile settings navigation keeps the audio form usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(_container(view: _view()), const SettingsPage(session: 1)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MobileShell), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.byType(Drawer), findsNothing);
    expect(find.byType(AudioSection), findsNothing);
    await tester.tap(find.text('通知'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsSection), findsOneWidget);
    expect(find.text('音频'), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsSection), findsNothing);
    await tester.tap(find.text('音频'));
    await tester.pumpAndSettle();
    expect(find.byType(AudioSection), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the connect page', (tester) async {
    await tester.pumpWidget(_app(_container(), const ConnectPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a connected server', (tester) async {
    await tester.pumpWidget(
      _app(_container(view: _view()), const ServerPage(session: 1)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('About opens before the core returns settings', (tester) async {
    await tester.pumpWidget(_app(_container(), const SettingsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    expect(find.text('Nightcord Speak'), findsOneWidget);
    expect(find.text('MIT OR Apache-2.0'), findsOneWidget);
    expect(find.text('查看组件许可证'), findsOneWidget);
    expect(find.text('正在加载设置…'), findsNothing);
    // Asset IO must complete outside the widget test's simulated clock.
    await tester.runAsync(loadBundledLicenses);
    await tester.ensureVisible(find.text('查看组件许可证'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('查看组件许可证'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a short channel name keeps its topic close in the desktop header',
    (tester) async {
      final view = _view();
      view.channels[1] = const Channel(
        id: 1,
        name: 'Default Channel',
        topic: 'Channel topic',
      );
      await tester.pumpWidget(
        _app(_container(view: view), const ServerPage(session: 1)),
      );
      await tester.pumpAndSettle();
      // Regression: Expanded reserved half the header for even a short name.
      final name = tester.getRect(
        find.descendant(
          of: find.byType(ChatPanel),
          matching: find.text('Default Channel'),
        ),
      );
      final topic = tester.getRect(find.text('Channel topic'));
      expect(topic.left - name.right, lessThan(40));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('online count stays at the right edge with or without a topic', (
    tester,
  ) async {
    final view = _view();
    for (final topic in [null, 'Channel topic']) {
      view.channels[1] = Channel(id: 1, name: 'Lobby', topic: topic);
      await tester.pumpWidget(
        _app(_container(view: view), const ServerPage(session: 1)),
      );
      await tester.pumpAndSettle();
      final panel = tester.getRect(find.byType(ChatPanel));
      final count = tester.getRect(find.text('4 人在线'));
      // Regression: a loose title left the count in the middle without a topic.
      expect(panel.right - count.right, closeTo(20, 1));
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('the settings page', (tester) async {
    // Built as the home route rather than pushed: the page is whole without a
    // Navigator behind it, which is also what the other pages' tests do.
    await tester.pumpWidget(
      _app(_container(view: _view()), const SettingsPage(session: 1)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the navigation column switches sections', (tester) async {
    // The point of the left-right layout: six sections that used to be one
    // scroller are now one at a time, and the navigation is what chooses.
    await tester.pumpWidget(
      _app(_container(view: _view()), const SettingsPage(session: 1)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('麦克风增益'),
      findsOneWidget,
      reason: 'audio is the section it opens on',
    );

    // The label, not the widget: the user picks a section by the word on it.
    await tester.tap(find.text('通知'));
    await tester.pumpAndSettle();

    expect(find.text('成员加入或离开'), findsOneWidget);
    expect(
      find.text('麦克风增益'),
      findsNothing,
      reason: 'the audio section is gone, not scrolled away',
    );

    await tester.tap(find.text('日志'));
    await tester.pumpAndSettle();
    expect(find.text('打开日志文件夹'), findsOneWidget);
  });

  testWidgets('notices over the server', (tester) async {
    await tester.pumpWidget(
      _app(
        _container(view: _view(), notices: true),
        const Stack(
          fit: StackFit.expand,
          children: [ServerPage(session: 1), NoticeStack()],
        ),
      ),
    );
    // `pump`, not `pumpAndSettle`: a notice dismisses itself on a four-second
    // timer, so settling would wait for every one of them to go.
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the voice bar asks before disconnecting', (tester) async {
    // The button ends the session *and* forgets it, so the channel tree and
    // the conversation go with it — which is why it asks. This checks the
    // asking: the tap alone must change nothing.
    final transport = _SilentTransport();
    final container = _container(view: _view(), transport: transport);

    await tester.pumpWidget(_app(container, const ServerPage(session: 1)));
    await tester.pumpAndSettle();

    // By icon rather than by tooltip: the tooltip is translated, the glyph is
    // not.
    expect(find.byIcon(Icons.logout), findsOneWidget);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(transport.calls, isEmpty, reason: 'it disconnected without asking');
    expect(container.read(sessionsProvider), contains(1));

    // Backing out leaves everything where it was.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(transport.calls, isEmpty);
    expect(container.read(sessionsProvider), contains(1));
  });

  testWidgets('confirming the dialog disconnects the session', (tester) async {
    final transport = _SilentTransport();
    final container = _container(view: _view(), transport: transport);

    await tester.pumpWidget(_app(container, const ServerPage(session: 1)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(transport.calls, contains('disconnect:1'));
    expect(container.read(sessionsProvider), isEmpty);
  });

  testWidgets('the away button goes away without a word', (tester) async {
    // A stored message does not change what the button does: it is the silent
    // way out, and the reason only goes out when someone types one into the
    // dialog. Sending the stored one here would put words in the user's mouth
    // every evening.
    final transport = _SilentTransport();
    final container = _container(
      view: _view(),
      settings: const Settings(presence: PresenceSettings(awayMessage: '在开会')),
      transport: transport,
    );

    await tester.pumpWidget(_app(container, const ServerPage(session: 1)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.snooze_outlined));
    await tester.pumpAndSettle();

    expect(transport.calls, contains('away:yes:'));
  });

  testWidgets('an away client shows the filled glyph and comes back on a tap', (
    tester,
  ) async {
    final transport = _SilentTransport();
    final view = _view();
    // Ourselves, away: the same event path a `notifyclientupdated` takes.
    view.apply(
      const ClientUpdatedEvent(
        Client(
          id: 1,
          name: 'TsukinoAyaka',
          channelId: 1,
          isSelf: true,
          flags: ClientFlags(away: true),
          awayMessage: '在开会',
        ),
      ),
    );
    final container = _container(
      view: view,
      settings: const Settings(presence: PresenceSettings(awayMessage: '在开会')),
      transport: transport,
    );

    await tester.pumpWidget(_app(container, const ServerPage(session: 1)));
    await tester.pumpAndSettle();

    // Scoped to the bar: the member list draws the same glyph for the away
    // client it is already showing, and an unqualified finder matches both.
    final bar = find.byType(VoiceBar);
    final filled = find.descendant(
      of: bar,
      matching: find.byIcon(Icons.snooze),
    );
    expect(
      filled,
      findsOneWidget,
      reason: 'away should not look the same as here',
    );
    expect(
      find.descendant(of: bar, matching: find.byIcon(Icons.snooze_outlined)),
      findsNothing,
    );

    await tester.tap(filled);
    await tester.pumpAndSettle();

    expect(transport.calls, contains('away:no:'));
  });

  testWidgets(
    'right-clicking the away button asks for a message and remembers it',
    (tester) async {
      // The one gesture that is not discoverable by looking, so it gets a test:
      // what it must do is prefill the remembered message, go away saying the new
      // one, and write it down.
      final transport = _SilentTransport();
      final container = _container(
        view: _view(),
        settings: const Settings(
          presence: PresenceSettings(awayMessage: '在开会'),
        ),
        transport: transport,
      );

      await tester.pumpWidget(_app(container, const ServerPage(session: 1)));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byIcon(Icons.snooze_outlined),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      // Scoped to the dialog: the page behind it has text fields of its own
      // (the chat composer), and an unqualified finder matches those too.
      final field = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      expect(
        tester.widget<TextField>(field).controller?.text,
        '在开会',
        reason: 'the field should start from the remembered message',
      );

      await tester.enterText(field, '午饭时间');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();

      expect(transport.calls, contains('away:yes:午饭时间'));
      expect(container.read(settingsProvider)?.presence.awayMessage, '午饭时间');
    },
  );

  testWidgets('the away button does nothing without a session', (tester) async {
    // Same rule as the mute buttons: a control with nothing behind it must not
    // queue a command the core would refuse, and the tap must not look like it
    // worked.
    final transport = _SilentTransport();
    final container = _container(
      view: ServerView(session: 1),
      transport: transport,
    );

    await tester.pumpWidget(_app(container, const ServerPage(session: 1)));
    await tester.pumpAndSettle();

    // Asserted on the button, not just on the calls: the store refuses the
    // command either way, so an enabled button that silently did nothing would
    // pass a calls-only check while looking perfectly clickable.
    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.snooze_outlined),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.byIcon(Icons.snooze_outlined), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(transport.calls, isEmpty);
  });

  testWidgets('a long press opens the same dialog, for fingers', (
    tester,
  ) async {
    // The same door as the right-click, because a touch screen has no second
    // button — and because an `IconButton` inside a `GestureDetector` is
    // exactly the case where a gesture can be swallowed by the wrong
    // recogniser without anyone noticing.
    final container = _container(view: _view());

    await tester.pumpWidget(_app(container, const ServerPage(session: 1)));
    await tester.pumpAndSettle();

    await tester.longPress(find.byIcon(Icons.snooze_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets(
    'resting on the microphone shows the gain, and moving away hides it',
    (tester) async {
      // The first hover test in this file, and the reason the flyout is worth
      // one: an `OverlayPortal` panel is invisible to every other kind of test —
      // it is not in the page's subtree, and only a pointer that really moves
      // will open it.
      final container = _container(view: _view());

      await tester.pumpWidget(_app(container, const ServerPage(session: 1)));
      await tester.pumpAndSettle();

      // The panel holds a reading and a slider and no words of its own — the
      // button above it is what says what it adjusts — so the reading is what
      // this looks for.
      expect(find.text('0 dB'), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await mouse.moveTo(tester.getCenter(find.byIcon(Icons.mic)));
      await tester.pumpAndSettle();

      expect(
        find.text('0 dB'),
        findsOneWidget,
        reason: 'unity until it is moved',
      );

      // Leaving closes it — after the grace period that lets the pointer cross
      // from the button into the panel.
      await mouse.moveTo(const Offset(60, 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('0 dB'), findsNothing);
    },
  );

  testWidgets('dragging the flyout writes the gain the settings keep', (
    tester,
  ) async {
    final transport = _SilentTransport();
    final container = _container(view: _view(), transport: transport);

    await tester.pumpWidget(_app(container, const ServerPage(session: 1)));
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byIcon(Icons.mic)));
    await tester.pumpAndSettle();

    // The panel's slider, not the page's: there is only one on screen here,
    // because the settings page is closed.
    //
    // Downwards, because it is drawn vertically — and a `Slider` follows the
    // pointer rather than accumulating the drag, so what matters is where the
    // drag *ends*: the middle of the panel is a long way above the silent
    // floor, which is where the bottom of the travel is.
    await tester.drag(find.byType(Slider), const Offset(0, 16));
    await tester.pumpAndSettle();

    final written = container.read(settingsProvider)!.audio.inputGainDb;
    expect(written, lessThan(0.0), reason: 'dragging down should attenuate');
    expect(
      written,
      greaterThan(gainMinAudibleDb),
      reason: 'and not jump to silence',
    );

    // All the way down really is silence — the reason the curve spends its
    // travel on the audible range instead of on the whole decibel range.
    await tester.drag(find.byType(Slider), const Offset(0, 200));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider)!.audio.inputGainDb, gainSilenceDb);

    // What the core is told is the same value the UI now shows.
    expect(
      transport.calls.where((call) => call.startsWith('updateSettings')),
      isNotEmpty,
    );
  });

  testWidgets('the settings page carries the same slider', (tester) async {
    // Two controls, one value: the settings page's slider has to be the
    // microphone gain's, and it has to write decibels — a copy that wrote a
    // fraction would look right and set the gain to nothing.
    final container = _container(
      view: _view(),
      settings: const Settings(audio: AudioSettings(inputGainDb: 6.0)),
    );

    await tester.pumpWidget(_app(container, const ServerPage(session: 1)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.text('麦克风增益'), findsOneWidget);
    expect(
      find.text('+6 dB'),
      findsOneWidget,
      reason: 'the stored value is what is drawn',
    );

    final slider = find.descendant(
      of: find
          .ancestor(of: find.text('麦克风增益'), matching: find.byType(Column))
          .first,
      matching: find.byType(Slider),
    );
    // The dialog scrolls, and in the test's window this one starts below the
    // fold — a drag at its centre would land on whatever is drawn there.
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();

    await tester.drag(slider, const Offset(-50, 0));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider)!.audio.inputGainDb, lessThan(6.0));
    // The playback volume next door is untouched by any of this.
    expect(container.read(settingsProvider)!.audio.outputVolume, 1.0);
  });

  testWidgets('an away client shows the message others set', (tester) async {
    // The message is the point of the state: a badge alone says someone is
    // quiet, not when they will be back.
    final view = _view();
    view.apply(
      const ClientUpdatedEvent(
        Client(
          id: 3,
          name: '远处的人',
          channelId: 1,
          flags: ClientFlags(away: true),
          awayMessage: '吃饭去了',
        ),
      ),
    );
    final container = _container(view: view);

    await tester.pumpWidget(_app(container, const ServerPage(session: 1)));
    await tester.pumpAndSettle();

    // The message rides on the name as a second span, so the whole line is what
    // `find.text` sees. Asserting the exact string is the point: an away client
    // whose message is only in a tooltip is a client where nobody reads it.
    expect(find.text('远处的人 (吃饭去了)'), findsOneWidget);
  });

  testWidgets('the name in the voice bar is lifted off its own line box', (
    tester,
  ) async {
    // Regression, and the third attempt at it. Reported twice as "the name is
    // not centred" after two changes to its line height — neither of which was
    // the cause.
    //
    // A line box is centred on the font's ascent and descent together, and Noto
    // Sans is nearly four times as much ascent as descent; most of that ascent
    // is empty space above the capitals. So the *box* is centred and the
    // glyphs inside it are not. Measured on screen, the name's ink sat 4.5
    // physical pixels below the middle of the bar while the icon next to it was
    // on it.
    //
    // What fixes it is a bottom-padded box — the row centres the padding, so
    // the text ends up above the middle. That is what this checks, because it
    // is the part a widget test can see: the test font has no real glyph
    // metrics, so the size of the lift can only be measured on screen.
    await tester.pumpWidget(
      _app(_container(view: _view()), const ServerPage(session: 1)),
    );
    await tester.pumpAndSettle();

    // Scoped to the bar: the member list shows the same name.
    final name = tester.getRect(
      find.descendant(
        of: find.byType(VoiceBar),
        matching: find.text('TsukinoAyaka'),
      ),
    );
    final bar = tester.getRect(find.byType(VoiceBar));
    expect(
      name.center.dy,
      lessThan(bar.center.dy),
      reason: 'the name is sitting on its line box, which draws it low',
    );
  });

  testWidgets('a saved server fills the form on one click, connects on two', (
    tester,
  ) async {
    // The connect page's row has both gestures: one click fills the form, so
    // the details can still be changed; two connect straight away, for someone
    // who already knows which server they want.
    final transport = _SilentTransport();
    final container = _container(bookmarks: true, transport: transport);

    await tester.pumpWidget(_app(container, const ConnectPage()));
    await tester.pumpAndSettle();

    final row = find.text('局域网测试服');
    expect(row, findsOneWidget);

    // One click: the form fills, nothing is dialled.
    //
    // **A single `pump`, with no timeout waited out.** This used to need a
    // 400 ms pump because `GestureDetector.onDoubleTap` made Flutter hold every
    // single tap back until it knew a second one was not coming. The row now
    // times the clicks itself, so the form fills on the frame of the click —
    // and that immediacy is what this asserts.
    await tester.tap(row);
    await tester.pump();
    expect(transport.calls, isEmpty, reason: 'a single click connected');
    final address = tester.widget<TextField>(find.byType(TextField).first);
    expect(address.controller?.text, '192.168.31.128:9987');

    // Two clicks: it connects, without waiting for the button.
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(row);
    // `pump`, not `pumpAndSettle`: connecting turns the button into a
    // `CircularProgressIndicator`, which schedules frames for as long as it is
    // on screen. Waiting for the tree to go quiet would wait forever.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(transport.calls, contains('connect:192.168.31.128:9987'));
  });

  testWidgets('two clicks far apart are two single clicks', (tester) async {
    // The other half of the hand-rolled double click: a click that arrives
    // after the window must fill the form again rather than dial. Getting this
    // backwards would connect on any two clicks on the same row, however far
    // apart — including a click, a minute of typing, and another click.
    final transport = _SilentTransport();
    await tester.pumpWidget(
      _app(
        _container(bookmarks: true, transport: transport),
        const ConnectPage(),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.text('局域网测试服');
    await tester.tap(row);
    await tester.pump();
    // Long enough for the row's window to close. Without this the two clicks
    // below would be a double click, which is the case the other test covers.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(row);
    await tester.pump();

    expect(
      transport.calls,
      isEmpty,
      reason: 'a click 500 ms after the last one is not a double click',
    );
  });

  testWidgets('the error bar centres its buttons on the bar', (tester) async {
    // Regression: the close button sat high, because Material's `SnackBar` lays
    // `action` out beside the content rather than in it — so the row's own
    // alignment never applied to everything the bar draws.
    final container = _container();
    await tester.pumpWidget(_app(container, const AppShell()));
    await tester.pumpAndSettle();

    container
        .read(lastErrorProvider.notifier)
        .report(const ClientError(kind: 'timeout'));
    await tester.pumpAndSettle();

    // The `SnackBar` widget itself is stretched over the Scaffold's whole
    // bottom slot, so its rect is not the bar anyone sees. The content row is:
    // the bar's padding is zero and the row fills it.
    final content = tester.getRect(
      find
          .descendant(of: find.byType(SnackBar), matching: find.byType(Row))
          .first,
    );

    // Both buttons and the close glyph, against the bar's own centre line.
    for (final glyph in [find.byIcon(Icons.close), find.text('打开日志')]) {
      expect(
        tester.getRect(glyph).center.dy,
        closeTo(content.center.dy, 1.0),
        reason: 'not on the bar centre line',
      );
    }
  });

  testWidgets('the permissions panel claims only what the server answered', (
    tester,
  ) async {
    // Regression: every bit reads as allowed when the server sends no permission
    // hints — which is right for deciding whether to grey out a button and wrong
    // for telling the user what they may do. On a server that reports nothing,
    // this panel used to list six rights the user did not have.
    final view = _view();
    view.apply(
      const PermissionsChangedEvent(
        // The fixture's own permissions: granted, but nobody confirmed them.
        Permissions(
          canJoinChannel: true,
          canSendChannelMessage: true,
          canSendPrivateMessage: true,
        ),
      ),
    );

    await tester.pumpWidget(
      _app(_container(view: view), const ServerPage(session: 1)),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(ChannelSidebar),
        matching: find.text('Nightcord 测试服'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的权限'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('不会向客户端提供权限信息'),
      findsOneWidget,
      reason: 'the server said nothing, so the panel says so',
    );
    for (final label in ['加入频道', '发频道消息', '发私聊消息', '移出成员', '封禁']) {
      expect(
        find.text(label),
        findsNothing,
        reason: '(label) was never confirmed',
      );
    }
  });

  testWidgets('the permissions panel lists the granted and known ones', (
    tester,
  ) async {
    final view = _view();
    view.apply(
      const PermissionsChangedEvent(
        Permissions(
          canJoinChannel: true,
          canSendChannelMessage: true,
          canKick: true,
          channelKnown: true,
          clientKnown: true,
        ),
      ),
    );

    await tester.pumpWidget(
      _app(_container(view: view), const ServerPage(session: 1)),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(ChannelSidebar),
        matching: find.text('Nightcord 测试服'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的权限'));
    await tester.pumpAndSettle();

    expect(find.text('加入频道'), findsOneWidget);
    expect(find.text('移出成员'), findsOneWidget);
    // Granted by silence, not by the server.
    expect(find.text('封禁'), findsNothing);
    expect(
      find.text('移动他人'),
      findsNothing,
      reason: 'client answers are known, and this one was not granted',
    );
  });

  testWidgets('the connected server can be bookmarked', (tester) async {
    // The server in front of the user is the one they are most likely to want
    // back, and the sheet is where server-level actions live. With no address
    // book at all, the sheet offers to start one.
    final transport = _SilentTransport();
    final container = _container(view: _view(), transport: transport);

    await tester.pumpWidget(_app(container, const ServerPage(session: 1)));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(ChannelSidebar),
        matching: find.text('Nightcord 测试服'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏服务器'));
    await tester.pumpAndSettle();

    // Through `addBookmark`, not `updateBookmarks`: the core owns the address
    // parser, so an entry saved here is spelt the same way as one saved on the
    // connect screen.
    expect(transport.calls, contains('addBookmark:192.168.31.128:9987'));
  });

  testWidgets('a server already saved offers to be unsaved instead', (
    tester,
  ) async {
    // The same row, decided by whether the address is in the book — the entry
    // is the address, so that is what the match is on.
    //
    // The fixture's address book already holds 192.168.31.128:9987, which is
    // the server the fixture is connected to.
    final transport = _SilentTransport();
    final container = _container(
      view: _view(),
      bookmarks: true,
      transport: transport,
    );

    await tester.pumpWidget(_app(container, const ServerPage(session: 1)));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(ChannelSidebar),
        matching: find.text('Nightcord 测试服'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('收藏服务器'), findsNothing);
    await tester.tap(find.text('取消收藏'));
    await tester.pumpAndSettle();

    expect(transport.calls, contains('updateBookmarks:0'));
  });

  testWidgets('add server reaches the connect screen with a session running', (
    tester,
  ) async {
    // Regression, and it was invisible from the outside: "add server" cleared
    // the selection and left the connection alone, exactly as intended — and
    // then the shell's own fallback put the session straight back, so the
    // button did nothing at all.
    final transport = _SilentTransport();
    final view = _view();
    final container = _container(view: view, transport: transport);
    final subscription = container.listen(sessionsProvider, (_, _) {});
    addTearDown(subscription.close);

    container.read(activeSessionProvider.notifier).select(view.session);

    await tester.pumpWidget(_app(container, const AppShell()));
    await tester.pumpAndSettle();
    expect(find.byType(ServerPage), findsOneWidget);

    // Open the switcher from the server header: its title is the sheet's handle.
    await tester.tap(
      find.descendant(
        of: find.byType(ChannelSidebar),
        matching: find.text('Nightcord 测试服'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加服务器'));
    await tester.pumpAndSettle();

    expect(find.byType(ConnectPage), findsOneWidget);
    expect(
      container.read(sessionsProvider),
      contains(view.session),
      reason: 'the connection keeps running in the background',
    );
  });

  testWidgets('a private conversation opens on a double click', (tester) async {
    // One click must not: opening a conversation is visible to the other
    // person, and it is the same gesture a channel row uses.
    await tester.pumpWidget(
      _app(_container(view: _view()), const ServerPage(session: 1)),
    );
    await tester.pumpAndSettle();

    final row = find.descendant(
      of: find.byType(ChannelSidebar),
      matching: find.text('同事二号'),
    );

    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      find.byIcon(Icons.arrow_back),
      findsNothing,
      reason: 'one click is not an intent to open anything',
    );

    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
  });

  testWidgets('settings open without a connection', (tester) async {
    // Regression: this used to require a session, and the only button that
    // opened it lived in the voice bar — which only exists on the server page.
    // So a user who could not connect had no way to reach the log folder, the
    // language, or their audio devices, which is exactly when they are looking
    // for them.
    await tester.pumpWidget(_app(_container(), const ConnectPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the settings page closes with its back button', (tester) async {
    // It is a pushed route now, so the way back is the page's own business —
    // and the connect page has no other route out of it.
    await tester.pumpWidget(_app(_container(), const ConnectPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsNothing);
    expect(find.byType(ConnectPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the member menu offers only what the server allows', (
    tester,
  ) async {
    // The fixture's permissions grant joining and messaging and nothing else,
    // which is what an ordinary user on a server looks like. Moderation items
    // must be present but dead, not missing: a missing item reads as "this
    // client cannot do that" rather than "you may not".
    await tester.pumpWidget(
      _app(_container(view: _view()), const ServerPage(session: 1)),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getCenter(
        find.descendant(
          of: find.byType(ChannelSidebar),
          matching: find.text('同事二号'),
        ),
      ),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('戳一戳'), findsOneWidget);
    expect(find.text('封禁…'), findsOneWidget);

    for (final label in ['移出频道', '移出服务器', '移动到频道…', '封禁…']) {
      expect(
        _menuItemEnabled(tester, label),
        isFalse,
        reason: '(label) should be greyed out',
      );
    }
  });

  testWidgets('a permitted kick sends the scope that was chosen', (
    tester,
  ) async {
    // The two kick items differ only by the scope they carry, so a menu that
    // wired both to the same value would look right and behave wrongly.
    final transport = _SilentTransport();
    final view = _view();
    view.apply(
      const PermissionsChangedEvent(
        Permissions(
          canJoinChannel: true,
          canSendChannelMessage: true,
          canSendPrivateMessage: true,
          canKick: true,
        ),
      ),
    );

    await tester.pumpWidget(
      _app(
        _container(view: view, transport: transport),
        const ServerPage(session: 1),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getCenter(
        find.descendant(
          of: find.byType(ChannelSidebar),
          matching: find.text('同事二号'),
        ),
      ),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('移出服务器'));
    await tester.pumpAndSettle();

    // The dialog collects a reason; confirming with it empty is still a kick.
    await tester.tap(find.widgetWithText(FilledButton, '移出服务器'));
    await tester.pumpAndSettle();

    expect(transport.calls, contains('kick:server:2:'));
  });

  testWidgets('the menu offers nothing to do to yourself', (tester) async {
    // Kicking yourself is not a moderation action, it is a way to lose a
    // connection by accident.
    await tester.pumpWidget(
      _app(_container(view: _view()), const ServerPage(session: 1)),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getCenter(
        find.descendant(
          of: find.byType(ChannelSidebar),
          matching: find.text('TsukinoAyaka'),
        ),
      ),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    for (final label in [
      '戳一戳',
      '移出频道',
      '封禁…',
      // Our own audio is already at whatever the output volume says; a second
      // control for it would be a way to make the same thing quiet twice.
      '调整音量…',
    ]) {
      expect(
        _menuItemEnabled(tester, label),
        isFalse,
        reason: '(label) should not apply to ourselves',
      );
    }
  });

  testWidgets('the brand mark is on the screens that carry it', (tester) async {
    // One on the connect page's title row, one in the server header. What this
    // guards is the wiring — that the mark is drawn rather than the old
    // `Icons.bubble_chart` having been left behind somewhere.
    await tester.pumpWidget(_app(_container(), const ConnectPage()));
    await tester.pumpAndSettle();
    expect(find.byType(AppLogo), findsOneWidget);
    expect(find.byIcon(Icons.bubble_chart), findsNothing);

    await tester.pumpWidget(
      _app(_container(view: _view()), const ServerPage(session: 1)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppLogo), findsOneWidget);
    expect(find.byIcon(Icons.bubble_chart), findsNothing);
  });

  testWidgets('the mark draws at every size it is put at', (tester) async {
    // Including 16, where the two eyes are barely a pixel across. How it
    // *looks* at each size is not asserted here — the painter is geometry, and
    // judging it means looking at it, which is what `scripts/make-app-icon.py`
    // exists to make possible.
    for (final size in [16.0, 24.0, 32.0, 256.0]) {
      await tester.pumpWidget(
        _app(_container(), Center(child: AppLogo(size: size))),
      );
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'failed to draw at ${size}px',
      );
    }
  });

  testWidgets('a session that has been forgotten', (tester) async {
    // The empty branch of `ServerPage` — reached when the user disconnects and
    // the view is dropped, which is the one state no other test draws.
    await tester.pumpWidget(_app(_container(), const ServerPage(session: 99)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sharing entry follows the capability, not the server', (
    tester,
  ) async {
    // TS3 has no stream command family, so the control must not be there at
    // all: a button that can never work is a promise the server never made.
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        _container(view: _view(), screen: _FakeScreenBackend()),
        const ServerPage(session: 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('共享屏幕'), findsNothing);

    await tester.pumpWidget(
      _app(
        _container(view: _view(screen: true), screen: _FakeScreenBackend()),
        const ServerPage(session: 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('共享屏幕'), findsOneWidget);
    // It lives in the voice bar — beside the away button and the microphone,
    // not in a band of its own above the conversation.
    expect(
      find.descendant(
        of: find.byType(VoiceBar),
        matching: find.byTooltip('共享屏幕'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sharing runs from the bar to the server and back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final transport = _SilentTransport();
    final backend = _FakeScreenBackend();
    await tester.pumpWidget(
      _app(
        _container(
          view: _view(screen: true),
          transport: transport,
          screen: backend,
        ),
        const ServerPage(session: 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('全屏'), findsNothing);

    await startThroughSetup(tester);
    expect(transport.calls.last, 'screen:start:');
    // Our own picture is local, so the window opens before the server has
    // answered — only the stream id has to come back.
    expect(find.byTooltip('全屏'), findsOneWidget);
    expect(find.text('观看人数 0'), findsNothing);

    transport.emit(
      const DomainEvent(
        session: 1,
        event: ScreenEvent({
          'type': 'available',
          'stream_id': 's',
          'client_id': 1,
          'name': '屏幕共享',
        }),
      ),
    );
    await tester.pumpAndSettle();
    // No limit was chosen, so the count stands alone — "/0" would read as
    // "nobody may watch", which is the opposite of what zero means here.
    expect(find.text('观看人数 0'), findsOneWidget);
    expect(find.textContaining('观看人数 0/'), findsNothing);

    // The same button turns into the way out — the stream id only exists now,
    // so a stop sent before the answer would name a stream that never was.
    await tester.tap(find.byIcon(Icons.stop_screen_share));
    await tester.pumpAndSettle();
    expect(transport.calls.last, 'screen:stop:s');
    expect(backend.media.closes, 1);
    expect(find.byTooltip('共享屏幕'), findsOneWidget);
    expect(find.byTooltip('全屏'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a share is entered from the row of the person doing it', (
    tester,
  ) async {
    // The badge is built from the server's streaming flag rather than from a
    // local guess: a member who is not marked as sharing must offer nothing.
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final transport = _SilentTransport();
    final backend = _FakeScreenBackend();
    await tester.pumpWidget(
      _app(
        _container(
          view: _view(screen: true),
          transport: transport,
          screen: backend,
        ),
        const ServerPage(session: 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('观看 · 同事二号'), findsOneWidget);
    expect(find.byTooltip('观看 · 远处的人'), findsNothing);

    await tester.tap(find.byTooltip('观看 · 同事二号'));
    // The row opens a private chat on a double click, so its single taps wait
    // out the double-tap window before they land — the same ~300ms the connect
    // page pays for the same reason (AGENTS.md §7).
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(transport.calls.last, 'screen:discover:2');
    // The same badge turns into the way out, from the press rather than from
    // the server's answer.
    expect(find.byTooltip('停止观看 · 同事二号'), findsOneWidget);

    // The server names the stream, we ask to join, the publisher accepts —
    // and only after that does a picture exist to draw.
    transport.emit(
      const DomainEvent(
        session: 1,
        event: ScreenEvent({
          'type': 'available',
          'stream_id': 's',
          'client_id': 2,
          'name': '同事二号的屏幕',
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(transport.calls.last, 'screen:join:2');

    transport.emit(
      const DomainEvent(
        session: 1,
        event: ScreenEvent({
          'type': 'join_answered',
          'stream_id': 's',
          'client_id': 2,
          'accepted': true,
          'sdp': 'offer',
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(backend.peers.single.calls, ['answer:offer']);
    expect(find.byTooltip('全屏'), findsNothing);

    backend.peers.single.onMedia(backend.peers.single.remote);
    await tester.pumpAndSettle();
    expect(find.byTooltip('全屏'), findsOneWidget);
    // Whose it is, rather than what the publisher typed: two streams on one
    // server can carry the same name.
    expect(find.byTooltip('停止观看'), findsOneWidget);

    // Closing the window is the only way to stop watching, so it has to end
    // the connection rather than just stop drawing it.
    await tester.tap(find.byTooltip('停止观看'));
    await tester.pumpAndSettle();
    expect(transport.calls.last, 'screen:leave:2');
    expect(backend.peers.single.closes, 1);
    expect(find.byTooltip('全屏'), findsNothing);
    expect(find.byTooltip('观看 · 同事二号'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the window follows the pointer, and only while it is grabbed', (
    tester,
  ) async {
    // Two things went wrong here at once and both look like "it will not drag":
    // the strip only answered where its children happened to be, and the
    // position was rebuilt from a value captured before the previous move.
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _FakeScreenBackend();
    await tester.pumpWidget(
      _app(
        _container(view: _view(screen: true), screen: backend),
        const ServerPage(session: 1),
      ),
    );
    await tester.pumpAndSettle();
    await startThroughSetup(tester);
    expect(find.byType(ScreenPip), findsOneWidget);

    final window = find
        .descendant(of: find.byType(ScreenPip), matching: find.byType(Material))
        .first;
    final before = tester.getTopLeft(window);

    // A press on the strip's own padding — the place with no child under it —
    // and a mouse, because that is what a desktop user has. The first version
    // of this test drove a touch and passed while the app did not.
    final strip = find.descendant(
      of: find.byType(ScreenPip),
      matching: find.byWidgetPredicate(
        (w) => w is Listener && w.onPointerMove != null,
      ),
    );
    final start = tester.getTopLeft(strip) + const Offset(6, 4);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: start);
    addTearDown(mouse.removePointer);
    await mouse.down(start);
    await mouse.moveTo(start + const Offset(-120, -90));
    await tester.pump();
    final moved = tester.getTopLeft(window);
    // One movement of the pointer, one movement of the window — not half of
    // it, and not none of it.
    expect(moved.dx, closeTo(before.dx - 120, 1));
    expect(moved.dy, closeTo(before.dy - 90, 1));

    await mouse.moveTo(start + const Offset(-160, -90));
    await tester.pump();
    expect(tester.getTopLeft(window).dx, closeTo(moved.dx - 40, 1));
    await mouse.up();
    await tester.pumpAndSettle();

    // The window stays where it was put.
    expect(tester.getTopLeft(window).dx, closeTo(moved.dx - 40, 1));

    // Stopping takes it away, and takes the start timeout with it.
    await tester.tap(find.byIcon(Icons.stop_screen_share));
    await tester.pumpAndSettle();
    expect(find.byType(ScreenPip), findsOneWidget);
    expect(find.byTooltip('全屏'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a window with no room to be kept in still moves', (
    tester,
  ) async {
    // The area can be smaller than the window — a narrow pane, or a layout
    // pass that has not produced a real size yet. Clamping against "no room"
    // pins the window at zero, which is indistinguishable from a broken drag:
    // an area with nothing to hold it in is not an instruction to stand still.
    final container = _container(
      view: _view(screen: true),
      screen: _FakeScreenBackend(),
    );
    final controller = container.read(screenControllerProvider(1));
    await controller.start(null, 'Share', screenOptions());
    const area = Size(200, 150);

    await tester.pumpWidget(
      _app(
        container,
        Center(
          child: SizedBox(
            width: area.width,
            height: area.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black),
                ScreenPip(
                  view: container.read(sessionsProvider)[1]!,
                  bounds: area,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('全屏'), findsOneWidget);

    final window = find
        .descendant(of: find.byType(ScreenPip), matching: find.byType(Material))
        .first;
    final before = tester.getTopLeft(window);
    final strip = find.descendant(
      of: find.byType(ScreenPip),
      matching: find.byWidgetPredicate(
        (w) => w is Listener && w.onPointerMove != null,
      ),
    );
    final start = tester.getTopLeft(strip) + const Offset(6, 4);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: start);
    addTearDown(mouse.removePointer);
    await mouse.down(start);
    await mouse.moveTo(start + const Offset(-40, -30));
    await tester.pump();
    expect(tester.getTopLeft(window).dx, closeTo(before.dx - 40, 1));
    await mouse.up();
    await tester.pumpAndSettle();

    await controller.stop();
    await tester.pumpAndSettle();
  });

  testWidgets('a private share asks the publisher before anyone is admitted', (
    tester,
  ) async {
    // The server stores the privacy setting and forwards every request anyway,
    // so the client is the only gate there is — a private share that admitted
    // on arrival was open to the whole channel.
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final transport = _SilentTransport();
    final backend = _FakeScreenBackend();
    final container = _container(
      view: _view(screen: true),
      transport: transport,
      screen: backend,
    );
    await tester.pumpWidget(_app(container, const ServerPage(session: 1)));
    await tester.pumpAndSettle();

    final controller = container.read(screenControllerProvider(1));
    await controller.start(
      null,
      'Share',
      screenOptions().copyWith(access: ScreenAccess.private),
    );
    await controller.receive(
      const ScreenEvent({
        'type': 'available',
        'stream_id': 's',
        'client_id': 1,
        'name': 'Share',
      }),
    );
    await controller.receive(
      const ScreenEvent({
        'type': 'join_requested',
        'stream_id': 's',
        'client_id': 2,
      }),
    );
    await tester.pumpAndSettle();

    // Held, and asked about — nothing opened while the request waits.
    expect(transport.starts.single['access'], 'private');
    expect(find.text('同事二号 想观看你的共享'), findsOneWidget);
    expect(backend.peers, isEmpty);

    await tester.tap(find.text('允许'));
    await tester.pumpAndSettle();
    expect(transport.calls, contains('screen:respond:2'));
    expect(backend.peers.single.calls, ['offer']);
    // Answered, so the dialog has nothing left to ask about.
    expect(find.text('同事二号 想观看你的共享'), findsNothing);
    expect(tester.takeException(), isNull);

    // Publication polls the encoder while it runs; the test does not end
    // while a timer is still owed.
    await controller.stop();
    await tester.pumpAndSettle();
  });

  testWidgets('a stale failed screen command leaves a running share alone', (
    tester,
  ) async {
    // The 2026-10-08 logs show a leave timing out and killing the share that
    // had been started three seconds earlier: the server drops commands it
    // cannot action without a word, and the deadline turned that silence into
    // a failure that tore down whatever was running.
    final transport = _SilentTransport();
    final backend = _FakeScreenBackend();
    final container = _container(
      view: _view(screen: true),
      transport: transport,
      screen: backend,
    );
    await tester.pumpWidget(_app(container, const ServerPage(session: 1)));
    await tester.pumpAndSettle();

    final controller = container.read(screenControllerProvider(1));
    await controller.start(null, 'Share', screenOptions());
    await controller.receive(
      const ScreenEvent({
        'type': 'available',
        'stream_id': 's',
        'client_id': 1,
        'name': 'Share',
      }),
    );
    await tester.pumpAndSettle();
    expect(controller.active, isTrue);

    transport.emit(
      const CommandResultEvent(
        CommandResult(
          command: 'screen',
          session: 1,
          outcome: CommandOutcome(ok: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.active, isTrue, reason: 'the share is established');
    expect(controller.error, isNull);

    await controller.stop();
    await tester.pumpAndSettle();
  });

  testWidgets('a failed screen command while still connecting is fatal', (
    tester,
  ) async {
    // While nothing is established yet the user is staring at "connecting",
    // so the error is worth showing now rather than at the timer.
    final transport = _SilentTransport();
    final backend = _FakeScreenBackend();
    final container = _container(
      view: _view(screen: true),
      transport: transport,
      screen: backend,
    );
    await tester.pumpWidget(_app(container, const ServerPage(session: 1)));
    await tester.pumpAndSettle();

    final controller = container.read(screenControllerProvider(1));
    await controller.start(null, 'Share', screenOptions());
    await tester.pump();
    expect(controller.starting, isTrue);

    transport.emit(
      const CommandResultEvent(
        CommandResult(
          command: 'screen',
          session: 1,
          outcome: CommandOutcome(ok: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.error, 'connection');
    expect(controller.active, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the wizard carries what was chosen into the share', (
    tester,
  ) async {
    _useInAppPicker(tester);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final transport = _SilentTransport();
    final backend = _FakeScreenBackend(
      available: const [
        ScreenSource('win-1', '编辑器', kind: ScreenSourceKind.window),
        ScreenSource('scr-1', '屏幕 1'),
      ],
    );
    // A capture that actually produced sound, because the wire follows the
    // capture and not the switch — a fake without a track would carry
    // `audio: false` and the assertion below would be about the wrong thing.
    backend.media.hasAudio = true;
    final container = _container(
      view: _view(screen: true),
      transport: transport,
      screen: backend,
    );
    await tester.pumpWidget(_app(container, const ServerPage(session: 1)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('共享屏幕'));
    await tester.pumpAndSettle();

    // Opens on the tab the first source is in, not on a fixed one, so a machine
    // with no camera does not greet anyone with an empty grid.
    expect(find.text('编辑器'), findsOneWidget);
    await tester.tap(find.text('编辑器'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一个'));
    await tester.pumpAndSettle();

    // A preset, then the one switch that is not part of one — so the assertion
    // below covers both halves of the page.
    await tester.tap(find.text('1440'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    await tester.tap(find.text('开始直播'));
    await tester.pumpAndSettle();

    expect(transport.starts, hasLength(1));
    expect(transport.starts.single, {
      'source': 'window',
      'height': 1440,
      'fps': 30,
      'video_bitrate_kbps': 6000,
      'audio': true,
      'audio_bitrate_kbps': 128,
      'access': 'public',
      'viewer_limit': 0,
      'mode': 'p2p',
      'detail': false,
    });
    // And it was remembered, not just sent: the next share opens where this
    // one was left, and the file is what remembers it.
    final saved = container.read(settingsProvider)!.screen;
    expect(saved.height, 1440);
    expect(saved.videoBitrateKbps, 6000);
    expect(saved.audio, isTrue);
    expect(
      transport.calls.any((call) => call.startsWith('updateSettings')),
      isTrue,
      reason:
          'the file is what remembers it, and the file is written through here',
    );

    // Stopping takes the start timeout with it.
    await tester.tap(find.byIcon(Icons.stop_screen_share));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('restoring the shortcuts asks the core rather than guessing', (
    tester,
  ) async {
    // The defaults differ by platform — Command on macOS, Control everywhere
    // else — and only `ts-settings` knows which. A page that filled them in
    // itself would be right on one platform and wrong on the other, silently.
    final transport = _SilentTransport();
    await tester.pumpWidget(
      _app(
        _container(view: _view(), transport: transport),
        const SettingsPage(session: 1),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('快捷键'));
    await tester.pumpAndSettle();

    // One per row, and the one that was pressed names its own row.
    final restore = find.byTooltip('恢复默认');
    expect(restore, findsNWidgets(ShortcutAction.values.length));

    // And the row *has* a button there, not just a tooltip: the first version
    // was a bare 18-pixel glyph with nothing around it, which read as part of
    // the background rather than as the one thing on the page that undoes a
    // change.
    expect(
      find.descendant(of: restore.first, matching: find.byType(OutlinedButton)),
      findsOneWidget,
    );

    await tester.tap(restore.last);
    await tester.pumpAndSettle();

    expect(transport.calls, contains('resetShortcut:push_to_talk'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('every theme builds every page', (tester) async {
    // The pages read their colours from `DesignTokens.of(context)`, so a new
    // palette reaches all of them without a code change — this is what proves
    // it, rather than assuming it. It cannot prove the result *looks* right;
    // `design_test.dart` has the assertions for that.
    for (final palette in AppPalette.all) {
      for (final home in <Widget>[
        const ConnectPage(),
        const ServerPage(session: 1),
        const SettingsPage(session: 1),
      ]) {
        await tester.pumpWidget(
          _app(
            _container(view: _view(), notices: true),
            home,
            palette: palette,
          ),
        );
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: '${palette.name} failed to build ${home.runtimeType}',
        );
      }
    }
  });
}
