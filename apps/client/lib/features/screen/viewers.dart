// How many people are watching a share, said the same way everywhere.

import '../../core/screen/screen_controller.dart';
import '../../l10n/app_localizations.dart';

/// "Viewers 3", or "Viewers 3/4" once a limit has been chosen.
///
/// A share with no limit says so by having nothing after the number: "/0" would
/// read as a limit of none, which is the opposite of what zero means here.
///
/// One function rather than the same expression in the button's tooltip and the
/// window's title strip. The number itself has one home too — see
/// [ScreenController.viewerLimit].
String viewerCount(AppLocalizations l10n, ScreenController controller) {
  final limit = controller.viewerLimit;
  return limit > 0
      ? '${l10n.screenViewers} ${controller.viewers}/$limit'
      : '${l10n.screenViewers} ${controller.viewers}';
}
