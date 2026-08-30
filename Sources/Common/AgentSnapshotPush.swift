//
//  AgentSnapshotPush.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

private let snapshotLog = AppLog.make(category: "AgentSnapshot")

enum AgentSnapshotPush {
  static let notificationNameString = "io.goodkind.fancurve.snapshotChanged"

  static func post() {
    snapshotLog.debug(
      "snapshot.pushed notification=\(notificationNameString, privacy: .public)")
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(notificationNameString as CFString),
      nil,
      nil,
      true)
  }
}
