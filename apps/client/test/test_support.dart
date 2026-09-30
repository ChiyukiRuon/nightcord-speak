// Shared helpers for the Dart tests.

import 'dart:async';

import 'package:nightcord_client/ffi/rust_client.dart';
import 'package:nightcord_client/models/events.dart';

/// Subscribes to [client] and waits for the named command to report back.
///
/// Everything goes through the stream rather than a direct poll: the core
/// releases each event exactly once, so a second reader would steal the answer.
Future<CommandResult> awaitCommand(
  RustClient client,
  String command, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final completer = Completer<CommandResult>();
  late StreamSubscription<FfiEvent> subscription;

  subscription = client.events.listen((event) {
    if (event is CommandResultEvent &&
        event.result.command == command &&
        !completer.isCompleted) {
      completer.complete(event.result);
    }
  });

  try {
    return await completer.future.timeout(
      timeout,
      onTimeout: () => throw TimeoutException('the core never answered `$command`'),
    );
  } finally {
    await subscription.cancel();
  }
}
