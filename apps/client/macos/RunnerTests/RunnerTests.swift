import Cocoa
import FlutterMacOS
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testExitWaitsForMainIsolateAndCleanupAcknowledgement() {
    // Closing during startup must not bypass cleanup or look like a crash.
    var shutdowns = 0
    var exits = 0
    var acknowledge: (() -> Void)?
    let coordinator = NightcordTerminationCoordinator(shutdown: { done in
      shutdowns += 1
      acknowledge = done
    }, finish: { exits += 1 })
    coordinator.requestExit()
    coordinator.requestExit()
    XCTAssertEqual(shutdowns, 0)
    coordinator.mainIsolateReady()
    XCTAssertEqual(shutdowns, 1)
    XCTAssertEqual(exits, 0)
    coordinator.requestExit()
    coordinator.mainIsolateReady()
    XCTAssertEqual(shutdowns, 1)
    acknowledge?()
    XCTAssertEqual(exits, 1)
  }

  func testReadyMainIsolateReceivesExactlyOneExitRequest() {
    var shutdowns = 0
    var exits = 0
    let coordinator = NightcordTerminationCoordinator(shutdown: { done in
      shutdowns += 1
      done()
    }, finish: { exits += 1 })
    coordinator.mainIsolateReady()
    coordinator.requestExit()
    coordinator.requestExit()
    XCTAssertEqual(shutdowns, 1)
    XCTAssertEqual(exits, 1)
  }

  @MainActor
  func testMainWindowCloseRequestsAppExitWhileChildRemainsOpen() {
    // Last-window-only termination left the core connected with a viewer open.
    let main = makeWindow(size: NSSize(width: 960, height: 640))
    let child = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    child.isReleasedWhenClosed = false
    defer { child.close() }
    main.close()
    XCTAssertEqual((main as? ExitTestWindow)?.exitRequests, 1)
    XCTAssertNotNil(main.contentView)
    XCTAssertNotNil(child.contentView)
  }

  private var localizationBundle: Bundle {
    if let path = ProcessInfo.processInfo.environment["NIGHTCORD_TEST_BUNDLE"],
      let bundle = Bundle(path: path) { return bundle }
    return Bundle(for: MainFlutterWindow.self)
  }

  @MainActor
  func testNativeMenuLanguageChangesPreserveActionsAndShortcuts() throws {
    // The nib's English labels used to ignore the Flutter language setting.
    let menu = NSMenu(title: "test")
    let settings = NSMenuItem(title: "Settings…", action: NSSelectorFromString("openSettings:"), keyEquivalent: ",")
    settings.identifier = NSUserInterfaceItemIdentifier("menu.settings")
    menu.addItem(settings)
    let submenu = NSMenu(title: "Edit")
    let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    edit.identifier = NSUserInterfaceItemIdentifier("menu.edit")
    edit.submenu = submenu
    menu.addItem(edit)
    let target = NSObject()
    let cut = NSMenuItem(title: "Cut", action: NSSelectorFromString("cut:"), keyEquivalent: "x")
    cut.identifier = NSUserInterfaceItemIdentifier("menu.cut")
    cut.target = target
    cut.keyEquivalentModifierMask = [.command, .shift]
    submenu.addItem(cut)
    let dynamic = NSMenuItem(title: "User window title", action: nil, keyEquivalent: "")
    submenu.addItem(dynamic)
    for language in ["en", "zh", "zh_Hant", "ja", "ko", "en"] {
      NightcordMenuLocalization.apply(to: menu, language: language, bundle: localizationBundle)
      let resource = NightcordMenuLocalization.resourceBundle(language: language, bundle: localizationBundle)
      XCTAssertEqual(settings.title, resource.localizedString(forKey: "menu.settings", value: nil, table: "Menu"))
      XCTAssertEqual(cut.title, resource.localizedString(forKey: "menu.cut", value: nil, table: "Menu"))
      XCTAssertEqual(submenu.title, edit.title)
      XCTAssertEqual(cut.action, NSSelectorFromString("cut:"))
      XCTAssertTrue(cut.target === target)
      XCTAssertEqual(cut.keyEquivalent, "x")
      XCTAssertEqual(cut.keyEquivalentModifierMask, [.command, .shift])
      XCTAssertEqual(settings.keyEquivalent, ",")
      XCTAssertEqual(dynamic.title, "User window title")
    }
    XCTAssertEqual(settings.title, "Settings…")
  }

  @MainActor
  func testNativeMenuBrandAndFullScreenStateAreLocalized() {
    let menu = NSMenu(title: "test")
    let about = NSMenuItem(title: "About", action: nil, keyEquivalent: "")
    about.identifier = NSUserInterfaceItemIdentifier("menu.about")
    menu.addItem(about)
    let fullScreen = NSMenuItem(title: "Enter Full Screen", action: nil, keyEquivalent: "f")
    fullScreen.identifier = NSUserInterfaceItemIdentifier("menu.enterFullScreen")
    menu.addItem(fullScreen)
    NightcordMenuLocalization.apply(to: menu, language: "zh_Hant", bundle: localizationBundle,
      applicationName: "Nightcord Speak", fullScreen: true)
    XCTAssertEqual(about.title, "關於 Nightcord Speak")
    XCTAssertEqual(fullScreen.title, "結束全螢幕")
    NightcordMenuLocalization.apply(to: menu, language: "en", bundle: localizationBundle)
    XCTAssertEqual(fullScreen.title, "Enter Full Screen")
    NightcordMenuLocalization.apply(to: menu, language: "unsupported", bundle: localizationBundle)
    XCTAssertEqual(about.title, "About Nightcord Speak")
  }

  func testNativeLocalizationResourcesArePresentAndComplete() throws {
    // A source-only translation is useless if Xcode leaves it out of the bundle.
    var englishKeys: Set<String> = []
    for language in ["en", "zh", "zh_Hant", "ja", "ko"] {
      let bundle = NightcordMenuLocalization.resourceBundle(language: language, bundle: localizationBundle)
      let path = try XCTUnwrap(bundle.path(forResource: "Menu", ofType: "strings"))
      let data = try Data(contentsOf: URL(fileURLWithPath: path))
      let table = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
      if language == "en" { englishKeys = Set(table.keys) }
      XCTAssertEqual(Set(table.keys), englishKeys)
      XCTAssertEqual(table.count, 52)
      XCTAssertTrue(table.values.allSatisfy { !$0.isEmpty })
      let microphone = bundle.localizedString(forKey: "NSMicrophoneUsageDescription", value: nil, table: "InfoPlist")
      XCTAssertTrue(microphone.contains("TeamSpeak"))
      if language != "en" {
        XCTAssertNotEqual(microphone, "Nightcord Speak uses the microphone to transmit your voice to the TeamSpeak server you are connected to.")
      }
    }
  }

  @MainActor
  func testInitialContentSizeIsClampedBeforeManualResize() {
    // The nib opened at 800x600 until the user dragged a window edge.
    let window = makeWindow(size: NSSize(width: 800, height: 600))
    defer { window.close() }
    window.enforceMinimumContentSize()

    XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size,
      NSSize(width: 960, height: 640))
    XCTAssertEqual(window.contentMinSize, NSSize(width: 960, height: 640))
    window.enforceMinimumContentSize()
    XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size,
      NSSize(width: 960, height: 640))
  }

  @MainActor
  func testLargerInitialContentSizeIsPreserved() {
    let window = makeWindow(size: NSSize(width: 1200, height: 800))
    defer { window.close() }
    window.enforceMinimumContentSize()

    XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size,
      NSSize(width: 1200, height: 800))
  }

  @MainActor
  func testOnlyUndersizedDimensionIsEnlarged() {
    for size in [NSSize(width: 1200, height: 600), NSSize(width: 800, height: 800)] {
      let window = makeWindow(size: size)
      window.enforceMinimumContentSize()
      XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size,
        NSSize(width: max(size.width, 960), height: max(size.height, 640)))
      window.close()
    }
  }

  @MainActor
  private func makeWindow(size: NSSize) -> MainFlutterWindow {
    let window = ExitTestWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    return window
  }

}

// Existing size tests close their windows without terminating the test host.
private class ExitTestWindow: MainFlutterWindow {
  var exitRequests = 0
  override func requestApplicationExit() { exitRequests += 1 }
}
