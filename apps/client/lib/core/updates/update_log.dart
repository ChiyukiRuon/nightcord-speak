import '../platform/services.dart';

typedef UpdateLogSink = void Function(String level, String message);

/// Diagnostics must neither interrupt an update nor expose signed CDN URLs.
class UpdateLogger {
  const UpdateLogger({this.sink = logToCore});
  final UpdateLogSink sink;

  void call(String level, String message) {
    final sanitized = message.replaceAll(
      RegExp(r'https?://[^\s]+', caseSensitive: false),
      '<url omitted>',
    );
    final bounded = sanitized.length > 4096
        ? '${sanitized.substring(0, 4096)} [truncated]'
        : sanitized;
    try {
      sink(level, 'desktop update: $bounded');
    } catch (_) {
      // A failed diagnostic sink must not change update behavior.
    }
  }
}

const updateLogger = UpdateLogger();
