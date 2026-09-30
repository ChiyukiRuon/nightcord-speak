// Locating and loading the Rust core.

import 'dart:ffi';
import 'dart:io';

import 'bindings.dart';

/// Raised when the shared library cannot be found.
class NativeLibraryNotFound implements Exception {
  NativeLibraryNotFound(this.tried);

  /// Every path that was attempted, in order. Shown to the developer because
  /// "DLL not found" is otherwise a guessing game.
  final List<String> tried;

  @override
  String toString() =>
      'Could not load the Nightcord core.\n'
      'Tried:\n${tried.map((p) => '  - $p').join('\n')}\n'
      'Build it with `cargo build -p ts-ffi`, or run through '
      '`flutter run -d windows` so the CMake hook copies it next to the '
      'executable.';
}

/// Loads and binds the Rust core.
class NativeLibrary {
  NativeLibrary._();

  static NightcordBindings? _bindings;

  /// The bound functions, loading the library on first use.
  ///
  /// Lazy so that merely importing this file — during a widget test, say — does
  /// not require the library to exist.
  static NightcordBindings load() => _bindings ??= NightcordBindings(_open());

  /// Whether the library has already been loaded.
  static bool get isLoaded => _bindings != null;

  /// Discards the cached bindings, for tests.
  static void reset() => _bindings = null;

  /// The platform's name for the shared library.
  static String get libraryFileName {
    if (Platform.isWindows) return 'nightcord_ffi.dll';
    if (Platform.isMacOS) return 'libnightcord_ffi.dylib';
    return 'libnightcord_ffi.so';
  }

  static DynamicLibrary _open() {
    final name = libraryFileName;
    final tried = <String>[];

    for (final candidate in [name, ..._developmentPaths(name)]) {
      tried.add(candidate);
      try {
        return DynamicLibrary.open(candidate);
      } on ArgumentError {
        // Not there; try the next. Only the final failure is reported.
        continue;
      }
    }

    throw NativeLibraryNotFound(tried);
  }

  /// Where the library lands when built from source.
  ///
  /// `flutter run` copies it beside the executable, which the bare name finds.
  /// `flutter test` runs from `apps/client` with no such copy, so the Cargo
  /// output directories are searched too.
  static Iterable<String> _developmentPaths(String name) sync* {
    // Walk up looking for the workspace root: `apps/client` is two levels down.
    var directory = Directory.current;
    for (var depth = 0; depth < 4; depth++) {
      for (final profile in ['debug', 'release']) {
        yield '${directory.path}/target/$profile/$name';
      }
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
  }
}
