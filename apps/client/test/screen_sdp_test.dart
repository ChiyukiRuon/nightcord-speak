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

  test('a bundled transport carries its routes once, in the first section', () {
    // The native description repeated every gathered candidate in every media
    // section — not always byte-identical, hence "everything after the first
    // section" rather than an equality filter. 26 routes twice measured 4.4 KB
    // of a 9.4 KB offer, and past the server's command ceiling the whole
    // respond vanished (2026-10-08).
    const sdp =
        'v=0\r\na=group:BUNDLE 0 1\r\n'
        'm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=mid:0\r\na=candidate:route\r\n'
        'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=mid:1\r\na=candidate:route\r\n'
        'a=candidate:variant\r\n';
    final result = withScreenCandidates(sdp, const []);
    expect('a=candidate:'.allMatches(result).length, 1);
    expect(result, isNot(contains('a=candidate:variant')));
    expect(
      result.indexOf('a=candidate:route') < result.indexOf('m=audio'),
      isTrue,
    );
  });

  test('without a bundle group each section keeps its own routes', () {
    // Identical lines in two sections of a non-bundled SDP are two separate
    // transports' routes — the same address used twice is legitimate.
    const sdp =
        'v=0\r\n'
        'm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=mid:0\r\na=candidate:route\r\n'
        'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=mid:1\r\na=candidate:route\r\n';
    final result = withScreenCandidates(sdp, const []);
    expect('a=candidate:route'.allMatches(result).length, 2);
  });
}
