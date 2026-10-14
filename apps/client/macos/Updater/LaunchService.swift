import Foundation
import Darwin

final class UpdateLaunchService: NSObject, NightcordUpdateLaunchProtocol {
  private let caller: pid_t
  init(caller: pid_t) { self.caller = caller }

  func launch(configuration: String, reply: @escaping (NSNumber?, NSError?) -> Void) {
    do {
      let path = URL(fileURLWithPath: configuration)
      let values = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any]
      guard let parent = values?["parent_pid"] as? NSNumber, parent.int32Value == caller,
        path.lastPathComponent == "update.json"
      else { throw NSError(domain: "NightcordUpdateLauncher", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Update request does not match the calling process"]) }
      let target = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      let executable = target.appendingPathComponent("Contents/Helpers/NightcordUpdater.app/Contents/MacOS/NightcordUpdater")
      let helper = Process()
      helper.executableURL = executable
      helper.arguments = [path.path]
      helper.standardInput = FileHandle.nullDevice
      helper.standardOutput = FileHandle.nullDevice
      helper.standardError = FileHandle.nullDevice
      // The service launches only its sealed sibling helper. The helper owns
      // package, target and parent validation and survives the client exit.
      try helper.run()
      reply(NSNumber(value: helper.processIdentifier), nil)
    } catch {
      reply(nil, error as NSError)
    }
  }
}

final class UpdateLaunchServiceDelegate: NSObject, NSXPCListenerDelegate {
  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
    guard connection.effectiveUserIdentifier == getuid() else { return false }
    connection.exportedInterface = NSXPCInterface(with: NightcordUpdateLaunchProtocol.self)
    connection.exportedObject = UpdateLaunchService(caller: connection.processIdentifier)
    connection.resume()
    return true
  }
}

@main
enum UpdateLaunchServiceMain {
  static func main() {
    let listener = NSXPCListener.service()
    let delegate = UpdateLaunchServiceDelegate()
    listener.delegate = delegate
    withExtendedLifetime(delegate) { listener.resume() }
  }
}
