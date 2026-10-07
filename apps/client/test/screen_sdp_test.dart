import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/core/screen/screen_sdp.dart';

void main() {
  test('gathered candidates reach their media section once, before its end', () {
    // Native getLocalDescription omitted routes, flooding one command per route.
    const sdp =
        'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=mid:a\r\n'
        'm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=mid:v\r\na=end-of-candidates\r\n';
    final routes = [
      {'candidate': 'candidate:video', 'mid': 'v', 'line': 0},
      {'candidate': 'candidate:audio', 'mid': 'missing', 'line': 0},
      {'candidate': 'candidate:video', 'mid': 'v', 'line': 1},
    ];
    final result = withScreenCandidates(sdp, routes);
    expect(result, contains('a=mid:a\r\na=candidate:audio\r\nm=video'));
    expect(
      result,
      contains('a=mid:v\r\na=candidate:video\r\na=end-of-candidates'),
    );
    expect(withScreenCandidates(result, routes), result);
  });
  test('unknown media routes leave SDP intact for trickle fallback', () {
    const sdp = 'v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=mid:v\r\n';
    expect(
      withScreenCandidates(sdp, [
        {'candidate': 'candidate:route', 'mid': 'missing', 'line': 3},
      ]),
      sdp,
    );
  });
}
