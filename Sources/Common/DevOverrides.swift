//
//  DevOverrides.swift
//  FanCurve
//
//  Copyright © 2026, all rights reserved.
//

import Foundation

/// Single source for developer override flags. Each flag is read from an
/// environment variable, a `UserDefaults` key, or a launch argument of the
/// form `-Key value`, so the same switch works whether the app is launched
/// directly, through `open --args`, or with a persisted default.
enum DevOverrides {
  /// Keeps the dashboard fully live while the window is backgrounded.
  static var keepsLiveWhenBackgrounded: Bool {
    boolFlag(environment: "FANCURVE_DEV_KEEP_LIVE", defaultsKey: "FanCurveDevKeepLive")
  }

  private static func boolFlag(environment: String, defaultsKey: String) -> Bool {
    if ProcessInfo.processInfo.environment[environment] == "1" {
      return true
    }
    return UserDefaults.standard.bool(forKey: defaultsKey)
  }
}
