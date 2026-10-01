// The application settings, as a page.
//
// Audio was the first thing to need settings, so this was an audio-only dialog
// that hid inside the voice bar. It became the app's settings surface, and then
// outgrew the shape: six sections stacked in one 480px scroller, with every new
// setting making the scroll longer and nothing on screen saying how much was
// left. It is a page now — a navigation column on the left, one section on the
// right — which is also what makes each section an independent piece
// (`sections/`) rather than another block in one Column.
//
// Every control, wherever it lives, writes through `settingsProvider`, which is
// what makes the values survive closing the page and restarting the app. Before
// that they lived in widget state and were gone the moment the surface closed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/settings.dart';
import '../../providers/providers.dart';
import 'sections/audio_section.dart';
import 'sections/connection_section.dart';
import 'sections/interface_section.dart';
import 'sections/log_section.dart';
import 'sections/notifications_section.dart';
import 'sections/shortcuts_section.dart';

/// How wide the navigation column is.
///
/// §19 gives 240–280 for a sidebar and warns against fixing every one of them
/// at its widest. This one takes the floor: its labels are one or two words,
/// against channel names that carry topics and counts.
const double _navWidth = 240;

/// The widest the form is allowed to get.
///
/// A dropdown stretched across a 1920px window is harder to read than one that
/// stops, and every control here is a single field in a column.
const double _contentWidth = 640;

/// The page's sections, in the order the navigation column lists them.
enum _Section {
  audio,
  connection,
  notifications,
  shortcuts,
  interface,
  log,
}

extension on _Section {
  /// What the section is called, in the navigation column and as the heading
  /// over its own controls — one string for both, because they are the same
  /// fact and two copies of it would eventually disagree.
  String label(AppLocalizations l10n) => switch (this) {
    _Section.audio => l10n.settingsAudioSection,
    _Section.connection => l10n.settingsConnectionSection,
    _Section.notifications => l10n.settingsNotificationsSection,
    _Section.shortcuts => l10n.settingsShortcutsSection,
    _Section.interface => l10n.settingsInterfaceSection,
    _Section.log => l10n.logLabel,
  };

  /// The glyph beside the label. Outlined throughout, like every other icon in
  /// the app (§16).
  IconData get icon => switch (this) {
    _Section.audio => Icons.mic_none,
    _Section.connection => Icons.link,
    _Section.notifications => Icons.notifications_none,
    _Section.shortcuts => Icons.keyboard_outlined,
    _Section.interface => Icons.palette_outlined,
    _Section.log => Icons.article_outlined,
  };
}

/// Settings, opened from the voice bar or from the connect screen.
class SettingsPage extends ConsumerStatefulWidget {
  /// Settings that apply to `session`, when there is one.
  const SettingsPage({this.session, super.key});

  /// The session the audio controls refer to, or null when the page was opened
  /// from somewhere that has no connection — the connect screen.
  ///
  /// Everything here except the microphone test and the device swap is a
  /// preference, and preferences do not need a server. Making this page
  /// unreachable until a connection existed put "where did the log go" and
  /// "which language" behind a server, which is exactly when a user is most
  /// likely to be looking for them.
  final int? session;

