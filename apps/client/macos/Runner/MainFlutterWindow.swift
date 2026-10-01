import Cocoa
import FlutterMacOS
import UserNotifications

/// The window, and the two things the app has to say to Flutter through it.
///
/// This file is the runner's wiring point rather than only the window's: it is
/// the one place in the macOS build that has a `FlutterViewController` in hand
/// at startup, and a platform channel needs one. `FlutterAppDelegate` cannot do
/// this job -- on macOS it does not conform to `FlutterPluginRegistry`, so it
/// has no messenger to open a channel with.
class MainFlutterWindow: NSWindow {
  /// The smallest window the layout can hold, in points.
  ///
  /// Below this the chat header gives up: its fixed pieces, the leading icon,
  /// the channel name, the topic divider and the online count, stop fitting in
  /// the row they share, and Flutter draws the striped overflow band across the
  /// top of the client. This is the same floor as `kMinWindowWidth` in the
  /// Windows runner (`windows/runner/win32_window.cpp`), and the two are meant
  /// to be read together.
  ///
  /// `contentMinSize` rather than `minSize`, because it measures the area
  /// Flutter draws into, so the title bar is not counted against the layout.
  /// Points are already logical, so a Retina display gets the same window as a
  /// 1x one. That is the property the Windows side has to scale for by hand.
  private static let minimumContentSize = NSSize(width: 960, height: 640)

  /// Menu commands, one way. The other end is `lib/util/app_menu.dart`.
  private var appMenuChannel: FlutterMethodChannel?

  /// Notifications, one way. The other end is `lib/util/system_notifications.dart`.
  ///
  /// `local_notifier` serves Windows and claims macOS, but its macOS side is
  /// built on the deprecated `NSUserNotificationCenter` and cannot report a
  /// failure, so nothing appears and nothing is logged. This channel is what
  /// macOS actually uses; see `docs/notifications.md`.
  private var notificationsChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // After the frame is restored: the minimum is what the window is allowed to
    // shrink to, not what it is opened at, and AppKit only pulls a too-small
    // frame up to the floor if the floor is already set when it sizes itself.
    self.contentMinSize = Self.minimumContentSize

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    let messenger = flutterViewController.engine.binaryMessenger

    // After `super`, so the menu the xib installed is in place to be wired.
    appMenuChannel = FlutterMethodChannel(name: "nightcord/shell", binaryMessenger: messenger)
    wirePreferencesMenuItem()

    // Before the first notification can arrive, and it has to be this object:
    // without a delegate macOS suppresses banners while the app is frontmost,
    // and `willPresent` below is the only chance to override that.
    UNUserNotificationCenter.current().delegate = self
    notificationsChannel = FlutterMethodChannel(
      name: "nightcord/notifications", binaryMessenger: messenger)
    notificationsChannel?.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "show":
        self?.showNotification(call, result: result)
      case "status":
        self?.reportStatus(result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Menu bar

  /// Gives the template's Preferences... item something to do.
  ///
  /// `MainMenu.xib` already binds it to Command+comma -- that is what
  /// `keyEquivalent = ","` with no modifier mask means -- but it carries no
  /// action and no target, so the item is inert and the shortcut does nothing.
  /// A dead menu item is worse than an absent one: it is the first thing a Mac
  /// user tries.
  ///
  /// Wired here rather than replaced in the xib, so the binding, the title and
  /// the position the template chose all survive. Found by its key equivalent
  /// rather than by its `id`, which is an Xcode object identifier and not
  /// something to depend on.
  ///
  /// The title stays "Preferences..." rather than becoming "Settings": it is
  /// the template's string, and the app's own translation system does not reach
  /// nib files. Localising the menu bar is a separate job.
  private func wirePreferencesMenuItem() {
    guard
      let appMenu = NSApplication.shared.mainMenu?.items.first?.submenu,
      let preferences = appMenu.items.first(where: { $0.keyEquivalent == "," })
    else {
      return
    }
    preferences.target = self
    preferences.action = #selector(openSettings)
  }

  @objc private func openSettings() {
    appMenuChannel?.invokeMethod("openSettings", arguments: nil)
  }

  // MARK: - Notifications

  /// Reports what macOS currently thinks of this app's notifications.
  ///
  /// `notDetermined` means the prompt has not been answered yet, which is what
  /// a fresh install reports; `denied` means somebody said no, once, and macOS
  /// has remembered it -- the app cannot ask again.
  private func reportStatus(_ result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async { result(describe(settings.authorizationStatus)) }
    }
  }

