import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/models/screen_options.dart';
import 'package:nightcord_client/models/settings.dart';

void main() {
  test('a preset is found by its numbers, and anything else is custom', () {
    // The preset is never stored — it is worked out from the numbers — so this
    // is the only thing standing between "the reference client's 720" and a
    // table that has quietly drifted away from it.
    expect(
      ScreenPreset.matching(720, 30, 2500),
      isNotNull,
      reason: 'the default settings must land on a preset',
    );
    expect(ScreenPreset.matching(720, 30, 2500)!.detail, isFalse);
    // The one preset that asks the encoder to give up frame rate rather than
    // sharpness, because it is for slides and code.
    expect(ScreenPreset.matching(0, 5, 3000)!.detail, isTrue);
    // One number off is the user's own choice, not a preset.
    expect(ScreenPreset.matching(720, 30, 2600), isNull);
  });

  test('the settings defaults are the reference starting preset', () {
    // 720p30 at 2500 kbps is what the official client opens its share dialog
    // with, so an untouched install produces the same stream it would.
    const screen = ScreenSettings();
    expect(ScreenPreset.matching(screen.height, screen.fps, screen.videoBitrateKbps), isNotNull);
  });

  test('the JSON is the shape the core reads', () {
    // The same payload is pinned on the Rust side, in `ts-model`'s
    // `the_front_ends_json_is_the_shape_this_module_reads`. Both directions are
    // asserted because neither side's own tests cross the boundary, and a
    // rename that only one of them followed is a share that starts and then
    // silently does nothing.
    const options = ScreenOptions(
      source: ScreenSourceKind.window,
      height: 1080,
      fps: 30,
      videoBitrateKbps: 4000,
      audio: true,
      audioBitrateKbps: 128,
      access: ScreenAccess.private,
      viewerLimit: 4,
      mode: ScreenMode.p2p,
      detail: true,
    );

    expect(options.toJson(), {
      'source': 'window',
      'height': 1080,
      'fps': 30,
      'video_bitrate_kbps': 4000,
      'audio': true,
      'audio_bitrate_kbps': 128,
      'access': 'private',
      'viewer_limit': 4,
      'mode': 'p2p',
      'detail': true,
    });
    expect(ScreenOptions.fromJson(options.toJson()).toJson(), options.toJson());
  });

  test('a word this build does not know costs one preference, not the share', () {
    // The core is the authority and refuses what it cannot encode. Falling back
    // here means the user gets that refusal, instead of a crash with less to
    // say about what went wrong.
    final options = ScreenOptions.fromJson(const {
      'source': 'hologram',
      'height': 720,
      'fps': 30,
      'video_bitrate_kbps': 2500,
      'audio': false,
      'audio_bitrate_kbps': 128,
      'access': 'acquaintances',
      'viewer_limit': 0,
      'mode': 'carrier-pigeon',
    });
    expect(options.source, ScreenSourceKind.screen);
    expect(options.access, ScreenAccess.public);
    expect(options.mode, ScreenMode.p2p);
  });
}
