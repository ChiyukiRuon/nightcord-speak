// The WebRTC audio device that carries a shared screen's sound.
//
// Installed on the peer connection factory (see FlutterWebRTCPlugin's
// setCustomAudioDevice:), so the plugin builds its audio device module around
// this object: whatever `deliverRecordedData` is fed is what a screen share
// records, and anything a remote share sends us is played back through
// `getPlayoutData`. Screen sharing is the only thing this app uses WebRTC
// audio for — voice takes the Rust pipeline — so "the microphone" here means
// "the shared screen's audio, or silence".
//
// The audio itself comes from ScreenCaptureKit, started only while recording
// is on, and only for the source the system picker chose. What SCK hands over
// is converted from whatever format it actually produced (rate, channel
// count, float layout) to the 48 kHz interleaved S16 the ADM expects — the
// first version assumed 48 kHz Float32 and produced sound nobody could make
// out (2026-10-08), so the format is now read rather than presumed. The first
// buffer's format is also written to `screen-audio.log` next to the app's own
// log, where "it sounds wrong" can be answered with numbers.
import AVFoundation
import CoreAudio
import Foundation
import ScreenCaptureKit
import WebRTC

@available(macOS 13.0, *)
final class NightcordSystemAudioDevice: NSObject, RTCAudioDevice {
  static let shared = NightcordSystemAudioDevice()

  private static let sampleRate: Double = 48_000
  private static let channelCount: UInt32 = 2
  /// The recording side is mono on purpose: the ADM consumes one sample
  /// per frame for this device (the audio track was created mono), so
  /// stereo delivery was read at half rate — 24k samples a second reached
  /// the encoder under 48k timestamps and the receiver concealed the other
  /// half (2026-10-08: concealedSamples grew 24k/s, packets came at 25/s).
  private static let inputChannels: UInt32 = 1
  private static let framesPerDelivery = 480  // 10 ms at 48 kHz
  private static let bufferDuration: TimeInterval = 0.01

  private var delegate: RTCAudioDeviceDelegate?
  private var initialized = false
  private var playoutInitialized = false
  private var playing = false
  private var recordingInitialized = false
  private var recording = false

  // MARK: - Playout (remote share audio out to the speakers)

  private var outputQueue: AudioQueueRef?
  private let playoutLock = NSRecursiveLock()
  private let renderLock = NSLock()
  private var defaultOutputListener: AudioObjectPropertyListenerBlock?
  private var playoutSampleTime: Double = 0
  private var playoutList: UnsafeMutableAudioBufferListPointer?

  /// The output the playout engine renders to; nil is the system default.
  private var selectedOutput: String?

  /// Playout evidence: is the render callback running at all, and is
  /// anything non-silent coming out of the ADM when it does.
  private var firstRender = true
  private var renderFrames = 0
  private var renderPeak = 0
  private var outputDeviceID: AudioDeviceID = kAudioObjectUnknown

