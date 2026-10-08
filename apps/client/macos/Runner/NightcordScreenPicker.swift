// Presents the system's own screen-sharing picker and reports the choice.
//
// The picker is macOS's UI (SCContentSharingPicker) — the same control the
// official client and every conferencing app show — so the source list is the
// system's, not a grid of our own. What the user picks arrives as an
// SCContentFilter: its id goes back to Dart for the capture backend, and the
// filter itself goes to the audio device, which captures that same content's
// sound.
//
// The conformance lives in an availability-scoped extension: the picker needs
// macOS 14, the app does not, and `isAvailable` is how callers tell.
import Foundation
import ScreenCaptureKit

/// One pick, in the vocabulary the Dart side speaks.
struct PickedScreenSource {
  /// The id the capture backend recognises, which is the CGWindowID for a
  /// window and the CGDirectDisplayID for a display, as a decimal string —
  /// the same spelling the plugin's own source list uses.
  let id: String
  let name: String
  /// `"window"` or `"screen"`.
  let kind: String
}

final class NightcordScreenPicker: NSObject {
  static let shared = NightcordScreenPicker()

  private var completion: ((PickedScreenSource?) -> Void)?
  private var activated = false

  /// Whether the system picker exists on this machine at all.
  static var isAvailable: Bool {
    if #available(macOS 14.0, *) { return true }
    return false
  }

  /// Shows the system picker; completion gets the choice, or nil when the
  /// user cancelled (or the picker failed to appear).
  func pick(completion: @escaping (PickedScreenSource?) -> Void) {
    guard #available(macOS 14.0, *) else {
      completion(nil)
      return
    }
    self.completion = completion
    let picker = SCContentSharingPicker.shared
    if !activated {
      activated = true
      picker.isActive = true
      picker.add(self)
    }
    picker.present()
  }

  fileprivate func finish(_ picked: PickedScreenSource?) {
    let completion = self.completion
    self.completion = nil
    completion?(picked)
  }
}

@available(macOS 14.0, *)
extension NightcordScreenPicker: SCContentSharingPickerObserver {
  func contentSharingPicker(
    _ picker: SCContentSharingPicker,
    didUpdateWith filter: SCContentFilter,
    for stream: SCStream?
  ) {
    let picked = describe(filter)
    if let picked {
      // The audio device captures what the video side records; hand it the
      // same filter rather than re-deriving it from the id.
      NightcordSystemAudioDevice.shared.setCaptureFilter(filter)
    }
    finish(picked)
  }

  func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
    finish(nil)
  }

  func contentSharingPickerStartDidFailWithError(_ error: Error) {
    finish(nil)
  }

  /// What the filter says, in our words.
  ///
  /// includedWindows/includedDisplays are the only way to learn what the user
  /// picked and they need 15.2; on anything older the pick happens but cannot
  /// be described, so an undescribable pick reads as a cancel — the channel
  /// turns nil into "the user backed out".
  private func describe(_ filter: SCContentFilter) -> PickedScreenSource? {
    guard #available(macOS 15.2, *) else { return nil }
    if let window = filter.includedWindows.first {
      return PickedScreenSource(
        id: String(window.windowID),
        name: window.title ?? "Window",
        kind: "window"
      )
    }
    if let display = filter.includedDisplays.first {
      return PickedScreenSource(
        id: String(display.displayID),
        name: "Display \(display.displayID)",
        kind: "screen"
      )
    }
    return nil
  }
}
