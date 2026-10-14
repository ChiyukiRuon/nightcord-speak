import Cocoa
import FlutterMacOS

// 使用真实 AppDelegate 和通道处理器，复现 Flutter 消息在主队列执行的上下文。
final class ExitProbeMessenger: NSObject, FlutterBinaryMessenger {
  private var handler: FlutterBinaryMessageHandler?
  private let codec = FlutterStandardMethodCodec.sharedInstance()

  func send(onChannel channel: String, message: Data?) {
    send(onChannel: channel, message: message, binaryReply: nil)
  }

  func send(onChannel channel: String, message: Data?, binaryReply: FlutterBinaryReply?) {
    guard let message = message,
      codec.decodeMethodCall(message).method == "shutdown" else { fatalError("Unexpected native call") }
    // 模拟 Flutter 在主队列异步返回清理确认。
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      print("MAIN_ISOLATE_CLEANUP_ACKNOWLEDGED")
      fflush(stdout)
      binaryReply?(self.codec.encodeSuccessEnvelope(true))
    }
  }

  func setMessageHandlerOnChannel(_ channel: String,
    binaryMessageHandler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
    handler = binaryMessageHandler
    return 1
  }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) { handler = nil }

  func call(_ method: String) {
    handler?(codec.encode(FlutterMethodCall(methodName: method, arguments: nil))) { _ in }
  }
}

@main
enum MacUpdateExitProbe {
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    let messenger = ExitProbeMessenger()
    app.delegate = delegate
    delegate.configureMainLifecycle(messenger: messenger)
    DispatchQueue.main.async {
      messenger.call("ready")
      DispatchQueue.main.async { messenger.call("quitForUpdate") }
    }
    withExtendedLifetime((delegate, messenger)) { app.run() }
  }
}
