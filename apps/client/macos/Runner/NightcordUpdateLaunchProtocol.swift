import Foundation

@objc protocol NightcordUpdateLaunchProtocol {
  func launch(configuration: String, reply: @escaping (NSNumber?, NSError?) -> Void)
}
