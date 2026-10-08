// Compile alongside Runner/NightcordSystemAudioDevice.swift and WebRTC.framework.
// Regression: engine startup succeeded but the hardware route could follow
// the OS default. Create a temporary aggregate output, change the default,
// assert the actual route, then restore the original default and destroy it.
import Foundation
import CoreAudio

@main
struct ScreenOutputSmoke {
  struct Failure: Error { let reason: String }
  static func check(_ value: Bool, _ reason: String) throws {
    if !value { throw Failure(reason: reason) }
  }
  static func defaultOutput() throws -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
      &address, 0, nil, &size, &id) == noErr, "read default")
    return id
  }
  static func setDefault(_ id: AudioDeviceID) throws {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var value = id
    try check(AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),
      &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value) == noErr, "set default")
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
  }
  static func main() throws {
    guard #available(macOS 13.0, *) else { return }
    let device = NightcordSystemAudioDevice()
    let original = try defaultOutput()
    try check(device.setOutputDevice(named: "BuiltInSpeakerDevice"), "select built-in")
    try check(device.initializePlayout(), "initialize")
    try check(device.startPlayout(), "start")
    let builtIn = device.activeOutputDeviceID
    print("original=\(original) builtIn=\(builtIn)")
    defer { _ = device.stopPlayout() }
    let description: [String: Any] = [
      kAudioAggregateDeviceNameKey: "Nightcord output regression",
      kAudioAggregateDeviceUIDKey: "nightcord-output-regression-\(UUID().uuidString)",
      kAudioAggregateDeviceIsPrivateKey: false,
      kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: "BuiltInSpeakerDevice"]],
      kAudioAggregateDeviceMainSubDeviceKey: "BuiltInSpeakerDevice",
    ]
    var alternate = AudioDeviceID(0)
    try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &alternate) == noErr,
      "create alternate output")
    defer {
      try? setDefault(original)
      AudioHardwareDestroyAggregateDevice(alternate)
    }
    for _ in 0..<3 {
      // A named output must stay pinned when the OS default changes.
      try setDefault(alternate)
      print("alternate=\(alternate) system=\(try defaultOutput()) namedActual=\(device.activeOutputDeviceID)")
      try check(device.activeOutputDeviceID == builtIn, "named output followed OS default")
      try check(device.setOutputDevice(named: nil), "select default")
      print("defaultActual=\(device.activeOutputDeviceID) expected=\(alternate)")
      try check(device.activeOutputDeviceID == (try defaultOutput()), "default did not resolve system: actual=\(device.activeOutputDeviceID) alternate=\(alternate) system=\(try defaultOutput()) original=\(original)")
      try setDefault(original)
      try check(device.activeOutputDeviceID == original, "default did not follow OS change")
      try check(device.setOutputDevice(named: "Nightcord output regression"), "select alternate explicitly")
      try check(device.activeOutputDeviceID == alternate, "explicit alternate was ignored")
      try setDefault(alternate)
      try setDefault(original)
      try check(device.activeOutputDeviceID == alternate, "explicit alternate followed OS default")
      try check(device.setOutputDevice(named: "BuiltInSpeakerDevice"), "return to built-in")
      try check(!device.setOutputDevice(named: "nightcord-missing-output"), "missing device accepted")
      try check(device.activeOutputDeviceID == builtIn, "failed selection lost old output")
    }
    try check(device.stopPlayout(), "stop")
    try check(device.startPlayout(), "restart")
    print("PASS: named output stays pinned; default follows OS; missing output recovers")
  }
}
