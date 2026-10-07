/// Native SDKs may return the original SDP without gathered ICE candidates.
/// Attach each route to its media section, preserving BUNDLE and audio/video.
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
  return '${[...header, for (final section in sections) ...section].join('\r\n')}\r\n';
}
