import Foundation

enum L10n {
    static func tr(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }

    static func fmt(_ key: String, _ args: CVarArg...) -> String {
        let format = tr(key)
        return String(format: format, locale: Locale.current, arguments: args)
    }
}
