// The microphone gain slider's curve, shared by the two places that draw it.
//
// The stored value is decibels (`AudioSettings.inputGainDb`) and the range runs
// to -200 dB, which is silence. Drawing that range linearly would spend most of
// the travel below the threshold of hearing — the slider would be a mute switch
// with a long, dead approach — so the *audible* range is what fills the travel,
// and the bottom position alone means silence.
//
// The two functions here are inverses of each other, which is what the tests
// pin: the settings page and the voice bar's flyout must not disagree about
// where a value sits on the slider.

import '../models/settings.dart';

/// The quietest gain the slider still treats as a level rather than as silence.
///
/// Below this nothing is audible on ordinary equipment, so everything under it
/// collapses into the silent position.
const double gainMinAudibleDb = -60.0;

/// Where the slider sits for a stored gain, `0.0..=1.0`.
double gainDbToSlider(double db) {
  if (db <= gainMinAudibleDb) return 0.0;
  return (db - gainMinAudibleDb) / (gainMaxDb - gainMinAudibleDb);
}

/// The gain a slider position means, in decibels.
///
/// The very bottom is silence rather than -60 dB: a slider that cannot reach
/// "off" is a slider someone has to open the settings page to mute with.
double gainSliderToDb(double position) {
  if (position <= 0.0) return gainSilenceDb;
  final db = gainMinAudibleDb + position * (gainMaxDb - gainMinAudibleDb);
  return db.clamp(gainMinAudibleDb, gainMaxDb);
}

/// The gain as the user reads it: `+0 dB`, `-12 dB`, or the silent label.
///
/// Whole decibels: a tenth of one is not a difference anyone can hear, and a
/// number that flickers while dragging reads as noise.
String formatGainDb(double db, {required String silentLabel}) {
  if (db <= gainMinAudibleDb) return silentLabel;
  final rounded = db.round();
  return rounded > 0 ? '+$rounded dB' : '$rounded dB';
}
