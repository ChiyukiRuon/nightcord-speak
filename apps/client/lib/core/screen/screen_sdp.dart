/// Native SDKs may return the original SDP without gathered ICE candidates.
/// Attach each route to its media section, preserving BUNDLE and audio/video.
///
/// Under BUNDLE the same routes must not be repeated in every section, and the
/// native description repeats them: 26 candidates measured twice — once in the
/// video section, once in the audio one — costing ~4.4 KB of a ~9.4 KB offer,
/// which is what pushed a two-track share over the server's command ceiling
/// (probed 2026-10-08; the whole respond was dropped silently past it). The
/// standard takes the routes from the bundled transport's own section, so the
/// first copy is the one that stays. Without a BUNDLE group, identical lines in
/// different sections are separate transports' routes and must survive.
String withScreenCandidates(String sdp, List<Map<String, dynamic>> candidates) {
  final header = <String>[];
  final sections = <List<String>>[];
  for (final line in sdp.split(RegExp(r'\r?\n'))) {
    if (line.isEmpty) continue;
    if (line.startsWith('m=')) sections.add([]);
    (sections.isEmpty ? header : sections.last).add(line);
  }
  for (final candidate in candidates) {
    final value = (candidate['candidate'] as String).trim();
    final attribute = value.startsWith('a=') ? value : 'a=$value';
    if (!attribute.startsWith('a=candidate:')) continue;
    var index = sections.indexWhere(
      (s) => s.contains('a=mid:${candidate['mid']}'),
    );
    if (index < 0) index = candidate['line'] as int? ?? -1;
    if (index < 0 || index >= sections.length) continue;
    final section = sections[index];
    if (!section.contains(attribute)) {
      final end = section.indexOf('a=end-of-candidates');
      section.insert(end < 0 ? section.length : end, attribute);
    }
  }
  // Under BUNDLE every route travels through the bundle's own transport, so
  // the copies the native puts in the later sections are pure weight — 26
  // routes duplicated once measured 4.4 KB, which is what pushed a two-track
  // offer past the server's command ceiling (2026-10-08). A receiver reads the
  // routes from the bundled transport's own section, which is the first one;
  // anything dropped that the first section does not carry is still trickled
  // afterwards.
  final bundled = header.any((line) => line.startsWith('a=group:BUNDLE'));
  final firstHasCandidates =
      sections.isNotEmpty &&
      sections.first.any((line) => line.startsWith('a=candidate'));
  if (bundled && firstHasCandidates) {
    for (final section in sections.skip(1)) {
      section.removeWhere((line) => line.startsWith('a=candidate'));
    }
  }
  return '${[...header, for (final section in sections) ...section].join('\r\n')}\r\n';
}
