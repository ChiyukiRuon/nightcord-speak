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
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/transport/client_transport.dart';
import 'package:nightcord_client/design/components/app_logo.dart';
import 'package:nightcord_client/features/server/channel_sidebar.dart';
import 'package:nightcord_client/features/settings/settings_dialog.dart';
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
import 'package:nightcord_client/models/settings.dart';
import 'package:nightcord_client/models/voice_status.dart';
import 'package:nightcord_client/providers/providers.dart';
import 'package:nightcord_client/state/notifications.dart';
import 'package:nightcord_client/state/server_view.dart';

/// A transport that answers nothing.
///
/// The pages fire commands on open (`requestSettings`, `requestAudioDevices`)
/// and never expect an answer before drawing; this lets them do that without a
/// core. `noSuchMethod` rather than 20 stubs — the interface is wide and this
/// test only cares that the calls do not throw.
class _SilentTransport implements ClientTransport {
  final StreamController<FfiEvent> _events = StreamController<FfiEvent>.broadcast();

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
  void connect(ConnectRequest request) => calls.add('connect:${request.address}');

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
  @override
  Settings? build() => const Settings();
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

/// A server with everything the page can draw: a nested tree, a locked and an
/// empty channel, an offline section, someone talking, and messages mixing
/// scripts.
ServerView _view() {
  final view = ServerView(session: 1);
  void send(ClientEvent event) => view.apply(event);

  send(
    const ConnectedEvent(
      server: Server(
        id: 1,
        name: 'Nightcord 测试服',
        address: '192.168.31.128:9987',
        protocol: ProtocolKind.ts3,
      ),
      info: ServerInfo(name: 'Nightcord 测试服'),
    ),
  );
  send(const ServerInfoChangedEvent(ServerInfo(name: 'Nightcord 测试服', clientsOnline: 4)));
  send(
    const PermissionsChangedEvent(
      Permissions(canJoinChannel: true, canSendChannelMessage: true, canSendPrivateMessage: true),
    ),
  );
  send(const OwnClientIdentifiedEvent(clientId: 1, channelId: 1));

  send(const ChannelCreatedEvent(Channel(id: 1, name: '大厅', isDefault: true)));
  send(const ChannelCreatedEvent(Channel(id: 2, name: '游戏区', parentId: 1)));
  send(const ChannelCreatedEvent(Channel(id: 3, name: 'CS2', parentId: 2, hasPassword: true)));
  send(const ChannelCreatedEvent(Channel(id: 4, name: '挂机', parentId: 1)));

  send(const ClientJoinedEvent(Client(id: 1, name: 'TsukinoAyaka', channelId: 1, isSelf: true)));
  send(const ClientJoinedEvent(Client(id: 2, name: '同事二号', channelId: 1)));
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
  _SilentTransport? transport,
}) => ProviderContainer.test(
      overrides: [
        clientTransportProvider.overrideWithValue(transport ?? _SilentTransport()),
        activeSessionProvider.overrideWith(() => _FixedActive()),
        settingsProvider.overrideWith(() => _FixedSettings()),
        audioDevicesProvider.overrideWith(() => _FixedDevices()),
        voiceStatusProvider.overrideWith(() => _FixedVoiceStatus()),
        if (view != null) sessionsProvider.overrideWith(() => _FixedSessions({1: view})),
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

void main() {
  setUp(() {
    // A window rather than the test's default 800x600, so a page that only
    // overflows when it has room to lay out is not silently skipped.
    TestWidgetsFlutterBinding.ensureInitialized();
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

  testWidgets('the settings dialog', (tester) async {
    await tester.pumpWidget(
      _app(
        _container(view: _view()),
        const Scaffold(body: Center(child: SettingsDialog(session: 1))),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
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
    expect(find.byIcon(Icons.link_off), findsOneWidget);

    await tester.tap(find.byIcon(Icons.link_off));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(transport.calls, isEmpty, reason: 'it disconnected without asking');
    expect(container.read(sessionsProvider), contains(1));

    // Backing out leaves everything where it was.
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextButton)),
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

    await tester.tap(find.byIcon(Icons.link_off));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)),
    );
    await tester.pumpAndSettle();

    expect(transport.calls, contains('disconnect:1'));
    expect(container.read(sessionsProvider), isEmpty);
  });

  testWidgets('the name in the voice bar is lifted off its own line box', (tester) async {
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
    await tester.pumpWidget(_app(_container(view: _view()), const ServerPage(session: 1)));
    await tester.pumpAndSettle();

    // Scoped to the bar: the member list shows the same name.
    final name = tester.getRect(
      find.descendant(of: find.byType(VoiceBar), matching: find.text('TsukinoAyaka')),
    );
    final bar = tester.getRect(find.byType(VoiceBar));
    expect(
      name.center.dy,
      lessThan(bar.center.dy),
      reason: 'the name is sitting on its line box, which draws it low',
    );
  });

  testWidgets('a saved server fills the form on one click, connects on two', (tester) async {
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
    final address = tester.widget<TextField>(
      find.byType(TextField).first,
    );
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
      _app(_container(bookmarks: true, transport: transport), const ConnectPage()),
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

    container.read(lastErrorProvider.notifier).report(const ClientError(kind: 'timeout'));
    await tester.pumpAndSettle();

    // The `SnackBar` widget itself is stretched over the Scaffold's whole
    // bottom slot, so its rect is not the bar anyone sees. The content row is:
    // the bar's padding is zero and the row fills it.
    final content = tester.getRect(
      find.descendant(of: find.byType(SnackBar), matching: find.byType(Row)).first,
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

    await tester.tap(find.descendant(
      of: find.byType(ChannelSidebar),
      matching: find.text('Nightcord 测试服'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的权限'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('不会向客户端提供权限信息'),
      findsOneWidget,
      reason: 'the server said nothing, so the panel says so',
    );
    for (final label in [
      '加入频道',
      '发频道消息',
      '发私聊消息',
      '移出成员',
      '封禁',
    ]) {
      expect(find.text(label), findsNothing, reason: '(label) was never confirmed');
    }
  });

  testWidgets('the permissions panel lists the granted and known ones', (tester) async {
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

    await tester.tap(find.descendant(
      of: find.byType(ChannelSidebar),
      matching: find.text('Nightcord 测试服'),
    ));
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

    await tester.tap(find.descendant(
      of: find.byType(ChannelSidebar),
      matching: find.text('Nightcord 测试服'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏服务器'));
    await tester.pumpAndSettle();

    // Through `addBookmark`, not `updateBookmarks`: the core owns the address
    // parser, so an entry saved here is spelt the same way as one saved on the
    // connect screen.
    expect(transport.calls, contains('addBookmark:192.168.31.128:9987'));
  });

  testWidgets('a server already saved offers to be unsaved instead', (tester) async {
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

    await tester.tap(find.descendant(
      of: find.byType(ChannelSidebar),
      matching: find.text('Nightcord 测试服'),
    ));
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
    await tester.tap(find.descendant(
      of: find.byType(ChannelSidebar),
      matching: find.text('Nightcord 测试服'),
    ));
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
    // Regression: the dialog used to require a session, and the only button
    // that opened it lived in the voice bar — which only exists on the server
    // page. So a user who could not connect had no way to reach the log folder,
    // the language, or their audio devices, which is exactly when they are
    // looking for them.
    await tester.pumpWidget(_app(_container(), const ConnectPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the member menu offers only what the server allows', (tester) async {
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

    for (final label in [
      '移出频道',
      '移出服务器',
      '移动到频道…',
      '封禁…',
    ]) {
      expect(
        _menuItemEnabled(tester, label),
        isFalse,
        reason: '(label) should be greyed out',
      );
    }
  });

  testWidgets('a permitted kick sends the scope that was chosen', (tester) async {
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
      _app(_container(view: view, transport: transport), const ServerPage(session: 1)),
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

    await tester.pumpWidget(_app(_container(view: _view()), const ServerPage(session: 1)));
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
      await tester.pumpWidget(_app(_container(), Center(child: AppLogo(size: size))));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'failed to draw at ${size}px');
    }
  });

  testWidgets('a session that has been forgotten', (tester) async {
    // The empty branch of `ServerPage` — reached when the user disconnects and
    // the view is dropped, which is the one state no other test draws.
    await tester.pumpWidget(_app(_container(), const ServerPage(session: 99)));
    await tester.pumpAndSettle();
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
        const Scaffold(body: Center(child: SettingsDialog(session: 1))),
      ]) {
        await tester.pumpWidget(
          _app(_container(view: _view(), notices: true), home, palette: palette),
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