  /// Shows a notification, asking macOS for permission the first time.
  ///
  /// The reply says *what happened*, not merely that the call was made. On
  /// macOS `local_notifier` answered `true` unconditionally, which is how a
  /// client whose notifications never worked looked identical to one that did;
  /// `"shown"`, `"denied"` and an error are three different things to tell the
  /// person, and only the first of them is success.
  ///
  /// Authorisation is requested here rather than at startup on purpose: this is
  /// the moment it is needed, so the prompt arrives with a reason attached
  /// instead of during the first second of the app's life.
  private func showNotification(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    let title = arguments["title"] as? String ?? ""
    let body = arguments["body"] as? String ?? ""

    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .notDetermined:
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
          if let error = error {
            self.reply(result, .failure(error.localizedDescription))
          } else if granted {
            self.deliver(title: title, body: body, center: center, result: result)
          } else {
            self.reply(result, .status("denied"))
          }
        }
      case .denied:
        // Asking again after a refusal does nothing and returns the same
        // refusal. It is a switch in System Settings now, not a prompt.
        self.reply(result, .status("denied"))
      default:
        self.deliver(title: title, body: body, center: center, result: result)
      }
    }
  }

  /// Hands one notification to the system.
  private func deliver(
    title: String,
    body: String,
    center: UNUserNotificationCenter,
    result: @escaping FlutterResult
  ) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    // A fresh identifier each time, so two notifications in the same instant
    // are two notifications rather than one replacing the other. The burst
    // that would make this noisy is already handled upstream, by the
    // notification policy's silence window.
    let request = UNNotificationRequest(
      identifier: UUID().uuidString, content: content, trigger: nil)

    center.add(request) { error in
      if let error = error {
        self.reply(result, .failure(error.localizedDescription))
      } else {
        self.reply(result, .status("shown"))
      }
    }
  }

  /// Answers a channel call on the main thread, which is where Flutter expects
  /// it; `getNotificationSettings`, `requestAuthorization` and `add` all call
  /// back on a private queue.
  private func reply(_ result: @escaping FlutterResult, _ outcome: Outcome) {
    DispatchQueue.main.async {
      switch outcome {
      case .status(let value):
        result(value)
      case .failure(let message):
        result(
          FlutterError(code: "notifications", message: message, details: nil))
      }
    }
  }

  private enum Outcome {
    case status(String)
    case failure(String)
  }
}

extension MainFlutterWindow: UNUserNotificationCenterDelegate {
  /// Shows a banner even while the app is frontmost.
  ///
  /// macOS suppresses notifications from the active app unless the delegate
  /// says otherwise, and for this client that default is exactly backwards: it
  /// tells you about a channel you are not looking at, and having the app in
  /// front is the normal state.
  ///
  /// Dart does not ask for a system notification while the window is focused --
  /// that case gets the in-app overlay instead -- so in practice this fires only
  /// in the gap where focus changed between the two. Showing it is the right
  /// answer there: a notification the user asked for and did not get is worse
  /// than one that arrives alongside the overlay.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }
}

/// The authorization status as a word Dart can print.
///
/// A string rather than an index: the numbers are an implementation detail of
/// the framework, and a log line that says `denied` is the whole point of
/// asking.
private func describe(_ status: UNAuthorizationStatus) -> String {
  switch status {
  case .notDetermined: return "notDetermined"
  case .denied: return "denied"
  case .authorized: return "authorized"
  case .provisional: return "provisional"
  case .ephemeral: return "ephemeral"
  @unknown default: return "unknown"
  }
}
