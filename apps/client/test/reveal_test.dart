// Opening the log folder in the platform's file manager.

import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/util/reveal.dart';

void main() {
  group('revealing a directory', () {
    test('Windows sound folders use native separators in a single argument', () {
      // The sound library used to append /sounds to a native Windows path;
      // Explorer could then open its default location rather than that folder.
      expect(revealCommand(r'D:\软件目录\Nightcord Speak/sounds', operatingSystem: 'windows'), [
        'explorer',
        r'D:\软件目录\Nightcord Speak\sounds',
      ]);
      expect(revealCommand('D:/Nightcord Speak/sounds', operatingSystem: 'windows'), [
        'explorer',
        r'D:\Nightcord Speak\sounds',
      ]);
    });

    test('uses the file manager each platform ships', () {
      // The command *is* the contract: the exit code cannot be consulted,
      // because Windows' Explorer reports failure even when it worked.
      expect(
        revealCommand(
          r'C:\Users\me\AppData\Roaming\Nightcord Speak\logs',
          operatingSystem: 'windows',
        ),
        ['explorer', r'C:\Users\me\AppData\Roaming\Nightcord Speak\logs'],
      );
      expect(revealCommand('/Users/me/Library/Logs', operatingSystem: 'macos'), [
        'open',
        '/Users/me/Library/Logs',
      ]);
      expect(revealCommand('/home/me/.config/logs', operatingSystem: 'linux'), [
        'xdg-open',
        '/home/me/.config/logs',
      ]);
    });

    test('an unrecognised platform still tries something', () {
      // The BSDs and anything Flutter adds later. Attempting the XDG opener and
      // failing quietly beats refusing on principle.
      expect(revealCommand('/var/log/nightcord', operatingSystem: 'freebsd'), [
        'xdg-open',
        '/var/log/nightcord',
      ]);
    });

    test('an empty path launches nothing', () async {
      // The UI passes whatever the core reported, and it reports an empty
      // string when there is no log file. Opening the working directory then
      // would be a small lie about where the logs are.
      await expectLater(revealDirectory(''), completes);
    });
  });
}
