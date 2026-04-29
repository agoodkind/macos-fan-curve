import Foundation

enum L10n {
    static func tr(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func fmt(_ key: String, _ args: CVarArg...) -> String {
        let format = tr(key)
        return withVaList(args) { pointer in
            NSString(format: format, locale: Locale.current, arguments: pointer) as String
        }
    }
}
