//
//  SharedConfigPush.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026, all rights reserved.
//

import Foundation

/// Cross-process ping used by the GUI to tell the Agent that something
/// in the shared UserDefaults suite changed. The Agent responds by
/// running an extra tick immediately instead of waiting for its next
/// poll. Implemented with Darwin notifications because they are the
/// lightest-weight cross-process signal on macOS and do not require
/// XPC or Mach ports.
///
/// Either side of the pipe uses the same notification name. The payload
/// is empty. The Agent re-reads the shared suite on every tick, so it
/// does not need to know what changed, only that something did.
enum SharedConfigPush {
  static let notificationNameString = "io.goodkind.fancurve.configChanged"

  static var notificationName: CFString { notificationNameString as CFString }
}
