// Step one: what to share.

import 'package:flutter/material.dart';

import '../../../core/screen/screen_share_backend.dart';
import '../../../design/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/screen_options.dart';

/// The tabs, in the order they are offered.
///
/// The same list decides which tab the dialog *opens* on, so the two cannot
/// drift: a machine with applications and screens but no camera opens on
/// 应用程序, the way the reference client does, rather than on whichever kind
/// happens to be declared first in the enum.
const sourceTabOrder = [
  ScreenSourceKind.window,
  ScreenSourceKind.screen,
  ScreenSourceKind.camera,
];

/// Picks one of the things that can be captured.
///
/// Three tabs because the platform has three kinds of answer — a window, a
/// whole display, a camera — and they are not interchangeable to the person
/// choosing: "share my screen" and "share this window" are different promises
/// about what everyone else will see.
///
/// Stateless, and told which tab it is on rather than remembering: the dialog
/// owns that because it also owns the captures, and a tab change is what starts
/// and stops them.
class SourceStep extends StatelessWidget {
  const SourceStep({
    required this.sources,
    required this.previews,
    required this.kind,
    required this.selected,
    required this.onKind,
    required this.onSelected,
    required this.onPreview,
    super.key,
  });

  final List<ScreenSource> sources;

  /// Whatever is being watched right now, by source id.
  ///
  /// One capture per tile, and the band above is the selected tile's — a second
  /// one for it would be a second capture of the same window.
  final Map<String, ScreenMedia> previews;

  final ScreenSourceKind kind;
  final ScreenSource? selected;
  final ValueChanged<ScreenSourceKind> onKind;
  final ValueChanged<ScreenSource?> onSelected;

  /// Opens the selected window for a look, when the user asks for one.
  final VoidCallback onPreview;

  List<ScreenSource> _of(ScreenSourceKind kind) => [
    for (final source in sources)
      if (source.kind == kind) source,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final labels = {
      ScreenSourceKind.window: l10n.screenSetupApps,
      ScreenSourceKind.screen: l10n.screenSetupScreens,
      ScreenSourceKind.camera: l10n.screenSetupCameras,
    };
    final here = _of(kind);
    final live = selected == null ? null : previews[selected!.id];
    final still = selected?.thumbnail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          // A fixed band rather than a 16:9 box: at this dialog's width an
          // aspect ratio makes the preview 378px tall, which left the grid
          // below it about as much as one row — and the bottom row of tiles
          // ended up under the dialog's own footer, unclickable. Whatever is
          // shown is letterboxed inside this instead.
          child: SizedBox(
            height: 240,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.bgDeep,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: switch ((still, live)) {
                  // Prefer a thumbnail supplied with the source list.
                  (final shot?, _) => Image.memory(
                    shot,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                  (_, final media?) => media.view(),
                  // Allow retrying a thumbnail that was not available.
                  _ when selected?.kind == ScreenSourceKind.window =>
                    _AskToPreview(source: selected!, onPreview: onPreview),
                  _ => Center(
                    child: Text(
                      l10n.screenSetupSources,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(color: tokens.textTertiary),
                    ),
                  ),
                },
              ),
            ),
          ),
        ),
        // The tabs, evenly spread and underlined, as in the reference client.
        Row(
          children: [
            for (final tab in sourceTabOrder)
              Expanded(
                child: _Tab(
                  label: labels[tab]!,
                  selected: tab == kind,
                  // A tab with nothing behind it still shows, greyed: a missing
                  // 「摄像头」 is information — this machine has none — where a
                  // missing tab would just look like the app forgot.
                  enabled: _of(tab).isNotEmpty,
                  onPressed: () => onKind(tab),
                ),
              ),
          ],
        ),
        Divider(height: 1, color: tokens.borderSubtle),
        Expanded(
          child: here.isEmpty
              ? Center(
                  child: Text(
                    l10n.screenSetupNoSources,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: tokens.textTertiary),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 16 / 11,
                  ),
                  itemCount: here.length,
                  itemBuilder: (context, index) {
                    final source = here[index];
                    return _SourceTile(
                      source: source,
                      preview: previews[source.id],
                      selected: source.id == selected?.id,
                      onPressed: () => onSelected(source),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return InkWell(
      onTap: enabled ? onPressed : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: selected ? tokens.primary : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: !enabled
                ? tokens.textDisabled
                : selected
                ? tokens.textPrimary
                : tokens.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.preview,
    required this.selected,
    required this.onPressed,
  });

  final ScreenSource source;
  final ScreenMedia? preview;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    final shot = source.thumbnail;
    // Still, then live, then a glyph: the same order as the band above, so a
    // tile and the picture it feeds agree about what this source looks like.
    final picture = switch ((shot, preview)) {
      (final shot?, _) => Image.memory(
        shot,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
      (_, final media?) => media.view(),
      _ => Center(
        child: Icon(
          _iconFor(source.kind),
          size: 32,
          color: tokens.textTertiary,
        ),
      ),
    };

    return Material(
      color: tokens.surface1,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? tokens.primary : Colors.transparent,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ColoredBox(color: tokens.bgDeep, child: picture),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  source.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: selected ? tokens.primary : tokens.textSecondary,
                    fontWeight: selected ? AppTypography.semibold : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(ScreenSourceKind kind) => switch (kind) {
    ScreenSourceKind.window => Icons.web_asset,
    ScreenSourceKind.screen => Icons.monitor,
    ScreenSourceKind.camera => Icons.photo_camera,
  };
}

/// Retry an unavailable window thumbnail.
class _AskToPreview extends StatelessWidget {
  const _AskToPreview({required this.source, required this.onPreview});

  final ScreenSource source;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          source.name,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(color: tokens.textPrimary),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onPreview,
          icon: const Icon(Icons.visibility_outlined, size: 18),
          label: Text(l10n.screenSetupPreview),
        ),
        const SizedBox(height: 8),
        // Missing thumbnails do not block the next step.
        Text(
          l10n.screenSetupPreviewNote,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: tokens.textTertiary),
        ),
      ],
    );
  }
}
