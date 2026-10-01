// The microphone gain slider's curve.
//
// Two widgets draw this slider — the settings dialog and the voice bar's
// flyout — and they must agree about where a stored decibel value sits and
// what a position means. These are the functions they share, so this is where
// that agreement is pinned.

import 'package:flutter_test/flutter_test.dart';
import 'package:nightcord_client/models/settings.dart';
import 'package:nightcord_client/util/gain.dart';

void main() {
  group('the slider curve', () {
    test('unity sits near the top, where a volume control belongs', () {
      final position = gainDbToSlider(0.0);
      expect(position, greaterThan(0.8), reason: '0 dB is nearly full travel');
      expect(position, lessThan(1.0));
      expect(gainSliderToDb(position), closeTo(0.0, 1e-6));
    });

    test('the top of the travel is the loudest gain', () {
      expect(gainSliderToDb(1.0), closeTo(gainMaxDb, 1e-6));
      expect(gainDbToSlider(gainMaxDb), closeTo(1.0, 1e-6));
    });

    test('the bottom of the travel is silence, not a quiet signal', () {
      // The whole point of the curved travel: the last millimetre is the mute
      // switch, and it stores the same value the core reads as silence.
      expect(gainSliderToDb(0.0), gainSilenceDb);
      expect(gainDbToSlider(gainSilenceDb), 0.0);
    });

    test('anything quieter than audible is drawn at the silent position', () {
      // Hand-edited files, and values stored by an older build, can be any
      // number in the range. They must not land off the end of the slider.
      for (final db in [-60.0, -70.0, -100.0, -200.0]) {
        expect(gainDbToSlider(db), 0.0, reason: '$db dB should read as silent');
      }
      expect(formatGainDb(-100.0, silentLabel: 'Silent'), 'Silent');
    });

    test('the two directions are inverses across the audible range', () {
      // Everything strictly above the audible floor. -60 dB itself is *the*
      // floor, which is also the silent position, so it comes back as silence
      // by design rather than by arithmetic — see the test above.
      for (final db in [-59.9, -40.0, -12.5, 0.0, 3.0, 10.0]) {
        expect(
          gainSliderToDb(gainDbToSlider(db)),
          closeTo(db, 1e-6),
          reason: '$db dB did not survive the round trip',
        );
      }
    });

    test('a position outside the slider is pulled back into range', () {
      expect(gainSliderToDb(-0.5), gainSilenceDb);
      expect(gainSliderToDb(1.5), gainMaxDb);
    });

    test('the value is read in whole decibels, signed', () {
      // A tenth of a decibel is not a difference anyone can hear, and a number
      // that flickers while dragging reads as noise.
      // Unity is written without a sign: it is the reference the others are
      // measured against, and "+0" reads as a mistake.
      expect(formatGainDb(0.0, silentLabel: 'Silent'), '0 dB');
      expect(formatGainDb(0.4, silentLabel: 'Silent'), '0 dB');
      expect(formatGainDb(6.0, silentLabel: 'Silent'), '+6 dB');
      expect(formatGainDb(-12.0, silentLabel: 'Silent'), '-12 dB');
      expect(formatGainDb(-59.6, silentLabel: 'Silent'), '-60 dB');
      expect(formatGainDb(-60.0, silentLabel: 'Silent'), 'Silent');
    });
  });
}