  deinit {
    if let queue = outputQueue { AudioQueueDispose(queue, true) }
    if let defaultOutputListener {
      var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
      AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
        &address, .main, defaultOutputListener)
    }
  }

  // MARK: - Recording (the shared screen's audio in)

  private let recordQueue = DispatchQueue(label: "nightcord.screen-audio.record")
  private var recordTimer: DispatchSourceTimer?
  private var deliverSampleTime: Double = 0
  private var deliverList: UnsafeMutableAudioBufferListPointer?

  /// Capture-side evidence: the exact PCM handed to the ADM, the first
  /// ~20 s of a run, plus one line per second of delivery statistics.
  private var wavHandle: FileHandle?
  private var wavFrames = 0
  private var wavFinalized = false
  private var deliveredFrames = 0
  private var underrunFrames = 0
  private var statsFrames = 0
  private static let wavFrameLimit = 48_000 * 20

  /// Interleaved S16 stereo, the format the delegate's block expects.
  private let ringLock = NSLock()
  private var ring = [Int16](repeating: 0, count: 96_000)  // one second
  private var ringRead = 0
  private var ringWrite = 0
  private var ringCount = 0

  private var captureFilter: SCContentFilter?
  private var captureStream: SCStream?
  private let captureQueue = DispatchQueue(label: "nightcord.screen-audio.capture")
  private var converter: AVAudioConverter?
  private var converterSourceFormat: AVAudioFormat?
  private var converterTargetFormat: AVAudioFormat?

  // MARK: - RTCAudioDevice state

  var deviceInputSampleRate: Double { Self.sampleRate }
  var inputIOBufferDuration: TimeInterval { Self.bufferDuration }
  var inputNumberOfChannels: Int { Int(Self.inputChannels) }
  var inputLatency: TimeInterval { Self.bufferDuration }
  var deviceOutputSampleRate: Double { Self.sampleRate }
  var outputIOBufferDuration: TimeInterval { Self.bufferDuration }
  var outputNumberOfChannels: Int { Int(Self.channelCount) }
  var outputLatency: TimeInterval { Self.bufferDuration }
  var isInitialized: Bool { initialized }
  var isPlayoutInitialized: Bool { playoutInitialized }
  var isPlaying: Bool { playing }
  var isRecordingInitialized: Bool { recordingInitialized }
  var isRecording: Bool { recording }

  /// Read back the hardware route rather than treating successful startup as
  /// proof that the explicitly selected device stayed selected.
  var activeOutputDeviceID: AudioDeviceID {
    guard let queue = outputQueue else { return kAudioObjectUnknown }
    var uid: CFString?
    var size = UInt32(MemoryLayout<CFString?>.size)
    let status = withUnsafeMutablePointer(to: &uid) {
      AudioQueueGetProperty(queue, kAudioQueueProperty_CurrentDevice, $0, &size)
    }
    guard status == noErr, let uid else { return kAudioObjectUnknown }
    return Self.findOutputDevice(named: uid as String) ?? kAudioObjectUnknown
  }

  func initialize(with delegate: RTCAudioDeviceDelegate) -> Bool {
    self.delegate = delegate
    initialized = true
    return true
  }

  func terminateDevice() -> Bool {
    _ = stopRecording()
    _ = stopPlayout()
    if let queue = outputQueue { AudioQueueDispose(queue, true) }
    outputQueue = nil
    playoutInitialized = false
    delegate = nil
    initialized = false
    return true
  }

  // MARK: - Playout

  func initializePlayout() -> Bool {
    playoutLock.lock()
    defer { playoutLock.unlock() }
    if outputQueue != nil { return true }
    return rebuildPlayout(resume: false)
  }

  /// Audio Queue binds directly to a device UID. AVAudioEngine can replace
  /// CurrentDevice after a system route change even when selection succeeded.
  private func rebuildPlayout(resume: Bool) -> Bool {
    var id = outputDeviceID
    if selectedOutput == nil {
      var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
      var size = UInt32(MemoryLayout<AudioDeviceID>.size)
      guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
        &address, 0, nil, &size, &id) == noErr else { return false }
    }
    guard let name = Self.deviceName(of: id, property: kAudioDevicePropertyDeviceUID)
    else { return false }
    var format = AudioStreamBasicDescription(
      mSampleRate: Self.sampleRate, mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
      mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
      mChannelsPerFrame: Self.channelCount, mBitsPerChannel: 16, mReserved: 0)
    var fresh: AudioQueueRef?
    let created = AudioQueueNewOutput(&format, { context, queue, buffer in
      guard let context else { return }
      Unmanaged<NightcordSystemAudioDevice>.fromOpaque(context).takeUnretainedValue()
        .renderPlayout(into: buffer, queue: queue)
    }, Unmanaged.passUnretained(self).toOpaque(), nil, nil, 0, &fresh)
    guard created == noErr, let fresh else {
      Self.writeDiagnostic("playout: queue creation failed status=\(created)")
      return false
    }
    var succeeded = false
    defer { if !succeeded { AudioQueueDispose(fresh, true) } }
    var uid: CFString = name as CFString
    let selected = withUnsafePointer(to: &uid) {
      AudioQueueSetProperty(fresh, kAudioQueueProperty_CurrentDevice,
        $0, UInt32(MemoryLayout<CFString>.size))
    }
    guard selected == noErr else {
      Self.writeDiagnostic("playout: queue selection failed uid=\(name) status=\(selected)")
      return false
    }
    // Three 10 ms buffers keep latency bounded. The queue handles hardware
    // sample-rate conversion without changing the ADM's 48 kHz PCM contract.
    for _ in 0..<3 {
      var buffer: AudioQueueBufferRef?
      guard AudioQueueAllocateBuffer(fresh, 480 * 4, &buffer) == noErr,
        let buffer else { return false }
      memset(buffer.pointee.mAudioData, 0, 480 * 4)
      buffer.pointee.mAudioDataByteSize = 480 * 4
      guard AudioQueueEnqueueBuffer(fresh, buffer, 0, nil) == noErr else { return false }
    }
    let previous = outputQueue
    if let previous { AudioQueuePause(previous) }
    if resume {
      let started = AudioQueueStart(fresh, nil)
      guard started == noErr else {
        Self.writeDiagnostic("playout: queue start failed status=\(started)")
        if let previous { AudioQueueStart(previous, nil) }
        return false
      }
    }
    outputQueue = fresh
    if let previous { AudioQueueDispose(previous, true) }
    succeeded = true
    playoutInitialized = true
    firstRender = true
    observeOutputChanges()
    Self.writeDiagnostic("playout: queue bound requested=\(selectedOutput ?? "default") uid=\(name) device=\(id) actual=\(activeOutputDeviceID) resumed=\(resume)")
    return true
  }

  private func observeOutputChanges() {
    guard defaultOutputListener == nil else { return }
    let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      guard let self else { return }
      self.playoutLock.lock()
      defer { self.playoutLock.unlock() }
      // Explicit UIDs stay pinned. Only a default selection follows the OS.
      if self.selectedOutput == nil, self.playoutInitialized {
        _ = self.rebuildPlayout(resume: self.playing)
      }
    }
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
      &address, .main, listener) == noErr { defaultOutputListener = listener }
  }

  func startPlayout() -> Bool {
    playoutLock.lock()
    defer { playoutLock.unlock() }
    guard let queue = outputQueue else { return false }
    let status = AudioQueueStart(queue, nil)
    guard status == noErr else {
      Self.writeDiagnostic("playout: queue start failed status=\(status)")
      return false
    }
    playing = true
    return true
  }

  func stopPlayout() -> Bool {
    playoutLock.lock()
    defer { playoutLock.unlock() }
    if let queue = outputQueue { AudioQueuePause(queue) }
    playing = false
    return true
  }

  @discardableResult
  func setOutputDevice(named name: String?) -> Bool {
    playoutLock.lock()
    defer { playoutLock.unlock() }
    let resolved = name.flatMap { Self.findOutputDevice(named: $0) }
    if let name, resolved == nil {
      Self.writeDiagnostic("output device not found: \(name); retaining the previous route")
      return false
    }
    let previous = outputDeviceID
    let previousName = selectedOutput
    selectedOutput = name
    outputDeviceID = resolved ?? kAudioObjectUnknown
    if playoutInitialized, !rebuildPlayout(resume: playing) {
      outputDeviceID = previous
      selectedOutput = previousName
      return false
    }
    return true
  }

  /// The CoreAudio device the voice engine meant, looked up by name.
  ///
  /// Two name properties are tried because CoreAudio answers both
  /// spellings — the canonical one (which is where the stored name comes
  /// from) and the localised one — and a loose match is still worth aiming
  /// at. No match at all leaves the system default in place.
  private static func findOutputDevice(named name: String) -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
    else { return nil }
    var ids = [AudioDeviceID](
      repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
    else { return nil }
    var loose: AudioDeviceID?
    for id in ids where hasOutputStreams(id) {
      var candidates: [String] = []
      // The raw C-string name (`BuiltInSpeakerDevice` and friends) and the
      // device UID (`74-77-86-7B-FB-1A:output` — what Bluetooth devices are
      // called) are the two spellings the stored names actually arrive in;
      // the friendly CF names are kept for anything a person typed.
      if let cname = Self.deviceCName(of: id) { candidates.append(cname) }
      for property: AudioObjectPropertySelector in [
        kAudioDevicePropertyDeviceUID,
        kAudioDevicePropertyDeviceNameCFString,
        kAudioObjectPropertyName,
      ] {
        if let friendly = Self.deviceName(of: id, property: property) {
          candidates.append(friendly)
        }
      }
      for deviceName in candidates {
        if deviceName == name { return id }
        if loose == nil, deviceName.contains(name) || name.contains(deviceName) {
          loose = id
        }
      }
    }
    return loose
  }

  /// The device's raw, unlocalised name (`kAudioDevicePropertyDeviceName`).
  private static func deviceCName(of id: AudioDeviceID) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceName,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var buffer = [CChar](repeating: 0, count: 256)
    var size = UInt32(buffer.count)
    let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &buffer)
    guard status == noErr else { return nil }
    return String(cString: buffer)
  }

  private static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams,
      mScope: kAudioObjectPropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
  }

  private static func deviceName(
    of id: AudioDeviceID, property: AudioObjectPropertySelector
  ) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: property,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var value: CFString?
    var size = UInt32(MemoryLayout<CFString?>.size)
    let status = withUnsafeMutablePointer(to: &value) {
      AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
    }
    guard status == noErr, let value else { return nil }
    return value as String
  }

  /// The queue and ADM both use interleaved S16 stereo, so no float-layout
  /// assumption or channel conversion is needed on the playback path.
  private func renderPlayout(into buffer: AudioQueueBufferRef, queue: AudioQueueRef) {
    // During a route handover the old queue's final callback can overlap the
    // new queue's first callback. Serialize access to the ADM and scratch PCM.
    renderLock.lock()
    defer { renderLock.unlock() }
    let frames = 480
    let list = playoutScratch(sampleCount: frames * 2)
    memset(list[0].mData!, 0, frames * 4)
    var flags = AudioUnitRenderActionFlags()
    var timestamp = AudioTimeStamp()
    timestamp.mSampleTime = playoutSampleTime
    timestamp.mFlags = .sampleTimeValid
    playoutSampleTime += Double(frames)
    if let delegate {
      _ = delegate.getPlayoutData(&flags, &timestamp, 0, UInt32(frames),
        UnsafeMutablePointer(mutating: list.unsafePointer))
    }
    memcpy(buffer.pointee.mAudioData, list[0].mData!, frames * 4)
    buffer.pointee.mAudioDataByteSize = UInt32(frames * 4)
    if firstRender {
      firstRender = false
      Self.writeDiagnostic("playout: first queue render frames=\(frames)")
    }
    renderFrames += frames
    let samples = list[0].mData!.assumingMemoryBound(to: Int16.self)
    for index in 0..<(frames * 2) { renderPeak = max(renderPeak, abs(Int(samples[index]))) }
    if renderFrames >= 48_000 * 5 {
      Self.writeDiagnostic("playout: 5s peak=\(renderPeak)")
      renderFrames = 0
      renderPeak = 0
    }
    AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
  }

  private func playoutScratch(sampleCount: Int) -> UnsafeMutableAudioBufferListPointer {
    let needed = sampleCount * MemoryLayout<Int16>.size
    if let list = playoutList, list[0].mDataByteSize >= UInt32(needed) {
      return list
    }
    if let old = playoutList {
      free(old[0].mData)
      free(UnsafeMutableRawPointer(mutating: old.unsafePointer))
    }
    let list = AudioBufferList.allocate(maximumBuffers: 1)
    list[0] = AudioBuffer(
      mNumberChannels: Self.channelCount,
      mDataByteSize: UInt32(needed),
      mData: malloc(needed)
    )
    playoutList = list
    return list
  }

  // MARK: - Recording

  /// What the system picker last chose. Nil means there is nothing to capture
  /// and recording delivers silence.
  func setCaptureFilter(_ filter: SCContentFilter?) {
    captureFilter = filter
    if recording {
      stopCaptureStream()
      startCaptureStream()
    }
  }

  func initializeRecording() -> Bool {
    recordingInitialized = true
    return true
  }

  func startRecording() -> Bool {
    guard recordingInitialized, !recording else { return recordingInitialized }
    recording = true
    openWav()
    if let delegate {
      Self.writeDiagnostic(
        "device: claimed rate=\(Self.sampleRate) inputChannels=\(Self.inputChannels) "
          + "admPreferredRate=\(delegate.preferredInputSampleRate) "
          + "admPreferredBuffer=\(delegate.preferredInputIOBufferDuration)")
    }
    deliveredFrames = 0
    underrunFrames = 0
    statsFrames = 0
    startCaptureStream()
    let timer = DispatchSource.makeTimerSource(queue: recordQueue)
    timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(1))
    timer.setEventHandler { [weak self] in self?.deliverRecorded() }
    timer.resume()
    recordTimer = timer
    return true
  }

  func stopRecording() -> Bool {
    closeWav()
    recordTimer?.cancel()
    recordTimer = nil
    stopCaptureStream()
    ringLock.lock()
    ringCount = 0
    ringRead = 0
    ringWrite = 0
    ringLock.unlock()
    recording = false
    return true
  }

  /// One 10 ms delivery to the ADM; underruns are padded with silence.
  private func deliverRecorded() {
    guard let delegate else { return }
    let frames = Self.framesPerDelivery
    let sampleCount = frames * Int(Self.inputChannels)
    let list = deliverScratch(sampleCount: sampleCount)
    let destination = list[0].mData!.assumingMemoryBound(to: Int16.self)
    let got = ringRead(into: destination, count: sampleCount)
    if got < sampleCount {
      memset(destination + got, 0, (sampleCount - got) * MemoryLayout<Int16>.size)
    }
    if let handle = wavHandle, wavFrames < Self.wavFrameLimit {
      handle.write(Data(bytes: destination, count: sampleCount * MemoryLayout<Int16>.size))
      wavFrames += frames
    }
    deliveredFrames += frames
    if got < sampleCount {
      underrunFrames += (sampleCount - got) / Int(Self.channelCount)
    }
    statsFrames += frames
    if statsFrames >= 48_000 {
      statsFrames = 0
      Self.writeDiagnostic(
        "delivering: totalFrames=\(deliveredFrames) underrunFrames=\(underrunFrames) "
          + "wavFrames=\(wavFrames)")
    }
    var flags = AudioUnitRenderActionFlags()
    var timestamp = AudioTimeStamp()
    timestamp.mSampleTime = deliverSampleTime
    timestamp.mFlags = .sampleTimeValid
    deliverSampleTime += Double(frames)
    _ = delegate.deliverRecordedData(
      &flags,
      &timestamp,
      0,
      UInt32(frames),
      list.unsafePointer,
      nil,
      nil
    )
  }

  private func deliverScratch(sampleCount: Int) -> UnsafeMutableAudioBufferListPointer {
    let needed = sampleCount * MemoryLayout<Int16>.size
    if let list = deliverList, list[0].mDataByteSize >= UInt32(needed) {
      return list
    }
    if let old = deliverList {
      free(old[0].mData)
      free(UnsafeMutableRawPointer(mutating: old.unsafePointer))
    }
    let list = AudioBufferList.allocate(maximumBuffers: 1)
    list[0] = AudioBuffer(
      mNumberChannels: Self.inputChannels,
      mDataByteSize: UInt32(needed),
      mData: malloc(needed)
    )
    deliverList = list
    return list
  }

  private func ringAppend(_ samples: UnsafePointer<Int16>, count: Int) {
    ringLock.lock()
    defer { ringLock.unlock() }
    for index in 0..<count {
      ring[ringWrite] = samples[index]
      ringWrite = (ringWrite + 1) % ring.count
      if ringCount == ring.count {
        ringRead = (ringRead + 1) % ring.count
      } else {
        ringCount += 1
      }
    }
  }

  private func ringRead(into destination: UnsafeMutablePointer<Int16>, count: Int) -> Int {
    ringLock.lock()
    defer { ringLock.unlock() }
    let available = min(count, ringCount)
    for index in 0..<available {
      destination[index] = ring[ringRead]
      ringRead = (ringRead + 1) % ring.count
    }
    ringCount -= available
    return available
  }

  // MARK: - ScreenCaptureKit audio

  private func startCaptureStream() {
    guard captureStream == nil, let filter = captureFilter else { return }
    let configuration = SCStreamConfiguration()
    configuration.capturesAudio = true
    configuration.sampleRate = Int(Self.sampleRate)
    configuration.channelCount = Int(Self.channelCount)
    // The app plays remote audio to the speakers; capturing that back would
    // echo everyone's own sound into the share.
    configuration.excludesCurrentProcessAudio = true
    // An SCStream always carries a video part; keep it as small and slow as
    // the API accepts — the video comes from the plugin's own capturer.
    configuration.width = 64
    configuration.height = 64
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
    let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
    do {
      try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: captureQueue)
    } catch {
      return
    }
    stream.startCapture { _ in }
    captureStream = stream
  }

  private func stopCaptureStream() {
    captureStream?.stopCapture { _ in }
    captureStream = nil
    converter = nil
    converterSourceFormat = nil
  }

  // MARK: - Format-driven conversion

  /// The converter for this source format, made (and reported) once.
  private func converter(for sourceFormat: AVAudioFormat, asbd: AudioStreamBasicDescription, frames: Int)
    -> AVAudioConverter?
  {
    if let converter, converterSourceFormat == sourceFormat { return converter }
    if converterTargetFormat == nil {
      converterTargetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Self.sampleRate,
        channels: Self.channelCount,
        interleaved: true)
    }
    guard let target = converterTargetFormat else { return nil }
    let fresh = AVAudioConverter(from: sourceFormat, to: target)
    converter = fresh
    converterSourceFormat = sourceFormat
    if !Self.loggedFormat {
      Self.loggedFormat = true
      Self.writeDiagnostic(
        "capture format: rate=\(asbd.mSampleRate) channels=\(asbd.mChannelsPerFrame) "
          + "bits=\(asbd.mBitsPerChannel) flags=0x\(String(asbd.mFormatFlags, radix: 16)) "
          + "frames=\(frames) -> converted to \(Self.sampleRate) Hz stereo")
    }
    return fresh
  }

  private static var loggedFormat = false
  private static var loggedConversionError = false

  private static func diagnosticDirectory() -> URL? {
    guard
      let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else { return nil }
    let directory = base.appendingPathComponent("Nightcord Speak/logs", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func openWav() {
    guard wavHandle == nil, let directory = Self.diagnosticDirectory() else { return }
    let file = directory.appendingPathComponent("screen-audio-capture.wav")
    FileManager.default.createFile(
      atPath: file.path,
      contents: Self.wavHeader(dataBytes: Self.wavFrameLimit * 4),
      attributes: nil)
    wavHandle = try? FileHandle(forWritingTo: file)
    wavFrames = 0
    wavFinalized = false
  }

  private func closeWav() {
    guard let handle = wavHandle else { return }
    wavHandle = nil
    let dataBytes = wavFrames * 4
    try? handle.seek(toOffset: 0)
    try? handle.write(contentsOf: Self.wavHeader(dataBytes: dataBytes))
    try? handle.truncate(atOffset: UInt64(44 + dataBytes))
    try? handle.close()
    if !wavFinalized {
      wavFinalized = true
      Self.writeDiagnostic("capture wav closed: frames=\(wavFrames) (48kHz mono s16)")
    }
  }

  /// A 44-byte WAV header: 48 kHz, stereo, 16-bit.
  private static func wavHeader(dataBytes: Int) -> Data {
    var header = Data()
    func put(_ text: String) { header.append(contentsOf: Array(text.utf8)) }
    func put32(_ value: Int) {
      var v = UInt32(truncatingIfNeeded: value).littleEndian
      withUnsafeBytes(of: &v) { header.append(contentsOf: $0) }
    }
    func put16(_ value: Int) {
      var v = UInt16(truncatingIfNeeded: value).littleEndian
      withUnsafeBytes(of: &v) { header.append(contentsOf: $0) }
    }
    put("RIFF")
    put32(36 + dataBytes)
    put("WAVE")
    put("fmt ")
    put32(16)
    put16(1)
    put16(1)
    put32(48_000)
    put32(48_000 * 2)
    put16(2)
    put16(16)
    put("data")
    put32(dataBytes)
    return header
  }

  /// Appends one line to `screen-audio.log` beside the app's own log — the
  /// folder the settings dialog opens — and echoes it to the system log.
  private static func writeDiagnostic(_ line: String) {
    NSLog("nightcord screen-audio: %@", line)
    let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
    guard let directory = diagnosticDirectory() else { return }
    let file = directory.appendingPathComponent("screen-audio.log")
    if let handle = try? FileHandle(forWritingTo: file) {
      handle.seekToEndOfFile()
      handle.write(Data(stamped.utf8))
      try? handle.close()
    } else {
      try? stamped.write(to: file, atomically: true, encoding: .utf8)
    }
  }

  private static func copy(
    _ source: UnsafeMutableAudioBufferListPointer, into buffer: AVAudioPCMBuffer
  ) -> Bool {
    let destination = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
    guard source.count == destination.count else { return false }
    for index in 0..<source.count {
      guard let from = source[index].mData, let to = destination[index].mData else { return false }
      let bytes = min(source[index].mDataByteSize, destination[index].mDataByteSize)
      memcpy(to, from, Int(bytes))
    }
    return true
  }

  private static func clamp(_ sample: Float32) -> Int16 {
    let scaled = sample * 32767.0
    if scaled >= 32767.0 { return 32767 }
    if scaled <= -32768.0 { return -32768 }
    return Int16(scaled)
  }
}

@available(macOS 13.0, *)
extension NightcordSystemAudioDevice: SCStreamOutput {
  func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .audio, sampleBuffer.isValid else { return }
    guard
      let description = CMSampleBufferGetFormatDescription(sampleBuffer),
      let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(description),
      let sourceFormat = AVAudioFormat(streamDescription: asbdPointer)
    else { return }
    let frames = CMSampleBufferGetNumSamples(sampleBuffer)
    guard frames > 0 else { return }
    guard let converter = converter(
      for: sourceFormat, asbd: asbdPointer.pointee, frames: frames)
    else { return }

    guard
      let input = AVAudioPCMBuffer(
        pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(frames))
    else { return }
    input.frameLength = AVAudioFrameCount(frames)
    var copied = false
    do {
      try sampleBuffer.withAudioBufferList { audioBufferList, _ in
        copied = Self.copy(audioBufferList, into: input)
      }
    } catch {}
    guard copied else { return }

    let ratio = Self.sampleRate / max(sourceFormat.sampleRate, 1)
    let capacity = AVAudioFrameCount(Double(frames) * ratio) + 64
    guard
      let target = converterTargetFormat,
      let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity)
    else { return }

    var supplied = false
    var conversionError: NSError?
    let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
      if supplied {
        outStatus.pointee = .noDataNow
        return nil
      }
      supplied = true
      outStatus.pointee = .haveData
      return input
    }
    guard status != .error, output.frameLength > 0, let channelData = output.floatChannelData
    else {
      if let conversionError, !Self.loggedConversionError {
        Self.loggedConversionError = true
        Self.writeDiagnostic("conversion failed: \(conversionError)")
      }
      return
    }

    // Interleaved Float32 stereo: buffer 0 holds L R L R.
    let framesOut = Int(output.frameLength)
    var mono = [Int16](repeating: 0, count: framesOut)
    let source = channelData[0]
    for index in 0..<framesOut {
      let left = source[index * 2]
      let right = source[index * 2 + 1]
      mono[index] = Self.clamp((left + right) / 2)
    }
    mono.withUnsafeBufferPointer { buffer in
      ringAppend(buffer.baseAddress!, count: buffer.count)
    }
  }

}