  /// Opens the page over whatever is showing.
  ///
  /// A route rather than a dialog: the whole app is behind it, and the way back
  /// is the back button in its own navigation column. A helper rather than a
  /// `showDialog` at each call site so "how settings open" has one answer —
  /// this is also the app's first pushed route, and the second call site is
  /// where a route with different arguments would otherwise appear.
  static Future<void> open(BuildContext context, {int? session}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => SettingsPage(session: session)),
      );

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  /// Which section the content area is showing.
  ///
  /// Audio first because it is the one people come here for, and because it is
  /// where the voice bar's gear button used to land.
  _Section _section = _Section.audio;

  @override
  void initState() {
    super.initState();
    // Asked once, here rather than in each section, so switching sections does
    // not re-ask. The device lists are the audio section's own business and it
    // asks for those itself.
    ref.read(clientTransportProvider).requestSettings();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final settings = ref.watch(settingsProvider);

    // A `Scaffold` of its own, not just a Row: errors are shown through
    // `ScaffoldMessenger`, which hands the bar to every registered `Scaffold` —
    // without one here, a failed settings write would put its SnackBar on the
    // shell's Scaffold *behind* this page and the user would see nothing.
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _navWidth,
            child: _SettingsNav(
              selected: _section,
              onSelect: (section) => setState(() => _section = section),
            ),
          ),
          VerticalDivider(width: 1, color: tokens.borderSubtle),
          Expanded(child: _content(l10n, settings)),
        ],
      ),
    );
  }

  /// The right-hand half: the current section's heading and controls.
  Widget _content(AppLocalizations l10n, Settings? settings) {
    final tokens = DesignTokens.of(context);

    // A `Material`, not a painted `Container`: the sections hold `ListTile`s
    // (the notification switches), and a tile paints its ink on the nearest
    // `Material` above it — a plain background colour in between hides the
    // splashes, which Flutter asserts about rather than letting pass.
    return Material(
      // §2.2: the content is the page step, one above the navigation column —
      // the same pairing the channel sidebar and the chat have.
      color: tokens.bgMain,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(tokens.space7),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _contentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _section.label(l10n),
                // §12.2's `title`: the heading of the whole content area, the
                // same level the chat header uses for the same job.
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SizedBox(height: tokens.space5),
              // Nothing to edit until the core answers. The navigation column
              // is drawn anyway, so the page does not flash its shape in and
              // out — and the sections are not built at all, rather than built
              // with defaults the user never chose.
              // (`DropdownButtonFormField.initialValue` is read once, so a form
              // built early would not correct itself afterwards.)
              if (settings == null)
                Text(
                  l10n.settingsLoading,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
                )
              else
                _sectionBody(settings),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionBody(Settings settings) => switch (_section) {
    _Section.audio => AudioSection(settings: settings, session: widget.session),
    _Section.connection => ConnectionSection(settings: settings),
    _Section.notifications => NotificationsSection(settings: settings),
    _Section.shortcuts => ShortcutsSection(settings: settings),
    _Section.interface => InterfaceSection(settings: settings),
    _Section.log => const LogSection(),
  };
}

/// The navigation column: the way back, the page's name, and the sections.
class _SettingsNav extends StatelessWidget {
  const _SettingsNav({required this.selected, required this.onSelect});

  final _Section selected;
  final ValueChanged<_Section> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);

    return Container(
      // §2.2: a navigation column is the `bgSidebar` step — one below the
      // content it sits beside, which is how the boundary is drawn instead of
      // with a border. The same step and the same 1px rule as the channel
      // sidebar.
      color: tokens.bgSidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NavHeader(),
          Divider(height: 1, color: tokens.borderSubtle),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(vertical: tokens.space2),
              children: [
                for (final section in _Section.values)
                  _NavItem(
                    section: section,
                    label: section.label(l10n),
                    selected: section == selected,
                    onTap: () => onSelect(section),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The back button and the page's name.
class _NavHeader extends StatelessWidget {
  const _NavHeader();

  /// The button's box, and the glyph inside it.
  ///
  /// A fixed box for the same reason the chat header has one: an `IconButton`
  /// is 48 by default and a bare icon is 24, and a header that changes height
  /// with its contents makes everything under it jump.
  static const double _buttonSize = 32;
  static const double _iconSize = 20;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);

    // The transparent `Material` is what makes the button's hover and splash
    // visible at all: ink is painted on the nearest `Material`, and the column
    // is a painted `Container` in between — the same reason the channel
    // sidebar's header wraps itself in one.
    //
    // The padding is what lines the title up with the section labels below it:
    // 12 (edge) + 32 (button) + 12 (gap) is the 56 the rows below reach through
    // their own 12 + 12 + 20 + 12.
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tokens.space3,
          tokens.space3,
          tokens.space4,
          tokens.space3,
        ),
        child: Row(
          children: [
            SizedBox(
              width: _buttonSize,
              height: _buttonSize,
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                iconSize: _iconSize,
                padding: EdgeInsets.zero,
                tooltip: l10n.backButton,
                // `maybePop`, not `pop`: harmless when the page is the root —
                // which is how the tests build it — and otherwise the same.
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            SizedBox(width: tokens.space3),
            Expanded(
              child: Text(
                l10n.settingsTitle,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in the navigation column.
///
/// The channel row's structure and its three states, because they are the same
/// control: hover is tracked by hand (§19 changes the *text* colour too, which
/// `InkWell` does not expose), selected beats hovered, hovered beats resting.
class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.section,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final _Section section;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    final text = Theme.of(context).textTheme;
    final contentColour = widget.selected || _hovered
        ? tokens.textPrimary
        : tokens.textSecondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.space3,
          vertical: tokens.space1,
        ),
        child: Material(
          color: widget.selected ? tokens.surface1 : Colors.transparent,
          borderRadius: AppRadius.smAll,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: AppRadius.smAll,
            hoverColor: tokens.channelHoverBg,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tokens.space3,
                vertical: tokens.space2,
              ),
              child: Row(
                children: [
                  Icon(widget.section.icon, size: 20, color: contentColour),
                  SizedBox(width: tokens.space3),
                  Expanded(
                    child: Text(
                      widget.label,
                      overflow: TextOverflow.ellipsis,
                      // The same emphasis split as a selected channel: 14/500
                      // when it is the one on screen, 14/400 otherwise.
                      style: widget.selected
                          ? text.titleMedium?.copyWith(color: contentColour)
                          : text.bodyMedium?.copyWith(color: contentColour),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
