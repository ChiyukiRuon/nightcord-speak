import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Keeps network estimates separate from the encoder's quality adaptation.
/// Only named metrics are logged: raw reports contain ICE addresses and URLs.
class ScreenDiagnostics {
  final _previous = <String, ({DateTime at, num bytes})>{};

  List<String> sample(List<StatsReport> reports, DateTime now) {
    final byId = {for (final report in reports) report.id: report};
    final lines = <String>[];
    final selectedPairs = <String>{};
    for (final report in reports) {
      if (report.type == 'transport') {
        final pair = report.values['selectedCandidatePairId'];
        if (pair is String) selectedPairs.add(pair);
      }
    }
    for (final report in reports) {
      final v = report.values;
      final kind = v['kind'] ?? v['mediaType'];
      if (report.type == 'outbound-rtp' && kind == 'video') {
        final bytes = v['bytesSent'];
        final before = _previous[report.id];
        num? sentBps;
        if (bytes is num) {
          final elapsed = before == null
              ? 0
              : now.difference(before.at).inMicroseconds;
          if (before != null && elapsed > 0 && bytes >= before.bytes) {
            sentBps = ((bytes - before.bytes) * 8000000 / elapsed).round();
          }
          _previous[report.id] = (at: now, bytes: bytes);
        }
        lines.add(
          'out-video sentBps=${sentBps ?? 'unknown'} '
          '${_numbers(v, const ['targetBitrate', 'bytesSent', 'packetsSent', 'retransmittedPacketsSent', 'framesEncoded', 'qpSum', 'totalEncodeTime', 'nackCount', 'pliCount'])}',
        );
      } else if (report.type == 'media-source' && kind == 'video') {
        lines.add(
          'source-video ${_numbers(v, const ['width', 'height', 'frames', 'framesPerSecond'])}',
        );
      } else if (report.type == 'remote-inbound-rtp' && kind == 'video') {
        lines.add(
          'remote-video ${_numbers(v, const ['packetsLost', 'fractionLost', 'roundTripTime', 'roundTripTimeMeasurements', 'jitter'])}',
        );
      } else if (report.type == 'candidate-pair' &&
          (selectedPairs.contains(report.id) || v['selected'] == true)) {
        final local = byId[v['localCandidateId']]?.values;
        final remote = byId[v['remoteCandidateId']]?.values;
        lines.add(
          'route local=${_candidateType(local)} remote=${_candidateType(remote)} '
          'protocol=${_protocol(local)} '
          '${_numbers(v, const ['availableOutgoingBitrate', 'currentRoundTripTime', 'bytesSent', 'bytesReceived'])}',
        );
      }
    }
    _previous.removeWhere((id, _) => !byId.containsKey(id));
    return lines;
  }

  static String _numbers(Map<dynamic, dynamic> values, List<String> keys) =>
      keys
          .map((key) {
            final value = values[key];
            return '$key=${value is num ? value : 'unknown'}';
          })
          .join(' ');

  static String _candidateType(Map<dynamic, dynamic>? values) {
    final value = values?['candidateType'];
    return const {'host', 'srflx', 'prflx', 'relay'}.contains(value)
        ? value as String
        : 'unknown';
  }

  static String _protocol(Map<dynamic, dynamic>? values) {
    final value = values?['protocol'];
    return const {'udp', 'tcp'}.contains(value) ? value as String : 'unknown';
  }
}
