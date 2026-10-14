import Cocoa
import FlutterMacOS

/// Waits for the main isolate, then performs cleanup exactly once. Child engine
/// creation must not change which isolate receives the application's exit.
class NightcordTerminationCoordinator {
  private var ready = false
  private var requested = false
  private var started = false
  private let shutdown: (@escaping () -> Void) -> Void
  private let finish: () -> Void

  init(shutdown: @escaping (@escaping () -> Void) -> Void, finish: @escaping () -> Void) {
    self.shutdown = shutdown
    self.finish = finish
  }

  func mainIsolateReady() {
    ready = true
    startIfReady()
  }

  func requestExit() {
    requested = true
    startIfReady()
  }

  private func startIfReady() {
    guard ready && requested && !started else { return }
    started = true
    shutdown(finish)
  }
}

@main
class AppDelegate: FlutterAppDelegate {
  private var lifecycleChannel: FlutterMethodChannel?
  private var cleanupComplete = false
  private lazy var termination = NightcordTerminationCoordinator(
    shutdown: { [weak self] done in
      self?.lifecycleChannel?.invokeMethod("shutdown", arguments: nil) { response in
        if response as? Bool != true {
          // Leave crash evidence intact if the isolate could not clean up.
          NSLog("Nightcord main isolate did not acknowledge shutdown")
        }
        done()
      }
    },
    finish: { [weak self] in
      self?.cleanupComplete = true
      // 清理完成后再从 RunLoop 发起退出，避免模态循环阻塞 Flutter 消息队列。
      RunLoop.main.perform { NSApp.terminate(nil) }
    }
  )

  func configureMainLifecycle(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "nightcord/lifecycle", binaryMessenger: messenger)
    lifecycleChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "startUpdateHelper" {
        guard let arguments = call.arguments as? [String: Any],
          let configuration = arguments["configuration"] as? String, !configuration.isEmpty
        else { result(FlutterError(code: "invalid_arguments", message: "Missing update configuration path", details: nil)); return }
        NightcordUpdateLauncher.launch(configuration: URL(fileURLWithPath: configuration)) { launched in
          switch launched {
          case .success(let pid): result(Int(pid))
          case .failure(let error):
            let native = error as NSError
            result(FlutterError(code: "launch_failed", message: native.localizedDescription,
              details: ["domain": native.domain, "code": native.code]))
          }
        }
        return
      }
      if call.method == "quitForUpdate" {
        result(nil)
        DispatchQueue.main.async { self?.termination.requestExit() }
        return
      }
      guard call.method == "ready" else { result(FlutterMethodNotImplemented); return }
      result(nil)
      DispatchQueue.main.async { self?.termination.mainIsolateReady() }
    }
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if cleanupComplete { return .terminateNow }
    DispatchQueue.main.async { self.termination.requestExit() }
    // 等待 Dart 关闭核心期间保留普通事件循环；terminateLater 会阻塞清理回调。
    return .terminateCancel
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
