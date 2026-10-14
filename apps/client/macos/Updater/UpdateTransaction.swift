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
  let log_file: String?
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
  private let started = Date()

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
    log("info", "started", "version=\(request.version) parent_pid=\(request.parent_pid) attempt=\(request.nonce) target=\(target.path)")
  }

  /// Keep helper diagnostics after the client core shuts down and staging is removed.
  func log(_ level: String, _ stage: String, _ message: String = "") {
    let path = request.log_file.map { URL(fileURLWithPath: $0) }
      ?? root.appendingPathComponent("updater-trace.log")
    let text = message.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    let line = "\(ISO8601DateFormatter().string(from: Date())) [\(level)] pid=\(getpid()) elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000)) stage=\(stage) \(text.prefix(4096))\n"
    do {
      if !files.fileExists(atPath: path.path) {
        guard files.createFile(atPath: path.path, contents: nil) else { return }
      }
      let handle = try FileHandle(forWritingTo: path)
      defer { try? handle.close() }
      try handle.seekToEnd()
      try handle.write(contentsOf: Data(line.utf8))
    } catch {
      // A diagnostic failure must not change installation or rollback behavior.
    }
  }

  @discardableResult
  func run(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    let diagnostic = root.appendingPathComponent("command-stderr-" + UUID().uuidString + ".log")
    let errorOutput = files.createFile(atPath: diagnostic.path, contents: nil)
      ? try? FileHandle(forWritingTo: diagnostic) : nil
    process.standardError = errorOutput ?? FileHandle.nullDevice
    defer { try? errorOutput?.close(); try? files.removeItem(at: diagnostic) }
    log("info", "command-started", URL(fileURLWithPath: executable).lastPathComponent)
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    log("info", "command-result", "command=\(URL(fileURLWithPath: executable).lastPathComponent) exit_code=\(process.terminationStatus)")
    guard process.terminationStatus == 0 else {
      if let reader = try? FileHandle(forReadingFrom: diagnostic) {
        defer { try? reader.close() }
        if let bytes = try? reader.read(upToCount: 8192) {
          log("error", "command-stderr", String(decoding: bytes, as: UTF8.self))
        }
      }
      throw NSError(domain: "NightcordUpdater", code: Int(process.terminationStatus))
    }
    return String(decoding: data, as: UTF8.self)
  }

  func prepare() throws {
    try assertNotAborted()
    log("info", "validate-package", "package=\(request.package)")
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
    log("info", "checksum-verified")
    let entries = try run("/usr/bin/zipinfo", ["-1", package.path])
    for entry in entries.split(separator: "\n") {
      let components = entry.split(separator: "/")
      guard !entry.hasPrefix("/"), !components.contains(".."), !entry.contains("\\"),
        components.first == "Nightcord Speak.app" || components.first == "__MACOSX"
      else { throw NSError(domain: "NightcordUpdater", code: 4) }
    }
    // Same-volume staging also checks permission before the client exits.
    try files.createDirectory(at: stage, withIntermediateDirectories: false)
    log("info", "extract", "stage=\(stage.path)")
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
    try releaseQuarantine(replacement)
    try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", replacement.path])
    #if arch(arm64)
    let architecture = "arm64"
    #else
    let architecture = "x86_64"
    #endif
    for relative in ["Contents/MacOS/Nightcord Speak", "Contents/Frameworks/libnightcord_ffi.dylib"] {
      try run("/usr/bin/lipo", [replacement.appendingPathComponent(relative).path, "-verify_arch", architecture])
    }
    try assertNotAborted()
    try request.nonce.write(to: root.appendingPathComponent("ready"), atomically: true, encoding: .utf8)
    log("info", "ready", "Waiting for client commit")
  }

  /// 沙盒客户端写出的更新包带有强制隔离标记（0086），ditto 解压时会把它传播到
  /// 每个文件；包内条目也可能自带该属性，所以仅用 --noqtn 解压并不够。留下的
  /// 标记会让内核以 EPERM 拒绝执行新版本及其内嵌助手，codesign 校验发现不了。
  func releaseQuarantine(_ bundle: URL) throws {
    let descendants = files.enumerator(atPath: bundle.path)?.compactMap { $0 as? String } ?? []
    var released = 0
    for path in [bundle.path] + descendants.map({ bundle.appendingPathComponent($0).path }) {
      if removexattr(path, "com.apple.quarantine", XATTR_NOFOLLOW) == 0 { released += 1 }
      else if errno != ENOATTR { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
    log("info", "quarantine-released", "items=\(released)")
  }

  func replace() throws {
    let commitDeadline = Date().addingTimeInterval(30)
    while (try? String(contentsOf: root.appendingPathComponent("commit"), encoding: .utf8)) != request.nonce {
      try assertNotAborted()
      guard Date() < commitDeadline else { throw NSError(domain: "NightcordUpdater", code: 9) }
      Thread.sleep(forTimeInterval: 0.1)
    }
    log("info", "committed", "Waiting for client process to exit")
    let deadline = Date().addingTimeInterval(60)
    while kill(request.parent_pid, 0) == 0 {
      try assertNotAborted()
      guard Date() < deadline else { throw NSError(domain: "NightcordUpdater", code: 7) }
      Thread.sleep(forTimeInterval: 0.1)
    }
    try assertNotAborted()
    parentExited = true
    log("info", "parent-exited", "backup=\(backup.path)")
    try files.moveItem(at: target, to: backup)
    oldMoved = true
    try files.moveItem(at: stage.appendingPathComponent("Nightcord Speak.app"), to: target)
    newMoved = true
    log("info", "installed")
  }

  func rollback() throws {
    log("warn", "rollback-started", "old_moved=\(oldMoved) new_moved=\(newMoved)")
    if newMoved { try files.removeItem(at: target); newMoved = false }
    if oldMoved { try files.moveItem(at: backup, to: target); oldMoved = false }
    log("info", "rollback-complete")
  }

  func finish() throws {
    log("info", "cleanup")
    if oldMoved { try files.removeItem(at: backup); oldMoved = false }
    try cleanStage()
    try "ok".write(to: root.appendingPathComponent("complete"), atomically: true, encoding: .utf8)
    log("info", "complete")
    if root.lastPathComponent.hasPrefix("nightcord-update-") { try files.removeItem(at: root) }
  }

  func cleanStage() throws {
    if files.fileExists(atPath: stage.path) { try files.removeItem(at: stage) }
  }

  func assertNotAborted() throws {
    if (try? String(contentsOf: root.appendingPathComponent("abort"), encoding: .utf8)) == request.nonce {
      throw NSError(domain: "NightcordUpdater", code: 10,
        userInfo: [NSLocalizedDescriptionKey: "Client aborted the update"])
    }
  }
}
