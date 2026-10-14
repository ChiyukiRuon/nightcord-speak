import Cocoa
import CryptoKit

@main
enum MacUpdateLaunchProbe {
  @MainActor
  static func main() throws {
    NSApplication.shared.setActivationPolicy(.accessory)
    let files = FileManager.default
    let root = files.temporaryDirectory.appendingPathComponent("nightcord-launch-probe-" + UUID().uuidString)
    try files.createDirectory(at: root, withIntermediateDirectories: false)
    let configuration = root.appendingPathComponent("update.json")
    // Invalid configuration proves entry without touching an installation.
    var request: [String: Any] = [
      "parent_pid": ProcessInfo.processInfo.processIdentifier,
      "target": Bundle.main.bundleURL.path,
    ]
    let prepare = CommandLine.arguments.contains("--prepare")
    let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    if prepare {
      let fixture = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/fixture.zip")
      let package = root.appendingPathComponent("update.zip")
      try files.copyItem(at: fixture, to: package)
      let digest = SHA256.hash(data: try Data(contentsOf: package)).map { String(format: "%02x", $0) }.joined()
      request.merge([
        "target": Bundle.main.bundleURL.path, "package": package.path,
        "sha256": digest, "version": "0.4.1", "nonce": nonce, "language": "en",
        "log_file": root.appendingPathComponent("trace.log").path,
      ]) { _, new in new }
    }
    try JSONSerialization.data(withJSONObject: request).write(to: configuration)
    NightcordUpdateLauncher.launch(configuration: configuration) { launched in
      switch launched {
      case .success(let pid): print("NATIVE_LAUNCH_PID=\(pid)")
      case .failure(let error):
        let native = error as NSError
        print("NATIVE_LAUNCH_FAILED domain=\(native.domain) code=\(native.code) \(native.localizedDescription)")
        print("PROBE_ERROR_DETAILS=\(native.userInfo)")
        exit(1)
      }
    }
    let started = Date()
    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
      let files = FileManager.default
      if prepare, files.fileExists(atPath: root.appendingPathComponent("ready").path) {
        try? nonce.write(to: root.appendingPathComponent("abort"), atomically: true, encoding: .utf8)
      }
      if files.fileExists(atPath: root.appendingPathComponent("updater-entry.log").path),
         files.fileExists(atPath: root.appendingPathComponent("error").path) {
        if prepare {
          guard files.fileExists(atPath: root.appendingPathComponent("ready").path) else {
            print("SANDBOX_PREPARATION_FAILED \((try? String(contentsOf: root.appendingPathComponent("updater.log"), encoding: .utf8)) ?? "unknown")")
            exit(3)
          }
          print("SANDBOX_XPC_PREPARATION_ABORT_VERIFIED")
        }
        print("SANDBOX_NATIVE_LAUNCH_ENTRY_VERIFIED")
        try? files.removeItem(at: root)
        exit(0)
      }
      if Date().timeIntervalSince(started) > (prepare ? 60 : 15) {
        print("SANDBOX_NATIVE_LAUNCH_ENTRY_TIMEOUT")
        exit(2)
      }
    }
    NSApp.run()
  }
}
