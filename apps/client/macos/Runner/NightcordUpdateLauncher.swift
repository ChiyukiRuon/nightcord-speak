import Cocoa

@MainActor
enum NightcordUpdateLauncher {
  static func launch(configuration: URL, completion: @escaping (Result<pid_t, Error>) -> Void) {
    let connection = NSXPCConnection(serviceName: "com.chiyukiruon.nightcordClient.updateLauncher")
    connection.remoteObjectInterface = NSXPCInterface(with: NightcordUpdateLaunchProtocol.self)
    var finished = false
    func finish(_ outcome: Result<pid_t, Error>) {
      guard !finished else { return }
      finished = true
      connection.interruptionHandler = nil
      connection.invalidationHandler = nil
      connection.invalidate()
      completion(outcome)
    }
    let unavailable = NSError(domain: "NightcordUpdateLauncher", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Update launch service became unavailable"])
    connection.interruptionHandler = { DispatchQueue.main.async { finish(.failure(unavailable)) } }
    connection.invalidationHandler = { DispatchQueue.main.async { finish(.failure(unavailable)) } }
    connection.resume()
    guard let service = connection.remoteObjectProxyWithErrorHandler({ error in
      DispatchQueue.main.async { finish(.failure(error)) }
    }) as? NightcordUpdateLaunchProtocol else {
      finish(.failure(unavailable))
      return
    }
    service.launch(configuration: configuration.path) { pid, error in
      DispatchQueue.main.async {
        if let error { finish(.failure(error)) }
        else if let pid, pid.int32Value > 0 { finish(.success(pid.int32Value)) }
        else { finish(.failure(unavailable)) }
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { finish(.failure(unavailable)) }
  }
}
