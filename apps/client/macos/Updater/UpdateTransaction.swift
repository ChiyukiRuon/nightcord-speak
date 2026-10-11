import Foundation
import CryptoKit
import Darwin

struct UpdateRequest: Decodable {
  let parent_pid: Int32
  let target: String
  let package: String
  let sha256: String
  let version: String
  let nonce: String
  let language: String
}

/// Preserve the old bundle until the replacement is verified on the same volume.
final class UpdateTransaction {
  let request: UpdateRequest
  let root: URL
  let target: URL
  let stage: URL
  let backup: URL
  let files = FileManager.default
  var oldMoved = false
  var newMoved = false
  var parentExited = false

  init(configuration: URL, allowedTarget: URL) throws {
    root = configuration.deletingLastPathComponent().standardizedFileURL
    request = try JSONDecoder().decode(UpdateRequest.self, from: Data(contentsOf: configuration))
    target = URL(fileURLWithPath: request.target).standardizedFileURL
    guard target == allowedTarget.standardizedFileURL, target.pathExtension == "app",
      request.parent_pid > 1, request.nonce.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil,
      request.version.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+(?:-(?:alpha|beta|rc)\\.[0-9]+)?$", options: .regularExpression) != nil
    else { throw NSError(domain: "NightcordUpdater", code: 1) }
    stage = target.deletingLastPathComponent().appendingPathComponent(".nightcord-update-stage-" + request.nonce)
    backup = target.deletingLastPathComponent().appendingPathComponent(".nightcord-update-backup-" + request.nonce)
  }

  @discardableResult
  func run(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw NSError(domain: "NightcordUpdater", code: Int(process.terminationStatus))
    }
    return String(decoding: data, as: UTF8.self)
  }

  func prepare() throws {
    let package = URL(fileURLWithPath: request.package).standardizedFileURL
    guard package.deletingLastPathComponent() == root,
      files.fileExists(atPath: target.appendingPathComponent("Contents/MacOS/Nightcord Speak").path),
      !files.fileExists(atPath: stage.path), !files.fileExists(atPath: backup.path)
    else { throw NSError(domain: "NightcordUpdater", code: 2) }
    let handle = try FileHandle(forReadingFrom: package)
    defer { try? handle.close() }
    var hash = SHA256()
    while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
    guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == request.sha256 else {
      throw NSError(domain: "NightcordUpdater", code: 3)
    }
    let entries = try run("/usr/bin/zipinfo", ["-1", package.path])
    for entry in entries.split(separator: "\n") {
      let components = entry.split(separator: "/")
      guard !entry.hasPrefix("/"), !components.contains(".."), !entry.contains("\\"),
        components.first == "Nightcord Speak.app" || components.first == "__MACOSX"
      else { throw NSError(domain: "NightcordUpdater", code: 4) }
    }
    // Same-volume staging also checks permission before the client exits.
    try files.createDirectory(at: stage, withIntermediateDirectories: false)
    try run("/usr/bin/ditto", ["-x", "-k", package.path, stage.path])
    let replacement = stage.appendingPathComponent("Nightcord Speak.app")
    let info = try PropertyListSerialization.propertyList(
      from: Data(contentsOf: replacement.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any]
    guard info?["CFBundleIdentifier"] as? String == "com.chiyukiruon.nightcordClient",
      info?["CFBundleShortVersionString"] as? String == request.version.components(separatedBy: "-")[0]
    else { throw NSError(domain: "NightcordUpdater", code: 5) }
    if let enumerator = files.enumerator(at: replacement, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
      for case let path as URL in enumerator {
        if try path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
          guard path.resolvingSymlinksInPath().path.hasPrefix(replacement.resolvingSymlinksInPath().path + "/") else {
            throw NSError(domain: "NightcordUpdater", code: 6)
          }
        }
      }
    }
    try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", replacement.path])
    #if arch(arm64)
    let architecture = "arm64"
    #else
    let architecture = "x86_64"
    #endif
    for relative in ["Contents/MacOS/Nightcord Speak", "Contents/Frameworks/libnightcord_ffi.dylib"] {
      try run("/usr/bin/lipo", [replacement.appendingPathComponent(relative).path, "-verify_arch", architecture])
    }
    try request.nonce.write(to: root.appendingPathComponent("ready"), atomically: true, encoding: .utf8)
  }

  func replace() throws {
    let commitDeadline = Date().addingTimeInterval(30)
    while (try? String(contentsOf: root.appendingPathComponent("commit"), encoding: .utf8)) != request.nonce {
      guard Date() < commitDeadline else { throw NSError(domain: "NightcordUpdater", code: 9) }
      Thread.sleep(forTimeInterval: 0.1)
    }
    let deadline = Date().addingTimeInterval(60)
    while kill(request.parent_pid, 0) == 0 {
      guard Date() < deadline else { throw NSError(domain: "NightcordUpdater", code: 7) }
      Thread.sleep(forTimeInterval: 0.1)
    }
    parentExited = true
    try files.moveItem(at: target, to: backup)
    oldMoved = true
    try files.moveItem(at: stage.appendingPathComponent("Nightcord Speak.app"), to: target)
    newMoved = true
  }

  func rollback() throws {
    if newMoved { try files.removeItem(at: target); newMoved = false }
    if oldMoved { try files.moveItem(at: backup, to: target); oldMoved = false }
  }

  func finish() throws {
    if oldMoved { try files.removeItem(at: backup); oldMoved = false }
    try cleanStage()
    try "ok".write(to: root.appendingPathComponent("complete"), atomically: true, encoding: .utf8)
    if root.lastPathComponent.hasPrefix("nightcord-update-") { try files.removeItem(at: root) }
  }

  func cleanStage() throws {
    if files.fileExists(atPath: stage.path) { try files.removeItem(at: stage) }
  }
}
