//
//  ExpandedRangeConfigurationStore.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-08-30.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

private let expandedRangeConfigurationStoreLog = AppLog.make(
  category: "ExpandedRangeConfigurationStore"
)

enum ExpandedRangeConfigurationStore {
  static func migrateIfNeeded(defaults: UserDefaults) {
    guard defaults.object(forKey: SharedConfigKeys.extendedRangeConfigurationAllowed) == nil else {
      return
    }

    let allowed = defaults.bool(forKey: SharedConfigKeys.overdriveEnabled)
      || defaults.bool(forKey: SharedConfigKeys.underdriveEnabled)
    defaults.set(allowed, forKey: SharedConfigKeys.extendedRangeConfigurationAllowed)
    expandedRangeConfigurationStoreLog.notice(
      "expanded_range.migrated allowed=\(allowed, privacy: .public)"
    )
  }

  static func setAllowed(_ allowed: Bool, defaults: UserDefaults) {
    if !allowed {
      defaults.set(false, forKey: SharedConfigKeys.overdriveEnabled)
      defaults.set(false, forKey: SharedConfigKeys.underdriveEnabled)
    }

    defaults.set(allowed, forKey: SharedConfigKeys.extendedRangeConfigurationAllowed)
    expandedRangeConfigurationStoreLog.notice(
      "expanded_range.allowed_changed allowed=\(allowed, privacy: .public)"
    )
  }
}
