// What the macOS system picker hands back, shared by both service worlds.
//
// Its own file rather than living in one of the two `services_*`
// implementations: the conditional export swaps one for the other, and a name
// that only existed on the native side would not typecheck on the web.

/// One choice from the system's screen picker.
class PickedScreenSource {
  const PickedScreenSource({
    required this.id,
    required this.name,
    required this.kind,
  });

  /// What the capture backend records — the same spelling its own source
  /// list uses (a CGWindowID or CGDirectDisplayID as a decimal string).
  final String id;

  final String name;

  /// `"window"` or `"screen"`.
  final String kind;
}
