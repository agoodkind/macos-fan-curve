//
//  DevOverrides.swift
//  FanCurve
//
//  Copyright © 2026
//

import AppLog
import Foundation

private let devOverridesLog = AppLog.make(category: "DevOverrides")

/// Single source for developer override flags. Each flag is read from an
/// environment variable, a `UserDefaults` key, or a launch argument of the
/// form `-Key value`, so the same switch works whether the app is launched
/// directly, through `open --args`, or with a persisted default.
enum DevOverrides {
    /// Keeps the dashboard fully live while the window is backgrounded.
    static var keepsLiveWhenBackgrounded: Bool {
        boolFlag(environment: "FANCURVE_DEV_KEEP_LIVE", defaultsKey: "FanCurveDevKeepLive")
    }

    /// Resolves a string override from an environment variable or a user default,
    /// preferring the environment variable when both are set.
    static func stringFlag(environment: String, defaultsKey: String) -> String? {
        let value =
            ProcessInfo.processInfo.environment[environment]
            ?? UserDefaults.standard.string(forKey: defaultsKey)
        if let value {
            devOverridesLog.notice(
                "dev.override.resolved key=\(defaultsKey, privacy: .public) value=\(value, privacy: .public)"
            )
        }
        return value
    }

    private static func boolFlag(environment: String, defaultsKey: String) -> Bool {
        if ProcessInfo.processInfo.environment[environment] == "1" {
            return true
        }
        return UserDefaults.standard.bool(forKey: defaultsKey)
    }
}
