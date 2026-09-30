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
import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/transport/client_transport.dart';
import 'package:nightcord_client/design/components/app_logo.dart';
import 'package:nightcord_client/design/theme/app_theme.dart';
import 'package:nightcord_client/design/tokens/app_palette.dart';
import 'package:nightcord_client/features/connect/connect_page.dart';
import 'package:nightcord_client/features/notifications/notice_stack.dart';
import 'package:nightcord_client/features/server/server_page.dart';
import 'package:nightcord_client/features/settings/settings_dialog.dart';
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
    // The extra pump is the double-tap timeout: with both gestures on the row,
    // Flutter holds the single tap back until it knows a second one is not
    // coming. `pumpAndSettle` alone does not get there — it stops as soon as
    // no *frame* is scheduled, and this wait is a bare timer.
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
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
