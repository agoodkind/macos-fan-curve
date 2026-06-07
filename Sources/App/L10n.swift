import Foundation

enum L10n {
  static func tr(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: nil, table: nil)
  }
}
