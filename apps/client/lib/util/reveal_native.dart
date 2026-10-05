// Opening a directory in the platform's file manager.
//
// Used for the log folder, which is the only way a user can reach the files a
// bug report needs — so it has to work on every desktop platform without
// pulling in a plugin for one small job.

import 'dart:io';

import '../core/platform/services.dart';

/// The command that reveals [path] in the file manager of [operatingSystem].
///
/// Split out from [revealDirectory] and taking the platform as a parameter, so
/// the mapping can be asserted in a test without launching anything — and so
/// `Platform.operatingSystem`'s spelling (`macos`, not `macOS`) is stated once.
List<String> revealCommand(String path, {required String operatingSystem}) {
  switch (operatingSystem) {
    case 'windows':
      // Explorer. Note that it reports exit code 1 even when it succeeded,
      // which is why `revealDirectory` never consults the exit code.
      return ['explorer', path];
    case 'macos':
      return ['open', path];
    default:
      // Linux and the BSDs. Every desktop environment ships one of these; which
      // one is not worth detecting, since the failure is silent either way.
      return ['xdg-open', path];
  }
}

/// Opens [path] in the platform's file manager.
///
/// Reports nothing on success and raises nothing on failure: whether the folder
/// actually appeared is not something this can know — Windows' Explorer exits
/// with a failure code when it worked. A platform with no opener at all is
/// written to the core's log, which is the only place left to say so.
Future<void> revealDirectory(String path) async {
  if (path.isEmpty) return;

  final command = revealCommand(path, operatingSystem: Platform.operatingSystem);
  try {
    await Process.run(command.first, command.skip(1).toList());
  } on ProcessException catch (error) {
    logToCore('warn', 'could not open $path in the file manager: $error');
  }
}
