import Cocoa

@main
struct NightcordUpdater {
  @MainActor
  static func launch(_ application: URL) async throws {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    _ = try await NSWorkspace.shared.openApplication(at: application, configuration: configuration)
  }

  @MainActor
  static func main() async {
    NSApplication.shared.setActivationPolicy(.accessory)
    guard CommandLine.arguments.count == 2 else { return }
    let configuration = URL(fileURLWithPath: CommandLine.arguments[1])
    let root = configuration.deletingLastPathComponent()
    var transaction: UpdateTransaction?
    do {
      let target = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      let update = try UpdateTransaction(configuration: configuration, allowedTarget: target)
      transaction = update
      guard NSRunningApplication(processIdentifier: update.request.parent_pid)?.bundleURL?.standardizedFileURL == target.standardizedFileURL else {
        throw NSError(domain: "NightcordUpdater", code: 8)
      }
      try update.prepare()
      try update.replace()
      update.log("info", "relaunch-started")
      try await launch(target)
      update.log("info", "relaunched")
      // Cleanup failure must not roll back a successfully relaunched update.
      do { try update.finish() } catch { update.log("warn", "cleanup-failed", String(describing: error)) }
    } catch {
      var recovered = true
      if let update = transaction {
        update.log("error", "failed", String(describing: error))
        do { try update.rollback() } catch {
          recovered = false
          update.log("error", "rollback-failed", String(describing: error))
        }
        try? update.cleanStage()
      }
      try? "Update failed".write(to: root.appendingPathComponent("error"), atomically: true, encoding: .utf8)
      try? String(describing: error).write(to: root.appendingPathComponent("updater.log"), atomically: true, encoding: .utf8)
      if let update = transaction, update.parentExited {
        if recovered {
          update.log("info", "relaunch-recovery")
          do { try await launch(update.target) } catch { update.log("error", "recovery-launch-failed", String(describing: error)) }
        }
        let alert = NSAlert()
        alert.messageText = "Nightcord Speak"
        let language = update.request.language
        if language.hasPrefix("zh") {
          alert.informativeText = language.contains("Hant") || language.contains("TW") || language.contains("HK") || language.contains("MO")
            ? "更新失敗，已嘗試恢復原版本。請重新下載後重試。"
            : "更新失败，已尝试恢复原版本。请重新下载后重试。"
        } else if language.hasPrefix("ja") {
          alert.informativeText = "更新に失敗しました。元のバージョンの復元を試みました。再ダウンロードしてお試しください。"
        } else if language.hasPrefix("ko") {
          alert.informativeText = "업데이트에 실패하여 이전 버전 복원을 시도했습니다. 다시 다운로드하여 시도하세요."
        } else {
          alert.informativeText = "Update failed. Recovery of the previous version was attempted. Download again and retry."
        }
        alert.runModal()
      }
    }
  }
}
