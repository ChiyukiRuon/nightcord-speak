import Cocoa

/// Native menus keep their actions, shortcuts and dynamic server/window titles.
/// Only items explicitly identified in the nib belong to the app's vocabulary.
enum NightcordMenuLocalization {
  static func resourceBundle(language: String?, bundle: Bundle = .main) -> Bundle {
    guard let language = language else { return bundle }
    let tag = language.replacingOccurrences(of: "_", with: "-")
    let localization: String
    switch tag {
    case "zh", "zh-Hans": localization = "zh-Hans"
    case "zh-Hant": localization = "zh-Hant"
    case "ja", "ko", "en": localization = tag
    default: localization = "en"
    }
    guard let path = bundle.path(forResource: localization, ofType: "lproj"),
      let localized = Bundle(path: path) else { return bundle }
    return localized
  }

  static func apply(to menu: NSMenu, language: String?, bundle: Bundle = .main,
    applicationName: String = "Nightcord Speak", fullScreen: Bool = false) {
    let localized = resourceBundle(language: language, bundle: bundle)
    apply(to: menu, localized: localized, applicationName: applicationName,
      fullScreen: fullScreen)
  }

  private static func apply(to menu: NSMenu, localized: Bundle,
    applicationName: String, fullScreen: Bool) {
    for item in menu.items {
      if let identifier = item.identifier?.rawValue,
        identifier.hasPrefix("menu.") {
        let key = identifier == "menu.enterFullScreen" && fullScreen
          ? "menu.exitFullScreen" : identifier
        item.title = localized.localizedString(forKey: key, value: item.title, table: "Menu")
          .replacingOccurrences(of: "%@", with: applicationName)
        item.submenu?.title = item.title
      }
      if let submenu = item.submenu {
        apply(to: submenu, localized: localized, applicationName: applicationName,
          fullScreen: fullScreen)
      }
    }
  }
}
