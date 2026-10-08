import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:nightcord_client/core/screen/screen_diagnostics.dart';

StatsReport _report(String id, String type, Map<String, dynamic> values) =>
    StatsReport(id, type, 0, values);

void main() {
  test(
    'separates sent bitrate, encoder target, source and network estimate',
    () {
      // A bandwidth label alone hid whether a LAN share hit the cap or congestion.
      final diagnostics = ScreenDiagnostics();
      final start = DateTime.utc(2026);
      List<StatsReport> reports(int bytes) => [
        _report('video', 'outbound-rtp', {
          'kind': 'video',
          'bytesSent': bytes,
          'targetBitrate': 3000000,
        }),
        _report('source', 'media-source', {
          'kind': 'video',
          'width': 3024,
          'height': 1964,
        }),
        _report('feedback', 'remote-inbound-rtp', {
          'kind': 'video',
          'packetsLost': 12,
          'roundTripTime': 0.02,
        }),
        _report('transport', 'transport', {'selectedCandidatePairId': 'pair'}),
        _report('pair', 'candidate-pair', {
          'localCandidateId': 'local',
          'remoteCandidateId': 'remote',
          'availableOutgoingBitrate': 15000000,
          'currentRoundTripTime': 0.01,
        }),
        _report('local', 'local-candidate', {
          'candidateType': 'host',
          'protocol': 'udp',
          'address': 'private-address',
          'url': 'private-url',
          'usernameFragment': 'private-credential',
        }),
        _report('remote', 'remote-candidate', {'candidateType': 'srflx'}),
        _report('unused', 'candidate-pair', {'availableOutgoingBitrate': 999}),
      ];
      expect(
        diagnostics.sample(reports(1000), start).first,
        contains('sentBps=unknown'),
      );
      final lines = diagnostics.sample(
        reports(2501000),
        start.add(const Duration(seconds: 10)),
      );
      final text = lines.join('\n');
      expect(text, contains('sentBps=2000000'));
      expect(text, contains('targetBitrate=3000000'));
      expect(text, contains('source-video width=3024 height=1964'));
      expect(text, contains('packetsLost=12'));
      expect(text, contains('local=host remote=srflx protocol=udp'));
      expect(text, contains('availableOutgoingBitrate=15000000'));
      expect(text, isNot(contains('availableOutgoingBitrate=999')));
      expect(text, isNot(contains('private-')));
    },
  );

  test(
    'missing metrics and restarted counters are unknown rather than zero',
    () {
      final diagnostics = ScreenDiagnostics();
      final start = DateTime.utc(2026);
      List<StatsReport> reports(int bytes) => [
        _report('video', 'outbound-rtp', {
          'mediaType': 'video',
          'bytesSent': bytes,
        }),
      ];
      diagnostics.sample(reports(1000), start);
      final restarted = diagnostics
          .sample(reports(10), start.add(const Duration(seconds: 10)))
          .single;
      expect(restarted, contains('sentBps=unknown'));
      expect(restarted, contains('targetBitrate=unknown'));
      diagnostics.sample([], start);
      expect(
        diagnostics.sample(reports(1000), start).single,
        contains('sentBps=unknown'),
      );
    },
  );
}
