import '../../../core/platform/services.dart';
// What is worth interrupting the user for (§43).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/settings.dart';
import '../../../providers/providers.dart';

/// The notification switches.
class NotificationsSection extends ConsumerWidget {
  /// Edits `settings`.
  const NotificationsSection({required this.settings, super.key});

  final Settings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tokens = DesignTokens.of(context);
    final notifications = settings.notifications;

    void update(NotificationSettings next) =>
        ref.read(settingsProvider.notifier).update(settings.copyWith(notifications: next));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _switch(
          context,
          l10n.settingsNotifyPresence,
          notifications.presence,
          (v) => update(notifications.copyWith(presence: v)),
        ),
        _switch(
          context,
          l10n.settingsNotifyPoke,
          notifications.poke,
          (v) => update(notifications.copyWith(poke: v)),
        ),
        _switch(
          context,
          l10n.settingsNotifyChannelMessage,
          notifications.channelMessage,
          (v) => update(notifications.copyWith(channelMessage: v)),
        ),
        _switch(
          context,
          l10n.settingsNotifyDirectMessage,
          notifications.directMessage,
          (v) => update(notifications.copyWith(directMessage: v)),
        ),
        _switch(
          context,
          l10n.settingsNotifyConnection,
          notifications.connection,
          (v) => update(notifications.copyWith(connection: v)),
        ),
        SizedBox(height: tokens.space2),
        // Separate from the switches above because it answers a different
        // question — where the notification goes, not whether there is one.
        _switch(context, l10n.settingsNotifySystem, notifications.system, (v) {
          if (v) requestNotificationPermission();
          update(notifications.copyWith(system: v));
        }),
      ],
    );
  }

  // The switch's colours come from the theme's `switchTheme` (§5: primary
  // when it is on); only the label style is this widget's.
  Widget _switch(BuildContext context, String label, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: Text(label, style: Theme.of(context).textTheme.labelLarge),
        dense: true,
        contentPadding: EdgeInsets.zero,
      );
}
