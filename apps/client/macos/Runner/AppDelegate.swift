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
    finish: { NSApp.reply(toApplicationShouldTerminate: true) }
  )

  func configureMainLifecycle(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "nightcord/lifecycle", binaryMessenger: messenger)
    lifecycleChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "quitForUpdate" {
        result(nil)
        DispatchQueue.main.async { NSApp.terminate(nil) }
        return
      }
      guard call.method == "ready" else { result(FlutterMethodNotImplemented); return }
      result(nil)
      // AppKit must receive NSTerminateLater before its deferred reply.
      DispatchQueue.main.async { self?.termination.mainIsolateReady() }
    }
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    DispatchQueue.main.async { self.termination.requestExit() }
    return .terminateLater
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
