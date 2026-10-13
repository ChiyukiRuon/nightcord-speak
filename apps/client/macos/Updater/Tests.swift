import Foundation
import CryptoKit

/// Standalone native tests use only isolated bundles, never a running user app.
@main
struct UpdaterTests {
  static func require(_ value: Bool, _ message: String) throws {
    if !value { throw NSError(domain: message, code: 1) }
  }

  static func main() throws {
    guard CommandLine.arguments.count == 2 else { throw NSError(domain: "Missing fixture bundle", code: 1) }
    let source = URL(fileURLWithPath: CommandLine.arguments[1])
    let files = FileManager.default
    let root = files.temporaryDirectory.appendingPathComponent("nightcord-updater-tests-" + UUID().uuidString)
    try files.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? files.removeItem(at: root) }
    let archive = root.appendingPathComponent("fixture.zip")
    let zip = Process()
    zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    zip.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, archive.path]
    try zip.run(); zip.waitUntilExit()
    try require(zip.terminationStatus == 0, "Fixture archive failed")
    let digest = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
    let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: source.appendingPathComponent("Contents/Info.plist")), format: nil) as! [String: Any]
    let version = info["CFBundleShortVersionString"] as! String

    func fixture(_ name: String, hash: String? = nil, requestedVersion: String? = nil, unavailableLog: Bool = false) throws -> UpdateTransaction {
      let folder = root.appendingPathComponent(name)
      try files.createDirectory(at: folder, withIntermediateDirectories: false)
      let target = folder.appendingPathComponent("Nightcord Speak.app")
      try files.copyItem(at: source, to: target)
      try "original".write(to: target.appendingPathComponent("original-marker"), atomically: true, encoding: .utf8)
      let download = folder.appendingPathComponent("nightcord-update-" + name)
      try files.createDirectory(at: download, withIntermediateDirectories: false)
      let package = download.appendingPathComponent("update.zip")
      try files.copyItem(at: archive, to: package)
      let request: [String: Any] = [
        "parent_pid": 999999, "target": target.path, "package": package.path,
        "sha256": hash ?? digest, "version": requestedVersion ?? version,
        "nonce": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), "language": "en",
        "log_file": folder.appendingPathComponent(unavailableLog ? "missing/update.log" : "update.log").path,
      ]
      let configuration = download.appendingPathComponent("update.json")
      try JSONSerialization.data(withJSONObject: request).write(to: configuration)
      return try UpdateTransaction(configuration: configuration, allowedTarget: target)
    }

    let rollback = try fixture("rollback")
    try rollback.prepare()
    try require(files.fileExists(atPath: rollback.target.appendingPathComponent("original-marker").path), "Prepare changed original")
    try rollback.request.nonce.write(to: rollback.root.appendingPathComponent("commit"), atomically: true, encoding: .utf8)
    try rollback.replace()
    try require(!files.fileExists(atPath: rollback.target.appendingPathComponent("original-marker").path), "Replacement not applied")
    try rollback.rollback()
    try require(files.fileExists(atPath: rollback.target.appendingPathComponent("original-marker").path), "Launch failure rollback lost original")
    try rollback.cleanStage()
    let rollbackLog = try String(contentsOf: URL(fileURLWithPath: rollback.request.log_file!), encoding: .utf8)
    try require(rollbackLog.contains("stage=rollback-started") && rollbackLog.contains("stage=rollback-complete"), "Rollback diagnostics missing")
    print("Verified preparation, replacement and launch-failure rollback.")

    let partial = try fixture("partial")
    try partial.prepare()
    try files.removeItem(at: partial.stage.appendingPathComponent("Nightcord Speak.app"))
    try partial.request.nonce.write(to: partial.root.appendingPathComponent("commit"), atomically: true, encoding: .utf8)
    var failed = false
    do { try partial.replace() } catch { failed = true }
    try require(failed, "Expected interrupted replacement")
    try partial.rollback()
    try require(files.fileExists(atPath: partial.target.appendingPathComponent("original-marker").path), "Partial failure did not recover original")
    try partial.cleanStage()
    print("Verified rollback after moving the original but before moving the replacement.")

    for (name, hash, requestedVersion) in [
      ("checksum", String(repeating: "0", count: 64), version),
      ("version", digest, "999.0.0"),
    ] {
      let invalid = try fixture(name, hash: hash, requestedVersion: requestedVersion)
      failed = false
      do { try invalid.prepare() } catch { failed = true }
      try require(failed, "Invalid package accepted")
      try require(files.fileExists(atPath: invalid.target.appendingPathComponent("original-marker").path), "Invalid package changed original")
      try invalid.cleanStage()
    }
    print("Verified checksum and installed-version rejection.")

    let success = try fixture("success")
    let sounds = success.target.deletingLastPathComponent().appendingPathComponent("sounds/custom")
    try files.createDirectory(at: sounds, withIntermediateDirectories: true)
    let userFile = sounds.appendingPathComponent("config.json")
    try "keep".write(to: userFile, atomically: true, encoding: .utf8)
    try success.prepare()
    try success.request.nonce.write(to: success.root.appendingPathComponent("commit"), atomically: true, encoding: .utf8)
    try success.replace()
    try success.finish()
    try require(!files.fileExists(atPath: success.backup.path), "Successful update left backup")
    try require(try String(contentsOf: userFile, encoding: .utf8) == "keep", "User sounds changed")
    try require(!files.fileExists(atPath: success.root.path), "Successful update left temporary transaction files")
    let successLog = try String(contentsOf: URL(fileURLWithPath: success.request.log_file!), encoding: .utf8)
    for stage in ["started", "checksum-verified", "ready", "committed", "parent-exited", "installed", "complete"] {
      try require(successLog.contains("stage=" + stage), "Missing persistent update diagnostic: " + stage)
    }
    print("Verified successful update cleanup and user-sound preservation.")

    let diagnostics = try fixture("command-diagnostics")
    failed = false
    do { try diagnostics.run("/bin/sh", ["-c", "printf 'fixture diagnostic failure' >&2; exit 7"]) } catch { failed = true }
    let commandLog = try String(contentsOf: URL(fileURLWithPath: diagnostics.request.log_file!), encoding: .utf8)
    try require(failed && commandLog.contains("exit_code=7") && commandLog.contains("fixture diagnostic failure"), "Command error diagnostics missing")
    let unavailable = try fixture("unavailable-log", unavailableLog: true)
    try unavailable.prepare()
    try unavailable.cleanStage()
    print("Verified persistent phase logs, stderr diagnostics and unavailable log sink.")
  }
}
