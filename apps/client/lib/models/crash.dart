// What the previous runs left behind, as the core's neighbour crate sees it
// (`ts-crash` → `docs/crash.md`).

/// The crash evidence waiting on disk.
///
/// Plain data: the directory, how much is in it, and the one fact the banner
/// acts on — whether a previous run's process died without a clean exit.
class CrashStatus {
  const CrashStatus({
    required this.available,
    required this.abnormal,
    required this.notes,
    required this.directory,
  });

  /// False on platforms with no application data directory (Android, iOS),
  /// where the evidence has nowhere to live.
  final bool available;

  /// A previous run left a marker behind and its process is gone: it did not
  /// exit cleanly.
  final bool abnormal;

  /// How many crash notes are waiting to be looked at.
  final int notes;

  /// Where the evidence lives; empty when [available] is false.
  final String directory;

  /// Reads the core's answer.
  ///
  /// Type-checks rather than casts, which is stricter than the sibling models:
  /// this one is read at the very start of a launch, and it crosses the ABI
  /// from a library that might not be the one this build was compiled against.
  /// A malformed answer has to degrade to "nothing to report", never to a
  /// throw before the first frame.
  factory CrashStatus.fromJson(Map<String, dynamic> json) => CrashStatus(
    available: json['available'] is bool ? json['available'] as bool : false,
    abnormal: json['abnormal'] is bool ? json['abnormal'] as bool : false,
    notes: json['notes'] is int ? json['notes'] as int : 0,
    directory: json['directory'] is String ? json['directory'] as String : '',
  );

  /// The default when the core cannot be asked at all.
  static const CrashStatus none = CrashStatus(
    available: false,
    abnormal: false,
    notes: 0,
    directory: '',
  );

  /// Whether the previous session is worth telling the user about.
  ///
  /// Only an abnormal exit raises the banner. Crash notes on their own do not:
  /// a worker panic already put an error in front of the user while it
  /// happened, and a marker without a dead process is just this run's.
  bool get shouldNotify => available && abnormal;
}
