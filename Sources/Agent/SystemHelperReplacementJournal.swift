//
//  SystemHelperReplacementJournal.swift
//  FanCurveAgent
//
//  Created by Claude <noreply@anthropic.com> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - SystemHelperReplacementJournaling

/// Records that an automatic System Helper replacement unregistered the old
/// helper but has not yet completed the new registration. The marker survives
/// agent restarts, so an interrupted replacement resumes instead of stranding
/// the machine with no registered helper.
protocol SystemHelperReplacementJournaling: Sendable {
  var hasPendingReplacement: Bool { get }

  func recordPendingReplacement()
  func clearPendingReplacement()
}

// MARK: - SystemHelperReplacementJournal

final class SystemHelperReplacementJournal:
  SystemHelperReplacementJournaling,
  @unchecked Sendable
{
  private let defaults: UserDefaults

  init(
    defaults: UserDefaults = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard
  ) {
    self.defaults = defaults
  }

  var hasPendingReplacement: Bool {
    defaults.bool(forKey: SharedConfigKeys.systemHelperReplacementPending)
  }

  func recordPendingReplacement() {
    defaults.set(true, forKey: SharedConfigKeys.systemHelperReplacementPending)
  }

  func clearPendingReplacement() {
    defaults.removeObject(forKey: SharedConfigKeys.systemHelperReplacementPending)
  }
}
