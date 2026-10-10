import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sounds/sound_library.dart';
import '../../../design/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/settings.dart';
import '../../../providers/providers.dart';
import '../../../providers/sounds.dart';

class SoundsSection extends ConsumerStatefulWidget {
  const SoundsSection({required this.settings, super.key});
  final Settings settings;
  @override
  ConsumerState<SoundsSection> createState() => _SoundsSectionState();
}

class _SoundsSectionState extends ConsumerState<SoundsSection> {
  bool _saving = false;
  bool _opening = false;
  String? _error;

  String label(AppLocalizations l10n, SoundAction action) => switch (action) {
    SoundAction.voiceJoined => l10n.soundVoiceJoined,
    SoundAction.voiceLeft => l10n.soundVoiceLeft,
    SoundAction.microphoneOff => l10n.soundMicrophoneOff,
    SoundAction.microphoneOn => l10n.soundMicrophoneOn,
    SoundAction.speakersOff => l10n.soundSpeakersOff,
    SoundAction.speakersOn => l10n.soundSpeakersOn,
    SoundAction.awayOn => l10n.soundAwayOn,
    SoundAction.awayOff => l10n.soundAwayOff,
    SoundAction.message => l10n.soundMessage,
  };

  void update(NotificationSettings next) =>
      ref.read(settingsProvider.notifier).update(widget.settings.copyWith(notifications: next));

  Future<void> save(SoundPack pack, SoundAction action, String? file) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(soundLibraryProvider).save(pack.name, {...pack.mapping, action: file});
      ref.invalidate(soundPacksProvider);
      await ref.read(soundPacksProvider.future);
    } catch (_) {
      if (mounted) setState(() => _error = AppLocalizations.of(context).soundsWriteError);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> preview(SoundPack pack, String file) async {
    try {
      await ref
          .read(soundLibraryProvider)
          .play(
            pack.name,
            file,
            output: widget.settings.audio.outputDevice,
            volume: widget.settings.audio.outputVolume,
          );
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).soundsPlayError);
      }
    }
  }

  Future<void> chooseDirectory() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final path = await ref.read(soundDirectoryChooserProvider)();
      if (mounted && path != null) {
        update(widget.settings.notifications.copyWith(soundDirectory: path));
      }
    } catch (_) {
      if (mounted) setState(() => _error = AppLocalizations.of(context).soundsOpenError);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> openDirectory() async {
    setState(() => _opening = true);
    final library = ref.read(soundLibraryProvider);
    final open = ref.read(soundDirectoryOpenerProvider);
    try {
      await open(await library.directory());
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).soundsOpenError);
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final library = ref.watch(soundLibraryProvider);
    if (!library.available) {
      return Padding(
        padding: EdgeInsets.only(top: tokens.space4),
        child: Text(l10n.soundsUnavailable),
      );
    }
    final notifications = widget.settings.notifications;
    final packs = notifications.sounds ? ref.watch(soundPacksProvider) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: tokens.space4 * 2),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(l10n.soundsEnabled),
          value: notifications.sounds,
          onChanged: (value) => update(notifications.copyWith(sounds: value)),
        ),
        if (notifications.sounds) ...[
          Text(l10n.soundsHint, style: Theme.of(context).textTheme.bodySmall),
          FutureBuilder<String>(
            future: library.directory(),
            builder: (context, snapshot) => snapshot.hasData
                ? SelectableText(snapshot.data!, style: Theme.of(context).textTheme.bodySmall)
                : const SizedBox.shrink(),
          ),
          SizedBox(height: tokens.space4),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: tokens.space3,
              runSpacing: tokens.space2,
              children: [
                TextButton.icon(
                  onPressed: _opening || _saving ? null : chooseDirectory,
                  icon: const Icon(Icons.folder_outlined),
                  label: Text(l10n.soundsChooseFolder),
                ),
                TextButton(
                  onPressed: _opening || _saving || notifications.soundDirectory.isEmpty
                      ? null
                      : () => update(notifications.copyWith(soundDirectory: '')),
                  child: Text(l10n.soundsDefaultFolder),
                ),
                TextButton.icon(
                  onPressed: _saving ? null : () => ref.invalidate(soundPacksProvider),
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.soundsRefresh),
                ),
                TextButton.icon(
                  onPressed: _opening ? null : openDirectory,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: Text(l10n.soundsOpenFolder),
                ),
              ],
            ),
          ),
          SizedBox(height: tokens.space4),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          packs!.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, stack) => Text(
              l10n.soundsReadError,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            data: (packs) {
              final pack = packs.where((pack) => pack.name == notifications.soundPack).firstOrNull;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey(notifications.soundPack),
                    initialValue: pack?.name,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: l10n.soundsPack),
                    items: [
                      for (final pack in packs)
                        DropdownMenuItem(value: pack.name, child: Text(pack.name)),
                    ],
                    onChanged: _saving
                        ? null
                        : (name) {
                            if (name != null) update(notifications.copyWith(soundPack: name));
                          },
                  ),
                  if (pack == null)
                    Padding(
                      padding: EdgeInsets.only(top: tokens.space2),
                      child: Text(l10n.soundsMissingPack),
                    ),
                  if (pack != null && pack.files.isEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: tokens.space2),
                      child: Text(l10n.soundsEmpty),
                    ),
                  if (pack != null) Divider(height: tokens.space4 * 2),
                  if (pack != null)
                    for (final action in SoundAction.values)
                      Padding(
                        padding: EdgeInsets.only(top: tokens.space3),
                        child: Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                key: ValueKey('${pack.name}/${action.key}/${pack.mapping[action]}'),
                                initialValue: pack.mapping[action] ?? '',
                                isExpanded: true,
                                decoration: InputDecoration(labelText: label(l10n, action)),
                                items: [
                                  DropdownMenuItem(value: '', child: Text(l10n.soundsNone)),
                                  for (final file in pack.files)
                                    DropdownMenuItem(
                                      value: file,
                                      child: Text(file, overflow: TextOverflow.ellipsis),
                                    ),
                                  if (pack.mapping[action] != null &&
                                      !pack.files.contains(pack.mapping[action]))
                                    DropdownMenuItem(
                                      value: pack.mapping[action],
                                      child: Text(
                                        '${pack.mapping[action]} (${l10n.soundsMissingFile})',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: _saving
                                    ? null
                                    : (file) {
                                        if (file != null) {
                                          save(pack, action, file.isEmpty ? null : file);
                                        }
                                      },
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.soundsPreview,
                              icon: const Icon(Icons.play_arrow),
                              onPressed: pack.files.contains(pack.mapping[action])
                                  ? () => preview(pack, pack.mapping[action]!)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}
